import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dev/inspector.dart';
import '../editor/canvas_view.dart';
import '../editor/canvas_painter.dart' show kAccent;
import '../editor/controller.dart';
import '../editor/interactor.dart';
import '../io/files.dart';
import '../io/paths.dart';
import '../io/prefs.dart';
import '../model/scene.dart';
import 'collection_panel.dart';
import 'cutout_card.dart';
import 'kit.dart' show kMuted;
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

  /// How much of the right column the Layers list takes; the rest is the
  /// settings panel. Dragged with the handle between them and remembered.
  double layersFraction = _defaultLayersFraction;
  static const double _defaultLayersFraction = 0.42;
  Prefs _prefs = Prefs(null);
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
      final data = appDataDir(
        Platform.environment,
        windows: Platform.isWindows,
      );
      if (data != null) {
        _prefs = Prefs(File('$data${Platform.pathSeparator}prefs.json'));
        layersFraction = _prefs.layersFraction ?? layersFraction;
      }
      c.recoveryFile =
          widget.recoveryFile ??
          (data == null
              ? null
              : File('$data${Platform.pathSeparator}recovery.thinkspace'));
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

    if (c.tool == Tool.cutout && c.cutoutOptionsOpen) {
      if (k == LogicalKeyboardKey.enter) {
        c.cutoutOptionsOpen = false;
        c.notify();
        return KeyEventResult.handled;
      }
    }

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
        } else if (c.bgSessionObject != null) {
          c.endBgSession();
        } else if (c.tool != Tool.select) {
          c.setTool(Tool.select);
        } else if (c.selectedCollectionId != null) {
          c.selectCollectionItem(null);
        } else {
          c.clearSelection();
        }
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        final item = c.selectedCollectionId;
        item != null ? c.removeFromCollection(item) : c.deleteSelection();
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
        final item = c.selectedCollectionId;
        if (item != null) {
          k == LogicalKeyboardKey.enter
              ? c.placeCollectionItem(item)
              : c.beginCollectionRename(item);
          return KeyEventResult.handled;
        }
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
        c.selectedCollectionId != null
            ? c.shiftCollectionItem(1)
            : c.reorderSelection('forward');
      case LogicalKeyboardKey.bracketLeft:
        c.selectedCollectionId != null
            ? c.shiftCollectionItem(-1)
            : c.reorderSelection('backward');
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
                            child: LayoutBuilder(
                              builder: (context, box) {
                                const handle = 9.0, minLayers = 110.0;
                                const minSettings = 190.0;
                                final total = box.maxHeight - handle;
                                final layersH = (total * layersFraction)
                                    .clamp(
                                      minLayers,
                                      math.max(minLayers, total - minSettings),
                                    )
                                    .toDouble();
                                return Column(
                                  children: [
                                    SizedBox(
                                      height: layersH,
                                      child: LayersPanel(controller: c),
                                    ),
                                    _HSplitter(
                                      onDrag: (dy) => setState(
                                        // From the current fraction, not from this
                                        // build's height: several drag events can
                                        // arrive before the next rebuild.
                                        () => layersFraction =
                                            (layersFraction.clamp(
                                                      minLayers / total,
                                                      math.max(
                                                        minLayers / total,
                                                        (total - minSettings) /
                                                            total,
                                                      ),
                                                    ) +
                                                    dy / total)
                                                .clamp(
                                                  minLayers / total,
                                                  math.max(
                                                    minLayers / total,
                                                    (total - minSettings) /
                                                        total,
                                                  ),
                                                )
                                                .toDouble(),
                                      ),
                                      onEnd: _savePrefs,
                                      onReset: () {
                                        setState(
                                          () => layersFraction =
                                              _defaultLayersFraction,
                                        );
                                        _savePrefs();
                                      },
                                    ),
                                    Expanded(
                                      child: PropertiesPanel(controller: c),
                                    ),
                                  ],
                                );
                              },
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

  void _savePrefs() {
    _prefs.layersFraction = layersFraction;
    _prefs.save();
  }

  /// The hint sits in the middle of the part of the page you can see, so it
  /// is centred on the page wherever the page is.
  Widget _emptyHint() {
    final page = Rect.fromLTWH(
      c.pan.dx,
      c.pan.dy,
      c.doc.canvasSize.width * c.zoom,
      c.doc.canvasSize.height * c.zoom,
    );
    final seen = page.intersect(Offset.zero & c.viewport);
    if (seen.width < 260 || seen.height < 60) return const SizedBox.shrink();
    return Positioned.fromRect(
      rect: seen,
      child: const IgnorePointer(child: Center(child: _EmptyHint())),
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
          if (c.tool == Tool.cutout && !c.cutoutOptionsOpen)
            Positioned(
              top: 8,
              left: 52,
              right: 8,
              child: Align(
                alignment: Alignment.topCenter,
                child: CutoutPill(c: c),
              ),
            ),
          if (c.tool == Tool.cutout && c.cutoutOptionsOpen)
            Positioned.fill(
              child: Center(child: CutoutCard(c: c)),
            ),
          if (c.bgSessionObject != null && c.tool == Tool.select)
            Positioned(
              top: 8,
              left: 52,
              right: 8,
              child: Align(
                alignment: Alignment.topCenter,
                child: _BackgroundBar(c: c),
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
            _emptyHint(),
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
  Widget build(BuildContext context) => const Text(
    'Paste a picture (Ctrl+V), drop a file here,\nor press A to draw an arrow',
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 15, height: 1.5, color: Color(0xFFA0A6B5)),
  );
}

/// The handle between the Layers list and the settings below it.
class _HSplitter extends StatefulWidget {
  const _HSplitter({
    required this.onDrag,
    required this.onEnd,
    required this.onReset,
  });
  final void Function(double dy) onDrag;
  final VoidCallback onEnd, onReset;

  @override
  State<_HSplitter> createState() => _HSplitterState();
}

class _HSplitterState extends State<_HSplitter> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeRow,
    onEnter: (_) => setState(() => _hot = true),
    onExit: (_) => setState(() => _hot = false),
    child: GestureDetector(
      key: const ValueKey('layers-splitter'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => widget.onDrag(d.delta.dy),
      onVerticalDragEnd: (_) => widget.onEnd(),
      onDoubleTap: widget.onReset,
      child: Container(
        height: 9,
        color: kPanel,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Divider(height: 1, color: kBorder),
            // A little grip, so it reads as something to hold.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hot ? 1 : 0.55,
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: _hot
                      ? const Color(0xFF9AA0AE)
                      : const Color(0xFFC3C8D3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
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

/// Shown right after a background was removed: how much counts as
/// background, and whether the gaps inside the picture go too.
class _BackgroundBar extends StatelessWidget {
  const _BackgroundBar({required this.c});
  final EditorController c;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('background-bar'),
    elevation: 3,
    borderRadius: BorderRadius.circular(10),
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          const Icon(Icons.auto_fix_high, size: 16, color: kAccent),
          const Text(
            'Background removed',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          Tooltip(
            message:
                'How different from the background a colour can be and still go. '
                'More takes light greys and shadows too, but can start eating into the picture.',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Less',
                  style: TextStyle(fontSize: 12, color: kMuted),
                ),
                SizedBox(
                  width: 140,
                  child: Slider(
                    key: const ValueKey('background-amount'),
                    value: c.wandTolerance,
                    min: 0.02,
                    max: 0.5,
                    onChanged: (v) {
                      c.wandTolerance = v;
                      c.adjustBackground();
                    },
                  ),
                ),
                const Text(
                  'More',
                  style: TextStyle(fontSize: 12, color: kMuted),
                ),
              ],
            ),
          ),
          Tooltip(
            message:
                'Also clear background-coloured gaps the outside cannot reach, '
                'like the space inside an outline or between branches.',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 24,
                  child: Transform.scale(
                    scale: 0.72,
                    child: Switch(
                      key: const ValueKey('background-enclosed'),
                      value: c.bgInside,
                      onChanged: (v) {
                        c.bgInside = v;
                        c.adjustBackground();
                      },
                    ),
                  ),
                ),
                const Text(
                  'Include enclosed areas',
                  style: TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            key: const ValueKey('background-done'),
            onPressed: c.endBgSession,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}
