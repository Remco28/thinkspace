import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../model/assets.dart';
import '../model/geometry.dart';

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
Future<CutResult?> cutoutPolygon(Asset src, List<Offset> polyPx,
    {bool leaveHole = false}) async {
  if (polyPx.length < 3) return null;
  var box = rectFromPoints(polyPx).intersect(
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()));
  if (box.isEmpty || box.width < 2 || box.height < 2) return null;
  box = Rect.fromLTRB(box.left.floorToDouble(), box.top.floorToDouble(),
      box.right.ceilToDouble(), box.bottom.ceilToDouble());
  final path = Path()..addPolygon(polyPx, true);

  final rec = PictureRecorder();
  final c = Canvas(rec);
  c.translate(-box.left, -box.top);
  c.clipPath(path, doAntiAlias: true);
  c.drawImage(
      src.image, Offset.zero, Paint()..filterQuality = FilterQuality.none);
  final piece =
      await rec.endRecording().toImage(box.width.round(), box.height.round());

  Image? rest;
  if (leaveHole) {
    final r2 = PictureRecorder();
    final c2 = Canvas(r2);
    final full =
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());
    c2.saveLayer(full, Paint());
    c2.drawImage(src.image, Offset.zero, Paint());
    c2.clipPath(path, doAntiAlias: true);
    c2.drawPaint(Paint()..blendMode = BlendMode.clear);
    c2.restore();
    rest = await r2.endRecording().toImage(src.width, src.height);
  }
  return CutResult(piece, box, rest);
}

Future<Image> imageFromRgba(Uint8List rgba, int w, int h) {
  final c = Completer<Image>();
  decodeImageFromPixels(rgba, w, h, PixelFormat.rgba8888, c.complete);
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
  final source = await src.rgbaBytes();
  final px = Uint8List.fromList(source);
  final limit = tolerance * 441.67;
  final done = Uint8List(w * h);
  int removed = 0;

  void clear(int p) {
    final i = p * 4;
    if (px[i + 3] != 0) removed++;
    px[i + 3] = 0;
    done[p] = 1;
  }

  for (final (sx, sy) in seeds) {
    if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue;
    final si = (sy * w + sx) * 4;
    if (source[si + 3] < 8) continue;
    final r = source[si], g = source[si + 1], b = source[si + 2];
    if (!contiguous) {
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
  if (removed == 0) return null;
  return ColorRemoval(await imageFromRgba(px, w, h), removed);
}

/// Remove the page-coloured background by flooding from the four corners.
Future<ColorRemoval?> removeBackground(Asset src, double tolerance) =>
    removeColorFrom(
        src,
        [
          (0, 0),
          (src.width - 1, 0),
          (0, src.height - 1),
          (src.width - 1, src.height - 1)
        ],
        tolerance);
