import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../editor/canvas_painter.dart';
import '../editor/controller.dart';

const Color kPanel = Color(0xFFF7F8FA);
const Color kBorder = Color(0xFFD9DCE3);

class PanelHeader extends StatelessWidget {
  const PanelHeader(this.title, {super.key, this.actions = const []});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.only(left: 12, right: 4),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: kBorder)),
    ),
    child: Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Color(0xFF5B6272),
          ),
        ),
        const Spacer(),
        ...actions,
      ],
    ),
  );
}

class SmallIconButton extends StatelessWidget {
  const SmallIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 18,
    this.color,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 500),
    child: InkResponse(
      onTap: onPressed,
      radius: 16,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? kAccent.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: size,
          color: onPressed == null
              ? const Color(0xFFB4B8C2)
              : active
              ? kAccent
              : color ?? const Color(0xFF444B5A),
        ),
      ),
    ),
  );
}

class LabeledRow extends StatelessWidget {
  const LabeledRow(this.label, this.child, {super.key});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF5B6272)),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// A slider that records one undo step per drag.
class LiveSlider extends StatefulWidget {
  const LiveSlider({
    super.key,
    required this.controller,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.apply,
    this.divisions,
  });
  final EditorController controller;
  final double value, min, max;
  final String label;
  final int? divisions;
  final void Function(double v) apply;

  @override
  State<LiveSlider> createState() => _LiveSliderState();
}

class _LiveSliderState extends State<LiveSlider> {
  EditToken? _token;

  @override
  Widget build(BuildContext context) => SliderTheme(
    data: SliderTheme.of(context).copyWith(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: SliderComponentShape.noOverlay,
    ),
    child: Slider(
      value: widget.value.clamp(widget.min, widget.max),
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      onChangeStart: (_) => _token = widget.controller.beginEdit(widget.label),
      onChanged: widget.apply,
      onChangeEnd: (_) {
        if (_token != null) widget.controller.endEdit(_token!);
        _token = null;
      },
    ),
  );
}

class ColorRow extends StatelessWidget {
  const ColorRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowNone = false,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    Widget swatch(int argb) {
      final selected = value == argb;
      return GestureDetector(
        onTap: () => onChanged(argb),
        child: Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(right: 4, bottom: 4),
          decoration: BoxDecoration(
            color: argb == 0 ? Colors.white : Color(argb),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? kAccent : const Color(0xFFBFC4CF),
              width: selected ? 2 : 1,
            ),
          ),
          child: argb == 0
              ? const Icon(Icons.block, size: 12, color: Color(0xFFD32F2F))
              : null,
        ),
      );
    }

    final custom = !kPalette.contains(value) && value != 0;
    return Wrap(
      children: [
        if (allowNone) swatch(0),
        for (final c in kPalette) swatch(c),
        GestureDetector(
          onTap: () async {
            final v = await showHexDialog(context, value);
            if (v != null) onChanged(v);
          },
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: custom ? Color(value) : null,
              gradient: custom
                  ? null
                  : const SweepGradient(
                      colors: [
                        Colors.red,
                        Colors.yellow,
                        Colors.green,
                        Colors.blue,
                        Colors.purple,
                        Colors.red,
                      ],
                    ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: custom ? kAccent : const Color(0xFFBFC4CF),
                width: custom ? 2 : 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<int?> showHexDialog(BuildContext context, int current) {
  final ctl = TextEditingController(
    text: current == 0
        ? ''
        : (current & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase(),
  );
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Custom colour'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: const InputDecoration(prefixText: '#', hintText: 'RRGGBB'),
        onSubmitted: (s) => Navigator.pop(ctx, _parseHex(s)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, _parseHex(ctl.text)),
          child: const Text('Use colour'),
        ),
      ],
    ),
  );
}

int? _parseHex(String s) {
  var t = s.trim().replaceAll('#', '');
  if (t.length == 3) t = t.split('').map((e) => '$e$e').join();
  if (t.length != 6) return null;
  final v = int.tryParse(t, radix: 16);
  return v == null ? null : 0xFF000000 | v;
}

class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.value,
    required this.onSubmitted,
    this.suffix,
    this.width = 64,
  });
  final double value;
  final ValueChanged<double> onSubmitted;
  final String? suffix;
  final double width;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _ctl = TextEditingController(
    text: _fmt(widget.value),
  );
  final FocusNode _focus = FocusNode();

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) {
      _ctl.text = _fmt(widget.value);
    }
  }

  void _submit() {
    final v = double.tryParse(_ctl.text.trim());
    if (v != null && v != widget.value) widget.onSubmitted(v);
    _ctl.text = _fmt(v ?? widget.value);
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: 30,
    child: TextField(
      controller: _ctl,
      focusNode: _focus,
      style: const TextStyle(fontSize: 12.5),
      decoration: InputDecoration(
        isDense: true,
        suffixText: widget.suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      onSubmitted: (_) {
        _submit();
        _giveBackFocus();
      },
      // Clicking anywhere else ends the edit, so the one-key shortcuts work
      // again without having to click the page first.
      onTapOutside: (_) => _giveBackFocus(),
    ),
  );

  /// Hand keyboard focus back to the editor around us (the shortcut handler).
  void _giveBackFocus() {
    if (!_focus.hasFocus) return;
    final editor = Focus.maybeOf(context);
    if (editor != null) {
      editor.requestFocus();
    } else {
      _focus.unfocus();
    }
  }
}

/// Taps respond instantly; a second tap within a moment counts as a double
/// tap. (GestureDetector.onDoubleTap would delay every single tap.)
class QuickTap extends StatefulWidget {
  const QuickTap({
    super.key,
    required this.onTap,
    this.onDoubleTap,
    required this.child,
    this.onSecondaryTapDown,
  });
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final Widget child;

  @override
  State<QuickTap> createState() => _QuickTapState();
}

class _QuickTapState extends State<QuickTap> {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onSecondaryTapDown: widget.onSecondaryTapDown,
    onTap: () {
      final now = DateTime.now();
      final again = now.difference(_last).inMilliseconds < 380;
      _last = again ? DateTime.fromMillisecondsSinceEpoch(0) : now;
      if (again && widget.onDoubleTap != null) {
        widget.onDoubleTap!();
      } else {
        widget.onTap();
      }
    },
    child: widget.child,
  );
}

const _imageExts = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'];

bool isImagePath(String p) =>
    _imageExts.contains(p.split('.').last.toLowerCase());

/// Accepts files dragged in from the desktop.
class FileDropZone extends StatefulWidget {
  const FileDropZone({super.key, required this.child, required this.onFiles});
  final Widget child;
  final void Function(List<String> paths, Offset local) onFiles;

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (_) => setState(() => _over = true),
    onDragExited: (_) => setState(() => _over = false),
    onDragDone: (d) {
      setState(() => _over = false);
      widget.onFiles([for (final f in d.files) f.path], d.localPosition);
    },
    child: Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (_over)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.08),
                  border: Border.all(color: kAccent, width: 2),
                ),
                child: const Center(
                  child: Text(
                    'Drop to add',
                    style: TextStyle(
                      color: kAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// A little keyboard key. Used wherever the app says "press this", so a
/// keystroke always looks like one.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, this.compact = false});
  final String label;

  /// Smaller, for the toolbar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 14.0 : 20.0;
    return Container(
      constraints: BoxConstraints(
        minWidth: h + (compact ? 2 : 4),
        minHeight: h,
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFD),
        borderRadius: BorderRadius.circular(compact ? 3.5 : 5),
        border: Border.all(color: const Color(0xFFB9BECB)),
        // The flat shadow under the key is what makes it read as a key.
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9BA2B4),
            offset: Offset(0, compact ? 1.5 : 2.5),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 9.5 : 12,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF2B3140),
        ),
      ),
    );
  }
}
