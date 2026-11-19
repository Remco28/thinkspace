import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/editor/render.dart';
import 'package:thinkspace/model/scene.dart';

import 'helpers.dart';

/// Painting keeps laid-out text, pixelated tiles and pen paths between
/// frames. Whatever changes what they show must still show at once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorController c;
  setUp(() {
    c = newEditor();
    c.doc.background = 0xFFFFFFFF;
    c.doc.canvasSize = const Size(200, 100);
  });

  Future<ByteData> render() async {
    final img = await renderDocument(c.doc, c.assets);
    return (await img.toByteData())!;
  }

  int red(ByteData px, int x, int y) => px.getUint8((y * 200 + x) * 4);
  int blue(ByteData px, int x, int y) => px.getUint8((y * 200 + x) * 4 + 2);

  /// How many pixels in [r] are not white.
  int inked(ByteData px, Rect r) {
    var n = 0;
    for (int y = r.top.toInt(); y < r.bottom; y++) {
      for (int x = r.left.toInt(); x < r.right; x++) {
        if (red(px, x, y) < 200) n++;
      }
    }
    return n;
  }

  test('text shows its new colour, words and width', () async {
    final t = c.createText(const Offset(100, 50), width: 180, text: 'MMMM');
    t.color = 0xFF000000;
    t.fontSize = 30;
    fitText(t);
    t.center = const Offset(100, 50);
    c.addObject(t);
    expect(t.bounds.left, closeTo(10, 1e-6));
    final first = await render();
    expect(inked(first, const Rect.fromLTWH(0, 0, 200, 100)), greaterThan(50));

    t.color = 0xFFFF0000;
    final reddened = await render();
    var redInk = 0;
    for (int y = 0; y < 100; y++) {
      for (int x = 0; x < 200; x++) {
        if (red(reddened, x, y) > 200 && blue(reddened, x, y) < 80) redInk++;
      }
    }
    expect(redInk, greaterThan(50));

    t.text = '';
    expect(inked(await render(), const Rect.fromLTWH(0, 0, 200, 100)), 0);

    // Aligned to the other side, the same letter moves across the box.
    t
      ..color = 0xFF000000
      ..text = 'M'
      ..align = TextAlign.left;
    final left = await render();
    t.align = TextAlign.right;
    final right = await render();
    expect(inked(left, const Rect.fromLTWH(0, 0, 60, 100)), greaterThan(20));
    expect(inked(right, const Rect.fromLTWH(0, 0, 60, 100)), 0);
  });

  test('a pixelating box follows what moves under it', () async {
    final black = ShapeObject(
      id: 'black',
      name: 'black',
      ellipse: false,
      center: const Offset(25, 50),
      size: const Size(50, 100),
      fill: 0xFF000000,
      strokeWidth: 0,
    );
    final h = HideObject(
      id: 'h',
      name: 'h',
      center: const Offset(100, 50),
      size: const Size(200, 100),
      block: 100,
    );
    c.currentLayer.objects.addAll([black, h]);
    final a = await render();
    final b = await render();
    expect(red(b, 10, 10), red(a, 10, 10), reason: 'the same twice');
    expect(red(a, 10, 10), lessThan(200), reason: 'the left tile is grey');
    expect(red(a, 150, 10), greaterThan(245), reason: 'the right tile white');

    black.center = const Offset(175, 50);
    final moved = await render();
    expect(red(moved, 10, 10), greaterThan(245));
    expect(red(moved, 150, 10), lessThan(200));

    // A box underneath that changes counts too.
    final under = HideObject(
      id: 'under',
      name: 'under',
      center: const Offset(100, 50),
      size: const Size(200, 100),
      solid: true,
      color: 0xFF0000FF,
    );
    c.currentLayer.objects.insert(1, under);
    final covered = await render();
    expect(blue(covered, 10, 10), greaterThan(150));
    under.color = 0xFFFF0000;
    final recoloured = await render();
    expect(red(recoloured, 10, 10), greaterThan(150));
    expect(blue(recoloured, 10, 10), lessThan(80));
  });

  test('a pen mark is drawn where its points now are', () async {
    final s = StrokeObject(
      id: 's',
      name: 's',
      points: const [Offset(10, 20), Offset(40, 20), Offset(70, 20)],
      color: 0xFF000000,
      width: 6,
    );
    c.currentLayer.objects.add(s);
    final a = await render();
    expect(red(a, 40, 20), lessThan(50));
    s.translate(const Offset(100, 50));
    final b = await render();
    expect(red(b, 40, 20), greaterThan(245));
    expect(red(b, 140, 70), lessThan(50));
  });

  test('a pixelating box follows a pen mark that moves under it', () async {
    final s = StrokeObject(
      id: 's',
      name: 's',
      points: const [Offset(10, 10), Offset(10, 90)],
      color: 0xFF000000,
      width: 20,
    );
    final h = HideObject(
      id: 'h',
      name: 'h',
      center: const Offset(100, 50),
      size: const Size(200, 100),
      block: 100,
    );
    c.currentLayer.objects.addAll([s, h]);
    final a = await render();
    expect(red(a, 50, 50), lessThan(245));
    expect(red(a, 150, 50), greaterThan(245));
    s.translate(const Offset(170, 0));
    final b = await render();
    expect(red(b, 50, 50), greaterThan(245));
    expect(red(b, 150, 50), lessThan(245));
    s.color = 0xFF0000FF;
    final c2 = await render();
    expect(blue(c2, 150, 50), greaterThan(red(c2, 150, 50)));
  });
}
