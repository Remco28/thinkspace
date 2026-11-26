import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/controller.dart';
import '../io/screenshot_shortcut.dart';
import 'design.dart';
import 'shortcuts.dart';

/// Where the dialog reads and writes the shortcut; tests put a stand-in here.
ScreenshotShortcut Function() screenshotShortcutStore =
    screenshotShortcutForThisComputer;

/// Choose the keys that take a screenshot from anywhere, even with
/// Thinkspace in the background. GNOME on Linux, and Windows.
Future<void> showScreenshotShortcut(BuildContext context, EditorController c) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ShortcutDialog(screenshotShortcutStore(), c),
    );

class _ShortcutDialog extends StatefulWidget {
  const _ShortcutDialog(this.store, this.c);
  final ScreenshotShortcut store;
  final EditorController c;

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  bool? _available;
  String? _current;
  ({String accel, List<String> caps})? _picked;
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final available = await widget.store.available();
    final current = available ? await widget.store.current() : null;
    if (!mounted) return;
    setState(() {
      _available = available;
      _current = current;
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    final k = e.logicalKey;
    // Esc still closes, Tab still moves on, and modifiers wait for a key.
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    if (_isModifier(k)) return KeyEventResult.handled;
    final hw = HardwareKeyboard.instance;
    if (hw.isMetaPressed && !widget.store.superKey) {
      setState(
        () => _note =
            "Windows keeps the Windows key for itself. Use Ctrl or Alt.",
      );
      return KeyEventResult.handled;
    }
    final s = shortcutFor(
      k,
      ctrl: hw.isControlPressed,
      alt: hw.isAltPressed,
      shift: hw.isShiftPressed,
      meta: hw.isMetaPressed,
    );
    setState(() {
      if (s != null) {
        _picked = s;
        _note = null;
      } else {
        _note =
            'Add Ctrl${widget.store.superKey ? ', Alt or Super' : ' or Alt'} '
            'to a letter, so typing never sets it off.';
      }
    });
    return KeyEventResult.handled;
  }

  bool _isModifier(LogicalKeyboardKey k) =>
      LogicalKeyboardKey.collapseSynonyms({k}).any(
        (m) => {
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.meta,
        }.contains(m),
      );

  Future<void> _save() async {
    final p = _picked;
    if (p == null) return;
    setState(() => _busy = true);
    final ok = await widget.store.set(p.accel);
    if (!mounted) return;
    if (ok) {
      widget.c.showToast('Screenshot shortcut: ${p.caps.join(' + ')}');
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _note = "Couldn't save it in the desktop's keyboard settings.";
      });
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    final ok = await widget.store.remove();
    if (!mounted) return;
    if (ok) {
      widget.c.showToast('Screenshot shortcut removed');
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _note = "Couldn't remove it from the desktop's keyboard settings.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(fontSize: kTextBody, color: kInk, height: 1.4);
    const soft = TextStyle(
      fontSize: kTextCaption,
      color: kInkSoft,
      height: 1.4,
    );
    final caps =
        _picked?.caps ?? (_current == null ? null : capsForAccel(_current!));
    return AlertDialog(
      title: const Text('Screenshot shortcut'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Keys that take a screenshot from anywhere, even with '
              'Thinkspace in the background. The picture goes to the '
              'Thinkspace window you used last, or opens one.',
              style: body,
            ),
            const SizedBox(height: kSpace16),
            if (_available == null)
              const Text('Checking the keyboard settings…', style: soft)
            else if (_available == false) ...[
              const Text(
                "This desktop doesn't take shortcuts from apps. Add one in "
                'its keyboard settings that runs:',
                style: body,
              ),
              const SizedBox(height: kSpace8),
              SelectableText(
                widget.store.command,
                key: const ValueKey('capture-command'),
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: kTextCaption,
                  color: kInk,
                ),
              ),
            ] else ...[
              Focus(
                autofocus: true,
                onKeyEvent: _onKey,
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return GestureDetector(
                      onTap: () => Focus.of(context).requestFocus(),
                      child: Container(
                        key: const ValueKey('shortcut-keys'),
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: focused ? kAccentSoft : kPanel,
                          borderRadius: BorderRadius.circular(kRadius),
                          border: Border.all(
                            color: focused ? kAccent : kControlBorder,
                          ),
                        ),
                        child: caps == null
                            ? Text(
                                focused
                                    ? 'Press the keys you want'
                                    : 'No shortcut. Click here, then press keys',
                                style: soft,
                              )
                            : KeyCombo(caps),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: kSpace8),
              Text(
                _note ??
                    'Ctrl + Print works well. If the keys do nothing later, '
                        '${widget.store.superKey ? 'the desktop' : 'Windows'} '
                        'uses them for something else.',
                style: soft.copyWith(color: _note == null ? kInkSoft : kDanger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_current != null)
          TextButton(
            onPressed: _busy ? null : _remove,
            child: const Text('Remove shortcut'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_available == false ? 'Close' : 'Cancel'),
        ),
        if (_available == true)
          FilledButton(
            onPressed: _busy || _picked == null ? null : _save,
            child: const Text('Save'),
          ),
      ],
    );
  }
}
