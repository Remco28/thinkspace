import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/scene.dart';
import 'controller.dart';
import 'render.dart';

const Color kAccent = Color(0xFF2F6BFF);
const Color kWorkspace = Color(0xFFE4E6EB);

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
        ..color = const Color(0x33000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 / c.zoom),
    );
    paintPageBackground(canvas, doc);
    if (c.showGrid) _paintGrid(canvas, page);
    paintDocumentObjects(canvas, doc, c.assets, hidden: {if (c.editingTextId != null) c.editingTextId!});
    canvas.drawRect(
      page,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / c.zoom
        ..color = const Color(0x33000000),
    );
    canvas.restore();

    _paintOverlays(canvas, size);
  }

  void _paintGrid(Canvas canvas, Rect page) {
    final g = c.doc.gridSize;
    if (g * c.zoom < 6) return;
    final p = Paint()
      ..color = const Color(0x1F000000)
      ..strokeWidth = 1 / c.zoom;
    for (double x = g; x < page.width; x += g) {
      canvas.drawLine(Offset(x, 0), Offset(x, page.height), p);
    }
    for (double y = g; y < page.height; y += g) {
      canvas.drawLine(Offset(0, y), Offset(page.width, y), p);
    }
  }

  Offset _s(Offset scene) => c.toScreen(scene);

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
      _dashedRect(canvas, Rect.fromPoints(_s(c.selectionBounds.topLeft), _s(c.selectionBounds.bottomRight)).inflate(4), accent);
    }
    final one = c.single;
    if (one != null && !one.locked && c.editingTextId == null) _paintHandles(canvas, one);
    if (sel.isNotEmpty && c.editingTextId == null) _paintLabel(canvas, sel, size);

    if (c.marquee != null) {
      final r = Rect.fromPoints(_s(c.marquee!.topLeft), _s(c.marquee!.bottomRight));
      canvas.drawRect(r, Paint()..color = kAccent.withValues(alpha: 0.10));
      canvas.drawRect(r, accent..strokeWidth = 1);
    }
    if (c.cutBox != null) {
      final r = Rect.fromPoints(_s(c.cutBox!.topLeft), _s(c.cutBox!.bottomRight));
      _dashedRect(canvas, r, Paint()
        ..color = const Color(0xFFFF6D00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    if (c.lasso != null && c.lasso!.length > 1) {
      final path = Path();
      final pts = c.lasso!.map(_s).toList();
      path.moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0x22FF6D00));
      _dashedPath(canvas, path, Paint()
        ..color = const Color(0xFFFF6D00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  void _outline(Canvas canvas, SceneObject o, Paint accent) {
    if (o is BoxObject) {
      final pts = o.corners.map(_s).toList();
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(path, accent);
    } else if (o is LineObject) {
      canvas.drawLine(_s(o.p1), _s(o.p2), Paint()
        ..color = kAccent.withValues(alpha: 0.35)
        ..strokeWidth = math.max(3, o.width * c.zoom + 4)
        ..strokeCap = StrokeCap.round);
    } else {
      final b = o.bounds;
      _dashedRect(canvas, Rect.fromPoints(_s(b.topLeft), _s(b.bottomRight)).inflate(3), accent);
    }
  }

  void _paintHandles(Canvas canvas, SceneObject o) {
    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = kAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final h in c.handlesFor(o)) {
      final p = _s(h.pos);
      if (h.kind == HandleKind.rotate && o is BoxObject) {
        final top = _s(o.toScene(Offset(0, -o.size.height / 2)));
        canvas.drawLine(top, p, stroke);
        canvas.drawCircle(p, 6, fill);
        canvas.drawCircle(p, 6, stroke);
        // little arc to hint at rotation
        canvas.drawArc(Rect.fromCircle(center: p, radius: 3), -2.4, 4.4, false, stroke..strokeWidth = 1.2);
        stroke.strokeWidth = 1.5;
      } else if (h.kind == HandleKind.lineStart || h.kind == HandleKind.lineEnd) {
        canvas.drawCircle(p, 6.5, fill);
        canvas.drawCircle(p, 6.5, stroke);
      } else {
        final r = Rect.fromCenter(center: p, width: 9, height: 9);
        canvas.drawRect(r, fill);
        canvas.drawRect(r, stroke);
      }
    }
  }

  void _paintGrips(Canvas canvas) {
    final fill = Paint()..color = const Color(0xFFB8BDC9);
    final line = Paint()
      ..color = const Color(0xFF8C93A3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final e in c.gripPositions.entries) {
      final p = _s(e.value);
      final Rect r;
      switch (e.key) {
        case CanvasGrip.right:
          r = Rect.fromCenter(center: p + const Offset(5, 0), width: 8, height: 36);
        case CanvasGrip.bottom:
          r = Rect.fromCenter(center: p + const Offset(0, 5), width: 36, height: 8);
        case CanvasGrip.corner:
          r = Rect.fromCenter(center: p + const Offset(6, 6), width: 12, height: 12);
      }
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, line);
    }
  }

  void _paintLabel(Canvas canvas, List<SceneObject> sel, Size size) {
    final String text;
    if (sel.length == 1) {
      final l = c.doc.layerOf(sel.first.id);
      text = '${sel.first.name} · ${l?.name ?? ''}';
    } else {
      text = '${sel.length} objects';
    }
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 260);
    final b = c.selectionBounds;
    var anchor = _s(b.topLeft);
    if (sel.length == 1 && sel.first is BoxObject) {
      final o = sel.first as BoxObject;
      anchor = _s(o.corners.reduce((a, b) => (a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx)) ? a : b));
    }
    final w = tp.width + 14, h = tp.height + 6;
    var pos = anchor + Offset(0, -h - 8);
    if (sel.length == 1 && sel.first is BoxObject) pos += const Offset(0, -34); // clear the rotate handle
    pos = Offset(pos.dx.clamp(4, math.max(4, size.width - w - 4)), pos.dy < 4 ? anchor.dy + 10 : pos.dy);
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(pos.dx, pos.dy, w, h), const Radius.circular(5));
    canvas.drawRRect(r, Paint()..color = kAccent);
    tp.paint(canvas, pos + const Offset(7, 3));
    tp.dispose();
  }

  void _dashedRect(Canvas canvas, Rect r, Paint p) => _dashedPath(canvas, Path()..addRect(r), p);

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
