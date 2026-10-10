import 'dart:io';

import 'package:file_selector/file_selector.dart';

const _images = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
);
const _project = XTypeGroup(
  label: 'Thinkspace projects',
  extensions: ['thinkspace'],
);
const _png = XTypeGroup(label: 'PNG image', extensions: ['png']);

Future<List<String>> pickImages() async {
  final files = await openFiles(acceptedTypeGroups: [_images]);
  return [for (final f in files) f.path];
}

Future<String?> pickProject() async =>
    (await openFile(acceptedTypeGroups: [_project]))?.path;

Future<String?> chooseProjectPath(String suggested) async {
  final loc = await getSaveLocation(
    acceptedTypeGroups: [_project],
    suggestedName: suggested,
  );
  if (loc == null) return null;
  return loc.path.endsWith('.thinkspace') ? loc.path : '${loc.path}.thinkspace';
}

Future<String?> choosePngPath(String suggested) async {
  final loc = await getSaveLocation(
    acceptedTypeGroups: [_png],
    suggestedName: suggested,
  );
  if (loc == null) return null;
  return loc.path.toLowerCase().endsWith('.png') ? loc.path : '${loc.path}.png';
}

String baseName(String path) {
  final n = path.split(Platform.pathSeparator).last;
  return n.replaceAll(RegExp(r'\.[^.]+$'), '');
}
