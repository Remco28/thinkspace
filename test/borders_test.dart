import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/editor/render.dart';
import 'package:thinkspace/model/scene.dart';
import 'package:thinkspace/ui/shell.dart';

import 'helpers.dart';

Future<(ByteData, int)> pixels(EditorController c) async {
  final img = await renderDocument(c.doc, c.assets);
  return ((await img.toByteData())!, img.width);
}

int channel(ByteData px, int width, int x, int y, int i) =>
    px.getUint8((y * width + x) * 4 + i);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stored', () {
    test('a border round-trips; a picture without one saves as before', () {
      final pic = ImageObject(
        id: 'p',
        name: 'p',
        assetId: 'a',
        center: Offset.zero,
        size: const Size(10, 10),
      );
      expect(
        pic.toJson().keys,
        isNot(
          anyOf(
            contains('border'),
            contains('borderWidth'),
            contains('shadow'),
          ),
        ),
      );
      pic
        ..border = 0xFF1E88E5
        ..borderWidth = 9
        ..shadow = true;
      final back = SceneObject.fromJson(pic.toJson()) as ImageObject;
      expect(back.border, 0xFF1E88E5);
      expect(back.borderWidth, 9);
      expect(back.shadow, isTrue);
      final t = TextObject(
        id: 't',
        name: 't',
        text: 'x',
        center: Offset.zero,
        size: const Size(10, 10),
      )..border = 0xFF222222;
      final tb = SceneObject.fromJson(t.toJson()) as TextObject;
      expect(tb.border, 0xFF222222);
      expect(tb.copyWith().border, 0xFF222222);
    });

    test('a width without a border is not written', () {
      final pic = ImageObject(
        id: 'p',
        name: 'p',
        assetId: 'a',
        center: Offset.zero,
        size: const Size(10, 10),
      )..borderWidth = 12;
      expect(pic.toJson().containsKey('borderWidth'), isFalse);
    });

    test('a damaged border opens as no border', () {
      final j = ImageObject(
        id: 'p',
        name: 'p',
        assetId: 'a',
        center: Offset.zero,
        size: const Size(10, 10),
      ).toJson();
      j['border'] = 'red';
      j['borderWidth'] = -3;
      j['shadow'] = 'yes';
      final back = SceneObject.fromJson(j) as ImageObject;
      expect(back.border, 0);
      expect(back.borderWidth, 4);
      expect(back.shadow, isFalse);
    });
  });

  group('drawn', () {
    late EditorController c;
    late ImageObject pic;

    setUp(() async {
      c = newEditor();
      c.doc.canvasSize = const Size(200, 200);
      c.doc.background = 0xFFFFFFFF;
      final a = await makeAsset(c, w: 100, h: 100, color: 0xFFFF0000);
      pic =
          ImageObject(
              id: 'pic',
              name: 'pic',
              assetId: a.id,
              center: const Offset(100, 100),
              size: const Size(100, 100),
            )
            ..border = 0xFF0000FF
            ..borderWidth = 10;
      c.currentLayer.objects.add(pic);
    });

    test(
      'the border is outside the edge and covers none of the picture',
      () async {
        final (px, w) = await pixels(c);
        // Just inside the edge: still the picture's red.
        expect(channel(px, w, 52, 100, 0), greaterThan(240));
        expect(channel(px, w, 52, 100, 2), lessThan(20));
        // In the band just outside: blue.
        expect(channel(px, w, 45, 100, 2), greaterThan(240));
        expect(channel(px, w, 45, 100, 0), lessThan(20));
        // Beyond it: the white page.
        expect(channel(px, w, 35, 100, 0), greaterThan(240));
      },
    );

    test('the shadow falls below, and fades with a faded picture', () async {
      pic
        ..border = 0
        ..shadow = true;
      final (px, w) = await pixels(c);
      // Below the bottom edge it is darker than above the top edge.
      final below = channel(px, w, 100, 153, 1);
      final above = channel(px, w, 100, 47, 1);
      expect(below, lessThan(above));
      expect(below, lessThan(250));
      pic
        ..border = 0xFF0000FF
        ..opacity = 0.5;
      final (px2, w2) = await pixels(c);
      // The half-faded border is still drawn, outside the edge.
      expect(channel(px2, w2, 45, 100, 2), greaterThan(240));
      expect(channel(px2, w2, 45, 100, 0), inInclusiveRange(100, 160));
    });

    test('a cut-out\'s shadow follows its outline, not its box', () async {
      // A picture that is red on its left half and see-through on its right.
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 50, 100),
        Paint()..color = const Color(0xFFFF0000),
      );
      final img = await rec.endRecording().toImage(100, 100);
      final a = await c.assets.addImage(img);
      pic
        ..assetId = a.id
        ..border = 0
        ..shadow = true;
      final (px, w) = await pixels(c);
      // Under the see-through half, just below the box: no shadow.
      expect(channel(px, w, 135, 156, 1), greaterThan(250));
      // Under the solid half: shadow.
      expect(channel(px, w, 75, 154, 1), lessThan(250));
    });

    test('merging a turned picture keeps its border corners', () async {
      pic.rotation = math.pi / 4;
      final other = ShapeObject(
        id: 's',
        name: 's',
        ellipse: false,
        center: const Offset(10, 10),
        size: const Size(4, 4),
        fill: 0xFF000000,
      );
      c.currentLayer.objects.add(other);
      c.select(['pic', 's']);
      final merged = await c.flattenSelection();
      expect(merged, isNotNull);
      const reach = (50 + 10) * math.sqrt2;
      expect(merged!.bounds.right, greaterThanOrEqualTo(100 + reach));
    });

    test('Give all pictures this border skips locked ones', () async {
      final a = await makeAsset(c);
      final other = ImageObject(
        id: 'o',
        name: 'o',
        assetId: a.id,
        center: const Offset(10, 10),
        size: const Size(10, 10),
      );
      final locked = ImageObject(
        id: 'l',
        name: 'l',
        assetId: a.id,
        center: const Offset(10, 10),
        size: const Size(10, 10),
        locked: true,
      );
      c.currentLayer.objects.addAll([other, locked]);
      final depth = c.undoDepth;
      c.matchPictureBorders(pic);
      expect(other.border, 0xFF0000FF);
      expect(other.borderWidth, 10);
      expect(locked.border, 0);
      expect(c.undoDepth, depth + 1);
    });

    test('a click on the border selects the picture', () {
      expect(c.objectsAt(const Offset(46, 100)).map((o) => o.id), ['pic']);
      expect(c.objectsAt(const Offset(30, 100)), isEmpty);
    });
  });

  group('merging never un-hides', () {
    late EditorController c;
    late ImageObject a, b;
    late HideObject hide;

    setUp(() async {
      c = newEditor();
      c.doc.canvasSize = const Size(300, 200);
      c.doc.background = 0xFFFFFFFF;
      final red = await makeAsset(c, w: 100, h: 100, color: 0xFFFF0000);
      final green = await makeAsset(c, w: 40, h: 40, color: 0xFF00FF00);
      a = ImageObject(
        id: 'a',
        name: 'a',
        assetId: red.id,
        center: const Offset(100, 100),
        size: const Size(100, 100),
      );
      hide = HideObject(
        id: 'h',
        name: 'h',
        center: const Offset(80, 100),
        size: const Size(30, 30),
        solid: true,
        color: 0xFF000000,
      );
      b = ImageObject(
        id: 'b',
        name: 'b',
        assetId: green.id,
        center: const Offset(200, 100),
        size: const Size(40, 40),
      );
      c.currentLayer.objects.addAll([a, hide, b]);
    });

    Future<int> redAt(Offset p) async {
      final img = await renderDocument(c.doc, c.assets);
      final px = (await img.toByteData())!;
      return px.getUint8((p.dy.round() * img.width + p.dx.round()) * 4);
    }

    test('a Hide box between the parts is painted in, and stays', () async {
      expect(await redAt(const Offset(80, 100)), lessThan(20));
      c.select(['a', 'b']);
      final merged = await c.flattenSelection();
      expect(merged, isNotNull);
      expect(c.doc.objectById('h'), isNotNull);
      // Even with the box hidden, the merged picture itself keeps it covered.
      c.setObjectVisible('h', false);
      expect(await redAt(const Offset(80, 100)), lessThan(20));
      expect(await redAt(const Offset(120, 100)), greaterThan(240));
      c.setObjectVisible('h', true);
      // Taken apart again, the cover comes back above the part it hid.
      c.select([merged!.id]);
      c.unmerge();
      c.setObjectVisible('h', false);
      expect(await redAt(const Offset(80, 100)), lessThan(20));
    });

    test('a selected Hide box is not taken off the page', () async {
      c.select(['a', 'h', 'b']);
      await c.flattenSelection();
      expect(c.doc.objectById('h'), isNotNull);
      expect(await redAt(const Offset(80, 100)), lessThan(20));
    });

    test('a switched-off box between the parts stops the merge', () async {
      hide.visible = false;
      final sig = c.doc.signature();
      c.select(['a', 'b']);
      expect(await c.flattenSelection(), isNull);
      expect(c.doc.signature(), sig);
      expect(c.toastMessage, contains('switched-off'));
    });

    test('something visible between the parts stops the merge', () async {
      final label = TextObject(
        id: 't',
        name: 'Label',
        text: 'Hi',
        center: const Offset(110, 100),
        size: const Size(40, 20),
      );
      c.currentLayer.objects.insert(1, label);
      c.select(['a', 'b']);
      expect(await c.flattenSelection(), isNull);
      expect(c.toastMessage, contains('Label'));
      // Outside every part it is no obstacle, even inside their outer box.
      label.center = const Offset(160, 30);
      expect(await c.flattenSelection(), isNotNull);
    });

    test('a box above every part is painted in too', () async {
      c.currentLayer.objects
        ..remove(hide)
        ..add(hide);
      c.select(['a', 'b']);
      final merged = await c.flattenSelection();
      expect(merged, isNotNull);
      // Moved out from under the box, the merged picture still hides it.
      c.select([merged!.id]);
      c.nudge(const Offset(0, 60));
      expect(await redAt(const Offset(80, 160)), lessThan(20));
      expect(await redAt(const Offset(120, 160)), greaterThan(240));
      // And unmerged there, the box comes back with the parts.
      c.unmerge();
      expect(await redAt(const Offset(80, 160)), lessThan(20));
    });

    test(
      'a box on another layer is painted in; the merge goes ahead',
      () async {
        c.currentLayer.objects.remove(hide);
        c.addLayer();
        c.currentLayer.objects.add(hide);
        c.currentLayer.objects.remove(b);
        c.doc.layers.first.objects.remove(b);
        c.addLayer();
        c.currentLayer.objects.add(b);
        c.select(['a', 'b']);
        final merged = await c.flattenSelection();
        expect(merged, isNotNull);
        c.setObjectVisible('h', false);
        expect(await redAt(const Offset(80, 100)), lessThan(20));
      },
    );

    test('highlights merged across a box stay see-through', () async {
      c.currentLayer.objects.removeWhere((o) => o.id != 'h');
      final s1 = StrokeObject(
        id: 's1',
        name: 's1',
        points: const [Offset(50, 100), Offset(150, 100)],
        width: 20,
        highlight: HighlightStyle.multiply,
      );
      final s2 = StrokeObject(
        id: 's2',
        name: 's2',
        points: const [Offset(50, 140), Offset(150, 140)],
        width: 20,
        highlight: HighlightStyle.multiply,
      );
      c.currentLayer.objects
        ..insert(0, s1)
        ..add(s2);
      c.select(['s1', 's2']);
      // A box between the highlights would end up tinted: refused.
      expect(await c.flattenSelection(), isNull);
      expect(c.toastMessage, contains('between these highlights'));
      // With the box above them both, they merge and stay see-through.
      c.currentLayer.objects
        ..remove(hide)
        ..add(hide);
      final merged = await c.flattenSelection();
      expect(merged!.multiply, isTrue);
      expect(c.doc.objectById('h'), isNotNull);
    });

    test('an edit made while a merge renders cancels the merge', () async {
      c.select(['a', 'b']);
      final pending = c.flattenSelection();
      // Before the picture is ready, the Hide box is moved.
      final t = c.beginEdit('move');
      hide.center += const Offset(0, 40);
      c.endEdit(t);
      final sig = c.doc.signature();
      expect(await pending, isNull);
      expect(c.toastMessage, contains('changed while merging'));
      expect(c.doc.signature(), sig);
      expect(c.doc.objectById('a'), isNotNull);
    });

    test(
      'a gesture begun during a merge, unchanged so far, cancels it too',
      () async {
        c.select(['a', 'b']);
        final pending = c.flattenSelection();
        final t = c.beginEdit('move');
        expect(await pending, isNull);
        c.abortEdit(t);
        expect(c.doc.objectById('a'), isNotNull);
      },
    );

    test('with no box over the parts, a merge is as before', () async {
      c.currentLayer.objects.remove(hide);
      c.select(['a', 'b']);
      final merged = await c.flattenSelection();
      expect(merged!.merged!.parts, hasLength(2));
      expect(await redAt(const Offset(80, 100)), greaterThan(240));
    });
  });

  group('the panel', () {
    Future<EditorController> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = EditorController();
      await tester.pumpWidget(
        MaterialApp(home: EditorShell(controller: c, startInspector: false)),
      );
      await tester.pump();
      return c;
    }

    testWidgets('pictures, text and a mix of them share one Border row', (
      tester,
    ) async {
      final c = await pump(tester);
      final a = await tester.runAsync(() => makeAsset(c));
      final pic = ImageObject(
        id: 'pic',
        name: 'pic',
        assetId: a!.id,
        center: const Offset(300, 300),
        size: const Size(100, 100),
      );
      final text = TextObject(
        id: 'txt',
        name: 'txt',
        text: 'Hi',
        center: const Offset(500, 300),
        size: const Size(100, 40),
      );
      final line = LineObject(
        id: 'ln',
        name: 'ln',
        p1: const Offset(100, 500),
        p2: const Offset(300, 500),
      );
      c.currentLayer.objects.addAll([pic, text, line]);
      for (final ids in [
        ['pic'],
        ['txt'],
        ['pic', 'ln'],
        ['pic', 'txt'],
      ]) {
        c.select(ids);
        await tester.pump();
        await tester.ensureVisible(find.byKey(const ValueKey('border-shadow')));
        await tester.pump();
        expect(find.byKey(const ValueKey('border-colour')), findsOneWidget);
      }
      final depth = c.undoDepth;
      await tester.tap(find.byKey(const ValueKey('border-shadow')));
      await tester.pump();
      expect(pic.shadow && text.shadow, isTrue);
      expect(c.undoDepth, depth + 1);
      // Picking a colour from the popover gives both a border.
      await tester.tap(find.byKey(const ValueKey('border-colour')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('swatch-popover')), findsOneWidget);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('swatch-popover'))) +
            const Offset(12 + 30, 12 + 10),
      );
      await tester.pumpAndSettle();
      expect(pic.border, isNot(0));
      expect(text.border, pic.border);
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
