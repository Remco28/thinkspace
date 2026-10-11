import 'dart:typed_data';

/// Pixels as straight (not premultiplied) RGBA, row by row from the top.
class RgbaPixels {
  RgbaPixels(this.width, this.height, this.rgba);
  final int width, height;
  final Uint8List rgba;
}

/// Read a Windows device-independent bitmap, the payload of the clipboard's
/// CF_DIB and CF_DIBV5 formats (a header, optional colour masks, then the
/// pixels). Handles the 24- and 32-bit bitmaps that screenshot tools and
/// browsers put there; anything else returns null.
///
/// No Windows calls are involved, so this runs (and is tested) anywhere.
RgbaPixels? decodeDib(Uint8List dib) {
  if (dib.length < 40) return null;
  final d = ByteData.sublistView(dib);
  final headerSize = d.getUint32(0, Endian.little);
  // 40 = BITMAPINFOHEADER, 108 = V4, 124 = V5. (12 = the ancient core header.)
  if (headerSize != 40 && headerSize != 108 && headerSize != 124) return null;
  if (dib.length < headerSize) return null;
  final width = d.getInt32(4, Endian.little);
  final rawHeight = d.getInt32(8, Endian.little);
  final bits = d.getUint16(14, Endian.little);
  final compression = d.getUint32(16, Endian.little);
  final colours = d.getUint32(32, Endian.little);
  if (width <= 0 || rawHeight == 0 || width > 32000) return null;
  final height = rawHeight.abs();
  if (height > 32000) return null;
  final topDown = rawHeight < 0;
  const biRgb = 0, biBitfields = 3;
  if (compression != biRgb && compression != biBitfields) return null;
  if (bits != 24 && bits != 32) return null;

  // Channel masks: in the header for V4/V5, after it for a plain 40-byte one.
  var offset = headerSize;
  var rMask = 0x00FF0000, gMask = 0x0000FF00, bMask = 0x000000FF, aMask = 0;
  if (compression == biBitfields) {
    if (headerSize >= 108) {
      rMask = d.getUint32(40, Endian.little);
      gMask = d.getUint32(44, Endian.little);
      bMask = d.getUint32(48, Endian.little);
      aMask = d.getUint32(52, Endian.little);
    } else {
      if (dib.length < 52) return null;
      rMask = d.getUint32(40, Endian.little);
      gMask = d.getUint32(44, Endian.little);
      bMask = d.getUint32(48, Endian.little);
      offset += 12;
    }
  } else if (headerSize >= 108) {
    aMask = d.getUint32(52, Endian.little);
    if (bits == 32 && aMask == 0) aMask = 0xFF000000;
  }
  offset += colours * 4;

  final stride = ((width * bits + 31) ~/ 32) * 4;
  if (offset + stride * height > dib.length) return null;

  int shiftOf(int mask) {
    if (mask == 0) return 0;
    var s = 0;
    while ((mask >> s) & 1 == 0) {
      s++;
    }
    return s;
  }

  int bitsIn(int mask) {
    var n = 0;
    for (var m = mask >> shiftOf(mask); m & 1 == 1; m >>= 1) {
      n++;
    }
    return n;
  }

  int channel(int px, int mask) {
    if (mask == 0) return 255;
    final n = bitsIn(mask);
    final v = (px & mask) >> shiftOf(mask);
    return n >= 8 ? v >> (n - 8) : (v * 255 ~/ ((1 << n) - 1));
  }

  final out = Uint8List(width * height * 4);
  var anyAlpha = false;
  for (var y = 0; y < height; y++) {
    final srcRow = offset + (topDown ? y : height - 1 - y) * stride;
    var o = y * width * 4;
    for (var x = 0; x < width; x++) {
      if (bits == 24) {
        final i = srcRow + x * 3;
        out[o] = dib[i + 2];
        out[o + 1] = dib[i + 1];
        out[o + 2] = dib[i];
        out[o + 3] = 255;
      } else {
        final px = d.getUint32(srcRow + x * 4, Endian.little);
        out[o] = channel(px, rMask);
        out[o + 1] = channel(px, gMask);
        out[o + 2] = channel(px, bMask);
        final a = aMask == 0 ? 255 : channel(px, aMask);
        out[o + 3] = a;
        if (a != 0) anyAlpha = true;
      }
      o += 4;
    }
  }
  // A 32-bit bitmap whose alpha is zero everywhere has no alpha at all (many
  // programs leave the byte unused); showing it as see-through would be wrong.
  if (bits == 32 && !anyAlpha) {
    for (var i = 3; i < out.length; i += 4) {
      out[i] = 255;
    }
  }
  return RgbaPixels(width, height, out);
}

/// A top-down, 32-bit CF_DIBV5 payload with straight alpha, for putting a
/// picture on the clipboard.
Uint8List encodeDibV5(RgbaPixels p) {
  const header = 124;
  final data = p.width * p.height * 4;
  final out = Uint8List(header + data);
  final d = ByteData.sublistView(out);
  d.setUint32(0, header, Endian.little);
  d.setInt32(4, p.width, Endian.little);
  d.setInt32(8, -p.height, Endian.little); // negative: rows run top to bottom
  d.setUint16(12, 1, Endian.little);
  d.setUint16(14, 32, Endian.little);
  d.setUint32(16, 3, Endian.little); // BI_BITFIELDS
  d.setUint32(20, data, Endian.little);
  d.setUint32(40, 0x00FF0000, Endian.little);
  d.setUint32(44, 0x0000FF00, Endian.little);
  d.setUint32(48, 0x000000FF, Endian.little);
  d.setUint32(52, 0xFF000000, Endian.little);
  d.setUint32(56, 0x73524742, Endian.little); // LCS_sRGB
  d.setUint32(108, 4, Endian.little); // LCS_GM_IMAGES
  var o = header;
  for (var i = 0; i < p.rgba.length; i += 4) {
    out[o] = p.rgba[i + 2];
    out[o + 1] = p.rgba[i + 1];
    out[o + 2] = p.rgba[i];
    out[o + 3] = p.rgba[i + 3];
    o += 4;
  }
  return out;
}
