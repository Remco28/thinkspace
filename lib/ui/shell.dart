import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dev/inspector.dart';
import '../editor/canvas_view.dart';
import '../editor/controller.dart';
import '../editor/image_ops.dart' show HoleFill;
import '../editor/interactor.dart';
import '../io/files.dart';
import '../io/samples.dart';
import '../model/scene.dart';
import 'collection_panel.dart';
import 'layers_panel.dart';
import 'properties_panel.dart';
import 'shortcuts.dart';
import 'top_bar.dart';
import 'widgets.dart';

class EditorShell extends StatefulWidget {
  const EditorShell({
    super.key,
    this.controller,
    this.startInspector = true,
    this.enableRecovery = false,
    this.recoveryFile,
    this.launchFiles = const [],
  });
  final EditorController? controller;

  /// Paths the app was started with (a project to open, pictures to place).
  final List<String> launchFiles;
  final bool startInspector;

  /// Keep unsaved work in a recovery file and offer it back after a crash.
  final bool enableRecovery;
  final File? recoveryFile;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  late final EditorController c = widget.controller ?? EditorController();
  late final CanvasInteractor ix = CanvasInteractor(c);
  final ValueNotifier<bool> spaceDown = ValueNotifier(false);
  final GlobalKey shotKey = GlobalKey();
  final FocusNode _focus = FocusNode(debugLabel: 'shell');
  double collectionWidth = 270;
  bool collectionOpen = true;
  Inspector? _inspector;
  AppLifecycleListener? _lifecycle;
  String? _lastTitle;
  static const _windowChannel = MethodChannel('thinkspace/window');

  void _syncTitle() {
    final t =
        '${c.dirty ? '• ' : ''}${c.filePath == null ? 'Untitled' : baseName(c.filePath!)} — Thinkspace';
    if (t == _lastTitle) return;
    _lastTitle = t;
    _windowChannel
        .invokeMethod<void>('setTitle', t)
        .catchError((_) {}); // absent in tests
  }

  @override
  void initState() {
    super.initState();
    if (widget.enableRecovery) c.addListener(_syncTitle);
    if (widget.enableRecovery) {
      final env = Platform.environment;
      final home = env['HOME'];
      final base =
          env['XDG_DATA_HOME'] ??
          (home == null || home.isEmpty ? null : '$home/.local/share');
      final data =
          env['THINKSPACE_DATA_DIR'] ??
          (base == null ? null : '$base/thinkspace');
      c.recoveryFile =
          widget.recoveryFile ??
          (data == null ? null : File('$data/recovery.thinkspace'));
      if (c.recoveryFile != null) c.startAutosave(c.recoveryFile!);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _offerRecovery();
        if (widget.launchFiles.isNotEmpty &&
            mounted &&
            (!c.dirty || await _confirmDiscard())) {
          await c.openLaunchFiles(widget.launchFiles);
        }
      });
      _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    }
    final port = int.tryParse(
      Platform.environment['THINKSPACE_DEBUG_PORT'] ?? '',
    );
    if (widget.startInspector && port != null) {
      _inspector = Inspector(c: c, ix: ix, shotKey: shotKey, port: port)
        ..start().catchError((Object e) {
          stderr.writeln('Thinkspace inspector could not start: $e');
        });
    }
  }

  Future<void> _offerRecovery() async {
    final when = c.pendingRecovery();
    if (when == null || !mounted) return;
    final ago = DateTime.now().difference(when);
    final label = ago.inMinutes < 1
        ? 'a moment ago'
        : ago.inHours < 1
        ? '${ago.inMinutes} minutes ago'
        : ago.inDays < 1
        ? '${ago.inHours} hours ago'
        : '${ago.inDays} days ago';
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick up where you left off?'),
        content: Text(
          'Thinkspace found work that was never saved (last changed $label).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Start fresh'),
          ),
          FilledButton(
            key: const ValueKey('restore'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore it'),
          ),
        ],
      ),
    );
    if (restore == true) {
      try {
        await c.restoreRecovery();
        c.showToast('Restored your unsaved work — save it to keep it');
      } catch (_) {
        c.showToast('That recovery file could not be read');
        c.clearRecovery();
      }
    } else {
      c.clearRecovery();
    }
  }

  Future<ui.AppExitResponse> _onExitRequested() async {
    if (!c.dirty) {
      c.clearRecovery();
      return ui.AppExitResponse.exit;
    }
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close with unsaved changes?'),
        content: const Text(
          'Save this project first, or close and lose the changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Keep working'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Close without saving'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save…'),
          ),
        ],
      ),
    );
    if (r == 'discard') {
      c.clearRecovery();
      return ui.AppExitResponse.exit;
    }
    if (r == 'save') {
      await _save();
      if (!c.dirty) return ui.AppExitResponse.exit;
    }
    return ui.AppExitResponse.cancel;
  }

  @override
  void dispose() {
    c.removeListener(_syncTitle);
    _lifecycle?.dispose();
    _inspector?.stop();
    _focus.dispose();
    super.dispose();
  }

  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  // ---- keyboard ------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_typing) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space) {
      spaceDown.value = e is! KeyUpEvent;
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed || hw.isMetaPressed;
    final shift = hw.isShiftPressed;

    if (c.pendingPaste != null) {
      if (k == LogicalKeyboardKey.enter) {
        c.resolvePaste(toCollection: false);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyC && !ctrl) {
        c.resolvePaste(toCollection: true);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.escape) {
        c.cancelPendingPaste();
        return KeyEventResult.handled;
      }
    }

    if (ctrl) {
      switch (k) {
        case LogicalKeyboardKey.keyZ:
          shift ? c.redo() : c.undo();
        case LogicalKeyboardKey.keyY:
          c.redo();
        case LogicalKeyboardKey.keyC:
          shift ? c.copyPageToClipboard() : c.copySelection();
        case LogicalKeyboardKey.keyX:
          c.cutSelection();
        case LogicalKeyboardKey.keyV:
          shift ? c.pasteToCollection() : c.paste();
        case LogicalKeyboardKey.keyD:
          c.duplicateSelection();
        case LogicalKeyboardKey.keyA:
          c.selectAll();
        case LogicalKeyboardKey.keyS:
          shift ? _saveAs() : _save();
        case LogicalKeyboardKey.keyO:
          _open();
        case LogicalKeyboardKey.keyE:
          _export(1);
        case LogicalKeyboardKey.keyI:
          _importImages();
        case LogicalKeyboardKey.keyN:
          _new();
        case LogicalKeyboardKey.digit0:
          c.fitToView();
        case LogicalKeyboardKey.digit1:
          c.zoomTo(1);
        case LogicalKeyboardKey.equal:
        case LogicalKeyboardKey.numpadAdd:
          c.zoomTo(c.zoom * 1.25);
        case LogicalKeyboardKey.minus:
        case LogicalKeyboardKey.numpadSubtract:
          c.zoomTo(c.zoom / 1.25);
        case LogicalKeyboardKey.bracketRight:
          c.reorderSelection('front');
        case LogicalKeyboardKey.bracketLeft:
          c.reorderSelection('back');
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (e.character == '?' || k == LogicalKeyboardKey.f1) {
      showShortcuts(context);
      return KeyEventResult.handled;
    }

    final step = c.snapOn ? c.doc.gridSize : (shift ? 10.0 : 1.0);
    switch (k) {
      case LogicalKeyboardKey.escape:
        if (ix.active) {
          ix.cancel();
        } else if (c.tool != Tool.select) {
          c.setTool(Tool.select);
        } else {
          c.clearSelection();
        }
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        c.deleteSelection();
      case LogicalKeyboardKey.arrowLeft:
        c.nudge(Offset(-step, 0));
      case LogicalKeyboardKey.arrowRight:
        c.nudge(Offset(step, 0));
      case LogicalKeyboardKey.arrowUp:
        // After clicking a row in the Layers list the arrows walk the list.
        c.listFocus ? c.listStep(-1, extend: shift) : c.nudge(Offset(0, -step));
      case LogicalKeyboardKey.arrowDown:
        c.listFocus ? c.listStep(1, extend: shift) : c.nudge(Offset(0, step));
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.f2:
        final one = c.single;
        if (one != null && one is TextObject) c.beginTextEdit(one.id);
      case LogicalKeyboardKey.keyV:
        c.setTool(Tool.select);
      case LogicalKeyboardKey.keyL:
        c.setTool(Tool.line);
      case LogicalKeyboardKey.keyA:
        c.setTool(Tool.arrow);
      case LogicalKeyboardKey.keyR:
        c.setTool(Tool.rect);
      case LogicalKeyboardKey.keyE:
        c.setTool(Tool.ellipse);
      case LogicalKeyboardKey.keyT:
        c.setTool(Tool.text);
      case LogicalKeyboardKey.keyP:
        c.setTool(Tool.pen);
      case LogicalKeyboardKey.keyN:
        c.setTool(Tool.badge);
      case LogicalKeyboardKey.keyC:
        c.setTool(Tool.cutout);
      case LogicalKeyboardKey.keyG:
        shift ? c.toggleSnap() : c.toggleGrid();
      case LogicalKeyboardKey.keyF:
        c.fitToView();
      case LogicalKeyboardKey.keyM:
        if (c.canMerge) {
          c.flattenSelection();
        } else if (c.selection.isNotEmpty) {
          c.showToast(
            'Nothing to merge: select two or more things that are visible and unlocked',
          );
        }
      case LogicalKeyboardKey.keyU:
        if (c.canUnmerge) {
          c.unmerge();
        } else if (c.selection.isNotEmpty) {
          c.showToast(
            'That picture was not made by merging, so it cannot be unmerged',
          );
        }
      case LogicalKeyboardKey.bracketRight:
        c.reorderSelection('forward');
      case LogicalKeyboardKey.bracketLeft:
        c.reorderSelection('backward');
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
        c.zoomTo(c.zoom * 1.25);
      case LogicalKeyboardKey.minus:
        c.zoomTo(c.zoom / 1.25);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- file operations -----------------------------------------------------

  Future<bool> _confirmDiscard() async {
    if (!c.dirty) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
          'This project has changes that haven’t been saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _new() async {
    if (await _confirmDiscard()) c.newDocument();
  }

  Future<void> _open() async {
    if (!await _confirmDiscard()) return;
    final p = await pickProject();
    if (p == null) return;
    await _openProject(p);
  }

  Future<void> _openProject(String path) async {
    try {
      await c.openFrom(path);
    } on FormatException catch (e) {
      c.showToast(
        e.message.startsWith('This project')
            ? e.message
            : 'That is not a Thinkspace project',
      );
    } catch (_) {
      c.showToast('Could not open that project');
    }
  }

  Future<void> _save() async {
    if (c.filePath == null) return _saveAs();
    await c.saveTo(c.filePath!);
  }

  Future<void> _saveAs() async {
    final p = await chooseProjectPath(
      c.filePath == null
          ? 'untitled.thinkspace'
          : '${baseName(c.filePath!)}.thinkspace',
    );
    if (p != null) await c.saveTo(p);
  }

  Future<void> _export(double scale) async {
    final name = c.filePath == null ? 'thinkspace' : baseName(c.filePath!);
    final p = await choosePngPath(
      '$name${scale == 1 ? '' : '@${scale.round()}x'}.png',
    );
    if (p == null) return;
    await c.exportPngTo(p, scale: scale);
  }

  /// Files dragged in from the desktop: pictures go to the page (or the
  /// collection), a project file opens.
  Future<void> _dropped(
    List<String> paths, {
    Offset? at,
    bool toCollection = false,
  }) async {
    final projects = paths.where((p) => p.endsWith('.thinkspace')).toList();
    final images = paths.where(isImagePath).toList();
    if (projects.isNotEmpty && await _confirmDiscard()) {
      await _openProject(projects.first);
      return;
    }
    if (images.isEmpty) {
      c.showToast(
        'Drop pictures (PNG, JPG, WebP, GIF, BMP) or a .thinkspace project',
      );
      return;
    }
    await c.importFiles(images, at: at, toCollection: toCollection);
  }

  Future<void> _importImages() async {
    final paths = await pickImages();
    if (paths.isNotEmpty) await c.importFiles(paths);
  }

  void _menu(MenuAction a) {
    switch (a) {
      case MenuAction.newDoc:
        _new();
      case MenuAction.open:
        _open();
      case MenuAction.save:
        _save();
      case MenuAction.saveAs:
        _saveAs();
      case MenuAction.importImage:
        _importImages();
      case MenuAction.sample:
        _confirmDiscard().then((ok) {
          if (ok) loadStorefrontSample(c);
        });
      case MenuAction.exportPng:
        _export(1);
      case MenuAction.exportPng2x:
        _export(2);
      case MenuAction.copyPage:
        c.copyPageToClipboard();
      case MenuAction.pasteAsk:
        c.pasteMode = PasteMode.ask;
        c.notify();
      case MenuAction.pasteLayer:
        c.pasteMode = PasteMode.layer;
        c.notify();
      case MenuAction.pasteCollection:
        c.pasteMode = PasteMode.collection;
        c.notify();
      case MenuAction.autoGrow:
        c.autoGrow = !c.autoGrow;
        c.notify();
      case MenuAction.shortcuts:
        showShortcuts(context);
    }
  }

  // ---- layout --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: shotKey,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: kPanel,
          // The top bar is drawn last so the keycap under the active tool can
          // hang over its lower edge.
          body: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                children: [
                  const SizedBox(height: kTopBarHeight),
                  Expanded(
                    child: Row(
                      children: [
                        if (collectionOpen) ...[
                          SizedBox(
                            width: collectionWidth,
                            child: FileDropZone(
                              onFiles: (paths, _) =>
                                  _dropped(paths, toCollection: true),
                              child: Material(
                                color: kPanel,
                                child: CollectionPanel(controller: c),
                              ),
                            ),
                          ),
                          _Divider(
                            onDrag: (dx) => setState(
                              () => collectionWidth = (collectionWidth + dx)
                                  .clamp(170, 560),
                            ),
                          ),
                        ],
                        Expanded(
                          child: FileDropZone(
                            onFiles: (paths, local) =>
                                _dropped(paths, at: c.toScene(local)),
                            child: _canvasArea(),
                          ),
                        ),
                        Container(
                          width: 292,
                          decoration: const BoxDecoration(
                            border: Border(left: BorderSide(color: kBorder)),
                          ),
                          child: Material(
                            color: kPanel,
                            child: Column(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: LayersPanel(controller: c),
                                ),
                                const Divider(height: 1, color: kBorder),
                                Expanded(
                                  flex: 6,
                                  child: PropertiesPanel(controller: c),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: kTopBarHeight,
                child: TopBar(c: c, onMenu: _menu),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _canvasArea() {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Stack(
        children: [
          Positioned.fill(
            child: CanvasView(
              controller: c,
              interactor: ix,
              spaceDown: spaceDown,
              focusNode: _focus,
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: Material(
              color: Colors.white,
              elevation: 1,
              borderRadius: BorderRadius.circular(8),
              child: SmallIconButton(
                key: const ValueKey('toggle-collection'),
                icon: collectionOpen
                    ? Icons.keyboard_double_arrow_left
                    : Icons.collections_outlined,
                tooltip: collectionOpen
                    ? 'Hide the collection'
                    : 'Show the collection',
                onPressed: () =>
                    setState(() => collectionOpen = !collectionOpen),
              ),
            ),
          ),
          if (c.tool == Tool.cutout)
            Positioned(
              top: 8,
              left: 52,
              right: 8,
              child: Align(
                alignment: Alignment.topCenter,
                child: _CutoutBar(c: c),
              ),
            ),
          if (c.pendingPaste != null)
            Positioned(
              bottom: 56,
              left: 0,
              right: 0,
              child: Center(child: _PasteChooser(c: c)),
            ),
          if (c.doc.allObjects.isEmpty &&
              c.pendingPaste == null &&
              c.tool == Tool.select)
            const Positioned.fill(child: IgnorePointer(child: _EmptyHint())),
          Positioned(left: 8, bottom: 8, child: _ZoomBar(c: c)),
          if (c.toastMessage != null)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE6222733),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      c.toastMessage!,
                      key: const ValueKey('toast'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
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
}

/// Shown over an empty page so a first-time user knows how things get in.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.only(bottom: 40),
      child: Text(
        'Paste a picture (Ctrl+V), drop a file here,\nor press A to draw an arrow',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, height: 1.5, color: Color(0xFFA0A6B5)),
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider({required this.onDrag});
  final void Function(double dx) onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      key: const ValueKey('collection-divider'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: Container(
        width: 7,
        color: kPanel,
        child: const Center(child: VerticalDivider(width: 1, color: kBorder)),
      ),
    ),
  );
}

class _ZoomBar extends StatelessWidget {
  const _ZoomBar({required this.c});
  final EditorController c;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 1,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmallIconButton(
            icon: Icons.remove,
            tooltip: 'Zoom out',
            onPressed: () => c.zoomTo(c.zoom / 1.25),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${(c.zoom * 100).round()}%',
              key: const ValueKey('zoom-label'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SmallIconButton(
            icon: Icons.add,
            tooltip: 'Zoom in',
            onPressed: () => c.zoomTo(c.zoom * 1.25),
          ),
          SmallIconButton(
            icon: Icons.fit_screen_outlined,
            tooltip: 'Fit the page  Ctrl+0',
            onPressed: c.fitToView,
          ),
          const SizedBox(width: 4),
          Text(
            '${c.doc.canvasSize.width.round()} × ${c.doc.canvasSize.height.round()}',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7385)),
          ),
          const SizedBox(width: 10),
          // Only when there is something off-screen to pan to: the moment
          // someone needs to know it.
          if (c.canPan && c.viewport.width > 520) ...[
            Container(width: 1, height: 18, color: kBorder),
            const SizedBox(width: 14),
            const _PanHint(),
            const SizedBox(width: 8),
          ],
        ],
      ),
    ),
  );
}

class _PanHint extends StatelessWidget {
  const _PanHint();

  @override
  Widget build(BuildContext context) => const Row(
    key: ValueKey('pan-hint'),
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Pan:', style: TextStyle(fontSize: 11.5, color: Color(0xFF6B7385))),
      SizedBox(width: 5),
      KeyCombo(['Space', 'drag']),
    ],
  );
}

class _PasteChooser extends StatefulWidget {
  const _PasteChooser({required this.c});
  final EditorController c;

  @override
  State<_PasteChooser> createState() => _PasteChooserState();
}

class _PasteChooserState extends State<_PasteChooser> {
  bool remember = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final a = c.pendingPaste == null ? null : c.assets[c.pendingPaste!.assetId];
    return Material(
      key: const ValueKey('paste-chooser'),
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (a != null)
                    Container(
                      width: 56,
                      height: 42,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: kBorder),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: RawImage(image: a.image, fit: BoxFit.contain),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pasted an image${a == null ? '' : ' (${a.width} × ${a.height})'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const Text(
                          'Where should it go?',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7385),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SmallIconButton(
                    icon: Icons.close,
                    tooltip: 'Discard  Esc',
                    onPressed: c.cancelPendingPaste,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('paste-to-layer'),
                      onPressed: () => c.resolvePaste(
                        toCollection: false,
                        remember: remember,
                      ),
                      child: Text(
                        'Add to “${c.currentLayer.name}”  ⏎',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: const ValueKey('paste-to-collection'),
                    onPressed: () =>
                        c.resolvePaste(toCollection: true, remember: remember),
                    child: const Text('Collection  C'),
                  ),
                ],
              ),
              SizedBox(
                height: 28,
                child: Row(
                  children: [
                    Checkbox(
                      value: remember,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setState(() => remember = v ?? false),
                    ),
                    const Flexible(
                      child: Text(
                        'Always do this (change it later in the menu)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CutoutBar extends StatelessWidget {
  const _CutoutBar({required this.c});
  final EditorController c;

  @override
  Widget build(BuildContext context) {
    final sel = c.single;
    return Material(
      key: const ValueKey('cutout-bar'),
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            const Icon(Icons.content_cut, size: 16, color: Color(0xFFFF6D00)),
            SegmentedButton<CutoutMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: CutoutMode.lasso, label: Text('Freehand')),
                ButtonSegment(value: CutoutMode.box, label: Text('Box')),
                ButtonSegment(
                  value: CutoutMode.wand,
                  label: Text('Remove colour'),
                ),
              ],
              selected: {c.cutoutMode},
              onSelectionChanged: (s) {
                c.cutoutMode = s.first;
                c.notify();
              },
            ),
            if (c.cutoutMode == CutoutMode.wand) ...[
              const Text('Match', style: TextStyle(fontSize: 12)),
              SizedBox(
                width: 120,
                child: Slider(
                  value: c.wandTolerance,
                  min: 0.02,
                  max: 0.5,
                  onChanged: (v) {
                    c.wandTolerance = v;
                    c.notify();
                  },
                ),
              ),
              FilterChip(
                label: const Text('Only touching'),
                selected: c.wandContiguous,
                visualDensity: VisualDensity.compact,
                onSelected: (v) {
                  c.wandContiguous = v;
                  c.notify();
                },
              ),
            ] else ...[
              Text(
                sel is ImageObject
                    ? 'Drag around the part to keep'
                    : 'Drag across an image',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7385)),
              ),
              FilterChip(
                label: const Text('Also remove it from the original'),
                selected: c.cutoutLeavesHole,
                visualDensity: VisualDensity.compact,
                onSelected: (v) {
                  c.cutoutLeavesHole = v;
                  c.notify();
                },
              ),
              if (c.cutoutLeavesHole) ...[
                const Text('Fill the gap', style: TextStyle(fontSize: 12)),
                SegmentedButton<HoleFill>(
                  key: const ValueKey('hole-fill'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: HoleFill.empty, label: Text('Empty')),
                    ButtonSegment(
                      value: HoleFill.blend,
                      label: Text('Blend in'),
                    ),
                    ButtonSegment(value: HoleFill.color, label: Text('Colour')),
                  ],
                  selected: {c.cutoutFill},
                  onSelectionChanged: (s) {
                    c.cutoutFill = s.first;
                    c.notify();
                  },
                ),
                if (c.cutoutFill == HoleFill.color)
                  SizedBox(
                    width: 190,
                    child: ColorRow(
                      value: c.cutoutFillColor,
                      onChanged: (v) {
                        c.cutoutFillColor = v;
                        c.notify();
                      },
                    ),
                  ),
              ],
            ],
            SmallIconButton(
              icon: Icons.close,
              tooltip: 'Done  Esc',
              onPressed: () => c.setTool(Tool.select),
            ),
          ],
        ),
      ),
    );
  }
}
