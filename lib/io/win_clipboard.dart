import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';

import '../editor/image_ops.dart' show imageFromRgba;
import 'dib.dart';

/// The Windows clipboard, spoken to directly (no helper program, no plugin).
///
/// Everything that touches the clipboard happens on the main isolate, in one
/// synchronous stretch between Open and Close: the clipboard belongs to the
/// thread that opened it.
class WinClipboard {
  static const _cfDib = 8, _cfHdrop = 15, _cfDibV5 = 17;
  static const _gmemMoveable = 0x0002;

  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _shell32 = DynamicLibrary.open('shell32.dll');

  static final _openClipboard = _user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'OpenClipboard',
      );
  static final _closeClipboard = _user32
      .lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
  static final _emptyClipboard = _user32
      .lookupFunction<Int32 Function(), int Function()>('EmptyClipboard');
  static final _getClipboardData = _user32
      .lookupFunction<IntPtr Function(Uint32), int Function(int)>(
        'GetClipboardData',
      );
  static final _setClipboardData = _user32
      .lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>(
        'SetClipboardData',
      );
  static final _registerFormat = _user32
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)
      >('RegisterClipboardFormatW');
  static final _isFormatAvailable = _user32
      .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'IsClipboardFormatAvailable',
      );
  static final _activeWindow = _user32
      .lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow');
  static final _foregroundWindow = _user32
      .lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');

  static final _globalAlloc = _kernel32
      .lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>(
        'GlobalAlloc',
      );
  static final _globalFree = _kernel32
      .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalFree');
  static final _globalLock = _kernel32
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('GlobalLock');
  static final _globalUnlock = _kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'GlobalUnlock',
      );
  static final _globalSize = _kernel32
      .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalSize');

  static final _dragQueryFile = _shell32
      .lookupFunction<
        Uint32 Function(IntPtr, Uint32, Pointer<Utf16>, Uint32),
        int Function(int, int, Pointer<Utf16>, int)
      >('DragQueryFileW');

  static int _format(String name) {
    final p = name.toNativeUtf16();
    try {
      return _registerFormat(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Another program may be holding the clipboard for a moment.
  static Future<bool> _open() async {
    for (var i = 0; i < 6; i++) {
      // A window of ours must own the clipboard when it is written to; for
      // reading any (or none) will do.
      final hwnd = _activeWindow() != 0 ? _activeWindow() : _foregroundWindow();
      if (_openClipboard(hwnd) != 0) return true;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return false;
  }

  static Uint8List? _copyOut(int handle) {
    if (handle == 0) return null;
    final size = _globalSize(handle);
    final p = _globalLock(handle);
    if (p == nullptr || size <= 0) return null;
    try {
      return Uint8List.fromList(p.cast<Uint8>().asTypedList(size));
    } finally {
      _globalUnlock(handle);
    }
  }

  /// A picture on the clipboard as PNG bytes: the "PNG" format when the
  /// source offers it (exact, and with transparency), else the bitmap.
  static Future<Uint8List?> readImage() async {
    if (!await _open()) return null;
    Uint8List? png;
    Uint8List? dib;
    try {
      for (final name in const ['PNG', 'image/png']) {
        final fmt = _format(name);
        if (fmt != 0 && _isFormatAvailable(fmt) != 0) {
          png = _copyOut(_getClipboardData(fmt));
          if (png != null) break;
        }
      }
      if (png == null) {
        for (final f in const [_cfDibV5, _cfDib]) {
          if (_isFormatAvailable(f) != 0) {
            dib = _copyOut(_getClipboardData(f));
            if (dib != null) break;
          }
        }
      }
    } finally {
      _closeClipboard();
    }
    if (png != null) return png;
    final pixels = dib == null ? null : decodeDib(dib);
    if (pixels == null) return null;
    final image = await imageFromRgba(pixels.rgba, pixels.width, pixels.height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  /// Files copied in Explorer (Ctrl+C on files), as paths.
  static Future<List<String>> readFiles() async {
    if (!await _open()) return const [];
    final out = <String>[];
    try {
      if (_isFormatAvailable(_cfHdrop) == 0) return const [];
      final h = _getClipboardData(_cfHdrop);
      if (h == 0) return const [];
      final count = _dragQueryFile(h, 0xFFFFFFFF, nullptr, 0);
      for (var i = 0; i < count; i++) {
        final len = _dragQueryFile(h, i, nullptr, 0);
        if (len == 0) continue;
        final buf = calloc<Uint16>(len + 1).cast<Utf16>();
        try {
          _dragQueryFile(h, i, buf, len + 1);
          out.add(buf.toDartString());
        } finally {
          calloc.free(buf);
        }
      }
    } finally {
      _closeClipboard();
    }
    return out;
  }

  /// Make a global memory block holding [bytes] for the clipboard to own.
  static int _block(Uint8List bytes) {
    final h = _globalAlloc(_gmemMoveable, bytes.length);
    if (h == 0) return 0;
    final p = _globalLock(h);
    if (p == nullptr) {
      _globalFree(h);
      return 0;
    }
    p.cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
    _globalUnlock(h);
    return h;
  }

  /// Put a picture on the clipboard: as "PNG" (transparency intact, which
  /// browsers and chat programs read) and as a 32-bit bitmap (which Paint and
  /// Word read; Windows derives the older bitmap formats from it).
  static Future<bool> writeImage(Uint8List png) async {
    Uint8List? dib;
    try {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      final w = frame.image.width, h = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (data != null) {
        dib = encodeDibV5(
          RgbaPixels(w, h, data.buffer.asUint8List(0, w * h * 4)),
        );
      }
    } catch (_) {}
    if (!await _open()) return false;
    var ok = false;
    try {
      if (_emptyClipboard() == 0) return false;
      final pngBlock = _block(png);
      if (pngBlock != 0) {
        if (_setClipboardData(_format('PNG'), pngBlock) != 0) {
          ok = true;
        } else {
          _globalFree(pngBlock); // the clipboard did not take it
        }
      }
      final dibBlock = dib == null ? 0 : _block(dib);
      if (dibBlock != 0) {
        if (_setClipboardData(_cfDibV5, dibBlock) != 0) {
          ok = true;
        } else {
          _globalFree(dibBlock);
        }
      }
    } finally {
      _closeClipboard();
    }
    return ok;
  }
}
