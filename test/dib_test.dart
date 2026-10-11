import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/io/dib.dart';

/// A BITMAPINFOHEADER (40 bytes) for the tests.
Uint8List _header40({
  required int w,
  required int h,
  required int bits,
  int compression = 0,
  int colours = 0,
}) {
  final b = Uint8List(40);
  final d = ByteData.sublistView(b);
  d.setUint32(0, 40, Endian.little);
  d.setInt32(4, w, Endian.little);
  d.setInt32(8, h, Endian.little);
  d.setUint16(12, 1, Endian.little);
  d.setUint16(14, bits, Endian.little);
  d.setUint32(16, compression, Endian.little);
  d.setUint32(32, colours, Endian.little);
  return b;
}

void main() {
  test('a 24-bit bottom-up bitmap, with row padding, reads back top-down', () {
    // 3 px wide: each row is 9 bytes + 3 padding = 12. Two rows.
    final rows = [
      // bottom row first: blue, green, red (as B,G,R)
      [255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0],
      // top row: white, black, grey
      [255, 255, 255, 0, 0, 0, 128, 128, 128, 0, 0, 0],
    ];
    final dib = Uint8List.fromList([
      ..._header40(w: 3, h: 2, bits: 24),
      ...rows.expand((r) => r),
    ]);
    final img = decodeDib(dib)!;
    expect((img.width, img.height), (3, 2));
    List<int> px(int x, int y) =>
        img.rgba.sublist((y * 3 + x) * 4, (y * 3 + x) * 4 + 4);
    expect(px(0, 0), [255, 255, 255, 255]);
    expect(px(1, 0), [0, 0, 0, 255]);
    expect(px(2, 0), [128, 128, 128, 255]);
    expect(px(0, 1), [0, 0, 255, 255], reason: 'B,G,R = blue');
    expect(px(1, 1), [0, 255, 0, 255]);
    expect(px(2, 1), [255, 0, 0, 255]);
  });

  test('a 32-bit bitmap with no alpha in use is opaque, not see-through', () {
    final dib = Uint8List.fromList([
      ..._header40(w: 1, h: 1, bits: 32),
      10, 20, 30, 0, // B, G, R, unused
    ]);
    expect(decodeDib(dib)!.rgba, [30, 20, 10, 255]);
  });

  test('a top-down 32-bit bitmap with an alpha mask keeps its alpha', () {
    final h = Uint8List(124);
    final d = ByteData.sublistView(h);
    d.setUint32(0, 124, Endian.little);
    d.setInt32(4, 2, Endian.little);
    d.setInt32(8, -1, Endian.little); // top-down
    d.setUint16(12, 1, Endian.little);
    d.setUint16(14, 32, Endian.little);
    d.setUint32(16, 3, Endian.little);
    d.setUint32(40, 0x00FF0000, Endian.little);
    d.setUint32(44, 0x0000FF00, Endian.little);
    d.setUint32(48, 0x000000FF, Endian.little);
    d.setUint32(52, 0xFF000000, Endian.little);
    final dib = Uint8List.fromList([
      ...h,
      0, 0, 255, 128, // red at half alpha (B,G,R,A)
      9, 8, 7, 0, // fully see-through
    ]);
    final img = decodeDib(dib)!;
    expect(img.rgba.sublist(0, 4), [255, 0, 0, 128]);
    expect(img.rgba[7], 0, reason: 'alpha stays as given when some is used');
  });

  test('a plain 40-byte header with BI_BITFIELDS reads its masks', () {
    // RGB565-style masks are unusual; use BGRA order swapped to RGBA masks.
    final h = _header40(w: 1, h: 1, bits: 32, compression: 3);
    final masks = Uint8List(12);
    final m = ByteData.sublistView(masks);
    m.setUint32(0, 0x000000FF, Endian.little); // red in the low byte
    m.setUint32(4, 0x0000FF00, Endian.little);
    m.setUint32(8, 0x00FF0000, Endian.little);
    final dib = Uint8List.fromList([...h, ...masks, 200, 100, 50, 0]);
    expect(decodeDib(dib)!.rgba, [200, 100, 50, 255]);
  });

  test('unsupported or damaged data gives null, never a crash', () {
    expect(decodeDib(Uint8List(0)), isNull);
    expect(decodeDib(Uint8List(60)), isNull, reason: 'header size 0');
    expect(
      decodeDib(Uint8List.fromList(_header40(w: 4, h: 4, bits: 8))),
      isNull,
      reason: 'palette bitmaps are not supported',
    );
    expect(
      decodeDib(Uint8List.fromList(_header40(w: 100, h: 100, bits: 24))),
      isNull,
      reason: 'the pixels are missing',
    );
    expect(
      decodeDib(Uint8List.fromList(_header40(w: 0, h: 5, bits: 24))),
      isNull,
    );
  });

  test('what is encoded for the clipboard reads back the same', () {
    final rgba = Uint8List.fromList([
      255, 0, 0, 255, 0, 255, 0, 128, //
      0, 0, 255, 0, 10, 20, 30, 255,
    ]);
    final back = decodeDib(encodeDibV5(RgbaPixels(2, 2, rgba)))!;
    expect((back.width, back.height), (2, 2));
    expect(back.rgba, rgba);
  });
}
