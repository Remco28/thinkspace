import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/scene.dart';
import 'canvas_painter.dart';
import 'controller.dart';
import 'interactor.dart';
import '../ui/context_menu.dart';
import '../ui/widgets.dart' show KeyCap;
import 'render.dart';
import '../ui/design.dart';

class CollectionDrag {
  const CollectionDrag(this.itemId);
  final String itemId;
}

class ObjectDrag {
  const ObjectDrag(this.ids);
  final List<String> ids;
}

Modifiers currentModifiers() => Modifiers(
  shift: HardwareKeyboard.instance.isShiftPressed,
  ctrl:
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed,
  alt: HardwareKeyboard.instance.isAltPressed,
);

class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.controller,
    required this.interactor,
    required this.spaceDown,
    this.focusNode,
  });
  final FocusNode? focusNode;
  final EditorController controller;
  final CanvasInteractor interactor;
  final ValueNotifier<bool> spaceDown;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  EditorController get c => widget.controller;
  CanvasInteractor get ix => widget.interactor;
  MouseCursor _cursor = SystemMouseCursors.basic;
  final _key = GlobalKey();
  Offset? _rightDown;
  bool _rightMoved = false;

  /// The press that answered the eyedropper; its release is not a click.
  int? _pickPointer;

  // ---- fingers --------------------------------------------------------------
  // One finger does what the mouse does. A second finger turns the gesture
  // into moving and zooming the page (whatever the first one started is
  // taken back), and holding a finger still opens the right-click menu.
  final Map<int, Offset> _touches = {};
  bool _navigating = false;
  Offset _navCentre = Offset.zero;
  double _navDist = 1;
  Timer? _longPress;
  Offset? _pressStart;

  @override
  void dispose() {
    _longPress?.cancel();
    super.dispose();
  }

  void _beginNavigation() {
    final ids = _touches.keys.take(2).toList();
    final a = _touches[ids[0]]!, b = _touches[ids[1]]!;
    _navCentre = (a + b) / 2;
    _navDist = (a - b).distance;
  }

  void _navigate() {
    final ids = _touches.keys.take(2).toList();
    if (ids.length < 2) return;
    final a = _touches[ids[0]]!, b = _touches[ids[1]]!;
    final centre = (a + b) / 2;
    final dist = (a - b).distance;
    c.panBy(centre - _navCentre);
    if (dist > 1 && _navDist > 1) {
      c.zoomTo(c.zoom * dist / _navDist, anchorScreen: centre);
    }
    _navCentre = centre;
    _navDist = dist;
  }

  void _longPressed(Offset local, Offset global) {
    if (!mounted || _navigating || _touches.isEmpty) return;
    ix.cancel(); // the press was not the start of a drag after all
    final hits = c.objectsAt(c.toScene(local));
    if (hits.isNotEmpty && !c.selection.contains(hits.first.id)) {
      c.select([hits.first.id]);
    }
    if (hits.isEmpty) c.clearSelection();
    showObjectMenu(context, c, global);
  }

  /// The eyedropper and Remove marks draw their own pointer, so the painter
  /// needs to know where it is.
  void _trackPointer(Offset at) {
    if (!c.pickingColour && c.tool != Tool.remove) return;
    c.pointerScreen = at;
    if (c.pickingColour) c.pickHoverColour = c.colourAt(c.toScene(at));
    c.notify();
  }

  void _hover(PointerHoverEvent e) {
    _trackPointer(e.localPosition);
    final g = ix.gripAt(e.localPosition);
    if (g != c.hoverGrip) {
      c.hoverGrip = g;
      c.notify();
    }
    final cur = ix.cursorAt(e.localPosition, spaceDown: widget.spaceDown.value);
    if (cur != _cursor) setState(() => _cursor = cur);
  }

  /// The merge / unmerge pill appears beside a resting selection, never in
  /// the middle of a drag, a text edit or a paste decision.
  bool get _showActions =>
      c.tool == Tool.select &&
      !ix.active &&
      c.editingTextId == null &&
      c.pendingPaste == null &&
      c.selection.isNotEmpty &&
      (c.mergeParts.length > 1 || c.canUnmerge);

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => d.data is CollectionDrag,
      onAcceptWithDetails: (d) {
        final box = _key.currentContext!.findRenderObject() as RenderBox;
        final local = box.globalToLocal(d.offset);
        final data = d.data;
        if (data is CollectionDrag) {
          c.placeCollectionItem(data.itemId, at: c.toScene(local));
        }
      },
      builder: (context, candidate, rejected) => LayoutBuilder(
        key: _key,
        builder: (context, box) {
          c.setViewport(box.biggest);
          return ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: MouseRegion(
                    cursor: _cursor,
                    onHover: _hover,
                    onExit: (_) {
                      if (c.pointerScreen == null) return;
                      c.pointerScreen = null;
                      c.notify();
                    },
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) {
                        widget.focusNode?.requestFocus();
                        final touch = e.kind == PointerDeviceKind.touch;
                        c.touchInput = touch;
                        if (touch) {
                          _touches[e.pointer] = e.localPosition;
                          if (_touches.length >= 2) {
                            _longPress?.cancel();
                            if (!_navigating) {
                              ix.cancel();
                              _navigating = true;
                              _beginNavigation();
                            }
                            return;
                          }
                        }
                        if (c.pickingColour) {
                          // The eyedropper takes this click: the selection
                          // and the tool stay as they were.
                          _pickPointer = e.pointer;
                          c.finishColourPick(
                            e.buttons == kPrimaryButton
                                ? c.colourAt(c.toScene(e.localPosition))
                                : null,
                          );
                          return;
                        }
                        c.endListWalk();
                        // Starting to draw is also "Start" for the cut-out options.
                        if (c.cutoutOptionsOpen) {
                          c.cutoutOptionsOpen = false;
                          c.notify();
                        }
                        if (c.selectedCollectionId != null) {
                          c.selectCollectionItem(null);
                        }
                        final right = e.buttons == kSecondaryMouseButton;
                        final pan =
                            e.buttons == kMiddleMouseButton ||
                            widget.spaceDown.value ||
                            right;
                        _rightDown = right ? e.localPosition : null;
                        _rightMoved = false;
                        ix.pointerDown(
                          e.localPosition,
                          currentModifiers(),
                          forcePan: pan,
                        );
                        _longPress?.cancel();
                        if (touch && c.tool == Tool.select) {
                          _pressStart = e.localPosition;
                          final local = e.localPosition, global = e.position;
                          _longPress = Timer(
                            const Duration(milliseconds: 550),
                            () => _longPressed(local, global),
                          );
                        }
                      },
                      onPointerMove: (e) {
                        if (e.pointer == _pickPointer) return;
                        if (e.kind == PointerDeviceKind.touch) {
                          _touches[e.pointer] = e.localPosition;
                          if (_navigating) {
                            _navigate();
                            return;
                          }
                          if (_pressStart != null &&
                              (e.localPosition - _pressStart!).distance > 10) {
                            _longPress?.cancel();
                          }
                        }
                        if (_rightDown != null &&
                            (e.localPosition - _rightDown!).distance > 4) {
                          _rightMoved = true;
                        }
                        ix.pointerMove(e.localPosition, currentModifiers());
                        _trackPointer(e.localPosition);
                        final cur = ix.cursorAt(
                          e.localPosition,
                          spaceDown: widget.spaceDown.value,
                        );
                        if (cur != _cursor) setState(() => _cursor = cur);
                      },
                      onPointerUp: (e) {
                        if (e.pointer == _pickPointer) {
                          _pickPointer = null;
                          return;
                        }
                        if (e.kind == PointerDeviceKind.touch) {
                          _touches.remove(e.pointer);
                          _longPress?.cancel();
                          if (_navigating) {
                            // Lifting fingers one by one never starts a
                            // drag with the one that is left.
                            if (_touches.isEmpty) _navigating = false;
                            return;
                          }
                        }
                        ix.pointerUp(e.localPosition, currentModifiers());
                        final rd = _rightDown;
                        _rightDown = null;
                        if (rd != null && !_rightMoved) {
                          // Right-click without dragging: a menu for what's under the pointer.
                          final hits = c.objectsAt(c.toScene(rd));
                          if (hits.isNotEmpty &&
                              !c.selection.contains(hits.first.id)) {
                            c.select([hits.first.id]);
                          }
                          if (hits.isEmpty) c.clearSelection();
                          showObjectMenu(context, c, e.position);
                        }
                      },
                      onPointerCancel: (e) {
                        _touches.remove(e.pointer);
                        _longPress?.cancel();
                        if (_touches.isEmpty) _navigating = false;
                        ix.cancel();
                      },
                      onPointerSignal: (e) {
                        if (e is PointerScrollEvent) {
                          ix.scroll(
                            e.localPosition,
                            e.scrollDelta,
                            currentModifiers(),
                          );
                        }
                      },
                      onPointerPanZoomUpdate: (e) {
                        if (e.scale != 1) {
                          c.zoomTo(
                            c.zoom * (1 + (e.scale - 1) * 0.05),
                            anchorScreen: e.localPosition,
                          );
                        }
                        c.panBy(e.panDelta);
                      },
                      child: CustomPaint(
                        painter: CanvasPainter(c),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
                if (_showActions)
                  _SelectionActions(
                    c: c,
                    area: box.biggest,
                    refocus: () => widget.focusNode?.requestFocus(),
                  ),
                if (selectionTag(c, box.biggest) case final tag?)
                  _TagLock(
                    c: c,
                    rect: tag.lock,
                    refocus: () => widget.focusNode?.requestFocus(),
                  ),
                if (c.editingTextId != null)
                  _TextEditorOverlay(c: c, key: ValueKey(c.editingTextId)),
                if (candidate.isNotEmpty)
                  IgnorePointer(
                    child: Container(color: kAccent.withValues(alpha: 0.06)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A real text field positioned exactly over the text object, in the same
/// zoomed and rotated space, so editing happens on the page itself.
class _TextEditorOverlay extends StatefulWidget {
  const _TextEditorOverlay({super.key, required this.c});
  final EditorController c;

  @override
  State<_TextEditorOverlay> createState() => _TextEditorOverlayState();
}

class _TextEditorOverlayState extends State<_TextEditorOverlay> {
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();

  EditorController get c => widget.c;

  @override
  void initState() {
    super.initState();
    final t = c.doc.objectById(c.editingTextId!) as TextObject;
    _text = TextEditingController(text: t.text);
    _text.selection = TextSelection(baseOffset: 0, extentOffset: t.text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = c.doc.objectById(c.editingTextId ?? '');
    if (t is! TextObject) return const SizedBox.shrink();
    final m = Matrix4.identity()
      ..translateByDouble(c.pan.dx, c.pan.dy, 0, 1)
      ..scaleByDouble(c.zoom, c.zoom, 1, 1)
      ..translateByDouble(t.center.dx, t.center.dy, 0, 1)
      ..rotateZ(t.rotation)
      ..translateByDouble(-t.size.width / 2, -t.size.height / 2, 0, 1);
    return Positioned(
      left: 0,
      top: 0,
      child: Transform(
        transform: m,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: t.size.width,
          height: t.size.height,
          child: Focus(
            onKeyEvent: (node, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.escape) {
                c.finishTextEdit();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _text,
              focusNode: _focus,
              key: const ValueKey('text-editor'),
              maxLines: null,
              style: textStyleFor(t),
              textAlign: t.align,
              cursorColor: kAccent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                filled: t.background != 0,
                fillColor: Color(t.background),
                contentPadding: const EdgeInsets.all(TextObject.pad),
              ),
              onChanged: c.updateEditingText,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small pill just under the selection with the one thing you most likely
/// want to do with it: merge several things into one picture, or take a
/// merged picture apart again. It carries its shortcut key, like the toolbar.
class _SelectionActions extends StatelessWidget {
  const _SelectionActions({
    required this.c,
    required this.area,
    required this.refocus,
  });
  final EditorController c;
  final Size area;
  final VoidCallback refocus;

  static const double _h = 30;
  static const _labelStyle = TextStyle(
    fontFamily: kUiFont,
    fontSize: kTextBody,
    fontWeight: kWeightStrong,
    color: kInk,
  );

  @override
  Widget build(BuildContext context) {
    final merge = !c.canUnmerge;
    final b = c.selectionBounds;
    final bottom = c.toScreen(b.bottomCenter);
    // Below the selection and its handles; pulled inside the view if the
    // selection runs off the bottom or the sides.
    // As wide as its label needs, measured in the font it is drawn in, so a
    // different font or wording never wraps it.
    final label = merge ? 'Merge into one image' : 'Unmerge';
    final tp = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = kSpace12 + kIcon + kSpace8 + tp.width + kSpace8 + 22 + kSpace8;
    tp.dispose();
    final left = (bottom.dx - w / 2)
        .clamp(8.0, math.max(8.0, area.width - w - 8))
        .toDouble();
    final top = (bottom.dy + 18)
        .clamp(8.0, math.max(8.0, area.height - _h - 12))
        .toDouble();
    return Positioned(
      left: left,
      top: top,
      child: Material(
        key: const ValueKey('selection-actions'),
        color: Colors.white,
        elevation: 3,
        shadowColor: kShadow,
        borderRadius: BorderRadius.circular(_h / 2),
        child: InkWell(
          key: ValueKey(merge ? 'quick-merge' : 'quick-unmerge'),
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(_h / 2),
          onTap: () {
            if (merge) {
              c.flattenSelection();
            } else {
              c.unmerge();
            }
            refocus();
          },
          child: Container(
            width: w,
            height: _h,
            padding: const EdgeInsets.only(left: kSpace12, right: kSpace8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_h / 2),
              border: Border.all(color: kBorder),
            ),
            child: Row(
              children: [
                Icon(
                  merge ? Icons.layers_clear_outlined : Icons.call_split,
                  size: kIcon,
                  color: kAccent,
                ),
                const SizedBox(width: kSpace8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: _labelStyle,
                  ),
                ),
                KeyCap(merge ? 'M' : 'U', compact: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The padlock at the end of the selection's name tag: one click locks it in
/// place (or unlocks it), without the right-click menu.
class _TagLock extends StatelessWidget {
  const _TagLock({required this.c, required this.rect, required this.refocus});
  final EditorController c;
  final Rect rect;
  final VoidCallback refocus;

  @override
  Widget build(BuildContext context) {
    final locked = c.selectionLocked;
    return Positioned.fromRect(
      rect: rect,
      child: Tooltip(
        message: locked ? 'Unlock  (Ctrl+L)' : 'Lock in place  (Ctrl+L)',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('tag-lock'),
            canRequestFocus: false,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(kRadius),
            ),
            hoverColor: kOnAccentHover,
            onTap: () {
              c.toggleLockSelection();
              refocus();
            },
            child: Center(
              child: Icon(
                locked ? Icons.lock : Icons.lock_open_outlined,
                size: kIconSmall,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
