import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A decoded raster image plus the encoded bytes it came from.
///
/// Hit-testing only needs to know which parts are see-through, so a coarse
/// alpha mask (at most ~1024 px on a side) is kept instead of a full copy of
/// every pixel; full pixels are read on demand for colour operations.
class Asset {
  Asset(this.id, this.bytes, this.image, this._mask, this._maskW, this._maskH);
  final String id;
  final Uint8List bytes;
  final ui.Image image;
  final Uint8List _mask;
  final int _maskW, _maskH;
  int get width => image.width;
  int get height => image.height;

  /// Alpha at a source pixel (0 outside the image). Coarse for large images:
  /// a block counts as opaque if any pixel in it is.
  int alphaAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    final mx = x * _maskW ~/ width, my = y * _maskH ~/ height;
    return _mask[my * _maskW + mx];
  }

  /// Every pixel as RGBA bytes.
  Future<Uint8List> rgbaBytes() async {
    final raw = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return raw!.buffer.asUint8List();
  }
}

(Uint8List, int, int) _buildAlphaMask(Uint8List rgba, int w, int h) {
  final k = (math.max(w, h) / 1024).ceil().clamp(1, 64);
  final mw = (w / k).ceil(), mh = (h / k).ceil();
  final mask = Uint8List(mw * mh);
  for (int y = 0; y < h; y++) {
    final row = (y ~/ k) * mw;
    for (int x = 0; x < w; x++) {
      final a = rgba[(y * w + x) * 4 + 3];
      final i = row + x ~/ k;
      if (a > mask[i]) mask[i] = a;
    }
  }
  return (mask, mw, mh);
}

/// Image data lives outside the undoable document: objects only hold ids, so
/// history snapshots stay tiny and an undone image can always come back.
class AssetStore {
  final Map<String, Asset> _assets = {};
  final Map<String, DateTime> _made = {};
  int _next = 1;

  Asset? operator [](String id) => _assets[id];
  Iterable<Asset> get all => _assets.values;
  int get length => _assets.length;

  Future<Asset> addEncoded(Uint8List bytes, {String? id}) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return _register(bytes, frame.image, id);
  }

  Future<Asset> addImage(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return _register(data!.buffer.asUint8List(), image, null);
  }

  Future<Asset> _register(Uint8List bytes, ui.Image image, String? id) async {
    final raw = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final assetId = id ?? 'a${_next++}';
    if (id != null) {
      final n = int.tryParse(id.substring(1));
      if (n != null && n >= _next) _next = n + 1;
    }
    final (mask, mw, mh) = _buildAlphaMask(
      raw!.buffer.asUint8List(),
      image.width,
      image.height,
    );
    final asset = Asset(assetId, bytes, image, mask, mw, mh);
    _assets[assetId] = asset;
    _made[assetId] = DateTime.now();
    return asset;
  }

  Map<String, String> encode(Set<String> used) => {
    for (final id in used)
      if (_assets[id] != null) id: base64Encode(_assets[id]!.bytes),
  };

  /// Drop every picture not in [keep] that is older than [minAge]. The images
  /// are left to the garbage collector (see [clear]).
  void retain(Set<String> keep, Duration minAge) {
    final cutoff = DateTime.now().subtract(minAge);
    _assets.removeWhere(
      (id, _) => !keep.contains(id) && (_made[id]?.isBefore(cutoff) ?? false),
    );
    _made.removeWhere((id, _) => !_assets.containsKey(id));
  }

  /// Forget a picture nothing refers to yet (one made for an edit that was
  /// then given up). The image is left for the garbage collector.
  void forget(String id) {
    _assets.remove(id);
    _made.remove(id);
  }

  /// For tests: pretend a picture was made [by] ago.
  void backdate(String id, Duration by) =>
      _made[id] = DateTime.now().subtract(by);

  /// Forget everything. Images are left for the garbage collector rather than
  /// disposed, because a widget built a moment ago may still paint one.
  void clear() {
    _assets.clear();
    _made.clear();
    _next = 1;
  }

  /// Take over another store's contents in one step.
  void replaceWith(AssetStore other) {
    _assets
      ..clear()
      ..addAll(other._assets);
    _made
      ..clear()
      ..addAll(other._made);
    _next = other._next;
  }
}
