import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../model/scene.dart';
import 'controller.dart';
import 'render.dart';
import '../ui/design.dart';

/// Paints the page from the document, then the editing overlays on top.
class CanvasPainter extends CustomPainter {
  CanvasPainter(this.c) : super(repaint: c);
  final EditorController c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kWorkspace);
    final doc = c.doc;
    final page = Offset.zero & doc.canvasSize;

    canvas.save();
    canvas.translate(c.pan.dx, c.pan.dy);
    canvas.scale(c.zoom);

    // Page, with a soft shadow.
    canvas.drawRect(
      page.shift(Offset(0, 3 / c.zoom)).inflate(1 / c.zoom),
      Paint()
        ..color = kShadowSoft
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 / c.zoom),
    );
    paintPageBackground(canvas, doc);
    if (c.showGrid) _paintGrid(canvas, page);
    paintDocumentObjects(
      canvas,
      doc,
      c.assets,
      hidden: {if (c.editingTextId != null) c.editingTextId!},
      faded: c.removing,
    );
    final editing = c.editingTextId == null
        ? null
        : c.doc.objectById(c.editingTextId!);
    if (editing is TextObject && editing.visible) {
      paintTextFrame(canvas, editing);
    }
    canvas.drawRect(
      page,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / c.zoom
        ..color = kShadowSoft,
    );
    canvas.restore();

    _paintOverlays(canvas, size);
    _paintPickLoupe(canvas);
    _paintRemovePointer(canvas);
  }

  void _paintGrid(Canvas canvas, Rect page) {
    final g = c.doc.gridSize;
    if (g * c.zoom < 6) return;
    final p = Paint()
      ..color = kShadowFaint
      ..strokeWidth = 1 / c.zoom;
    for (double x = g; x < page.width; x += g) {
      canvas.drawLine(Offset(x, 0), Offset(x, page.height), p);
    }
    for (double y = g; y < page.height; y += g) {
      canvas.drawLine(Offset(0, y), Offset(page.width, y), p);
    }
  }

  Offset _s(Offset scene) => c.toScreen(scene);

  /// Page to screen, for paths.
  Float64List get _viewMatrix =>
      (Matrix4.identity()
            ..translateByDouble(c.pan.dx, c.pan.dy, 0, 1)
            ..scaleByDouble(c.zoom, c.zoom, 1, 1))
          .storage;

  void _paintOverlays(Canvas canvas, Size size) {
    _paintGrips(canvas);
    final accent = Paint()
      ..color = kAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final sel = c.selectedObjects;
    for (final o in sel) {
      _outline(canvas, o, accent);
    }
    if (sel.length > 1) {
      _dashedRect(
        canvas,
        Rect.fromPoints(
          _s(c.selectionBounds.topLeft),
          _s(c.selectionBounds.bottomRight),
        ).inflate(4),
        accent,
      );
    }
    // What a line's end is about to attach to.
    final hover = c.attachHover == null
        ? null
        : c.doc.objectById(c.attachHover!);
    if (hover is BoxObject) {
      _outline(
        canvas,
        hover,
        Paint()
          ..color = kAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    final one = c.single;
    if (one != null && !one.locked && c.editingTextId == null) {
      _paintHandles(canvas, one);
    }
    if (sel.isNotEmpty && c.editingTextId == null) {
      _paintLabel(canvas, sel, size);
    }

    if (c.marquee != null) {
      final r = Rect.fromPoints(
        _s(c.marquee!.topLeft),
        _s(c.marquee!.bottomRight),
      );
      canvas.drawRect(r, Paint()..color = kAccent.withValues(alpha: 0.10));
      canvas.drawRect(r, accent..strokeWidth = 1);
    }
    if (c.cutBox != null) {
      final r = Rect.fromPoints(
        _s(c.cutBox!.topLeft),
        _s(c.cutBox!.bottomRight),
      );
      _dashedRect(
        canvas,
        r,
        Paint()
          ..color = kCutLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (c.lasso != null && c.lasso!.length > 1) {
      final path = Path();
      final pts = c.lasso!.map(_s).toList();
      path.moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = kCutFill);
      _dashedPath(
        canvas,
        path,
        Paint()
          ..color = kCutLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _outline(Canvas canvas, SceneObject o, Paint accent) {
    if (o is BoxObject) {
      final pts = o.corners.map(_s).toList();
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(path, accent);
    } else if (o is LineObject) {
      canvas.drawPath(
        linePath(o).transform(_viewMatrix),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = kAccent.withValues(alpha: 0.35)
          ..strokeWidth = math.max(3, o.width * c.zoom + 4)
          ..strokeCap = StrokeCap.round,
      );
    } else {
      final b = o.bounds;
      _dashedRect(
        canvas,
        Rect.fromPoints(_s(b.topLeft), _s(b.bottomRight)).inflate(3),
        accent,
      );
    }
  }

  /// Remove marks' pointer: a ring the size of what it reaches, with a small
  /// cross in the middle, so it is clear what a sweep will catch.
  void _paintRemovePointer(Canvas canvas) {
    final at = c.pointerScreen;
    if (c.tool != Tool.remove || c.pickingColour || at == null) return;
    final r = c.removeRadius;
    final halo = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    final ink = Paint()
      ..color = kInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(at, r, Paint()..color = kWash);
    canvas.drawCircle(at, r, halo);
    canvas.drawCircle(at, r, ink);
    const k = 3.2;
    for (final p in [halo, ink]) {
      canvas.drawLine(at + const Offset(-k, -k), at + const Offset(k, k), p);
      canvas.drawLine(at + const Offset(-k, k), at + const Offset(k, -k), p);
    }
  }

  /// While the eyedropper is waiting: an eyedropper for a pointer, its tip
  /// on the spot that will be taken, and a round sample of the colour there.
  /// The dropper leans up and to the right, so the sample sits up and to the
  /// left where nothing covers it (and a right hand on a touchscreen doesn't
  /// either); near the top or left edge it moves round to stay in view.
  void _paintPickLoupe(Canvas canvas) {
    final at = c.pointerScreen;
    if (!c.pickingColour || at == null) return;
    final colour = c.pickHoverColour;
    if (colour != null) {
      final dx = at.dx < 48 ? 30.0 : -30.0;
      final dy = at.dy < 48 ? 30.0 : -30.0;
      final centre = at + Offset(dx, dy);
      canvas.drawCircle(
        centre,
        17,
        Paint()
          ..color = kShadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(centre, 16, Paint()..color = Colors.white);
      canvas.drawCircle(centre, 12.5, Paint()..color = Color(colour));
      canvas.drawCircle(
        centre,
        12.5,
        Paint()
          ..color = kShadowSoft
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    // The Material "colorize" glyph has its tip about (3, 21) into its 24px
    // box; drawn with a white edge so it shows on dark and light alike.
    const icon = Icons.colorize, px = 22.0;
    final origin = at - const Offset(3, 21) * (px / 24);
    for (final edge in [true, false]) {
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: px,
            height: 1,
            foreground: edge
                ? (Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..strokeJoin = StrokeJoin.round
                    ..color = Colors.white)
                : (Paint()..color = kInk),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, origin);
      tp.dispose();
    }
  }

  void _paintHandles(Canvas canvas, SceneObject o) {
    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = kAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    // Fingers need bigger things to hit than a mouse pointer does.
    final k = c.touchInput ? 1.7 : 1.0;
    for (final h in c.handlesFor(o)) {
      final p = _s(h.pos);
      if (h.kind == HandleKind.rotate && o is BoxObject) {
        final top = _s(o.toScene(Offset(0, -o.size.height / 2)));
        canvas.drawLine(top, p, stroke);
        canvas.drawCircle(p, 6 * k, fill);
        canvas.drawCircle(p, 6 * k, stroke);
        // little arc to hint at rotation
        canvas.drawArc(
          Rect.fromCircle(center: p, radius: 3 * k),
          -2.4,
          4.4,
          false,
          stroke..strokeWidth = 1.2,
        );
        stroke.strokeWidth = 1.5;
      } else if (h.kind == HandleKind.lineStart ||
          h.kind == HandleKind.lineEnd) {
        // An end that is attached to something is filled in.
        final attached =
            o is LineObject &&
            (h.kind == HandleKind.lineStart ? o.start : o.end) != null;
        canvas.drawCircle(
          p,
          6.5 * k,
          attached ? (Paint()..color = kAccent) : fill,
        );
        canvas.drawCircle(p, 6.5 * k, stroke);
      } else if (h.kind == HandleKind.lineBend) {
        // A small diamond in the middle: pull it to bend the line.
        final r = 5.5 * k;
        final d = Path()
          ..moveTo(p.dx, p.dy - r)
          ..lineTo(p.dx + r, p.dy)
          ..lineTo(p.dx, p.dy + r)
          ..lineTo(p.dx - r, p.dy)
          ..close();
        canvas.drawPath(d, fill);
        canvas.drawPath(d, stroke);
      } else {
        final r = Rect.fromCenter(center: p, width: 9 * k, height: 9 * k);
        canvas.drawRect(r, fill);
        canvas.drawRect(r, stroke);
      }
    }
  }

  /// The three handles on the page's edge: a white pill on each side and a
  /// round one at the corner, with a few dots so they read as things to hold.
  /// They light up under the pointer and while being dragged.
  void _paintGrips(Canvas canvas) {
    for (final e in c.gripPositions.entries) {
      final p = _s(e.value);
      final hot = c.hoverGrip == e.key || c.draggingGrip == e.key;
      final edge = hot ? kAccent : kOutline;
      final ink = hot ? kAccent : kInkFaint;
      final fill = Paint()..color = hot ? kAccentSoft : Colors.white;
      final line = Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = hot ? 1.4 : 1;
      final shadow = Paint()
        ..color = kShadowSoft
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      final dot = Paint()..color = ink;
      switch (e.key) {
        case CanvasGrip.right || CanvasGrip.bottom:
          final vertical = e.key == CanvasGrip.right;
          final r = Rect.fromCenter(
            center: p + (vertical ? const Offset(8, 0) : const Offset(0, 8)),
            width: vertical ? 10 : 42,
            height: vertical ? 42 : 10,
          );
          final rr = RRect.fromRectAndRadius(r, const Radius.circular(kRadius));
          canvas.drawRRect(rr.shift(const Offset(0, 1)), shadow);
          canvas.drawRRect(rr, fill);
          canvas.drawRRect(rr, line);
          for (final d in [-6.0, 0.0, 6.0]) {
            canvas.drawCircle(
              r.center + (vertical ? Offset(0, d) : Offset(d, 0)),
              1.3,
              dot,
            );
          }
        case CanvasGrip.corner:
          final centre = p + const Offset(9, 9);
          canvas.drawCircle(centre + const Offset(0, 1), 8.5, shadow);
          canvas.drawCircle(centre, 8.5, fill);
          canvas.drawCircle(centre, 8.5, line);
          // Two short diagonal strokes, the usual "resize" mark.
          final mark = Paint()
            ..color = ink
            ..strokeWidth = 1.2
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            centre + const Offset(-3.5, 3.5),
            centre + const Offset(3.5, -3.5),
            mark,
          );
          canvas.drawLine(
            centre + const Offset(0.5, 3.5),
            centre + const Offset(3.5, 0.5),
            mark,
          );
      }
    }
  }

  void _paintLabel(Canvas canvas, List<SceneObject> sel, Size size) {
    final tag = selectionTag(c, size);
    if (tag == null) return;
    final tp = _tagText(tag.text)..layout(maxWidth: _tagTextMax);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tag.tag, const Radius.circular(kRadius)),
      Paint()..color = kAccent,
    );
    tp.paint(canvas, tag.tag.topLeft + const Offset(7, 3));
    tp.dispose();
    // A hairline between the name and the padlock, which is a button laid
    // over the tag by the canvas view.
    canvas.drawLine(
      Offset(tag.lock.left, tag.tag.top + 4),
      Offset(tag.lock.left, tag.tag.bottom - 4),
      Paint()
        ..color = kOnAccentLine
        ..strokeWidth = 1,
    );
  }

  void _dashedRect(Canvas canvas, Rect r, Paint p) =>
      _dashedPath(canvas, Path()..addRect(r), p);

  void _dashedPath(Canvas canvas, Path path, Paint p) {
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(m.length, d + 6)), p);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CanvasPainter old) => true;
}

const double _tagTextMax = 260;
const double kTagLockWidth = 22;

TextPainter _tagText(String text) => TextPainter(
  text: TextSpan(
    text: text,
    style: const TextStyle(
      fontFamily: kUiFont,
      color: Colors.white,
      fontSize: kTextCaption,
      fontWeight: kWeightStrong,
    ),
  ),
  textDirection: TextDirection.ltr,
);

/// Where the selection's name tag sits on screen (in a view of [size]), and
/// the padlock button at its end. Null when nothing is selected or a text is
/// being typed.
({Rect tag, Rect lock, String text})? selectionTag(
  EditorController c,
  Size size,
) {
  final sel = c.selectedObjects;
  if (sel.isEmpty || c.editingTextId != null) return null;
  final String text;
  if (sel.length == 1) {
    final l = c.doc.layerOf(sel.first.id);
    text = '${sel.first.name} · ${l?.name ?? ''}';
  } else {
    text = '${sel.length} objects';
  }
  final tp = _tagText(text)..layout(maxWidth: _tagTextMax);
  final w = tp.width + 14 + kTagLockWidth, h = tp.height + 6;
  tp.dispose();
  final b = c.selectionBounds;
  var anchor = c.toScreen(b.topLeft);
  final one = sel.length == 1 ? sel.first : null;
  if (one is BoxObject) {
    anchor = c.toScreen(
      one.corners.reduce(
        (a, b) => (a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx)) ? a : b,
      ),
    );
  }
  var pos = anchor + Offset(0, -h - 8);
  // Clear the rotate handle, and stay put when locking hides it, so the
  // padlock is still under the pointer to click again.
  if (one is BoxObject) pos += const Offset(0, -34);
  pos = Offset(
    pos.dx.clamp(4, math.max(4, size.width - w - 4)),
    pos.dy < 4 ? anchor.dy + 10 : pos.dy,
  );
  final tag = Rect.fromLTWH(pos.dx, pos.dy, w, h);
  return (
    tag: tag,
    lock: Rect.fromLTRB(
      tag.right - kTagLockWidth,
      tag.top,
      tag.right,
      tag.bottom,
    ),
    text: text,
  );
}
