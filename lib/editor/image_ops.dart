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
  final res = w * h > 400000
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

/// Remove the background of an image: the colours that run around its edge,
/// flooded inwards. It follows a background that changes gradually, such as
/// a gradient, a studio backdrop or darker corners, and one made of a few
/// colours, such as a two-tone wall. A colour on only one side of the edge is
/// taken for the subject running off the image, not background. With
/// [inside], roomy areas of a background colour that the flood could not
/// reach, such as the gaps inside a drawing's outline, go too. The pixels
/// along the new edge are "un-mixed" from the background beside them, so a
/// drawing on white does not keep a pale halo when it is placed over another
/// colour.
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
  final res = w * h > 400000 ? await compute(_removeBg, job) : _removeBg(job);
  if (res.removed == 0) return null;
  return ColorRemoval(await imageFromRgba(res.px, w, h), res.removed);
}

typedef _BgJob = ({Uint8List source, int w, int h, double limit, bool inside});

/// How different two colours look, squared. Red-mean weighting: closer to
/// the eye than plain RGB distance (green differences count for more, blue
/// for less), scaled so that greys measure the same as before.
double _seen2(int r1, int g1, int b1, int r2, int g2, int b2) {
  final rm = (r1 + r2) / 2;
  final dr = r1 - r2, dg = g1 - g2, db = b1 - b2;
  return ((2 + rm / 256) * dr * dr +
          4 * dg * dg +
          (2 + (255 - rm) / 256) * db * db) /
      3;
}

/// The background's colours, worked out from the image's edge: each colour
/// that covers a fair share of it, on at least two of its sides. [plain] when
/// nearly all the edge is one colour. Null when the edge has no background to
/// speak of.
({List<(int, int, int)> colours, bool plain})? _edgePalette(
  Uint8List src,
  int w,
  int h,
  double limit,
) {
  // [count, r, g, b, top, bottom, left, right]
  final bins = <int, List<int>>{};
  void sample(int p, int side) {
    final i = p * 4;
    if (src[i + 3] < 200) return;
    final key =
        ((src[i] >> 3) << 10) | ((src[i + 1] >> 3) << 5) | (src[i + 2] >> 3);
    final e = bins.putIfAbsent(key, () => List.filled(8, 0));
    e[0]++;
    e[1] += src[i];
    e[2] += src[i + 1];
    e[3] += src[i + 2];
    e[4 + side]++;
  }

  for (int x = 0; x < w; x++) {
    sample(x, 0);
    sample((h - 1) * w + x, 1);
  }
  for (int y = 1; y < h - 1; y++) {
    sample(y * w, 2);
    sample(y * w + w - 1, 3);
  }
  if (bins.isEmpty) return null;
  final edgeCount = bins.values.fold<int>(0, (n, e) => n + e[0]);

  // Gather similar colours together, the commonest first.
  final merge = math.max(6.0, limit / 2);
  final groups = <List<int>>[];
  for (final b in bins.values.toList()..sort((a, b) => b[0] - a[0])) {
    final r = b[1] ~/ b[0], g = b[2] ~/ b[0], bl = b[3] ~/ b[0];
    List<int>? home;
    for (final gr in groups) {
      final d2 = _seen2(
        r,
        g,
        bl,
        gr[1] ~/ gr[0],
        gr[2] ~/ gr[0],
        gr[3] ~/ gr[0],
      );
      if (d2 <= merge * merge) {
        home = gr;
        break;
      }
    }
    if (home == null) {
      groups.add(List.of(b));
    } else {
      for (int k = 0; k < 8; k++) {
        home[k] += b[k];
      }
    }
  }
  groups.sort((a, b) => b[0] - a[0]);

  final sideLen = [w, w, math.max(1, h - 2), math.max(1, h - 2)];
  bool onTwoSides(List<int> g) {
    var sides = 0;
    for (int s = 0; s < 4; s++) {
      if (g[4 + s] >= sideLen[s] * 0.1) sides++;
    }
    return sides >= 2;
  }

  final first = groups.first;
  final kept = <List<int>>[
    // The commonest colour counts as background when it is the bulk of the
    // edge, as a plain background is.
    if (first[0] >= edgeCount * 0.3 || onTwoSides(first)) first,
    for (final g in groups.skip(1))
      if (g[0] >= edgeCount * 0.04 && onTwoSides(g)) g,
  ];
  final covered = kept.fold<int>(0, (n, g) => n + g[0]);
  // A real background is most of the edge, not one colour among many.
  if (kept.isEmpty ||
      (first[0] < edgeCount * 0.3 && covered < edgeCount * 0.5)) {
    return null;
  }
  // Plain: nearly all the edge is within a whisker of its commonest colour,
  // whatever the tolerance.
  final fr = first[1] ~/ first[0], fg = first[2] ~/ first[0];
  final fb = first[3] ~/ first[0];
  var near = 0;
  for (final b in bins.values) {
    final d2 = _seen2(b[1] ~/ b[0], b[2] ~/ b[0], b[3] ~/ b[0], fr, fg, fb);
    if (d2 <= 12 * 12) near += b[0];
  }
  final plain = near >= edgeCount * 0.9;
  return (
    colours: [
      for (final g in kept.take(8)) (g[1] ~/ g[0], g[2] ~/ g[0], g[3] ~/ g[0]),
    ],
    plain: plain,
  );
}

({Uint8List px, int removed}) _removeBg(_BgJob j) {
  final w = j.w, h = j.h, src = j.source, limit = j.limit;
  final px = Uint8List.fromList(src);
  final n = w * h;
  final none = (px: px, removed: 0);

  // 1. What colours is the background? Those that run around the edge.
  final edge = _edgePalette(src, w, h, limit);
  if (edge == null) return none;
  final palette = edge.colours;

  /// How far a pixel is from the nearest background colour, squared.
  double far2(int p) {
    final i = p * 4;
    var best = double.infinity;
    for (final (r, g, b) in palette) {
      final d = _seen2(src[i], src[i + 1], src[i + 2], r, g, b);
      if (d < best) best = d;
    }
    return best;
  }

  /// A pixel's colour averaged with its neighbours, so noise and JPEG
  /// speckle do not count as steps.
  (int, int, int) smooth(int p) {
    final x = p % w, y = p ~/ w;
    var r = 0, g = 0, b = 0, k = 0;
    for (int yy = math.max(0, y - 1); yy <= math.min(h - 1, y + 1); yy++) {
      for (int xx = math.max(0, x - 1); xx <= math.min(w - 1, x + 1); xx++) {
        final i = (yy * w + xx) * 4;
        r += src[i];
        g += src[i + 1];
        b += src[i + 2];
        k++;
      }
    }
    return (r ~/ k, g ~/ k, b ~/ k);
  }

  final lim2 = limit * limit;
  // A background that changes gradually is followed one small step at a
  // time, but never further than this from its colours on the edge. Not
  // when the edge is one plain colour, as with a product photo on white:
  // there the background does not change, and the soft shading of something
  // white on it, a lamp shade or a pot, would be followed in instead.
  final step = math.max(2.5, limit * 0.04);
  final step2 = step * step;
  final drift2 = edge.plain ? lim2 : 4 * lim2;
  bool clear0(int p) => src[p * 4 + 3] < 8;

  final gone = Uint8List(n); // 1 = background
  int removed = 0;
  void clear(int p) {
    if (px[p * 4 + 3] != 0) removed++;
    px[p * 4 + 3] = 0;
    gone[p] = 1;
  }

  // 2. Flood in from the edge.
  final stack = <int>[];
  void seed(int p) {
    if (gone[p] == 0 && (clear0(p) || far2(p) <= lim2)) {
      clear(p);
      stack.add(p);
    }
  }

  for (int x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (int y = 1; y < h - 1; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % w, y = p ~/ w;
    (int, int, int)? here;
    void reach(int q) {
      if (gone[q] != 0) return;
      var ok = clear0(q);
      if (!ok) {
        final d = far2(q);
        ok = d <= lim2;
        if (!ok && d <= drift2) {
          final a = here ??= smooth(p), b = smooth(q);
          ok = _seen2(a.$1, a.$2, a.$3, b.$1, b.$2, b.$3) <= step2;
        }
      }
      if (ok) {
        clear(q);
        stack.add(q);
      }
    }

    if (x > 0) reach(p - 1);
    if (x < w - 1) reach(p + 1);
    if (y > 0) reach(p - w);
    if (y < h - 1) reach(p + w);
  }

  // 3. Roomy pockets of a background colour that the flood could not reach.
  if (j.inside) {
    final tight = math.min(limit, 31.0);
    final tight2 = tight * tight;
    final minArea = math.max(48, n ~/ 3000);
    final seen = Uint8List(n);
    for (int s = 0; s < n; s++) {
      if (gone[s] == 1 || seen[s] == 1 || clear0(s) || far2(s) > tight2) {
        continue;
      }
      final comp = <int>[s];
      seen[s] = 1;
      for (int k = 0; k < comp.length; k++) {
        final p = comp[k];
        final x = p % w, y = p ~/ w;
        void visit(int q) {
          if (seen[q] == 0 && gone[q] != 1 && !clear0(q) && far2(q) <= tight2) {
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
  if (removed == 0) return none;

  // 4. Un-mix the thin edge left behind: a pixel that is part picture and
  // part background keeps only its picture colour, with the rest as opacity.
  // The background it is mixed with is the one removed right beside it.
  final band = <(int, int, int, int)>[]; // pixel, and its background colour
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = y * w + x;
      if (gone[p] == 1 || clear0(p)) continue;
      var r = 0, g = 0, b = 0, k = 0;
      for (int dy = -2; dy <= 2; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (int dx = -2; dx <= 2; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final q = yy * w + xx;
          if (gone[q] == 1 && !clear0(q)) {
            r += src[q * 4];
            g += src[q * 4 + 1];
            b += src[q * 4 + 2];
            k++;
          }
        }
      }
      if (k > 0) band.add((p, r ~/ k, g ~/ k, b ~/ k));
    }
  }

  // The picture's own colour near a band pixel: the colour furthest from the
  // background within a few pixels, which is the middle of the stroke.
  List<int>? purestNear(int x, int y, int br, int bg, int bb) {
    var best = -1.0;
    int? bp;
    for (int dy = -3; dy <= 3; dy++) {
      for (int dx = -3; dx <= 3; dx++) {
        final xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        final q = yy * w + xx;
        if (gone[q] == 1 || src[q * 4 + 3] < 200) continue;
        final d = _dist(src, q * 4, br, bg, bb);
        if (d > best) {
          best = d;
          bp = q;
        }
      }
    }
    if (bp == null) return null;
    return [src[bp * 4], src[bp * 4 + 1], src[bp * 4 + 2]];
  }

  for (final (p, br, bg, bb) in band) {
    final i = p * 4;
    final bgc = [br, bg, bb];
    final f = purestNear(p % w, p ~/ w, br, bg, bb);
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
    rgb: color,
  );
  // Small pictures are quick; anything bigger would hitch the window, so the
  // pixel work moves to another isolate.
  final px = w * h > 400000
      ? await compute(_fillPixels, job)
      : _fillPixels(job);
  return imageFromRgba(px, w, h);
}

typedef _FillJob = ({Uint8List px, Uint8List cover, int w, int h, int rgb});

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

  final r = (j.rgb >> 16) & 0xFF, g = (j.rgb >> 8) & 0xFF, b = j.rgb & 0xFF;
  for (int p = 0; p < w * h; p++) {
    if (hole[p] == 1 && px[p * 4 + 3] > 0) {
      px[p * 4] = r;
      px[p * 4 + 1] = g;
      px[p * 4 + 2] = b;
    }
  }
  return px;
}
