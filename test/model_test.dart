import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/model/assets.dart';
import 'package:thinkspace/model/geometry.dart';
import 'package:thinkspace/model/scene.dart';

void main() {
  final assets = AssetStore();

  test('a document survives a JSON round trip, every object kind included', () {
    final d = Document.blank();
    final layer = d.layers.first;
    layer.objects.addAll([
      ImageObject(id: d.newId('o'), name: 'img', assetId: 'a1', center: const Offset(10, 20), size: const Size(30, 40), rotation: 0.5, flipX: true, opacity: 0.4),
      TextObject(id: d.newId('o'), name: 'txt', text: 'hi', center: const Offset(1, 2), size: const Size(100, 30), bold: true, background: 0xFF112233, align: TextAlign.center),
      ShapeObject(id: d.newId('o'), name: 'box', ellipse: false, center: const Offset(5, 5), size: const Size(10, 10), fill: 0xFF00FF00),
      ShapeObject(id: d.newId('o'), name: 'oval', ellipse: true, center: const Offset(5, 5), size: const Size(10, 10)),
      LineObject(id: d.newId('o'), name: 'arrow', p1: const Offset(0, 0), p2: const Offset(9, 9), headEnd: true, dashed: true),
      StrokeObject(id: d.newId('o'), name: 'pen', points: const [Offset(1, 1), Offset(2, 3)]),
    ]);
    d.collection.add(CollectionItem(id: d.newId('c'), name: 'thing', assetId: 'a1'));
    d.canvasSize = const Size(800, 2400);
    d.background = 0;

    final again = Document.decode(d.encode());
    expect(again.encode(), d.encode());
    expect(again.canvasSize, const Size(800, 2400));
    expect(again.layers.first.objects.length, 6);
    expect(again.collection.single.assetId, 'a1');
  });

  test('a rotated box is hit where it is drawn, not where its bounds are', () {
    final o = ShapeObject(id: 'o1', name: 'r', ellipse: false, center: const Offset(100, 100), size: const Size(200, 20), fill: 0xFF000000, rotation: math.pi / 4);
    // Along the rotated long axis.
    expect(o.hitTest(const Offset(150, 150), 0, assets), isTrue);
    // Inside the axis-aligned bounds, but off the shape.
    expect(o.hitTest(const Offset(150, 60), 0, assets), isFalse);
  });

  test('an empty outline is only grabbable on its outline', () {
    final o = ShapeObject(id: 'o1', name: 'r', ellipse: false, center: const Offset(100, 100), size: const Size(200, 100), strokeWidth: 4);
    expect(o.hitTest(const Offset(100, 100), 0, assets), isFalse);
    expect(o.hitTest(const Offset(0, 100), 0, assets), isTrue);
    final filled = ShapeObject(id: 'o2', name: 'r', ellipse: true, center: const Offset(100, 100), size: const Size(200, 100), fill: 0xFFFF0000);
    expect(filled.hitTest(const Offset(100, 100), 0, assets), isTrue);
    expect(filled.hitTest(const Offset(5, 5), 0, assets), isFalse);
  });

  test('lines are hit near the segment only', () {
    final l = LineObject(id: 'l', name: 'l', p1: const Offset(0, 0), p2: const Offset(100, 0), width: 4);
    expect(l.hitTest(const Offset(50, 3), 2, assets), isTrue);
    expect(l.hitTest(const Offset(50, 20), 2, assets), isFalse);
    expect(l.hitTest(const Offset(150, 0), 2, assets), isFalse);
  });

  test('strokes simplify without losing their shape', () {
    final pts = [for (int i = 0; i <= 100; i++) Offset(i.toDouble(), 0.2 * math.sin(i.toDouble()))];
    final s = simplifyPolyline(pts, 1);
    expect(s.length, lessThan(5));
    expect(s.first, pts.first);
    expect(s.last, pts.last);
  });

  test('polygon containment', () {
    final poly = [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10), const Offset(0, 10)];
    expect(polygonContains(poly, const Offset(5, 5)), isTrue);
    expect(polygonContains(poly, const Offset(15, 5)), isFalse);
  });

  test('copies are independent of the original', () {
    final a = LineObject(id: 'a', name: 'a', p1: const Offset(0, 0), p2: const Offset(1, 1));
    final b = a.copyWith(id: 'b')..translate(const Offset(5, 5));
    expect(a.p1, Offset.zero);
    expect(b.p1, const Offset(5, 5));
    expect(b.id, 'b');
  });
}
