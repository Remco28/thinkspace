import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Reading and writing `.thinkspace` files without stalling the window.
///
/// A project is a small document plus its images as base64, so nearly all of
/// a large file is image bytes. Encoding or decoding those on the UI isolate
/// froze the window for most of a second with a few photos, so above
/// [backgroundBytes] the work moves to a short-lived isolate. Small projects
/// stay on the UI isolate, where starting an isolate would cost more.
///
/// The file layout is exactly what `jsonEncode` of
/// `{format, version, document, assets}` gives, so either path reads the
/// other's files.
const backgroundBytes = 1 << 20;

/// The parts of a project file: the document's JSON and each image's bytes.
typedef ProjectParts = (Map<String, dynamic> document, Map<String, Uint8List>);

/// Write a project to [path] atomically: a temporary file beside it is
/// written in full, then renamed into place, so a crash or a full disk never
/// leaves a half-written project. [documentJson] is the encoded document.
Future<void> writeProjectFile(
  String path,
  String documentJson,
  Map<String, Uint8List> images,
) {
  final size = images.values.fold<int>(0, (n, b) => n + b.length);
  if (size < backgroundBytes) return _write(path, documentJson, images);
  return Isolate.run(() => _write(path, documentJson, images));
}

Future<void> _write(
  String path,
  String documentJson,
  Map<String, Uint8List> images,
) async {
  final tmp = File('$path.tmp');
  try {
    final sink = tmp.openWrite();
    sink.write('{"format":"thinkspace","version":1,"document":');
    sink.write(documentJson);
    sink.write(',"assets":{');
    var first = true;
    for (final e in images.entries) {
      if (!first) sink.write(',');
      first = false;
      // base64 never needs escaping inside a JSON string.
      sink
        ..write(jsonEncode(e.key))
        ..write(':"')
        ..write(base64Encode(e.value))
        ..write('"');
    }
    sink.write('}}');
    await sink.flush();
    await sink.close();
    await tmp.rename(path);
  } catch (_) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

/// Read and parse a project file, in the background when it is large.
Future<ProjectParts> readProjectFile(String path) async {
  final f = File(path);
  if (await f.length() < backgroundBytes) {
    return parseProject(await f.readAsString());
  }
  return Isolate.run(() => parseProject(File(path).readAsStringSync()));
}

/// Parse a project's text. Throws [FormatException] if it is not a
/// Thinkspace project or was made by a newer version. An image whose data is
/// not valid base64 comes back empty, so it fails to decode and the caller
/// counts it as unreadable.
ProjectParts parseProject(String s) {
  final j = jsonDecode(s);
  if (j is! Map<String, dynamic> || j['format'] != 'thinkspace') {
    throw const FormatException('Not a Thinkspace project');
  }
  final version = j['version'];
  if (version is num && version > 1) {
    throw const FormatException('This project was made by a newer Thinkspace');
  }
  final images = <String, Uint8List>{};
  final encoded = j['assets'];
  if (encoded is Map) {
    for (final e in encoded.entries) {
      try {
        images[e.key as String] = base64Decode(e.value as String);
      } catch (_) {
        images[e.key as String] = Uint8List(0);
      }
    }
  }
  return (Map<String, dynamic>.from(j['document']), images);
}
