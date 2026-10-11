import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/editor/image_ops.dart';
import 'package:thinkspace/editor/interactor.dart';
import 'package:thinkspace/editor/render.dart';
import 'package:thinkspace/model/assets.dart';
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

  Future<ImageObject> addImage({
    Offset at = const Offset(300, 300),
    int w = 200,
    int h = 100,
    int color = 0xFFFF0000,
    int? centerColor,
  }) async {
    final a = await makeAsset(
      c,
      w: w,
      h: h,
      color: color,
      centerColor: centerColor,
    );
    c.doc.canvasSize = const Size(1600, 1000); // not "pristine"
    c.doc.layers.first.objects.add(
      ImageObject(
        id: c.doc.newId('o'),
        name: 'image ${c.doc.nextId}',
        assetId: a.id,
        center: at,
        size: Size(w.toDouble(), h.toDouble()),
      ),
    );
    return c.doc.layers.first.objects.last as ImageObject;
  }

  group('drawing', () {
    test('an arrow is one drag and one undo', () {
      c.setTool(Tool.arrow);
      drag(ix, const Offset(100, 100), const Offset(300, 200));
      final l = c.doc.allObjects.single as LineObject;
      expect(l.headEnd, isTrue);
      expect(l.p1, const Offset(100, 100));
      expect(l.p2, const Offset(300, 200));
      expect(c.tool, Tool.select, reason: 'tools hand back to select');
      expect(c.undoDepth, 1);
      c.undo();
      expect(c.doc.allObjects, isEmpty);
      c.redo();
      expect(c.doc.allObjects.single, isA<LineObject>());
    });

    test('an arrow can be resized by dragging either end', () {
      c.setTool(Tool.arrow);
      drag(ix, const Offset(100, 100), const Offset(300, 100));
      final l = c.doc.allObjects.single as LineObject;
      drag(ix, const Offset(300, 100), const Offset(400, 250));
      expect(l.p2, const Offset(400, 250));
      drag(ix, const Offset(100, 100), const Offset(50, 60));
      expect(l.p1, const Offset(50, 60));
      expect(c.undoDepth, 3);
    });

    test('shift keeps a line on a 15 degree step', () {
      c.setTool(Tool.line);
      drag(
        ix,
        const Offset(100, 100),
        const Offset(300, 110),
        m: const Modifiers(shift: true),
      );
      final l = c.doc.allObjects.single as LineObject;
      expect((l.p2 - l.p1).direction, closeTo(0, 1e-9));
    });

    test('a click without dragging draws nothing', () {
      c.setTool(Tool.line);
      click(ix, const Offset(100, 100));
      expect(c.doc.allObjects, isEmpty);
      expect(c.undoDepth, 0);
    });

    test('rectangles, ellipses and a click-made default shape', () {
      c.setTool(Tool.rect);
      drag(ix, const Offset(100, 100), const Offset(260, 180));
      final r = c.doc.allObjects.single as ShapeObject;
      expect(r.size, const Size(160, 80));
      expect(r.center, const Offset(180, 140));
      c.setTool(Tool.ellipse);
      click(ix, const Offset(500, 500));
      expect(c.doc.allObjects.length, 2);
      expect((c.doc.allObjects.last as ShapeObject).ellipse, isTrue);
    });

    test('the pen records and simplifies a stroke', () {
      c.setTool(Tool.pen);
      ix.pointerDown(const Offset(100, 100), noMods);
      for (int i = 1; i <= 40; i++) {
        ix.pointerMove(
          Offset(100 + i * 5.0, 100 + (i.isEven ? 0.3 : 0)),
          noMods,
        );
      }
      ix.pointerUp(const Offset(300, 100), noMods);
      final s = c.doc.allObjects.single as StrokeObject;
      expect(s.points.length, lessThan(6));
      expect(c.tool, Tool.pen, reason: 'the pen stays active for more strokes');
    });

    test('text: click, type, and an empty one disappears', () {
      c.setTool(Tool.text);
      click(ix, const Offset(120, 140));
      expect(c.editingTextId, isNotNull);
      c.updateEditingText('Hello');
      c.finishTextEdit();
      final t = c.doc.allObjects.single as TextObject;
      expect(t.text, 'Hello');
      expect(c.undoDepth, 1, reason: 'creating and typing is a single step');

      c.setTool(Tool.text);
      click(ix, const Offset(120, 400));
      c.updateEditingText('');
      c.finishTextEdit();
      expect(c.doc.allObjects.length, 1);
    });

    test('a locked tool keeps drawing', () {
      c.setTool(Tool.arrow, lock: true);
      drag(ix, const Offset(0, 0), const Offset(100, 0));
      drag(ix, const Offset(0, 50), const Offset(100, 50));
      expect(c.doc.allObjects.length, 2);
      expect(c.tool, Tool.arrow);
    });
  });

  group('selecting and transforming', () {
    test('moving is one undo step regardless of how many moves', () async {
      final img = await addImage();
      drag(ix, const Offset(300, 300), const Offset(400, 380), steps: 20);
      expect(img.center, const Offset(400, 380));
      expect(c.undoDepth, 1);
      c.undo();
      expect(
        (c.doc.allObjects.single as ImageObject).center,
        const Offset(300, 300),
      );
    });

    test('a tiny wobble while clicking does not move anything', () async {
      await addImage();
      ix.pointerDown(const Offset(300, 300), noMods);
      ix.pointerMove(const Offset(301, 301), noMods);
      ix.pointerUp(const Offset(301, 301), noMods);
      expect(
        (c.doc.allObjects.single as ImageObject).center,
        const Offset(300, 300),
      );
      expect(c.undoDepth, 0);
    });

    test('shift while moving locks an axis', () async {
      await addImage();
      drag(
        ix,
        const Offset(300, 300),
        const Offset(400, 320),
        m: const Modifiers(shift: true),
      );
      expect(
        (c.doc.allObjects.single as ImageObject).center,
        const Offset(400, 300),
      );
    });

    test('snapping aligns an object to the grid; ctrl bypasses it', () async {
      final img = await addImage(at: const Offset(300, 300));
      c.snapOn = true;
      c.doc.gridSize = 40;
      drag(ix, const Offset(300, 300), const Offset(353, 337));
      // The nearest of left / centre / right edges lands on a grid line.
      final b = img.bounds;
      final onGrid = [
        b.left,
        b.center.dx,
        b.right,
      ].any((v) => (v / 40 - (v / 40).round()).abs() < 1e-6);
      expect(onGrid, isTrue);
      final before = img.center;
      drag(
        ix,
        const Offset(353, 337),
        const Offset(373, 357),
        m: const Modifiers(ctrl: true),
      );
      expect(
        img.center - before,
        const Offset(20, 20),
        reason: 'ctrl moves freely',
      );
    });

    test('corner handles resize an image proportionally', () async {
      final img = await addImage(at: const Offset(300, 300), w: 200, h: 100);
      c.select([img.id]);
      // Bottom-right corner is at (400, 350).
      drag(ix, const Offset(400, 350), const Offset(500, 380));
      expect(img.size.width / img.size.height, closeTo(2, 1e-6));
      expect(img.size.width, greaterThan(250));
      // Top-left stayed put.
      expect(img.bounds.topLeft.dx, closeTo(200, 1e-6));
      expect(img.bounds.topLeft.dy, closeTo(250, 1e-6));
    });

    test('shift releases the aspect lock on an image', () async {
      final img = await addImage(at: const Offset(300, 300), w: 200, h: 100);
      c.select([img.id]);
      drag(
        ix,
        const Offset(400, 350),
        const Offset(500, 350),
        m: const Modifiers(shift: true),
      );
      expect(img.size.height, closeTo(100, 1e-6));
      expect(img.size.width, closeTo(300, 1e-6));
    });

    test('resizing a rotated object keeps the opposite corner fixed', () async {
      final img = await addImage(at: const Offset(300, 300), w: 200, h: 100);
      img.rotation = math.pi / 6;
      c.select([img.id]);
      final anchor = img.corners[0];
      final handle = img.corners[2];
      drag(ix, handle, handle + const Offset(60, 40));
      expect(img.corners[0].dx, closeTo(anchor.dx, 1e-6));
      expect(img.corners[0].dy, closeTo(anchor.dy, 1e-6));
      expect(img.rotation, closeTo(math.pi / 6, 1e-9));
    });

    test(
      'the rotate handle turns an object and snaps near 15 degrees',
      () async {
        final img = await addImage(at: const Offset(300, 300), w: 200, h: 100);
        c.select([img.id]);
        // Rotate handle sits 30px above the top edge.
        const handle = Offset(300, 250 - 30);
        drag(
          ix,
          handle,
          const Offset(500, 300 + 1),
        ); // pointing right => 90 degrees
        expect(img.rotation, closeTo(math.pi / 2, 0.02));
        expect(c.undoDepth, 1);
      },
    );

    test('click again reaches the object underneath', () async {
      final back = await addImage(
        at: const Offset(300, 300),
        w: 300,
        h: 300,
        color: 0xFF00FF00,
      );
      final front = await addImage(
        at: const Offset(320, 320),
        w: 300,
        h: 300,
        color: 0xFF0000FF,
      );
      click(ix, const Offset(320, 320));
      expect(c.selection, [front.id]);
      click(ix, const Offset(320, 320));
      expect(c.selection, [
        back.id,
      ], reason: 'a second click goes down the stack');
      click(ix, const Offset(320, 320));
      expect(c.selection, [front.id]);
    });

    test('alt-click picks the one beneath directly', () async {
      final back = await addImage(at: const Offset(300, 300), w: 300, h: 300);
      final front = await addImage(at: const Offset(320, 320), w: 300, h: 300);
      click(ix, const Offset(320, 320));
      expect(c.selection, [front.id]);
      click(ix, const Offset(320, 320), m: const Modifiers(alt: true));
      expect(c.selection, [back.id]);
    });

    test('a selected object behind another can still be dragged', () async {
      final back = await addImage(at: const Offset(300, 300), w: 300, h: 300);
      await addImage(at: const Offset(320, 320), w: 300, h: 300);
      c.select([back.id]);
      drag(ix, const Offset(320, 320), const Offset(420, 320));
      expect(back.center, const Offset(400, 300));
    });

    test('transparent pixels are not grabbable', () async {
      // A cutout-like image: opaque only in its left half.
      final back = await addImage(
        at: const Offset(300, 300),
        w: 200,
        h: 200,
        color: 0xFF00FF00,
      );
      final a = await makeAsset(c, w: 100, h: 100, color: 0x00000000);
      final ghost = ImageObject(
        id: c.doc.newId('o'),
        name: 'ghost',
        assetId: a.id,
        center: const Offset(300, 300),
        size: const Size(200, 200),
      );
      c.doc.layers.first.objects.add(ghost);
      click(ix, const Offset(300, 300));
      expect(c.selection, [back.id]);
    });

    test('marquee selects what it touches; shift adds', () async {
      final a = await addImage(at: const Offset(100, 100), w: 50, h: 50);
      final b = await addImage(at: const Offset(300, 100), w: 50, h: 50);
      final far = await addImage(at: const Offset(900, 700), w: 50, h: 50);
      drag(ix, const Offset(20, 20), const Offset(350, 160));
      expect(c.selection.toSet(), {a.id, b.id});
      drag(
        ix,
        const Offset(800, 600),
        const Offset(1000, 800),
        m: const Modifiers(shift: true),
      );
      expect(c.selection.toSet(), {a.id, b.id, far.id});
    });

    test('arrow keys nudge, escape clears', () async {
      final img = await addImage();
      c.select([img.id]);
      c.nudge(const Offset(10, 0));
      expect(img.center, const Offset(310, 300));
      expect(c.undoDepth, 1);
    });
  });

  group('layers', () {
    test('adding, hiding, reordering and deleting layers', () {
      c.addLayer();
      c.addLayer();
      expect(c.doc.layers.map((l) => l.name), [
        'Layer 1',
        'Layer 2',
        'Layer 3',
      ]);
      c.moveLayer(2, 0);
      expect(c.doc.layers.map((l) => l.name), [
        'Layer 3',
        'Layer 1',
        'Layer 2',
      ]);
      c.setLayerVisible(c.doc.layers[1].id, false);
      expect(c.doc.layers[1].visible, isFalse);
      c.undo();
      expect(c.doc.layers[1].visible, isTrue);
      c.deleteLayer(c.doc.layers.first.id);
      expect(c.doc.layers.length, 2);
    });

    test('the last layer cannot be deleted', () {
      c.deleteLayer(c.doc.layers.first.id);
      expect(c.doc.layers.length, 1);
    });

    test('hidden layers and hidden objects cannot be hit', () async {
      final img = await addImage();
      expect(c.objectsAt(const Offset(300, 300)), [img]);
      c.setObjectVisible(img.id, false);
      expect(c.objectsAt(const Offset(300, 300)), isEmpty);
      c.setObjectVisible(img.id, true);
      c.setLayerVisible(c.doc.layers.first.id, false);
      expect(c.objectsAt(const Offset(300, 300)), isEmpty);
    });

    test(
      'selecting a layer selects its contents, which move together',
      () async {
        final a = await addImage(at: const Offset(100, 100), w: 50, h: 50);
        final b = await addImage(at: const Offset(300, 100), w: 50, h: 50);
        c.addLayer();
        final other = await makeAsset(c);
        c.currentLayer.objects.add(
          ImageObject(
            id: c.doc.newId('o'),
            name: 'other',
            assetId: other.id,
            center: const Offset(500, 500),
            size: const Size(50, 50),
          ),
        );

        c.selectLayerContents(c.doc.layers.first.id);
        expect(c.selection.toSet(), {a.id, b.id});
        final depth = c.undoDepth;
        drag(ix, const Offset(100, 100), const Offset(130, 160));
        expect(a.center, const Offset(130, 160));
        expect(b.center, const Offset(330, 160));
        expect(c.doc.allObjects.last.name, 'other');
        expect(
          (c.doc.allObjects.last as ImageObject).center,
          const Offset(500, 500),
        );
        expect(
          c.undoDepth,
          depth + 1,
          reason: 'moving a whole layer is one step',
        );
      },
    );

    test('an object can change layers and stay itself', () async {
      final img = await addImage();
      img.rotation = 0.3;
      img.opacity = 0.5;
      c.addLayer();
      final target = c.currentLayer;
      c.moveObjectsToLayer([img.id], target.id);
      final moved = c.doc.objectById(img.id) as ImageObject;
      expect(c.doc.layerOf(img.id)!.id, target.id);
      expect(moved.center, const Offset(300, 300));
      expect(moved.rotation, 0.3);
      expect(moved.opacity, 0.5);
      expect(moved.assetId, img.assetId);
      c.undo();
      expect(c.doc.layerOf(img.id)!.id, c.doc.layers.first.id);
    });

    test('z-order within a layer', () async {
      final a = await addImage(at: const Offset(100, 100));
      final b = await addImage(at: const Offset(200, 100));
      final cc = await addImage(at: const Offset(300, 100));
      c.select([a.id]);
      c.reorderSelection('front');
      expect(c.doc.layers.first.objects.map((o) => o.id), [b.id, cc.id, a.id]);
      c.reorderSelection('backward');
      expect(c.doc.layers.first.objects.map((o) => o.id), [b.id, a.id, cc.id]);
      c.reorderSelection('back');
      expect(c.doc.layers.first.objects.first.id, a.id);
    });

    test('hiding a layer drops its objects from the selection', () async {
      final img = await addImage();
      c.select([img.id]);
      c.setLayerVisible(c.doc.layers.first.id, false);
      expect(c.selection, isEmpty);
    });
  });

  group('editing selections', () {
    test('opacity and rotation edit as one step each', () async {
      final img = await addImage();
      c.select([img.id]);
      c.editSelected('opacity', (o) => o.opacity = 0.3);
      c.editSelected('rotate', (o) => (o as BoxObject).rotation = 1);
      expect(img.opacity, 0.3);
      expect(c.undoDepth, 2);
      c.undo();
      expect((c.doc.allObjects.single as ImageObject).rotation, 0);
    });

    test('live slider edits record one step at the end', () async {
      final img = await addImage();
      c.select([img.id]);
      final t = c.beginEdit('opacity');
      for (final v in [0.9, 0.7, 0.5, 0.2]) {
        c.liveEditSelected((o) => o.opacity = v);
      }
      c.endEdit(t);
      expect(c.undoDepth, 1);
      c.undo();
      expect((c.doc.allObjects.single as ImageObject).opacity, 1);
    });

    test('duplicate offsets the copy and selects it', () async {
      final img = await addImage();
      c.select([img.id]);
      c.duplicateSelection();
      expect(c.doc.allObjects.length, 2);
      expect(c.selection.single, isNot(img.id));
      expect((c.single as ImageObject).center, const Offset(324, 324));
    });

    test('copy and paste within the app', () async {
      final img = await addImage();
      c.select([img.id]);
      c.copySelection();
      c.pasteObjects();
      c.pasteObjects();
      expect(c.doc.allObjects.length, 3);
      final centers = c.doc.allObjects
          .map((o) => (o as ImageObject).center)
          .toSet();
      expect(
        centers.length,
        3,
        reason: 'each paste steps further so copies are visible',
      );
    });

    test('delete and undo bring an object back with its data', () async {
      final img = await addImage();
      img.opacity = 0.6;
      c.select([img.id]);
      c.deleteSelection();
      expect(c.doc.allObjects, isEmpty);
      c.undo();
      expect((c.doc.allObjects.single as ImageObject).opacity, 0.6);
    });

    test('locked objects cannot be grabbed', () async {
      final img = await addImage();
      c.select([img.id]);
      c.editSelected('lock', (o) => o.locked = true);
      expect(c.objectsAt(const Offset(300, 300)), isEmpty);
    });
  });

  group('canvas', () {
    test('resizing the page leaves objects alone and is undoable', () async {
      final img = await addImage();
      c.setCanvasSize(const Size(800, 3000));
      expect(c.doc.canvasSize, const Size(800, 3000));
      expect(img.center, const Offset(300, 300));
      c.undo();
      expect(c.doc.canvasSize, const Size(1600, 1000));
    });

    test('dragging the corner grip resizes the page', () {
      drag(ix, const Offset(1600, 1000), const Offset(2000, 1500));
      expect(c.doc.canvasSize, const Size(2000, 1500));
      expect(c.undoDepth, 1);
    });

    test('canvas size is clamped to something sensible', () {
      c.setCanvasSize(const Size(5, 99999));
      expect(c.doc.canvasSize.width, 64);
      expect(c.doc.canvasSize.height, 12000);
    });

    test('fit page to content shifts content and shrinks the page', () async {
      await addImage(at: const Offset(500, 500), w: 100, h: 100);
      c.fitCanvasToContent(padding: 20);
      expect(c.doc.canvasSize, const Size(140, 140));
      expect(
        (c.doc.allObjects.single as ImageObject).center,
        const Offset(70, 70),
      );
    });

    test('fit page to content can be exact (no border)', () async {
      await addImage(at: const Offset(500, 500), w: 100, h: 100);
      c.fitCanvasToContent(padding: 0);
      expect(c.doc.canvasSize, const Size(100, 100));
      expect(
        (c.doc.allObjects.single as ImageObject).center,
        const Offset(50, 50),
      );
    });

    test(
      'page grip follows the grab point instead of jumping to the cursor',
      () {
        // Grab the corner grip 6px inside it; the page must not jump by 6px.
        ix.pointerDown(const Offset(1594, 994), noMods);
        ix.pointerMove(const Offset(1494, 894), noMods);
        ix.pointerUp(const Offset(1494, 894), noMods);
        expect(c.doc.canvasSize, const Size(1500, 900));
      },
    );

    test('page grip snaps exactly onto the content edge', () async {
      await addImage(at: const Offset(251, 163), w: 200, h: 100);
      // Image spans x 151..351, y 113..213; drag the corner grip near it.
      ix.pointerDown(const Offset(1600, 1000), noMods);
      ix.pointerMove(const Offset(354, 216), noMods);
      ix.pointerUp(const Offset(354, 216), noMods);
      expect(c.doc.canvasSize, const Size(351, 213));
    });

    test('shrinking the page is not undone by auto-grow margins', () async {
      await addImage(at: const Offset(251, 163), w: 200, h: 100);
      c.autoGrow = true;
      ix.pointerDown(const Offset(1600, 1000), noMods);
      ix.pointerMove(const Offset(351, 213), noMods);
      ix.pointerUp(const Offset(351, 213), noMods);
      expect(c.doc.canvasSize, const Size(351, 213));
    });

    test(
      'with snap on, an image can still be sized to the page edge',
      () async {
        final img = await addImage(at: const Offset(300, 300), w: 200, h: 100);
        c.doc.canvasSize = const Size(1633, 1000); // not a multiple of the grid
        c.snapOn = true;
        c.select([img.id]);
        c.setTool(Tool.select);
        // Drag the image's right edge handle toward the page edge.
        final r = img.center + Offset(img.size.width / 2, 0);
        ix.pointerDown(r, noMods);
        ix.pointerMove(const Offset(1630, 300), noMods);
        ix.pointerUp(const Offset(1630, 300), noMods);
        expect((img.center.dx + img.size.width / 2), closeTo(1633, 0.01));
      },
    );

    test('auto-grow expands the page to include new content', () async {
      c.autoGrow = true;
      c.setTool(Tool.rect);
      drag(ix, const Offset(1500, 900), const Offset(1900, 1300));
      expect(c.doc.canvasSize.width, greaterThanOrEqualTo(1900));
      expect(c.doc.canvasSize.height, greaterThanOrEqualTo(1300));
    });

    test('zoom keeps the point under the pointer still', () {
      const p = Offset(400, 300);
      final scene = c.toScene(p);
      c.zoomTo(2.5, anchorScreen: p);
      expect(c.toScene(p).dx, closeTo(scene.dx, 1e-9));
      expect(c.toScene(p).dy, closeTo(scene.dy, 1e-9));
      expect(
        c.doc.allObjects,
        isEmpty,
        reason: 'zoom is a view change, not a document change',
      );
      expect(c.undoDepth, 0);
    });
  });

  group('images and the collection', () {
    test('the first big image becomes the page', () async {
      final a = await makeAsset(c, w: 900, h: 600);
      final o = c.placeAsset(a);
      expect(c.doc.canvasSize, const Size(900, 600));
      expect(o.center, const Offset(450, 300));
      expect(o.size, const Size(900, 600));
    });

    test(
      'later images are fitted into view and land in the current layer',
      () async {
        final first = await makeAsset(c, w: 900, h: 600);
        c.placeAsset(first);
        c.addLayer();
        final big = await makeAsset(c, w: 3000, h: 2000);
        final o = c.placeAsset(big);
        expect(o.size.width, lessThan(3000));
        expect(o.size.width / o.size.height, closeTo(1.5, 1e-6));
        expect(c.doc.layerOf(o.id)!.id, c.currentLayerId);
      },
    );

    test('paste can ask: image goes to the layer or the collection', () async {
      final a = await makeAsset(c, w: 400, h: 400);
      c.pendingPaste = PendingPaste(a.id, 'pasted');
      c.resolvePaste(toCollection: true);
      expect(c.doc.collection.length, 1);
      expect(c.doc.allObjects, isEmpty);

      c.pendingPaste = PendingPaste(a.id, 'pasted');
      c.resolvePaste(toCollection: false, remember: true);
      expect(c.doc.allObjects.length, 1);
      expect(
        c.pasteMode,
        PasteMode.layer,
        reason: 'Always do this is remembered',
      );
    });

    test(
      'placing a collected image leaves the source in the collection',
      () async {
        final a = await makeAsset(c, w: 100, h: 100);
        final item = c.addToCollection(a, name: 'awning');
        final o1 = c.placeCollectionItem(item.id, at: const Offset(200, 200))!;
        final o2 = c.placeCollectionItem(item.id, at: const Offset(400, 200))!;
        expect(c.doc.collection.length, 1);
        expect(o1.id, isNot(o2.id));
        expect(o1.assetId, o2.assetId);
      },
    );

    test('a placed image can be kept in the collection', () async {
      final img = await addImage();
      c.select([img.id]);
      c.sendSelectionToCollection();
      expect(c.doc.collection.single.assetId, img.assetId);
    });
  });

  group('cutouts', () {
    test(
      'a box cutout makes a new object and leaves the original intact',
      () async {
        final img = await addImage(
          at: const Offset(300, 300),
          w: 200,
          h: 100,
          color: 0xFF0000FF,
          centerColor: 0xFFFFFF00,
        );
        c.select([img.id]);
        final piece = await c.cutout(img, [
          const Offset(250, 275),
          const Offset(350, 275),
          const Offset(350, 325),
          const Offset(250, 325),
        ]);
        expect(piece, isNotNull);
        expect(c.doc.allObjects.length, 2);
        expect(piece!.size.width, closeTo(100, 1));
        expect(piece.size.height, closeTo(50, 1));
        expect(piece.center.dx, closeTo(300, 1));
        expect(piece.center.dy, closeTo(300, 1));
        final a = c.assets[piece.assetId]!;
        expect(a.width, 100);
        // The piece is the yellow middle.
        final i = (25 * a.width + 50) * 4;
        expect((await a.rgbaBytes()).sublist(i, i + 3), [255, 255, 0]);
        expect(
          c.assets[img.assetId]!.width,
          200,
          reason: 'the original asset is untouched',
        );
        expect(c.selection, [piece.id]);
        expect(c.undoDepth, 1);
      },
    );

    test('a triangular lasso is transparent outside the triangle', () async {
      final img = await addImage(
        at: const Offset(300, 300),
        w: 200,
        h: 200,
        color: 0xFFFF0000,
      );
      final piece = await c.cutout(img, [
        const Offset(200, 200),
        const Offset(400, 200),
        const Offset(200, 400),
      ]);
      final a = c.assets[piece!.assetId]!;
      expect(a.alphaAt(10, 10), 255);
      expect(a.alphaAt(190, 190), 0);
    });

    // Cut the blue middle out of a red picture and see what is left there.
    Future<List<int>> centreAfterCut(
      HoleFill fill, {
      int color = 0xFF00FF00,
    }) async {
      final img = await addImage(
        at: const Offset(300, 300),
        w: 200,
        h: 100,
        color: 0xFFFF0000,
        centerColor: 0xFF0000FF,
      );
      c.cutoutFill = fill;
      c.cutoutFillColor = color;
      await c.cutout(img, [
        const Offset(250, 275),
        const Offset(350, 275),
        const Offset(350, 325),
        const Offset(250, 325),
      ], leaveHole: true);
      final a = c.assets[(c.doc.objectById(img.id) as ImageObject).assetId]!;
      final px = await a.rgbaBytes();
      int at(int x, int y) => (y * a.width + x) * 4;
      final i = at(100, 50), edge = at(5, 5);
      expect(px.sublist(edge, edge + 4), [
        255,
        0,
        0,
        255,
      ], reason: 'outside the hole is untouched');
      return px.sublist(i, i + 4);
    }

    test('a gap can be filled with a flat colour', () async {
      expect(await centreAfterCut(HoleFill.color), [0, 255, 0, 255]);
    });

    test('a gap can be blended in from what surrounds it', () async {
      final px = await centreAfterCut(HoleFill.blend);
      expect(px[0], greaterThan(245));
      expect(px[1], lessThan(10));
      expect(px[2], lessThan(10));
      expect(px[3], 255);
    });

    test('an empty gap stays see-through', () async {
      expect((await centreAfterCut(HoleFill.empty))[3], 0);
    });

    test('blending carries a gradient across the gap', () async {
      // Black on the left fading to white on the right, with a hole between.
      const w = 64, h = 16;
      final px = Uint8List(w * h * 4);
      final hole = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          final v = (x * 255 / (w - 1)).round();
          px[i] = px[i + 1] = px[i + 2] = v;
          px[i + 3] = 255;
          if (x >= 24 && x < 40) hole[y * w + x] = 1;
        }
      }
      blendFill(px, w, h, hole);
      int g(int x) => px[(8 * w + x) * 4];
      expect(g(26), lessThan(g(32)));
      expect(g(32), lessThan(g(38)));
      expect(g(32), closeTo(127, 30));
    });

    test('blend fill leaves a hole alone when nothing surrounds it', () {
      final px = Uint8List(8 * 8 * 4); // fully transparent
      final hole = Uint8List(64)..fillRange(0, 64, 1);
      blendFill(px, 8, 8, hole);
      expect(px.every((v) => v == 0), isTrue);
    });

    test('a hole can be left in the original', () async {
      final img = await addImage(
        at: const Offset(300, 300),
        w: 200,
        h: 100,
        color: 0xFF0000FF,
      );
      final oldAsset = img.assetId;
      await c.cutout(img, [
        const Offset(250, 275),
        const Offset(350, 275),
        const Offset(350, 325),
        const Offset(250, 325),
      ], leaveHole: true);
      final orig = c.doc.objectById(img.id) as ImageObject;
      expect(orig.assetId, isNot(oldAsset));
      final a = c.assets[orig.assetId]!;
      expect(a.alphaAt(100, 50), 0);
      expect(a.alphaAt(5, 5), 255);
      c.undo();
      expect((c.doc.objectById(img.id) as ImageObject).assetId, oldAsset);
    });

    test('a rotated, flipped image cuts out the right pixels', () async {
      final img = await addImage(
        at: const Offset(300, 300),
        w: 200,
        h: 100,
        color: 0xFF0000FF,
        centerColor: 0xFFFFFF00,
      );
      img.rotation = math.pi / 2;
      img.flipX = true;
      // After a quarter turn the image is 100 wide and 200 tall on the page.
      final piece = await c.cutout(img, [
        const Offset(250, 250),
        const Offset(350, 250),
        const Offset(350, 350),
        const Offset(250, 350),
      ]);
      expect(piece, isNotNull);
      expect(piece!.rotation, math.pi / 2);
      expect(piece.flipX, isTrue);
      expect(piece.center.dx, closeTo(300, 1));
      expect(piece.center.dy, closeTo(300, 1));
    });

    test(
      'remove background clears the surrounding colour but not the subject',
      () async {
        final img = await addImage(
          w: 100,
          h: 100,
          color: 0xFFFFFFFF,
          centerColor: 0xFFCC0000,
        );
        final ok = await c.removeBackgroundFrom(img);
        expect(ok, isTrue);
        final a = c.assets[(c.doc.objectById(img.id) as ImageObject).assetId]!;
        expect(a.alphaAt(2, 2), 0);
        expect(a.alphaAt(50, 50), 255);
        expect(c.undoDepth, 1);
      },
    );

    test('removing a colour only floods what touches the click', () async {
      final img = await addImage(
        w: 100,
        h: 100,
        color: 0xFFFFFFFF,
        centerColor: 0xFF000000,
      );
      final inner = img.copyWith();
      expect(inner, isNotNull);
      // Click on the black square: the white border must survive.
      final ok = await c.removeColorAt(img, const Offset(300, 300));
      expect(ok, isTrue);
      final a = c.assets[(c.doc.objectById(img.id) as ImageObject).assetId]!;
      expect(a.alphaAt(50, 50), 0);
      expect(a.alphaAt(2, 2), 255);
    });
  });

  group('markers, alignment, layer copies', () {
    test('numbered markers count up as they are placed', () {
      c.setTool(Tool.badge);
      click(ix, const Offset(100, 100));
      click(ix, const Offset(200, 100));
      click(ix, const Offset(300, 100));
      final badges = c.doc.allObjects.whereType<BadgeObject>().toList();
      expect(badges.map((b) => b.number), [1, 2, 3]);
      expect(c.tool, Tool.badge, reason: 'stays active for the next number');
      expect(c.undoDepth, 3);
      // Deleting 2 and placing again takes the next free number, not a repeat.
      c.select([badges[1].id]);
      c.deleteSelection();
      c.setTool(Tool.badge);
      click(ix, const Offset(400, 100));
      expect(c.doc.allObjects.whereType<BadgeObject>().last.number, 4);
    });

    test('a marker is round to the touch and resizes as a circle', () {
      c.setTool(Tool.badge);
      click(ix, const Offset(300, 300));
      final b = c.single as BadgeObject;
      expect(
        b.hitTest(const Offset(320, 320), 0, c.assets),
        isFalse,
        reason: 'the corner of its box is empty',
      );
      expect(b.hitTest(const Offset(300, 300), 0, c.assets), isTrue);
      c.setTool(Tool.select);
      final h = c.handlesFor(b);
      expect(
        h.where((x) => x.kind == HandleKind.resize).length,
        4,
        reason: 'corners only',
      );
      drag(ix, const Offset(322, 322), const Offset(372, 340));
      expect(b.size.width, closeTo(b.size.height, 1e-6));
      expect(b.size.width, greaterThan(60));
    });

    test('align to each other, or to the page when alone', () async {
      final a = await addImage(at: const Offset(100, 200), w: 100, h: 50);
      final b = await addImage(at: const Offset(400, 500), w: 200, h: 80);
      c.select([a.id, b.id]);
      c.alignSelection('left');
      expect(a.bounds.left, closeTo(b.bounds.left, 1e-9));
      expect(
        a.bounds.left,
        closeTo(50, 1e-9),
        reason: 'the leftmost edge of the pair',
      );
      c.alignSelection('middle');
      expect(a.center.dy, closeTo(b.center.dy, 1e-9));
      c.select([b.id]);
      c.alignSelection('centre');
      expect(
        b.center.dx,
        closeTo(800, 1e-9),
        reason: 'centre of a 1600 wide page',
      );
      c.alignSelection('bottom');
      expect(b.bounds.bottom, closeTo(1000, 1e-9));
    });

    test('a duplicated layer holds independent copies', () async {
      final a = await addImage(at: const Offset(100, 100), w: 50, h: 50);
      a.opacity = 0.4;
      c.duplicateLayer(c.doc.layers.first.id);
      expect(c.doc.layers.length, 2);
      expect(c.doc.layers[1].name, 'Layer 1 copy');
      final copy = c.doc.layers[1].objects.single as ImageObject;
      expect(copy.id, isNot(a.id));
      expect(copy.opacity, 0.4);
      expect(copy.assetId, a.assetId);
      copy.translate(const Offset(300, 0));
      expect(a.center, const Offset(100, 100));
      expect(c.selection, [copy.id]);
      c.undo();
      expect(c.doc.layers.length, 1);
    });
  });

  group('large images', () {
    test(
      'big images keep a coarse alpha mask that still finds thin parts',
      () async {
        final rec = PictureRecorder();
        final canvas = Canvas(rec);
        // 4000x3000, transparent except a 6px-wide vertical bar.
        canvas.drawRect(
          const Rect.fromLTWH(2000, 0, 6, 3000),
          Paint()..color = const Color(0xFF00FF00),
        );
        final img = await rec.endRecording().toImage(4000, 3000);
        final a = await c.assets.addImage(img);
        expect(a.alphaAt(2003, 1500), 255);
        expect(a.alphaAt(100, 100), 0);
        expect(a.alphaAt(-5, 10), 0);
        expect((await a.rgbaBytes()).length, 4000 * 3000 * 4);
      },
    );

    test('exports are limited to something a GPU can make', () async {
      c.setCanvasSize(const Size(12000, 12000));
      final png = await c.exportPng(scale: 4);
      final codec = await instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, lessThanOrEqualTo(16000));
    });
  });

  group('merge and recovery', () {
    test(
      'merging pieces makes one image and undo brings the pieces back',
      () async {
        final a = await addImage(
          at: const Offset(100, 100),
          w: 100,
          h: 100,
          color: 0xFFFF0000,
        );
        final b = await addImage(
          at: const Offset(200, 100),
          w: 100,
          h: 100,
          color: 0xFF0000FF,
        );
        c.select([a.id, b.id]);
        final merged = await c.flattenSelection();
        expect(merged, isNotNull);
        expect(c.doc.allObjects.length, 1);
        expect(merged!.size.width, closeTo(202, 2));
        expect(merged.size.height, closeTo(102, 2));
        final asset = c.assets[merged.assetId]!;
        // Red on the left half, blue on the right.
        final rgba = await asset.rgbaBytes();
        int px(int x, int y) => rgba[(y * asset.width + x) * 4];
        expect(px(10, 50), 255, reason: 'red channel on the red side');
        expect(px(asset.width - 10, 50), 0, reason: 'no red on the blue side');
        c.undo();
        expect(c.doc.allObjects.length, 2);
      },
    );

    test('unsaved work is autosaved and can be restored', () async {
      final dir = Directory.systemTemp.createTempSync('thinkspace_recovery');
      addTearDown(() => dir.deleteSync(recursive: true));
      c.startAutosave(
        File('${dir.path}/recovery.thinkspace'),
        every: const Duration(days: 1),
      );
      await addImage();
      c.setCanvasSize(const Size(900, 900));
      await c.autosaveNow();
      expect(c.pendingRecovery(), isNotNull);

      final fresh = newEditor();
      fresh.recoveryFile = c.recoveryFile;
      expect(fresh.pendingRecovery(), isNotNull);
      await fresh.restoreRecovery();
      expect(fresh.doc.canvasSize, const Size(900, 900));
      expect(fresh.doc.allObjects.length, 1);
      expect(fresh.dirty, isTrue, reason: 'restored work still needs saving');

      await c.saveTo('${dir.path}/real.thinkspace');
      expect(
        c.pendingRecovery(),
        isNull,
        reason: 'saving clears the recovery file',
      );
    });

    test('undo and redo labels say what they will do', () async {
      expect(c.undoLabel, isNull);
      c.setTool(Tool.arrow);
      drag(ix, const Offset(0, 0), const Offset(100, 0));
      expect(c.undoLabel, 'draw arrow');
      c.undo();
      expect(c.redoLabel, 'draw arrow');
    });
  });

  group('projects', () {
    test('save and load bring back the editable pieces', () async {
      final img = await addImage(
        at: const Offset(300, 300),
        w: 120,
        h: 80,
        color: 0xFF336699,
      );
      img.rotation = 0.4;
      img.opacity = 0.55;
      c.addLayer();
      c.setTool(Tool.arrow);
      drag(ix, const Offset(10, 10), const Offset(200, 120));
      final item = c.addToCollection(
        await makeAsset(c, w: 30, h: 30),
        name: 'swatch',
      );
      c.setCanvasSize(const Size(1234, 777));

      final dir = Directory.systemTemp.createTempSync('thinkspace_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/demo.thinkspace';
      await c.saveTo(path);
      expect(c.dirty, isFalse);

      final c2 = newEditor();
      await c2.openFrom(path);
      expect(c2.doc.encode(), c.doc.encode());
      expect(c2.doc.canvasSize, const Size(1234, 777));
      final loaded = c2.doc.objectById(img.id) as ImageObject;
      expect(loaded.rotation, 0.4);
      expect(loaded.opacity, 0.55);
      expect(c2.assets[loaded.assetId]!.width, 120);
      expect(c2.assets[c2.doc.collection.single.assetId], isNotNull);
      expect(c2.doc.collection.single.id, item.id);
      expect(
        c2.undoDepth,
        0,
        reason: 'a freshly opened project has no history',
      );
      // The file is plain JSON.
      expect(jsonDecode(File(path).readAsStringSync())['format'], 'thinkspace');
    });

    test('unused assets are not written', () async {
      await addImage();
      await makeAsset(c, w: 500, h: 500); // never placed
      final j = jsonDecode(c.projectJson()) as Map<String, dynamic>;
      expect((j['assets'] as Map).length, 1);
    });

    test('a non-project file is rejected without damage', () async {
      await addImage();
      expect(
        () => c.loadProjectJson('{"format":"other"}'),
        throwsFormatException,
      );
      expect(c.doc.allObjects.length, 1);
    });

    test('export renders the page at the requested scale', () async {
      final img = await addImage(
        at: const Offset(100, 100),
        w: 100,
        h: 100,
        color: 0xFFFF0000,
      );
      expect(img, isNotNull);
      c.setCanvasSize(const Size(300, 200));
      final png = await c.exportPng(scale: 2);
      final codec = await instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 600);
      expect(frame.image.height, 400);
      final raw = (await frame.image.toByteData(
        format: ImageByteFormat.rawRgba,
      ))!;
      int px(int x, int y) => raw.getUint32((y * 600 + x) * 4);
      expect(px(200, 200), 0xFF0000FF, reason: 'red object, rgba order');
      expect(px(500, 350), 0xFFFFFFFF, reason: 'white page');
    });

    test(
      'hidden things are not exported, and the page can be transparent',
      () async {
        final img = await addImage(at: const Offset(100, 100), w: 100, h: 100);
        c.setObjectVisible(img.id, false);
        c.setCanvasSize(const Size(200, 200));
        c.setBackground(0);
        final codec = await instantiateImageCodec(await c.exportPng());
        final image = (await codec.getNextFrame()).image;
        final raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
        expect(raw.getUint8(3), 0);
      },
    );

    test('undo history is not shared with a new document', () async {
      await addImage();
      c.deleteSelection();
      c.newDocument();
      expect(c.canUndo, isFalse);
      expect(c.doc.layers.length, 1);
      expect(c.assets.length, 0);
    });
  });

  group('review fixes', () {
    ShapeObject shape({
      bool ellipse = false,
      double sw = 4,
      bool filled = false,
    }) => ShapeObject(
      id: 's',
      name: 's',
      ellipse: ellipse,
      center: const Offset(200, 200),
      size: const Size(200, 100),
      strokeWidth: sw,
      fill: filled ? 0xFF00FF00 : 0,
    );

    test(
      'an unfilled ellipse cannot be grabbed in the empty corners of its box',
      () {
        final e = shape(ellipse: true);
        expect(e.hitTest(const Offset(298, 248), 3, c.assets), isFalse);
        expect(e.hitTest(const Offset(300, 200), 3, c.assets), isTrue);
        expect(e.hitTest(const Offset(200, 250), 3, c.assets), isTrue);
        expect(e.hitTest(const Offset(200, 200), 3, c.assets), isFalse);
      },
    );

    test('a thick outline counts toward a shape\'s bounds', () {
      final r = shape(sw: 10);
      expect(r.bounds, const Rect.fromLTRB(95, 145, 305, 255));
    });

    test('hidden layers do not count as content', () {
      c.doc.layers.first.objects.add(shape());
      final l = Layer(id: 'lh', name: 'hidden', visible: false);
      l.objects.add(
        ShapeObject(
          id: 'far',
          name: 'far',
          ellipse: false,
          center: const Offset(1500, 900),
          size: const Size(100, 100),
        ),
      );
      c.doc.layers.add(l);
      expect(contentBounds(c.doc).right, lessThan(400));
    });

    test(
      'dragging a text box by a top corner keeps its bottom edge in place',
      () {
        final t = TextObject(
          id: 't1',
          name: 'text',
          text: 'hello there',
          center: const Offset(400, 400),
          size: const Size(200, 40),
          fontSize: 28,
        );
        c.doc.layers.first.objects.add(t);
        c.select([t.id]);
        final bottomBefore = t.bounds.bottom;
        final h = c
            .handlesFor(t)
            .firstWhere(
              (h) => h.kind == HandleKind.resize && h.hx == 1 && h.hy == -1,
            );
        drag(ix, h.pos, h.pos + const Offset(40, -20));
        final now = c.doc.objectById(t.id) as TextObject;
        expect(now.bounds.bottom, closeTo(bottomBefore, 0.5));
      },
    );

    test('undoing back to the saved state leaves the project clean', () async {
      await addImage();
      c.dirty = false;
      c.markSaved();
      c.setBackground(0xFF112233);
      expect(c.dirty, isTrue);
      c.undo();
      expect(c.dirty, isFalse);
      c.redo();
      expect(c.dirty, isTrue);
    });

    test('changing the grid size counts as an edit that can be undone', () {
      c.dirty = false;
      c.markSaved();
      final before = c.doc.gridSize;
      c.setGridSize(before + 20);
      expect(c.dirty, isTrue);
      expect(c.undoDepth, 1);
      c.undo();
      expect(c.doc.gridSize, before);
      expect(c.dirty, isFalse);
    });

    test(
      'a replaced document starts clean, and undo can return to clean',
      () async {
        await c.replaceDocument(Document.blank());
        expect(c.dirty, isFalse);
        c.setBackground(0xFF445566);
        expect(c.dirty, isTrue);
        c.undo();
        expect(c.dirty, isFalse);
      },
    );

    test('a damaged file:// launch argument is skipped, not fatal', () async {
      await c.openLaunchFiles(['file://%zz%zz', 'not-a-file.txt']);
      expect(c.doc.allObjects, isEmpty);
    });

    test('a text alignment stored as a decimal still loads', () {
      final t = TextObject(
        id: 't',
        name: 't',
        text: 'x',
        center: Offset.zero,
        size: const Size(10, 10),
      );
      final j = t.toJson()..['align'] = 1.0;
      expect(
        (SceneObject.fromJson(j) as TextObject).align,
        TextAlign.values[1],
      );
    });

    test('a failed edit is rolled back instead of half-applied', () {
      final before = c.doc.signature();
      expect(
        () => c.transact('boom', () {
          c.doc.layers.first.objects.add(shape());
          throw StateError('nope');
        }),
        throwsStateError,
      );
      expect(c.doc.signature(), before);
      expect(c.undoDepth, 0);
    });

    test(
      'saving to somewhere impossible reports it and stays unsaved',
      () async {
        await addImage();
        c.dirty = true;
        final ok = await c.saveTo('/nonexistent-dir-xyz/p.thinkspace');
        expect(ok, isFalse);
        expect(c.dirty, isTrue);
        expect(c.toastMessage, contains('Could not save'));
      },
    );

    test('saving leaves a whole file and no temp file behind', () async {
      await addImage();
      final dir = Directory.systemTemp.createTempSync('thinkspace_save');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/p.thinkspace');
      await f.writeAsString('old contents');
      expect(await c.saveTo(f.path), isTrue);
      expect(jsonDecode(await f.readAsString())['format'], 'thinkspace');
      expect(dir.listSync().length, 1);
    });

    test(
      'a project from a newer version is refused with a clear message',
      () async {
        final j = jsonDecode(c.projectJson()) as Map<String, dynamic>;
        j['version'] = 99;
        expect(
          () => c.loadProjectJson(jsonEncode(j)),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('a project missing optional fields still opens', () async {
      await addImage();
      c.doc.layers.first.objects.add(shape());
      final j = jsonDecode(c.projectJson()) as Map<String, dynamic>;
      for (final l in j['document']['layers']) {
        for (final o in l['objects']) {
          o.remove('opacity');
        }
      }
      await c.loadProjectJson(jsonEncode(j));
      expect(c.doc.allObjects.length, 2);
      expect(c.doc.allObjects.every((o) => o.opacity == 1), isTrue);
    });

    test(
      'one unreadable picture does not stop the project from opening',
      () async {
        await addImage();
        final j = jsonDecode(c.projectJson()) as Map<String, dynamic>;
        (j['assets'] as Map)[(j['assets'] as Map).keys.first] = base64Encode([
          1,
          2,
          3,
          4,
        ]);
        await c.loadProjectJson(jsonEncode(j));
        expect(c.doc.allObjects.length, 1);
        expect(c.toastMessage, contains("couldn't be read"));
      },
    );

    test('launching with a project file path opens it', () async {
      await addImage();
      final dir = Directory.systemTemp.createTempSync('thinkspace_launch');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/p.thinkspace')
        ..writeAsStringSync(c.projectJson());
      final c2 = newEditor();
      await c2.openLaunchFiles([f.path]);
      expect(c2.doc.allObjects.length, 1);
      expect(c2.filePath, f.path);
    });

    test('launching with a picture places it on the page', () async {
      final a = await makeAsset(c, w: 60, h: 40);
      final dir = Directory.systemTemp.createTempSync('thinkspace_launch');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/pic.png')..writeAsBytesSync(a.bytes);
      final c2 = newEditor();
      await c2.openLaunchFiles([f.path]);
      expect(c2.doc.allObjects.single, isA<ImageObject>());
    });

    test(
      'pictures nothing refers to any more are forgotten, recent ones kept',
      () async {
        final used = await addImage();
        final orphan = await makeAsset(c, w: 20, h: 20);
        final fresh = await makeAsset(c, w: 20, h: 20);
        c.assets.backdate(orphan.id, const Duration(minutes: 10));
        c.assets.backdate(used.assetId, const Duration(minutes: 10));
        c.pruneAssets();
        expect(c.assets[orphan.id], isNull);
        expect(c.assets[used.assetId], isNotNull);
        expect(c.assets[fresh.id], isNotNull, reason: 'might be mid-edit');
      },
    );

    test(
      'a picture only kept alive by undo history is not forgotten',
      () async {
        final img = await addImage();
        final id = img.assetId;
        c.assets.backdate(id, const Duration(minutes: 10));
        c.select([img.id]);
        c.deleteSelection();
        c.pruneAssets();
        expect(c.assets[id], isNotNull);
        c.undo();
        expect(c.doc.allObjects.length, 1);
      },
    );
  });

  group('unmerge', () {
    ShapeObject box(String id, Offset at, {Size size = const Size(80, 40)}) =>
        ShapeObject(
          id: id,
          name: id,
          ellipse: false,
          center: at,
          size: size,
          fill: 0xFF3366FF,
        );

    Future<ImageObject> mergeTwo() async {
      c.doc.canvasSize = const Size(1600, 1000);
      c.doc.layers.first.objects
        ..add(box('a', const Offset(200, 200)))
        ..add(box('b', const Offset(320, 260), size: const Size(60, 60)));
      c.select(['a', 'b']);
      final m = await c.flattenSelection();
      return m!;
    }

    Offset centreOf(String name) =>
        (c.doc.allObjects.firstWhere((o) => o.name == name) as BoxObject)
            .center;

    test(
      'merging then unmerging puts the pieces back where they were',
      () async {
        await mergeTwo();
        expect(c.doc.allObjects.length, 1);
        expect(c.canUnmerge, isTrue);
        c.unmerge();
        expect(c.doc.allObjects.length, 2);
        expect(centreOf('a').dx, closeTo(200, 1e-6));
        expect(centreOf('b').dy, closeTo(260, 1e-6));
        expect(c.selection.length, 2);
      },
    );

    test('pieces follow the merged picture when it is moved', () async {
      final m = await mergeTwo();
      m.center += const Offset(50, 30);
      c.unmerge();
      expect(centreOf('a'), const Offset(250, 230));
      expect(centreOf('b').dx, closeTo(370, 1e-6));
    });

    test('pieces follow when the merged picture is scaled', () async {
      final m = await mergeTwo();
      final before = m.center;
      m.size = Size(m.size.width * 2, m.size.height * 2);
      c.unmerge();
      final a =
          c.doc.allObjects.firstWhere((o) => o.name == 'a') as ShapeObject;
      expect(a.size.width, closeTo(160, 1e-6));
      expect(a.center.dx, closeTo(before.dx + (200 - before.dx) * 2, 1e-6));
    });

    test('pieces follow when the merged picture is turned', () async {
      final m = await mergeTwo();
      final pivot = m.center;
      m.rotation = math.pi / 2;
      c.unmerge();
      // A point to the left of the middle ends up below it after a quarter turn.
      final a =
          c.doc.allObjects.firstWhere((o) => o.name == 'a') as ShapeObject;
      final d = a.center - pivot;
      final was = const Offset(200, 200) - pivot;
      expect(d.dx, closeTo(-was.dy, 1e-6));
      expect(d.dy, closeTo(was.dx, 1e-6));
      expect(a.rotation, closeTo(math.pi / 2, 1e-9));
    });

    test('fading the merged picture fades the pieces', () async {
      final m = await mergeTwo();
      m.opacity = 0.5;
      c.unmerge();
      expect(c.doc.allObjects.every((o) => o.opacity == 0.5), isTrue);
    });

    test('unmerge is one undo step, and merge can be redone after', () async {
      await mergeTwo();
      final depth = c.undoDepth;
      c.unmerge();
      expect(c.undoDepth, depth + 1);
      c.undo();
      expect(c.doc.allObjects.length, 1);
      expect(c.canUnmerge, isTrue);
    });

    test(
      'once the picture itself is cut, it can no longer be unmerged',
      () async {
        final m = await mergeTwo();
        await c.cutout(m, [
          Offset(m.center.dx - 20, m.center.dy - 20),
          Offset(m.center.dx + 20, m.center.dy - 20),
          Offset(m.center.dx + 20, m.center.dy + 20),
          Offset(m.center.dx - 20, m.center.dy + 20),
        ], leaveHole: true);
        c.select([m.id]);
        expect(c.canUnmerge, isFalse);
      },
    );

    test(
      'a merge survives saving and opening, with its original pictures',
      () async {
        c.doc.layers.first.objects.add(box('a', const Offset(200, 200)));
        final pic = await addImage(at: const Offset(300, 300));
        c.select(['a', pic.id]);
        await c.flattenSelection();
        final json = c.projectJson();
        final c2 = newEditor();
        await c2.loadProjectJson(json);
        final m = c2.doc.allObjects.single as ImageObject;
        expect(m.canUnmerge, isTrue);
        c2.select([m.id]);
        c2.unmerge();
        expect(c2.doc.allObjects.length, 2);
        final back = c2.doc.allObjects.whereType<ImageObject>().single;
        expect(c2.assets[back.assetId], isNotNull);
      },
    );

    test('merging merges: unmerging peels one level at a time', () async {
      await mergeTwo();
      c.doc.layers.first.objects.add(box('c', const Offset(500, 500)));
      c.select([c.doc.allObjects.first.id, 'c']);
      await c.flattenSelection();
      c.unmerge();
      expect(c.doc.allObjects.length, 2);
      final inner = c.doc.allObjects.whereType<ImageObject>().single;
      c.select([inner.id]);
      expect(c.canUnmerge, isTrue);
      c.unmerge();
      expect(c.doc.allObjects.length, 3);
    });

    test(
      'a copied merged picture keeps its originals through a prune',
      () async {
        final a = await addImage(at: const Offset(300, 300));
        final b = await addImage(at: const Offset(420, 300), color: 0xFF00FF00);
        c.select([a.id, b.id]);
        final m = (await c.flattenSelection())!;
        final parts = m.merged!.assets.toList();
        expect(parts, isNotEmpty);
        c.select([m.id]);
        c.copySelection();
        c.deleteSelection();
        await c.replaceDocument(Document.blank());
        for (final id in [m.assetId, ...parts]) {
          c.assets.backdate(id, const Duration(minutes: 10));
        }
        c.pruneAssets();
        c.pasteObjects();
        c.select([c.doc.allObjects.single.id]);
        expect(c.canUnmerge, isTrue);
        for (final id in parts) {
          expect(c.assets[id], isNotNull);
        }
      },
    );

    test('a merge record with no size cannot be unmerged', () async {
      final m = await mergeTwo();
      m.merged = MergeRecord(
        assetId: m.assetId,
        center: m.merged!.center,
        size: Size.zero,
        parts: m.merged!.parts,
      );
      expect(m.canUnmerge, isFalse);
    });
  });

  group('round four', () {
    test('Shift with the pen draws one straight line', () {
      c.setTool(Tool.pen);
      const shift = Modifiers(shift: true);
      ix.pointerDown(const Offset(100, 100), noMods);
      for (int i = 1; i <= 20; i++) {
        ix.pointerMove(Offset(100 + i * 10.0, 100 + i * 2.0 + (i % 3)), shift);
      }
      ix.pointerUp(const Offset(300, 140), shift);
      final s = c.doc.allObjects.single as StrokeObject;
      expect(s.points.length, 2);
      expect(s.points.first, const Offset(100, 100));
      // 15-degree steps: the end is on one of them, not at the wobbly mouse.
      final d = s.points.last - s.points.first;
      final a = math.atan2(d.dy, d.dx) / (math.pi / 12);
      expect(a, closeTo(a.roundToDouble(), 1e-6));
    });

    test('without Shift the pen is still freehand', () {
      c.setTool(Tool.pen);
      ix.pointerDown(const Offset(100, 100), noMods);
      for (int i = 1; i <= 10; i++) {
        ix.pointerMove(Offset(100 + i * 10.0, 100 + (i * i) * 2.0), noMods);
      }
      ix.pointerUp(const Offset(200, 300), noMods);
      expect(
        (c.doc.allObjects.single as StrokeObject).points.length,
        greaterThan(3),
      );
    });

    group('the Layers list', () {
      late List<String> ids;
      setUp(() {
        ids = [];
        for (int i = 0; i < 5; i++) {
          final o = ShapeObject(
            id: 's$i',
            name: 'shape $i',
            ellipse: false,
            center: Offset(100.0 + i * 60, 100),
            size: const Size(40, 40),
            fill: 0xFF3366FF,
          );
          c.doc.layers.first.objects.add(o);
          ids.add(o.id);
        }
      });

      // The list shows the topmost object first: s4, s3, s2, s1, s0.
      test('Down moves to the next row; Shift+Down extends the selection', () {
        c.clickListRow('s4');
        expect(c.selection, ['s4']);
        c.listStep(1);
        expect(c.selection, ['s3']);
        c.listStep(1, extend: true);
        c.listStep(1, extend: true);
        expect(c.selection.toSet(), {'s3', 's2', 's1'});
        c.listStep(-1, extend: true);
        expect(c.selection.toSet(), {'s3', 's2'});
        expect(c.listFocus, isTrue);
      });

      test('Shift+click selects the run between two rows', () {
        c.clickListRow('s4');
        c.clickListRow('s1', shift: true);
        expect(c.selection.toSet(), {'s4', 's3', 's2', 's1'});
        c.clickListRow('s0', ctrl: true);
        expect(c.selection.length, 5);
      });

      test(
        'picking something on the page hands the arrows back to nudging',
        () {
          c.clickListRow('s2');
          expect(c.listFocus, isTrue);
          c.select(['s0']);
          expect(c.listFocus, isFalse);
        },
      );

      test('folded layers are skipped', () {
        c.addLayer();
        final top = c.doc.layers.last;
        top.objects.add(
          ShapeObject(
            id: 'x',
            name: 'x',
            ellipse: false,
            center: const Offset(10, 10),
            size: const Size(20, 20),
          ),
        );
        c.collapsedLayers.add(top.id);
        expect(c.listOrder.first, 's4');
        expect(c.listOrder, isNot(contains('x')));
      });
    });

    test('text fonts survive saving, and sans stays out of the file', () async {
      final t = c.createText(const Offset(50, 50));
      c.doc.layers.first.objects.add(t);
      expect(t.toJson().containsKey('font'), isFalse);
      t.font = TextFont.hand;
      final c2 = newEditor();
      await c2.loadProjectJson(c.projectJson());
      expect((c2.doc.allObjects.single as TextObject).font, TextFont.hand);
      expect(TextFont.byName('nonsense'), TextFont.sans);
      expect(textStyleFor(t).fontFamily, 'Caveat');
    });

    test('a text alignment stored as text still loads', () {
      final t = TextObject(
        id: 't',
        name: 't',
        text: 'x',
        center: Offset.zero,
        size: const Size(10, 10),
      );
      final j = t.toJson()..['align'] = '1';
      expect(
        (SceneObject.fromJson(j) as TextObject).align,
        TextAlign.values[1],
      );
    });
  });

  group('round five', () {
    ShapeObject shape(String id, double x, {bool locked = false}) =>
        ShapeObject(
          id: id,
          name: id,
          ellipse: false,
          center: Offset(x, 100),
          size: const Size(40, 40),
          fill: 0xFF3366FF,
          locked: locked,
        );

    test('the list arrows hand back to nudging after anything else changes '
        'the selection', () async {
      c.doc.layers.first.objects.addAll([shape('a', 100), shape('b', 200)]);
      c.clickListRow('a');
      expect(c.listFocus, isTrue);
      // Merging replaces the selection without going through select().
      c.clickListRow('b', shift: true);
      await c.flattenSelection();
      expect(c.listFocus, isFalse);
      // Undo restores a selection, too.
      c.clickListRow(c.doc.allObjects.single.id);
      expect(c.listFocus, isTrue);
      c.undo();
      expect(c.listFocus, isFalse);
      // Clicking the page on the very same thing also ends the walk.
      c.clickListRow('a');
      c.endListWalk();
      expect(c.listFocus, isFalse);
    });

    test('Shift+click in the list runs from the current selection if it '
        'moved on', () {
      c.doc.layers.first.objects.addAll([
        shape('a', 100),
        shape('b', 200),
        shape('c', 300),
      ]);
      c.clickListRow('c'); // list order: c, b, a
      c.select(['a']); // chosen some other way
      c.clickListRow('c', shift: true);
      expect(c.selection.toSet(), {'a', 'b', 'c'});
    });

    test('a merge leaves locked and hidden things where they are', () async {
      final locked = shape('locked', 100, locked: true);
      final hidden = shape('hidden', 150)..visible = false;
      c.doc.layers.first.objects.addAll([
        locked,
        hidden,
        shape('a', 200),
        shape('b', 260),
      ]);
      c.select(['locked', 'hidden', 'a', 'b']);
      expect(c.mergeable.map((o) => o.id), ['a', 'b']);
      final m = await c.flattenSelection();
      expect(m, isNotNull);
      expect(
        c.doc.allObjects.map((o) => o.name).toSet(),
        containsAll(['locked', 'hidden']),
      );
      expect(c.doc.allObjects.length, 3);
    });

    test('nothing is merged if only one eligible thing is left', () async {
      c.doc.layers.first.objects.addAll([
        shape('a', 100, locked: true),
        shape('b', 200, locked: true),
      ]);
      c.select(['a', 'b']);
      expect(c.canMerge, isFalse);
      expect(await c.flattenSelection(), isNull);
      expect(c.doc.allObjects.length, 2);
    });

    test('a Shift-tap with the pen leaves nothing behind', () {
      c.setTool(Tool.pen);
      const shift = Modifiers(shift: true);
      ix.pointerDown(const Offset(100, 100), shift);
      ix.pointerUp(const Offset(100, 100), shift);
      expect(c.doc.allObjects, isEmpty);
      expect(c.undoDepth, 0);
    });

    test('removing a colour works the same through the isolate path', () async {
      final a = await makeAsset(c, w: 1400, h: 1100, color: 0xFFFF0000);
      final r = await removeBackground(a, 0.2);
      expect(r, isNotNull);
      expect(r!.removedPixels, 1400 * 1100);
    });
  });

  group('round six', () {
    test('a click or jittery press with the pen leaves no mark', () {
      c.setTool(Tool.pen);
      click(ix, const Offset(200, 200));
      ix.pointerDown(const Offset(300, 300), noMods);
      ix.pointerMove(const Offset(301, 302), noMods);
      ix.pointerMove(const Offset(299, 301), noMods);
      ix.pointerUp(const Offset(300, 300), noMods);
      expect(c.doc.allObjects, isEmpty);
      expect(c.undoDepth, 0);
    });

    test('a real stroke keeps its first point, even a short one', () {
      c.setTool(Tool.pen);
      ix.pointerDown(const Offset(100, 100), noMods);
      for (int i = 1; i <= 10; i++) {
        ix.pointerMove(Offset(100 + i * 3.0, 100), noMods);
      }
      ix.pointerUp(const Offset(130, 100), noMods);
      final st = c.doc.allObjects.single as StrokeObject;
      expect(st.points.first, const Offset(100, 100));
      expect(c.undoDepth, 1);
    });

    /// A tree as a line drawing on white: an outlined crown with a branch
    /// inside it, and a trunk. Nothing is filled.
    Future<Asset> treeDrawing() async {
      const w = 300, h = 300;
      final rec = PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 300, 300),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      final line = Paint()
        ..color = const Color(0xFF1B7A2B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..isAntiAlias = true;
      canvas.drawCircle(const Offset(150, 110), 80, line);
      canvas.drawLine(const Offset(150, 190), const Offset(150, 270), line);
      canvas.drawLine(const Offset(150, 140), const Offset(110, 100), line);
      canvas.drawLine(const Offset(150, 140), const Offset(190, 100), line);
      final img = await rec.endRecording().toImage(w, h);
      return c.assets.addImage(img);
    }

    Future<Uint8List> alphaOf(ColorRemoval r) async =>
        (await r.image.toByteData(
          format: ImageByteFormat.rawStraightRgba,
        ))!.buffer.asUint8List();

    int a(Uint8List px, int x, int y) => px[(y * 300 + x) * 4 + 3];

    test(
      'background removal clears the outside and the gaps inside a drawing',
      () async {
        final tree = await treeDrawing();
        final r = (await removeBackground(tree, 0.14))!;
        final px = await alphaOf(r);
        expect(a(px, 5, 5), 0, reason: 'outside');
        expect(
          a(px, 150, 110) + 0,
          0,
          reason: 'inside the crown, between lines',
        );
        expect(a(px, 230, 250), 0);
        expect(
          a(px, 150, 30),
          greaterThan(200),
          reason: 'the crown outline stays',
        );
      },
    );

    test('without "gaps inside" the enclosed white is left alone', () async {
      final tree = await treeDrawing();
      final r = (await removeBackground(tree, 0.14, inside: false))!;
      final px = await alphaOf(r);
      expect(a(px, 5, 5), 0);
      expect(a(px, 150, 70), 255, reason: 'enclosed, so kept');
    });

    test(
      'the edge keeps no pale halo: it is un-mixed from the white',
      () async {
        final tree = await treeDrawing();
        final r = (await removeBackground(tree, 0.14))!;
        final px = await alphaOf(r);
        var worst = 0;
        for (int i = 0; i < 300 * 300; i++) {
          if (px[i * 4 + 3] == 0) continue;
          // Everything left over should be the green of the pen, however faint.
          final red = px[i * 4], green = px[i * 4 + 1], blue = px[i * 4 + 2];
          // How wrong the colour is matters in proportion to how visible it is.
          final dev = math.max((red - 0x1B).abs(), (blue - 0x2B).abs());
          final wdev = dev * px[i * 4 + 3] ~/ 255;
          worst = math.max(worst, wdev);
          expect(green, greaterThan(0));
        }
        expect(worst, lessThan(6));
      },
    );

    test(
      'a background that is not white works too, and so does a noisy one',
      () async {
        final rec = PictureRecorder();
        final canvas = Canvas(rec);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 100, 100),
          Paint()..color = const Color(0xFFF4EFE0),
        );
        canvas.drawRect(
          const Rect.fromLTWH(30, 30, 40, 40),
          Paint()..color = const Color(0xFF223344),
        );
        final img = await rec.endRecording().toImage(100, 100);
        final asset = await c.assets.addImage(img);
        final r = (await removeBackground(asset, 0.14))!;
        final px = (await r.image.toByteData(
          format: ImageByteFormat.rawStraightRgba,
        ))!.buffer.asUint8List();
        expect(px[3], 0);
        expect(px[(50 * 100 + 50) * 4 + 3], 255);
      },
    );

    test('what was removed really shows the page colour underneath', () async {
      final tree = await treeDrawing();
      final r = (await removeBackground(tree, 0.14))!;
      final rec = PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 300, 300),
        Paint()..color = const Color(0xFF222222),
      );
      canvas.drawImage(r.image, Offset.zero, Paint());
      final out = await rec.endRecording().toImage(300, 300);
      final px = (await out.toByteData(
        format: ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      // Outside, and in the gap inside the crown: the dark page, not white.
      for (final (x, y) in [(5, 5), (150, 70), (280, 280)]) {
        final i = (y * 300 + x) * 4;
        expect(px.sublist(i, i + 3), [0x22, 0x22, 0x22], reason: '$x,$y');
      }
    });

    test('a half-see-through pixel survives a round trip unchanged', () async {
      final src = Uint8List.fromList([200, 100, 50, 128, 10, 20, 30, 255]);
      final img = await imageFromRgba(src, 2, 1);
      final asset = await c.assets.addImage(img);
      final back = await asset.rgbaBytes();
      for (int k = 0; k < 8; k++) {
        expect(
          (back[k] - src[k]).abs(),
          lessThanOrEqualTo(1),
          reason: 'byte $k',
        );
      }
    });

    test('a picture with nothing like a background says so', () async {
      final rec = PictureRecorder();
      final canvas = Canvas(rec);
      // Every border pixel a different colour: no background to speak of.
      for (int i = 0; i < 40; i++) {
        canvas.drawRect(
          Rect.fromLTWH(i.toDouble(), 0, 1, 40),
          Paint()
            ..color = Color.fromARGB(255, i * 6, 255 - i * 6, (i * 37) % 255),
        );
      }
      final asset = await c.assets.addImage(
        await rec.endRecording().toImage(40, 40),
      );
      expect(await removeBackground(asset, 0.02), isNull);
    });
  });
}
