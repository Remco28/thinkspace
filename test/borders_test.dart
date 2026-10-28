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
      c.currentLayer.objects.addAll([pic, text]);
      for (final ids in [
        ['pic'],
        ['txt'],
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
