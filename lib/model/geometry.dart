import 'dart:math' as math;
import 'dart:ui';

Offset rotateOffset(Offset v, double angle) {
  final c = math.cos(angle), s = math.sin(angle);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

double distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
    0.0,
    1.0,
  );
  return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
}

Rect rectFromPoints(Iterable<Offset> pts) {
  double? l, t, r, b;
  for (final p in pts) {
    l = l == null ? p.dx : math.min(l, p.dx);
    r = r == null ? p.dx : math.max(r, p.dx);
    t = t == null ? p.dy : math.min(t, p.dy);
    b = b == null ? p.dy : math.max(b, p.dy);
  }
  if (l == null) return Rect.zero;
  return Rect.fromLTRB(l, t!, r!, b!);
}

Rect unionRects(Iterable<Rect> rects) {
  Rect? out;
  for (final r in rects) {
    out = out == null ? r : out.expandToInclude(r);
  }
  return out ?? Rect.zero;
}

/// Ramer–Douglas–Peucker polyline simplification.
List<Offset> simplifyPolyline(List<Offset> pts, double epsilon) {
  if (pts.length < 3) return List.of(pts);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = keep[pts.length - 1] = true;
  void rec(int s, int e) {
    double maxD = 0;
    int idx = -1;
    for (int i = s + 1; i < e; i++) {
      final d = distToSegment(pts[i], pts[s], pts[e]);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (idx != -1 && maxD > epsilon) {
      keep[idx] = true;
      rec(s, idx);
      rec(idx, e);
    }
  }

  rec(0, pts.length - 1);
  return [
    for (int i = 0; i < pts.length; i++)
      if (keep[i]) pts[i],
  ];
}

/// Point-in-polygon (even-odd).
bool polygonContains(List<Offset> poly, Offset p) {
  bool inside = false;
  for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

double snapToGrid(double v, double grid) => (v / grid).roundToDouble() * grid;

double normalizeAngle(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a <= -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

/// A quick pass of the highlighter over a line of text wobbles. If the stroke
/// is nearly level (or nearly upright) and stays within about a stroke width
/// of its middle, return it as the perfectly straight line it was meant to be;
/// otherwise null, and the stroke stays as drawn.
List<Offset>? straightenMark(List<Offset> pts, double width) {
  if (pts.length < 3) return null;
  final first = pts.first, last = pts.last;
  final dx = (last.dx - first.dx).abs(), dy = (last.dy - first.dy).abs();
  if (math.max(dx, dy) < 24) return null;
  final slack = math.max(width, 8.0);
  const tolerance = 0.14; // tan of about 8 degrees
  if (dy <= dx * tolerance) {
    final mean = pts.fold<double>(0, (a, p) => a + p.dy) / pts.length;
    if (pts.any((p) => (p.dy - mean).abs() > slack)) return null;
    return [Offset(first.dx, mean), Offset(last.dx, mean)];
  }
  if (dx <= dy * tolerance) {
    final mean = pts.fold<double>(0, (a, p) => a + p.dx) / pts.length;
    if (pts.any((p) => (p.dx - mean).abs() > slack)) return null;
    return [Offset(mean, first.dy), Offset(mean, last.dy)];
  }
  return null;
}
