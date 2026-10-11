import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'win_clipboard.dart';

/// Flutter's clipboard only carries text, so images need help. On Windows they
/// go through the system clipboard directly ([WinClipboard]); on Linux through
/// the command line tools every desktop already has: wl-clipboard on Wayland
/// and xclip on X11.
class SystemClipboard {
  static final _png = [0x89, 0x50, 0x4E, 0x47];

  static bool get _wayland =>
      (Platform.environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;

  static Future<Uint8List?> readImage() async {
    if (Platform.isWindows) return WinClipboard.readImage();
    final attempts = <List<String>>[
      if (_wayland) ['wl-paste', '--no-newline', '--type', 'image/png'],
      ['xclip', '-selection', 'clipboard', '-t', 'image/png', '-o'],
    ];
    for (final cmd in attempts) {
      final bytes = await _run(cmd);
      if (bytes != null && bytes.length > 8 && _isPng(bytes)) return bytes;
    }
    // Some sources only offer JPEG.
    final jpeg = await _run([
      'xclip',
      '-selection',
      'clipboard',
      '-t',
      'image/jpeg',
      '-o',
    ]);
    if (jpeg != null && jpeg.length > 4 && jpeg[0] == 0xFF && jpeg[1] == 0xD8) {
      return jpeg;
    }
    return null;
  }

  static bool _isPng(Uint8List b) {
    for (int i = 0; i < _png.length; i++) {
      if (b[i] != _png[i]) return false;
    }
    return true;
  }

  static Future<Uint8List?> _run(List<String> cmd) async {
    try {
      final r = await Process.run(
        cmd.first,
        cmd.sublist(1),
        stdoutEncoding: null,
      ).timeout(const Duration(seconds: 4));
      if (r.exitCode != 0) return null;
      return Uint8List.fromList(r.stdout as List<int>);
    } catch (_) {
      return null;
    }
  }

  /// Put a PNG on the clipboard. Returns false if no tool is available.
  static Future<bool> writeImage(Uint8List png) async {
    if (Platform.isWindows) return WinClipboard.writeImage(png);
    final cmds = <List<String>>[
      if (_wayland) ['wl-copy', '--type', 'image/png'],
      ['xclip', '-selection', 'clipboard', '-t', 'image/png', '-i'],
    ];
    for (final cmd in cmds) {
      try {
        // xclip and wl-copy stay alive to serve the selection, so don't wait
        // for them to exit.
        final p = await Process.start(
          cmd.first,
          cmd.sublist(1),
          mode: ProcessStartMode.detachedWithStdio,
        );
        p.stdin.add(png);
        await p.stdin.close();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return true;
      } catch (_) {}
    }
    return false;
  }

  static const _pictureTypes = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'};

  /// Picture files that were copied in a file manager (Ctrl+C on files), as
  /// paths. Empty when the clipboard holds something else.
  static Future<List<String>> readPictureFiles() async {
    final all = Platform.isWindows
        ? await WinClipboard.readFiles()
        : await _linuxFiles();
    return [
      for (final f in all)
        if (_pictureTypes.contains(f.split('.').last.toLowerCase())) f,
    ];
  }

  static Future<List<String>> _linuxFiles() async {
    final attempts = <List<String>>[
      if (_wayland) ['wl-paste', '--no-newline', '--type', 'text/uri-list'],
      ['xclip', '-selection', 'clipboard', '-t', 'text/uri-list', '-o'],
      // GNOME's file manager says "copy" or "cut" on the first line.
      [
        'xclip',
        '-selection',
        'clipboard',
        '-t',
        'x-special/gnome-copied-files',
        '-o',
      ],
    ];
    for (final cmd in attempts) {
      final bytes = await _run(cmd);
      if (bytes == null || bytes.isEmpty) continue;
      final files = parseFileList(String.fromCharCodes(bytes));
      if (files.isNotEmpty) return files;
    }
    return const [];
  }

  /// Paths from a text/uri-list style block: one `file://` address a line.
  static List<String> parseFileList(String text) {
    final out = <String>[];
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final t = line.trim();
      if (!t.startsWith('file://')) continue;
      try {
        out.add(Uri.parse(t).toFilePath());
      } catch (_) {}
    }
    return out;
  }
}
