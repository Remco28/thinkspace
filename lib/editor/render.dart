import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../model/assets.dart';
import '../model/geometry.dart';
import '../model/scene.dart';

TextPainter textPainterFor(TextObject t, {double? width}) {
  final tp = TextPainter(
    text: TextSpan(text: t.text.isEmpty ? ' ' : t.text, style: textStyleFor(t)),
    textAlign: t.align,
    textDirection: TextDirection.ltr,
  );
  tp.layout(
    maxWidth: math.max(10, (width ?? t.size.width) - TextObject.pad * 2),
  );
  return tp;
}

TextStyle textStyleFor(TextObject t) => TextStyle(
  fontSize: t.fontSize,
  color: Color(t.color),
  fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
  fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
  height: 1.2,
);

/// Height a text object needs at its current width.
double measureTextHeight(TextObject t) =>
    textPainterFor(t).height + TextObject.pad * 2;

void paintDocumentObjects(
  ui.Canvas canvas,
  Document doc,
  AssetStore assets, {
  Set<String> hidden = const {},
}) {
  for (final layer in doc.layers) {
    if (!layer.visible) continue;
    for (final o in layer.objects) {
      if (!o.visible || hidden.contains(o.id)) continue;
      paintObject(canvas, o, assets);
    }
  }
}

void paintObject(ui.Canvas canvas, SceneObject o, AssetStore assets) {
  final grouped = o.opacity < 0.999;
  if (grouped) {
    canvas.saveLayer(
      o.bounds.inflate(4),
      Paint()..color = Color.fromRGBO(0, 0, 0, o.opacity.clamp(0.0, 1.0)),
    );
  }
  if (o is ImageObject) {
    _paintImage(canvas, o, assets);
  } else if (o is TextObject) {
    _paintText(canvas, o);
  } else if (o is ShapeObject) {
    _paintShape(canvas, o);
  } else if (o is BadgeObject) {
    _paintBadge(canvas, o);
  } else if (o is LineObject) {
    paintLine(canvas, o);
  } else if (o is StrokeObject) {
    _paintStroke(canvas, o);
  }
  if (grouped) canvas.restore();
}

void _boxTransform(ui.Canvas canvas, BoxObject b) {
  canvas.save();
  canvas.translate(b.center.dx, b.center.dy);
  canvas.rotate(b.rotation);
}

void _paintImage(ui.Canvas canvas, ImageObject o, AssetStore assets) {
  final a = assets[o.assetId];
  final dst = Rect.fromCenter(
    center: Offset.zero,
    width: o.size.width,
    height: o.size.height,
  );
  _boxTransform(canvas, o);
  if (a == null) {
    canvas.drawRect(dst, Paint()..color = const Color(0xFFCCCCCC));
  } else {
    if (o.flipX) canvas.scale(-1, 1);
    canvas.drawImageRect(
      a.image,
      Rect.fromLTWH(0, 0, a.width.toDouble(), a.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  }
  canvas.restore();
}

void _paintText(ui.Canvas canvas, TextObject t) {
  _boxTransform(canvas, t);
  final rect = Rect.fromCenter(
    center: Offset.zero,
    width: t.size.width,
    height: t.size.height,
  );
  if (t.background != 0) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = Color(t.background),
    );
  }
  final tp = textPainterFor(t);
  tp.paint(canvas, rect.topLeft + const Offset(TextObject.pad, TextObject.pad));
  tp.dispose();
  canvas.restore();
}

void _paintShape(ui.Canvas canvas, ShapeObject s) {
  _boxTransform(canvas, s);
  final rect = Rect.fromCenter(
    center: Offset.zero,
    width: s.size.width,
    height: s.size.height,
  );
  if (s.fill != 0) {
    final p = Paint()..color = Color(s.fill);
    s.ellipse ? canvas.drawOval(rect, p) : canvas.drawRect(rect, p);
  }
  if (s.strokeWidth > 0) {
    final p = Paint()
      ..color = Color(s.stroke)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.strokeWidth
      ..strokeJoin = StrokeJoin.round;
    s.ellipse ? canvas.drawOval(rect, p) : canvas.drawRect(rect, p);
  }
  canvas.restore();
}

void _paintBadge(ui.Canvas canvas, BadgeObject b) {
  _boxTransform(canvas, b);
  final r = Rect.fromCenter(
    center: Offset.zero,
    width: b.size.width,
    height: b.size.height,
  );
  canvas.drawOval(r, Paint()..color = Color(b.color));
  canvas.drawOval(
    r.deflate(b.size.shortestSide * 0.04),
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = b.size.shortestSide * 0.06,
  );
  final tp = TextPainter(
    text: TextSpan(
      text: '${b.number}',
      style: TextStyle(
        fontSize: b.size.shortestSide * (b.number > 9 ? 0.46 : 0.58),
        fontWeight: FontWeight.w800,
        color: const Color(0xFFFFFFFF),
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  tp.dispose();
  canvas.restore();
}

void paintLine(ui.Canvas canvas, LineObject l) {
  final d = l.p2 - l.p1;
  final len = d.distance;
  if (len < 0.01) return;
  final dir = d / len;
  final head = math.min(l.headSize, len * 0.9);
  var a = l.p1, b = l.p2;
  // Stop the shaft inside the head so a round cap doesn't poke past the tip.
  if (l.headStart) a = a + dir * (head * 0.7);
  if (l.headEnd) b = b - dir * (head * 0.7);
  final paint = Paint()
    ..color = Color(l.color)
    ..strokeWidth = l.width
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  if (l.dashed) {
    _dashedLine(canvas, a, b, paint, l.width * 2.2, l.width * 1.8);
  } else {
    canvas.drawLine(a, b, paint);
  }
  final fill = Paint()
    ..color = Color(l.color)
    ..style = PaintingStyle.fill;
  if (l.headEnd) _arrowHead(canvas, l.p2, dir, head, fill);
  if (l.headStart) _arrowHead(canvas, l.p1, -dir, head, fill);
}

void _arrowHead(
  ui.Canvas canvas,
  Offset tip,
  Offset dir,
  double len,
  Paint paint,
) {
  final n = Offset(-dir.dy, dir.dx);
  final base = tip - dir * len;
  final path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(base.dx + n.dx * len * 0.42, base.dy + n.dy * len * 0.42)
    ..lineTo(base.dx - n.dx * len * 0.42, base.dy - n.dy * len * 0.42)
    ..close();
  canvas.drawPath(path, paint);
}

void _dashedLine(
  ui.Canvas canvas,
  Offset a,
  Offset b,
  Paint paint,
  double dash,
  double gap,
) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return;
  final dir = d / len;
  double t = 0;
  while (t < len) {
    final e = math.min(len, t + dash);
    canvas.drawLine(a + dir * t, a + dir * e, paint);
    t = e + gap;
  }
}

Path smoothPath(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 1) {
    path.lineTo(pts.first.dx + 0.01, pts.first.dy);
  } else if (pts.length == 2) {
    path.lineTo(pts[1].dx, pts[1].dy);
  } else {
    for (int i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
  }
  return path;
}

void _paintStroke(ui.Canvas canvas, StrokeObject s) {
  canvas.drawPath(
    smoothPath(s.points),
    Paint()
      ..color = Color(s.color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
}

/// Render the document as a flat image (page only, clipped to its bounds).
Future<ui.Image> renderDocument(
  Document doc,
  AssetStore assets, {
  double scale = 1,
}) {
  final recorder = ui.PictureRecorder();
  final w = doc.canvasSize.width, h = doc.canvasSize.height;
  final canvas = Canvas(recorder);
  canvas.scale(scale);
  canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
  if (doc.background != 0) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = Color(doc.background),
    );
  }
  paintDocumentObjects(canvas, doc, assets);
  final pic = recorder.endRecording();
  return pic.toImage((w * scale).round(), (h * scale).round());
}

/// Draw the editor's page: transparency checkerboard when there's no fill.
void paintPageBackground(ui.Canvas canvas, Document doc) {
  final rect = Offset.zero & doc.canvasSize;
  if (doc.background != 0) {
    canvas.drawRect(rect, Paint()..color = Color(doc.background));
    return;
  }
  canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
  final p = Paint()..color = const Color(0xFFE6E6E6);
  const cell = 16.0;
  canvas.save();
  canvas.clipRect(rect);
  // Only the cells on screen: a huge page must not cost a huge frame.
  final vis = canvas.getLocalClipBounds().intersect(rect);
  final y0 = (vis.top / cell).floor() * cell,
      x0 = (vis.left / cell).floor() * cell;
  for (double y = y0; y < vis.bottom; y += cell) {
    for (double x = x0; x < vis.right; x += cell) {
      if (((x / cell).floor() + (y / cell).floor()) % 2 == 0) {
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), p);
      }
    }
  }
  canvas.restore();
}

/// What actually shows on the page: hidden things and hidden layers don't count.
Rect contentBounds(Document doc) => unionRects([
  for (final l in doc.layers)
    if (l.visible)
      for (final o in l.objects)
        if (o.visible) o.bounds,
]);
