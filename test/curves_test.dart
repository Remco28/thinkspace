import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/editor/interactor.dart';
import 'package:thinkspace/model/assets.dart';
import 'package:thinkspace/model/scene.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('curved lines', () {
    LineObject line({Offset bend = Offset.zero}) => LineObject(
      id: 'l',
      name: 'l',
      p1: const Offset(0, 0),
      p2: const Offset(200, 0),
      width: 4,
      bend: bend,
    );

    test('the bend point is where the curve passes halfway', () {
      final l = line()..mid = const Offset(100, -50);
      expect(l.curved, isTrue);
      expect(l.bend, const Offset(0, -0.25));
      expect(l.pointAt(0.5), const Offset(100, -50));
      expect(l.mid, const Offset(100, -50));
    });

    test('a curve is hit along the curve, not along the straight line', () {
      final l = line(bend: const Offset(0, -0.25));
      final assets = AssetStore();
      expect(l.hitTest(const Offset(100, -50), 2, assets), isTrue);
      expect(l.hitTest(const Offset(100, 0), 2, assets), isFalse);
      expect(l.bounds.top, lessThan(-50));
    });

    test('the bend follows the ends when they move', () {
      final l = line(bend: const Offset(0, -0.25));
      l.p2 = const Offset(400, 0);
      expect(l.mid, const Offset(200, -100));
      l.translate(const Offset(10, 10));
      expect(l.mid, const Offset(210, -90));
    });

    test('the bend is saved, and a straight line saves as before', () {
      final curved = line(bend: const Offset(0.1, -0.25));
      final back = SceneObject.fromJson(curved.toJson()) as LineObject;
      expect(back.bend, const Offset(0.1, -0.25));
      expect(line().toJson().containsKey('bend'), isFalse);
      expect(
        (SceneObject.fromJson(line().toJson()) as LineObject).curved,
        isFalse,
      );
    });
  });

  group('bending on the page', () {
    late EditorController c;
    late CanvasInteractor ix;

    setUp(() {
      c = newEditor();
      ix = CanvasInteractor(c);
    });

    LineObject drawArrow() {
      c.setTool(Tool.arrow);
      drag(ix, const Offset(100, 100), const Offset(300, 100));
      return c.doc.allObjects.single as LineObject;
    }

    test('dragging the middle bends an arrow in one undo step', () {
      final l = drawArrow();
      final before = c.undoDepth;
      drag(ix, const Offset(200, 100), const Offset(200, 40));
      expect(l.curved, isTrue);
      expect(l.mid, const Offset(200, 40));
      expect(c.undoDepth, before + 1);
      expect(c.undoLabel, 'bend');
      c.undo();
      expect((c.doc.allObjects.single as LineObject).curved, isFalse);
    });

    test('near the straight line it snaps straight again', () {
      final l = drawArrow();
      drag(ix, const Offset(200, 100), const Offset(200, 40));
      drag(ix, const Offset(200, 40), const Offset(203, 103));
      expect(l.curved, isFalse);
    });

    test('near the middle it snaps to an even arc; Ctrl does not snap', () {
      final l = drawArrow();
      drag(ix, const Offset(200, 100), const Offset(204, 40));
      expect(l.bend.dx, 0);
      drag(
        ix,
        const Offset(200, 40),
        const Offset(204, 40),
        m: const Modifiers(ctrl: true),
      );
      expect(l.mid, const Offset(204, 40));
    });
  });

  group('eyedropper', () {
    test('a click on the page answers with the colour there', () async {
      final c = newEditor();
      c.doc.background = 0xFF123456;
      c.doc.layers.first.objects.add(
        ShapeObject(
          id: 'r',
          name: 'r',
          ellipse: false,
          center: const Offset(100, 100),
          size: const Size(50, 50),
          fill: 0xFFFF8800,
          strokeWidth: 0,
        ),
      );
      final pick = c.pickColourFromPage();
      expect(c.pickingColour, isTrue);
      for (int i = 0; i < 200 && c.colourAt(Offset.zero) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(c.colourAt(const Offset(5, 5)), 0xFF123456);
      expect(c.colourAt(const Offset(100, 100)), 0xFFFF8800);
      expect(c.colourAt(const Offset(-5, 5)), isNull, reason: 'off the page');
      c.finishColourPick(c.colourAt(const Offset(100, 100)));
      expect(await pick, 0xFFFF8800);
      expect(c.pickingColour, isFalse);
    });

    test('changing tool cancels the pick', () async {
      final c = newEditor();
      final pick = c.pickColourFromPage();
      c.setTool(Tool.pen);
      expect(await pick, isNull);
    });
  });
}
