import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A decoded raster image plus the encoded bytes it came from.
class Asset {
  Asset(this.id, this.bytes, this.image, this.rgba);
  final String id;
  final Uint8List bytes;
  final ui.Image image;
  final Uint8List rgba;
  int get width => image.width;
  int get height => image.height;

  int alphaAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    return rgba[(y * width + x) * 4 + 3];
  }
}

/// Image data lives outside the undoable document: objects only hold ids, so
/// history snapshots stay tiny and an undone image can always come back.
class AssetStore {
  final Map<String, Asset> _assets = {};
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
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final assetId = id ?? 'a${_next++}';
    if (id != null) {
      final n = int.tryParse(id.substring(1));
      if (n != null && n >= _next) _next = n + 1;
    }
    final asset = Asset(assetId, bytes, image, raw!.buffer.asUint8List());
    _assets[assetId] = asset;
    return asset;
  }

  Map<String, String> encode(Set<String> used) => {
        for (final id in used)
          if (_assets[id] != null) id: base64Encode(_assets[id]!.bytes),
      };

  void clear() {
    for (final a in _assets.values) {
      a.image.dispose();
    }
    _assets.clear();
    _next = 1;
  }
}
