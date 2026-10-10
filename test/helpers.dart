import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/editor/interactor.dart';
import 'package:thinkspace/model/assets.dart';

/// A controller with a known 1:1 view so scene and screen coordinates agree.
EditorController newEditor() {
  final c = EditorController();
  c.viewport = const ui.Size(1200, 900);
  c.zoom = 1;
  c.pan = ui.Offset.zero;
  return c;
}

/// A solid image, optionally with a differently coloured square in the middle.
Future<Asset> makeAsset(EditorController c, {int w = 200, int h = 100, int color = 0xFFFF0000, int? centerColor}) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = Color(color));
  if (centerColor != null) {
    canvas.drawRect(ui.Rect.fromCenter(center: ui.Offset(w / 2, h / 2), width: w / 2, height: h / 2), ui.Paint()..color = Color(centerColor));
  }
  final img = await rec.endRecording().toImage(w, h);
  return c.assets.addImage(img);
}

const noMods = Modifiers();

void drag(CanvasInteractor ix, ui.Offset a, ui.Offset b, {Modifiers m = noMods, int steps = 6}) {
  ix.pointerDown(a, m);
  for (int i = 1; i <= steps; i++) {
    ix.pointerMove(ui.Offset.lerp(a, b, i / steps)!, m);
  }
  ix.pointerUp(b, m);
}

void click(CanvasInteractor ix, ui.Offset p, {Modifiers m = noMods}) {
  ix.pointerDown(p, m);
  ix.pointerUp(p, m);
}
