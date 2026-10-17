import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/editor/interactor.dart';
import 'package:thinkspace/model/scene.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorController c;
  late CanvasInteractor ix;

  setUp(() {
    c = newEditor();
    ix = CanvasInteractor(c);
  });

  /// A pen stroke, an arrow, a picture and a text box, all crossing the
  /// vertical line x = 300.
  Future<void> fill() async {
    c.setTool(Tool.pen);
    drag(ix, const Offset(250, 100), const Offset(350, 100));
    c.setTool(Tool.arrow);
    drag(ix, const Offset(250, 200), const Offset(350, 200));
    final a = await makeAsset(c, w: 100, h: 40);
    c.currentLayer.objects.addAll([
      ImageObject(
        id: c.doc.newId('o'),
        name: 'picture',
        assetId: a.id,
        center: const Offset(300, 300),
        size: const Size(100, 40),
      ),
      TextObject(
        id: c.doc.newId('o'),
        name: 'words',
        text: 'Hello',
        center: const Offset(300, 400),
        size: const Size(100, 40),
      ),
    ]);
    c.setTool(Tool.remove);
  }

  test('a sweep removes marks and leaves pictures and text', () async {
    await fill();
    final before = c.undoDepth;
    ix.pointerDown(const Offset(300, 50), noMods);
    ix.pointerMove(const Offset(300, 150), noMods);
    expect(c.removing, hasLength(1), reason: 'the pen stroke, faded so far');
    expect(c.doc.allObjects, hasLength(4), reason: 'nothing gone mid-drag');
    // One jump straight across the rest: everything in between still counts.
    ix.pointerMove(const Offset(300, 450), noMods);
    ix.pointerUp(const Offset(300, 450), noMods);
    expect(c.removing, isEmpty);
    expect(c.doc.allObjects.map((o) => o.kind), [
      ObjectKind.image,
      ObjectKind.text,
    ]);
    expect(c.undoDepth, before + 1);
    expect(c.undoLabel, 'remove marks');
    expect(c.tool, Tool.remove, reason: 'the tool stays for another sweep');
    c.undo();
    expect(c.doc.allObjects, hasLength(4));
  });

  test('a sweep over nothing removable leaves no undo step', () async {
    await fill();
    final before = c.undoDepth;
    drag(ix, const Offset(280, 300), const Offset(320, 400));
    expect(c.doc.allObjects, hasLength(4));
    expect(c.undoDepth, before);
  });

  test('locked things and hidden layers are left alone', () async {
    await fill();
    c.doc.allObjects.firstWhere((o) => o is StrokeObject).locked = true;
    c.currentLayer.visible = false;
    drag(ix, const Offset(300, 50), const Offset(300, 250));
    expect(c.doc.allObjects, hasLength(4));
  });

  test('Escape mid-sweep keeps everything', () async {
    await fill();
    ix.pointerDown(const Offset(300, 50), noMods);
    ix.pointerMove(const Offset(300, 250), noMods);
    expect(c.removing, hasLength(2));
    ix.cancel();
    ix.pointerUp(const Offset(300, 250), noMods);
    expect(c.removing, isEmpty);
    expect(c.doc.allObjects, hasLength(4));
  });
}
