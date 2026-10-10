import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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

  Future<ImageObject> addImage(
      {Offset at = const Offset(300, 300),
      int w = 200,
      int h = 100,
      int color = 0xFFFF0000,
      int? centerColor}) async {
    final a =
        await makeAsset(c, w: w, h: h, color: color, centerColor: centerColor);
    c.doc.canvasSize = const Size(1600, 1000); // not "pristine"
    c.doc.layers.first.objects.add(ImageObject(
        id: c.doc.newId('o'),
        name: 'image ${c.doc.nextId}',
        assetId: a.id,
        center: at,
        size: Size(w.toDouble(), h.toDouble())));
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
      drag(ix, const Offset(100, 100), const Offset(300, 110),
          m: const Modifiers(shift: true));
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
            Offset(100 + i * 5.0, 100 + (i.isEven ? 0.3 : 0)), noMods);
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
      expect((c.doc.allObjects.single as ImageObject).center,
          const Offset(300, 300));
    });

    test('a tiny wobble while clicking does not move anything', () async {
      await addImage();
      ix.pointerDown(const Offset(300, 300), noMods);
      ix.pointerMove(const Offset(301, 301), noMods);
      ix.pointerUp(const Offset(301, 301), noMods);
      expect((c.doc.allObjects.single as ImageObject).center,
          const Offset(300, 300));
      expect(c.undoDepth, 0);
    });

    test('shift while moving locks an axis', () async {
      await addImage();
      drag(ix, const Offset(300, 300), const Offset(400, 320),
          m: const Modifiers(shift: true));
      expect((c.doc.allObjects.single as ImageObject).center,
          const Offset(400, 300));
    });

    test('snapping aligns an object to the grid; ctrl bypasses it', () async {
      final img = await addImage(at: const Offset(300, 300));
      c.snapOn = true;
      c.doc.gridSize = 40;
      drag(ix, const Offset(300, 300), const Offset(353, 337));
      // The nearest of left / centre / right edges lands on a grid line.
      final b = img.bounds;
      final onGrid = [b.left, b.center.dx, b.right]
          .any((v) => (v / 40 - (v / 40).round()).abs() < 1e-6);
      expect(onGrid, isTrue);
      final before = img.center;
      drag(ix, const Offset(353, 337), const Offset(373, 357),
          m: const Modifiers(ctrl: true));
      expect(img.center - before, const Offset(20, 20),
          reason: 'ctrl moves freely');
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
      drag(ix, const Offset(400, 350), const Offset(500, 350),
          m: const Modifiers(shift: true));
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

    test('the rotate handle turns an object and snaps near 15 degrees',
        () async {
      final img = await addImage(at: const Offset(300, 300), w: 200, h: 100);
      c.select([img.id]);
      // Rotate handle sits 30px above the top edge.
      const handle = Offset(300, 250 - 30);
      drag(ix, handle,
          const Offset(500, 300 + 1)); // pointing right => 90 degrees
      expect(img.rotation, closeTo(math.pi / 2, 0.02));
      expect(c.undoDepth, 1);
    });

    test('click again reaches the object underneath', () async {
      final back = await addImage(
          at: const Offset(300, 300), w: 300, h: 300, color: 0xFF00FF00);
      final front = await addImage(
          at: const Offset(320, 320), w: 300, h: 300, color: 0xFF0000FF);
      click(ix, const Offset(320, 320));
      expect(c.selection, [front.id]);
      click(ix, const Offset(320, 320));
      expect(c.selection, [back.id],
          reason: 'a second click goes down the stack');
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
          at: const Offset(300, 300), w: 200, h: 200, color: 0xFF00FF00);
      final a = await makeAsset(c, w: 100, h: 100, color: 0x00000000);
      final ghost = ImageObject(
          id: c.doc.newId('o'),
          name: 'ghost',
          assetId: a.id,
          center: const Offset(300, 300),
          size: const Size(200, 200));
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
      drag(ix, const Offset(800, 600), const Offset(1000, 800),
          m: const Modifiers(shift: true));
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
      expect(
          c.doc.layers.map((l) => l.name), ['Layer 1', 'Layer 2', 'Layer 3']);
      c.moveLayer(2, 0);
      expect(
          c.doc.layers.map((l) => l.name), ['Layer 3', 'Layer 1', 'Layer 2']);
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

    test('selecting a layer selects its contents, which move together',
        () async {
      final a = await addImage(at: const Offset(100, 100), w: 50, h: 50);
      final b = await addImage(at: const Offset(300, 100), w: 50, h: 50);
      c.addLayer();
      final other = await makeAsset(c);
      c.currentLayer.objects.add(ImageObject(
          id: c.doc.newId('o'),
          name: 'other',
          assetId: other.id,
          center: const Offset(500, 500),
          size: const Size(50, 50)));

      c.selectLayerContents(c.doc.layers.first.id);
      expect(c.selection.toSet(), {a.id, b.id});
      final depth = c.undoDepth;
      drag(ix, const Offset(100, 100), const Offset(130, 160));
      expect(a.center, const Offset(130, 160));
      expect(b.center, const Offset(330, 160));
      expect(c.doc.allObjects.last.name, 'other');
      expect((c.doc.allObjects.last as ImageObject).center,
          const Offset(500, 500));
      expect(c.undoDepth, depth + 1,
          reason: 'moving a whole layer is one step');
    });

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
      final centers =
          c.doc.allObjects.map((o) => (o as ImageObject).center).toSet();
      expect(centers.length, 3,
          reason: 'each paste steps further so copies are visible');
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
      expect((c.doc.allObjects.single as ImageObject).center,
          const Offset(70, 70));
    });

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
      expect(c.doc.allObjects, isEmpty,
          reason: 'zoom is a view change, not a document change');
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

    test('later images are fitted into view and land in the current layer',
        () async {
      final first = await makeAsset(c, w: 900, h: 600);
      c.placeAsset(first);
      c.addLayer();
      final big = await makeAsset(c, w: 3000, h: 2000);
      final o = c.placeAsset(big);
      expect(o.size.width, lessThan(3000));
      expect(o.size.width / o.size.height, closeTo(1.5, 1e-6));
      expect(c.doc.layerOf(o.id)!.id, c.currentLayerId);
    });

    test('paste can ask: image goes to the layer or the collection', () async {
      final a = await makeAsset(c, w: 400, h: 400);
      c.pendingPaste = PendingPaste(a.id, 'pasted');
      c.resolvePaste(toCollection: true);
      expect(c.doc.collection.length, 1);
      expect(c.doc.allObjects, isEmpty);

      c.pendingPaste = PendingPaste(a.id, 'pasted');
      c.resolvePaste(toCollection: false, remember: true);
      expect(c.doc.allObjects.length, 1);
      expect(c.pasteMode, PasteMode.layer,
          reason: 'Always do this is remembered');
    });

    test('placing a collected image leaves the source in the collection',
        () async {
      final a = await makeAsset(c, w: 100, h: 100);
      final item = c.addToCollection(a, name: 'awning');
      final o1 = c.placeCollectionItem(item.id, at: const Offset(200, 200))!;
      final o2 = c.placeCollectionItem(item.id, at: const Offset(400, 200))!;
      expect(c.doc.collection.length, 1);
      expect(o1.id, isNot(o2.id));
      expect(o1.assetId, o2.assetId);
    });

    test('a placed image can be kept in the collection', () async {
      final img = await addImage();
      c.select([img.id]);
      c.sendSelectionToCollection();
      expect(c.doc.collection.single.assetId, img.assetId);
    });
  });

  group('cutouts', () {
    test('a box cutout makes a new object and leaves the original intact',
        () async {
      final img = await addImage(
          at: const Offset(300, 300),
          w: 200,
          h: 100,
          color: 0xFF0000FF,
          centerColor: 0xFFFFFF00);
      c.select([img.id]);
      final piece = await c.cutout(img, [
        const Offset(250, 275),
        const Offset(350, 275),
        const Offset(350, 325),
        const Offset(250, 325)
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
      expect(c.assets[img.assetId]!.width, 200,
          reason: 'the original asset is untouched');
      expect(c.selection, [piece.id]);
      expect(c.undoDepth, 1);
    });

    test('a triangular lasso is transparent outside the triangle', () async {
      final img = await addImage(
          at: const Offset(300, 300), w: 200, h: 200, color: 0xFFFF0000);
      final piece = await c.cutout(img, [
        const Offset(200, 200),
        const Offset(400, 200),
        const Offset(200, 400)
      ]);
      final a = c.assets[piece!.assetId]!;
      expect(a.alphaAt(10, 10), 255);
      expect(a.alphaAt(190, 190), 0);
    });

    test('a hole can be left in the original', () async {
      final img = await addImage(
          at: const Offset(300, 300), w: 200, h: 100, color: 0xFF0000FF);
      final oldAsset = img.assetId;
      await c.cutout(
          img,
          [
            const Offset(250, 275),
            const Offset(350, 275),
            const Offset(350, 325),
            const Offset(250, 325)
          ],
          leaveHole: true);
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
          centerColor: 0xFFFFFF00);
      img.rotation = math.pi / 2;
      img.flipX = true;
      // After a quarter turn the image is 100 wide and 200 tall on the page.
      final piece = await c.cutout(img, [
        const Offset(250, 250),
        const Offset(350, 250),
        const Offset(350, 350),
        const Offset(250, 350)
      ]);
      expect(piece, isNotNull);
      expect(piece!.rotation, math.pi / 2);
      expect(piece.flipX, isTrue);
      expect(piece.center.dx, closeTo(300, 1));
      expect(piece.center.dy, closeTo(300, 1));
    });

    test('remove background clears the surrounding colour but not the subject',
        () async {
      final img = await addImage(
          w: 100, h: 100, color: 0xFFFFFFFF, centerColor: 0xFFCC0000);
      final ok = await c.removeBackgroundFrom(img);
      expect(ok, isTrue);
      final a = c.assets[(c.doc.objectById(img.id) as ImageObject).assetId]!;
      expect(a.alphaAt(2, 2), 0);
      expect(a.alphaAt(50, 50), 255);
      expect(c.undoDepth, 1);
    });

    test('removing a colour only floods what touches the click', () async {
      final img = await addImage(
          w: 100, h: 100, color: 0xFFFFFFFF, centerColor: 0xFF000000);
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

  group('large images', () {
    test('big images keep a coarse alpha mask that still finds thin parts',
        () async {
      final rec = PictureRecorder();
      final canvas = Canvas(rec);
      // 4000x3000, transparent except a 6px-wide vertical bar.
      canvas.drawRect(const Rect.fromLTWH(2000, 0, 6, 3000),
          Paint()..color = const Color(0xFF00FF00));
      final img = await rec.endRecording().toImage(4000, 3000);
      final a = await c.assets.addImage(img);
      expect(a.alphaAt(2003, 1500), 255);
      expect(a.alphaAt(100, 100), 0);
      expect(a.alphaAt(-5, 10), 0);
      expect((await a.rgbaBytes()).length, 4000 * 3000 * 4);
    });

    test('exports are limited to something a GPU can make', () async {
      c.setCanvasSize(const Size(12000, 12000));
      final png = await c.exportPng(scale: 4);
      final codec = await instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, lessThanOrEqualTo(16000));
    });
  });

  group('merge and recovery', () {
    test('merging pieces makes one image and undo brings the pieces back',
        () async {
      final a = await addImage(
          at: const Offset(100, 100), w: 100, h: 100, color: 0xFFFF0000);
      final b = await addImage(
          at: const Offset(200, 100), w: 100, h: 100, color: 0xFF0000FF);
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
    });

    test('unsaved work is autosaved and can be restored', () async {
      final dir = Directory.systemTemp.createTempSync('thinkspace_recovery');
      addTearDown(() => dir.deleteSync(recursive: true));
      c.startAutosave(File('${dir.path}/recovery.thinkspace'),
          every: const Duration(days: 1));
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
      expect(c.pendingRecovery(), isNull,
          reason: 'saving clears the recovery file');
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
          at: const Offset(300, 300), w: 120, h: 80, color: 0xFF336699);
      img.rotation = 0.4;
      img.opacity = 0.55;
      c.addLayer();
      c.setTool(Tool.arrow);
      drag(ix, const Offset(10, 10), const Offset(200, 120));
      final item =
          c.addToCollection(await makeAsset(c, w: 30, h: 30), name: 'swatch');
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
      expect(c2.undoDepth, 0,
          reason: 'a freshly opened project has no history');
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
          () => c.loadProjectJson('{"format":"other"}'), throwsFormatException);
      expect(c.doc.allObjects.length, 1);
    });

    test('export renders the page at the requested scale', () async {
      final img = await addImage(
          at: const Offset(100, 100), w: 100, h: 100, color: 0xFFFF0000);
      expect(img, isNotNull);
      c.setCanvasSize(const Size(300, 200));
      final png = await c.exportPng(scale: 2);
      final codec = await instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 600);
      expect(frame.image.height, 400);
      final raw =
          (await frame.image.toByteData(format: ImageByteFormat.rawRgba))!;
      int px(int x, int y) => raw.getUint32((y * 600 + x) * 4);
      expect(px(200, 200), 0xFF0000FF, reason: 'red object, rgba order');
      expect(px(500, 350), 0xFFFFFFFF, reason: 'white page');
    });

    test('hidden things are not exported, and the page can be transparent',
        () async {
      final img = await addImage(at: const Offset(100, 100), w: 100, h: 100);
      c.setObjectVisible(img.id, false);
      c.setCanvasSize(const Size(200, 200));
      c.setBackground(0);
      final codec = await instantiateImageCodec(await c.exportPng());
      final image = (await codec.getNextFrame()).image;
      final raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      expect(raw.getUint8(3), 0);
    });

    test('undo history is not shared with a new document', () async {
      await addImage();
      c.deleteSelection();
      c.newDocument();
      expect(c.canUndo, isFalse);
      expect(c.doc.layers.length, 1);
      expect(c.assets.length, 0);
    });
  });
}
