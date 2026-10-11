import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show compute;

import '../model/assets.dart';
import '../model/geometry.dart';

/// What to put where a cut-out piece used to be.
enum HoleFill {
  /// Leave it see-through.
  empty,

  /// Continue the surroundings into the hole (smooth, like a screenshot
  /// background with the thing removed).
  blend,

  /// One flat colour.
  color,
}

class CutResult {
  CutResult(this.image, this.rectPx, this.remainder);

  /// Just the selected piece, sized to the bounding box of the selection.
  final Image image;

  /// Where the piece sat in the source image, in source pixels.
  final Rect rectPx;

  /// The source with the piece erased, when a hole was requested.
  final Image? remainder;
}

/// Cut a polygon (in source pixel coordinates) out of [src].
Future<CutResult?> cutoutPolygon(
  Asset src,
  List<Offset> polyPx, {
  bool leaveHole = false,
  HoleFill fill = HoleFill.empty,
  int fillColor = 0xFFFFFFFF,
}) async {
  if (polyPx.length < 3) return null;
  var box = rectFromPoints(
    polyPx,
  ).intersect(Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()));
  if (box.isEmpty || box.width < 2 || box.height < 2) return null;
  box = Rect.fromLTRB(
    box.left.floorToDouble(),
    box.top.floorToDouble(),
    box.right.ceilToDouble(),
    box.bottom.ceilToDouble(),
  );
  final path = Path()..addPolygon(polyPx, true);

  final rec = PictureRecorder();
  final c = Canvas(rec);
  c.translate(-box.left, -box.top);
  c.clipPath(path, doAntiAlias: true);
  c.drawImage(
    src.image,
    Offset.zero,
    Paint()..filterQuality = FilterQuality.none,
  );
  final piece = await rec.endRecording().toImage(
    box.width.round(),
    box.height.round(),
  );

  Image? rest;
  if (leaveHole && fill != HoleFill.empty) {
    rest = await _fillHole(src, path, fill, fillColor);
  } else if (leaveHole) {
    final r2 = PictureRecorder();
    final c2 = Canvas(r2);
    final full = Rect.fromLTWH(
      0,
      0,
      src.width.toDouble(),
      src.height.toDouble(),
    );
    c2.saveLayer(full, Paint());
    c2.drawImage(src.image, Offset.zero, Paint());
    c2.clipPath(path, doAntiAlias: true);
    c2.drawPaint(Paint()..blendMode = BlendMode.clear);
    c2.restore();
    rest = await r2.endRecording().toImage(src.width, src.height);
  }
  return CutResult(piece, box, rest);
}

/// A picture from straight (not premultiplied) RGBA bytes. The engine reads
/// the bytes as premultiplied, so they are converted first; without that, a
/// pixel made see-through but still holding white would paint white again.
Future<Image> imageFromRgba(Uint8List rgba, int w, int h) {
  final px = Uint8List(rgba.length);
  for (int i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a == 0) continue; // all zeros: nothing to paint
    if (a == 255) {
      px[i] = rgba[i];
      px[i + 1] = rgba[i + 1];
      px[i + 2] = rgba[i + 2];
    } else {
      px[i] = (rgba[i] * a + 127) ~/ 255;
      px[i + 1] = (rgba[i + 1] * a + 127) ~/ 255;
      px[i + 2] = (rgba[i + 2] * a + 127) ~/ 255;
    }
    px[i + 3] = a;
  }
  final c = Completer<Image>();
  decodeImageFromPixels(px, w, h, PixelFormat.rgba8888, c.complete);
  return c.future;
}

double _dist(Uint8List px, int i, int r, int g, int b) {
  final dr = px[i] - r, dg = px[i + 1] - g, db = px[i + 2] - b;
  return math.sqrt((dr * dr + dg * dg + db * db).toDouble());
}

class ColorRemoval {
  ColorRemoval(this.image, this.removedPixels);
  final Image image;
  final int removedPixels;
}

/// Make the colour at each seed transparent, flooding outwards through
/// similar-coloured neighbours. [tolerance] is 0..1 of the maximum colour
/// distance. Returns null if nothing changed.
Future<ColorRemoval?> removeColorFrom(
  Asset src,
  List<(int, int)> seeds,
  double tolerance, {
  bool contiguous = true,
}) async {
  final w = src.width, h = src.height;
  final job = (
    source: await src.rgbaBytes(),
    w: w,
    h: h,
    seeds: seeds,
    limit: tolerance * 441.67,
    contiguous: contiguous,
  );
  // Same rule as the gap fill: a big photo goes to another isolate.
  final res = w * h > 1500000
      ? await compute(_removeColor, job)
      : _removeColor(job);
  if (res.removed == 0) return null;
  return ColorRemoval(await imageFromRgba(res.px, w, h), res.removed);
}

typedef _RemoveJob = ({
  Uint8List source,
  int w,
  int h,
  List<(int, int)> seeds,
  double limit,
  bool contiguous,
});

({Uint8List px, int removed}) _removeColor(_RemoveJob j) {
  final w = j.w, h = j.h, source = j.source, limit = j.limit;
  final px = Uint8List.fromList(source);
  final done = Uint8List(w * h);
  int removed = 0;

  void clear(int p) {
    final i = p * 4;
    if (px[i + 3] != 0) removed++;
    px[i + 3] = 0;
    done[p] = 1;
  }

  for (final (sx, sy) in j.seeds) {
    if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue;
    final si = (sy * w + sx) * 4;
    if (source[si + 3] < 8) continue;
    final r = source[si], g = source[si + 1], b = source[si + 2];
    if (!j.contiguous) {
      for (int p = 0; p < w * h; p++) {
        if (done[p] == 0 &&
            source[p * 4 + 3] > 0 &&
            _dist(source, p * 4, r, g, b) <= limit) {
          clear(p);
        }
      }
      continue;
    }
    if (done[sy * w + sx] == 1) continue;
    final stack = <int>[sy * w + sx];
    done[sy * w + sx] = 2; // queued
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final x = p % w, y = p ~/ w;
      if (source[p * 4 + 3] < 8 || _dist(source, p * 4, r, g, b) > limit) {
        done[p] = 3; // visited, kept
        continue;
      }
      clear(p);
      if (x > 0 && done[p - 1] == 0) {
        done[p - 1] = 2;
        stack.add(p - 1);
      }
      if (x < w - 1 && done[p + 1] == 0) {
        done[p + 1] = 2;
        stack.add(p + 1);
      }
      if (y > 0 && done[p - w] == 0) {
        done[p - w] = 2;
        stack.add(p - w);
      }
      if (y < h - 1 && done[p + w] == 0) {
        done[p + w] = 2;
        stack.add(p + w);
      }
    }
  }
  return (px: px, removed: removed);
}

/// Remove the background of a picture: the colour that runs around its edge
/// (white, usually), flooded inwards through similar colours. With [inside],
/// roomy areas of that same colour that the flood could not reach, such as the
/// gaps inside a drawing's outline, go too. The pixels along the new edge are
/// "un-mixed" from the background, so a drawing on white does not keep a pale
/// halo when it is placed over another colour.
Future<ColorRemoval?> removeBackground(
  Asset src,
  double tolerance, {
  bool inside = true,
}) async {
  final w = src.width, h = src.height;
  final job = (
    source: await src.rgbaBytes(),
    w: w,
    h: h,
    limit: tolerance * 441.67,
    inside: inside,
  );
  final res = w * h > 1500000 ? await compute(_removeBg, job) : _removeBg(job);
  if (res.removed == 0) return null;
  return ColorRemoval(await imageFromRgba(res.px, w, h), res.removed);
}

typedef _BgJob = ({Uint8List source, int w, int h, double limit, bool inside});

({Uint8List px, int removed}) _removeBg(_BgJob j) {
  final w = j.w, h = j.h, src = j.source, limit = j.limit;
  final px = Uint8List.fromList(src);
  final n = w * h;

  // 1. What colour is the background? The commonest colour on the edge.
  final bins = <int, List<int>>{}; // key -> [count, r, g, b] sums
  void sample(int p) {
    final i = p * 4;
    if (src[i + 3] < 200) return;
    final key =
        ((src[i] >> 3) << 10) | ((src[i + 1] >> 3) << 5) | (src[i + 2] >> 3);
    final e = bins.putIfAbsent(key, () => [0, 0, 0, 0]);
    e[0]++;
    e[1] += src[i];
    e[2] += src[i + 1];
    e[3] += src[i + 2];
  }

  for (int x = 0; x < w; x++) {
    sample(x);
    sample((h - 1) * w + x);
  }
  for (int y = 1; y < h - 1; y++) {
    sample(y * w);
    sample(y * w + w - 1);
  }
  if (bins.isEmpty) return (px: px, removed: 0);
  final top = bins.values.reduce((a, b) => a[0] >= b[0] ? a : b);
  // A real background is the bulk of the edge, not one colour among many.
  final edgeCount = bins.values.fold<int>(0, (n, e) => n + e[0]);
  if (top[0] < edgeCount * 0.3) return (px: px, removed: 0);
  final br = top[1] ~/ top[0], bg = top[2] ~/ top[0], bb = top[3] ~/ top[0];

  double dist(int p) => _dist(src, p * 4, br, bg, bb);
  // Already see-through counts as background that can be flooded across.
  bool passes(int p, double lim) => src[p * 4 + 3] < 8 || dist(p) <= lim;

  final gone = Uint8List(n); // 1 = background, 2 = looked at and kept
  int removed = 0;
  void clear(int p) {
    if (px[p * 4 + 3] != 0) removed++;
    px[p * 4 + 3] = 0;
    gone[p] = 1;
  }

  // 2. Flood in from every pixel on the edge.
  final stack = <int>[];
  void push(int p) {
    if (gone[p] == 0) {
      gone[p] = 3; // queued
      stack.add(p);
    }
  }

  for (int x = 0; x < w; x++) {
    push(x);
    push((h - 1) * w + x);
  }
  for (int y = 1; y < h - 1; y++) {
    push(y * w);
    push(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    if (!passes(p, limit)) {
      gone[p] = 2;
      continue;
    }
    clear(p);
    final x = p % w, y = p ~/ w;
    if (x > 0) push(p - 1);
    if (x < w - 1) push(p + 1);
    if (y > 0) push(p - w);
    if (y < h - 1) push(p + w);
  }

  // 3. Roomy pockets of the very same colour that the flood could not reach.
  if (j.inside) {
    final tight = math.min(limit, 31.0);
    final minArea = math.max(48, n ~/ 3000);
    final seen = Uint8List(n);
    for (int s = 0; s < n; s++) {
      if (gone[s] != 0 && gone[s] != 2) continue;
      if (seen[s] == 1 || src[s * 4 + 3] < 8 || dist(s) > tight) continue;
      final comp = <int>[s];
      seen[s] = 1;
      for (int k = 0; k < comp.length; k++) {
        final p = comp[k];
        final x = p % w, y = p ~/ w;
        void visit(int q) {
          if (seen[q] == 0 &&
              gone[q] != 1 &&
              src[q * 4 + 3] >= 8 &&
              dist(q) <= tight) {
            seen[q] = 1;
            comp.add(q);
          }
        }

        if (x > 0) visit(p - 1);
        if (x < w - 1) visit(p + 1);
        if (y > 0) visit(p - w);
        if (y < h - 1) visit(p + w);
      }
      if (comp.length >= minArea) {
        for (final p in comp) {
          clear(p);
        }
      }
    }
  }
  if (removed == 0) return (px: px, removed: 0);

  // 4. Un-mix the thin edge left behind: a pixel that is part picture and
  // part background keeps only its picture colour, with the rest as opacity.
  final band = <int>[];
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = y * w + x;
      if (gone[p] == 1 || src[p * 4 + 3] < 8) continue;
      var near = false;
      for (int dy = -2; dy <= 2 && !near; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (int dx = -2; dx <= 2; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          if (gone[yy * w + xx] == 1) {
            near = true;
            break;
          }
        }
      }
      if (near) band.add(p);
    }
  }
  final bgc = [br, bg, bb];
  // The picture's own colour near a band pixel: the colour furthest from the
  // background within a few pixels, which is the middle of the stroke.
  List<int>? purestNear(int x, int y) {
    var best = -1.0;
    int? bp;
    for (int dy = -3; dy <= 3; dy++) {
      for (int dx = -3; dx <= 3; dx++) {
        final xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        final q = yy * w + xx;
        if (gone[q] == 1 || src[q * 4 + 3] < 200) continue;
        final d = dist(q);
        if (d > best) {
          best = d;
          bp = q;
        }
      }
    }
    if (bp == null) return null;
    return [src[bp * 4], src[bp * 4 + 1], src[bp * 4 + 2]];
  }

  for (final p in band) {
    final i = p * 4;
    final f = purestNear(p % w, p ~/ w);
    var alpha = 0.0;
    List<int>? fg;
    if (f != null) {
      final dr = f[0] - br, dg = f[1] - bg, db = f[2] - bb;
      final len2 = dr * dr + dg * dg + db * db;
      if (len2 > 900) {
        // Where along the way from background to picture colour is it?
        alpha =
            ((src[i] - br) * dr +
                (src[i + 1] - bg) * dg +
                (src[i + 2] - bb) * db) /
            len2;
        fg = f;
      }
    }
    if (fg == null) {
      // No solid colour nearby (a very thin line): the least picture that
      // could explain the pixel.
      for (int k = 0; k < 3; k++) {
        final c = src[i + k], b = bgc[k];
        final a = c < b
            ? (b == 0 ? 0.0 : (b - c) / b)
            : (b == 255 ? 0.0 : (c - b) / (255 - b));
        if (a > alpha) alpha = a;
      }
    }
    alpha = alpha.clamp(0.0, 1.0);
    if (alpha >= 0.995) continue;
    if (alpha <= 0.004) {
      px[i + 3] = 0;
      continue;
    }
    for (int k = 0; k < 3; k++) {
      final v = fg != null ? fg[k] : bgc[k] + (src[i + k] - bgc[k]) / alpha;
      px[i + k] = v.round().clamp(0, 255);
    }
    px[i + 3] = (src[i + 3] * alpha).round().clamp(0, 255);
  }
  return (px: px, removed: removed);
}

/// The source with the area inside [path] replaced by [fill]. Pixels that
/// were already see-through stay see-through: only picture is filled.
Future<Image> _fillHole(Asset src, Path path, HoleFill fill, int color) async {
  final w = src.width, h = src.height;
  // How much of each pixel the shape covers.
  final rec = PictureRecorder();
  Canvas(rec).drawPath(
    path,
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..isAntiAlias = true,
  );
  final cover = await rec.endRecording().toImage(w, h);
  final coverBytes = (await cover.toByteData(
    format: ImageByteFormat.rawStraightRgba,
  ))!.buffer.asUint8List();
  cover.dispose();

  final job = (
    px: Uint8List.fromList(await src.rgbaBytes()),
    cover: coverBytes,
    w: w,
    h: h,
    colour: fill == HoleFill.color,
    rgb: color,
  );
  // Screenshots are quick; a big photo would freeze the window, so the pixel
  // work moves to another isolate once the picture is large.
  final px = w * h > 1500000
      ? await compute(_fillPixels, job)
      : _fillPixels(job);
  return imageFromRgba(px, w, h);
}

typedef _FillJob = ({
  Uint8List px,
  Uint8List cover,
  int w,
  int h,
  bool colour,
  int rgb,
});

Uint8List _fillPixels(_FillJob j) {
  final px = j.px, coverBytes = j.cover, w = j.w, h = j.h;
  // The hole is every touched pixel plus a one-pixel rim, so no halo of the
  // removed thing survives at its edge.
  var hole = Uint8List(w * h);
  for (int p = 0; p < w * h; p++) {
    if (coverBytes[p * 4 + 3] > 0) hole[p] = 1;
  }
  final rim = Uint8List.fromList(hole);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (hole[y * w + x] == 0) continue;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && ny >= 0 && nx < w && ny < h) rim[ny * w + nx] = 1;
        }
      }
    }
  }
  hole = rim;

  if (j.colour) {
    final r = (j.rgb >> 16) & 0xFF, g = (j.rgb >> 8) & 0xFF, b = j.rgb & 0xFF;
    for (int p = 0; p < w * h; p++) {
      if (hole[p] == 1 && px[p * 4 + 3] > 0) {
        px[p * 4] = r;
        px[p * 4 + 1] = g;
        px[p * 4 + 2] = b;
      }
    }
  } else {
    blendFill(px, w, h, hole);
  }
  return px;
}

/// Replace the colour of every [hole] pixel (that has any opacity) with a
/// smooth continuation of the pixels around it. Works on a crop around the
/// hole so a small hole in a huge picture stays cheap.
///
/// This is the "push-pull" method: average the known pixels down into
/// smaller and smaller pictures until every cell has a value, then blend the
/// small values back up into the gaps.
void blendFill(Uint8List px, int w, int h, Uint8List hole) {
  int x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (hole[y * w + x] == 1) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return;
  final margin = math.min(256, math.max(24, math.max(x1 - x0, y1 - y0) ~/ 2));
  final cx0 = math.max(0, x0 - margin), cy0 = math.max(0, y0 - margin);
  final cx1 = math.min(w - 1, x1 + margin), cy1 = math.min(h - 1, y1 + margin);
  final cw = cx1 - cx0 + 1, ch = cy1 - cy0 + 1;

  // Level 0: known pixels weigh by their opacity, hole pixels weigh nothing.
  var lw = cw, lh = ch;
  var r = Float32List(lw * lh), g = Float32List(lw * lh);
  var b = Float32List(lw * lh), wt = Float32List(lw * lh);
  var any = false;
  for (int y = 0; y < ch; y++) {
    for (int x = 0; x < cw; x++) {
      final src = ((y + cy0) * w + (x + cx0));
      final i = y * cw + x;
      r[i] = px[src * 4].toDouble();
      g[i] = px[src * 4 + 1].toDouble();
      b[i] = px[src * 4 + 2].toDouble();
      if (hole[src] == 0) {
        wt[i] = px[src * 4 + 3] / 255;
        if (wt[i] > 0) any = true;
      }
    }
  }
  if (!any) return; // nothing around it to continue

  final levels =
      <(Float32List, Float32List, Float32List, Float32List, int, int)>[
        (r, g, b, wt, lw, lh),
      ];
  while (lw > 1 || lh > 1) {
    final pw = (lw + 1) >> 1, ph = (lh + 1) >> 1;
    final nr = Float32List(pw * ph), ng = Float32List(pw * ph);
    final nb = Float32List(pw * ph), nw = Float32List(pw * ph);
    for (int y = 0; y < lh; y++) {
      for (int x = 0; x < lw; x++) {
        final i = y * lw + x, j = (y >> 1) * pw + (x >> 1);
        final k = wt[i];
        if (k == 0) continue;
        nr[j] += r[i] * k;
        ng[j] += g[i] * k;
        nb[j] += b[i] * k;
        nw[j] += k;
      }
    }
    for (int j = 0; j < pw * ph; j++) {
      if (nw[j] > 1e-6) {
        nr[j] /= nw[j];
        ng[j] /= nw[j];
        nb[j] /= nw[j];
      }
      nw[j] = math.min(1.0, nw[j]);
    }
    r = nr;
    g = ng;
    b = nb;
    wt = nw;
    lw = pw;
    lh = ph;
    levels.add((r, g, b, wt, lw, lh));
  }

  // Pull: from the smallest level down, fill each gap from the level above it.
  for (int l = levels.length - 2; l >= 0; l--) {
    final (fr, fg, fb, fw, w1, h1) = levels[l];
    final (pr, pg, pb, _, pw, ph) = levels[l + 1];
    for (int y = 0; y < h1; y++) {
      final gy = ((y + 0.5) / 2 - 0.5).clamp(0.0, ph - 1.0);
      final yy = gy.floor(), ty = gy - yy, y2 = math.min(ph - 1, yy + 1);
      for (int x = 0; x < w1; x++) {
        final i = y * w1 + x;
        final k = fw[i];
        if (k >= 1) continue;
        final gx = ((x + 0.5) / 2 - 0.5).clamp(0.0, pw - 1.0);
        final xx = gx.floor(), tx = gx - xx, x2 = math.min(pw - 1, xx + 1);
        double lerp4(Float32List a) =>
            (a[yy * pw + xx] * (1 - tx) + a[yy * pw + x2] * tx) * (1 - ty) +
            (a[y2 * pw + xx] * (1 - tx) + a[y2 * pw + x2] * tx) * ty;
        fr[i] = fr[i] * k + lerp4(pr) * (1 - k);
        fg[i] = fg[i] * k + lerp4(pg) * (1 - k);
        fb[i] = fb[i] * k + lerp4(pb) * (1 - k);
        fw[i] = 1;
      }
    }
  }

  final (fr, fg, fb, _, _, _) = levels[0];
  for (int y = 0; y < ch; y++) {
    for (int x = 0; x < cw; x++) {
      final src = ((y + cy0) * w + (x + cx0));
      if (hole[src] == 0 || px[src * 4 + 3] == 0) continue;
      final i = y * cw + x;
      px[src * 4] = fr[i].round().clamp(0, 255);
      px[src * 4 + 1] = fg[i].round().clamp(0, 255);
      px[src * 4 + 2] = fb[i].round().clamp(0, 255);
    }
  }
}
