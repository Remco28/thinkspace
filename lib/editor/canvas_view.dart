import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/scene.dart';
import 'canvas_painter.dart';
import 'controller.dart';
import 'interactor.dart';
import '../ui/context_menu.dart';
import 'render.dart';

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

  void _hover(PointerHoverEvent e) {
    final cur = ix.cursorAt(e.localPosition, spaceDown: widget.spaceDown.value);
    if (cur != _cursor) setState(() => _cursor = cur);
  }

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
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) {
                        widget.focusNode?.requestFocus();
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
                      },
                      onPointerMove: (e) {
                        if (_rightDown != null &&
                            (e.localPosition - _rightDown!).distance > 4) {
                          _rightMoved = true;
                        }
                        ix.pointerMove(e.localPosition, currentModifiers());
                        final cur = ix.cursorAt(
                          e.localPosition,
                          spaceDown: widget.spaceDown.value,
                        );
                        if (cur != _cursor) setState(() => _cursor = cur);
                      },
                      onPointerUp: (e) {
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
                      onPointerCancel: (e) => ix.cancel(),
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
