import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart';

import '../editor/controller.dart';
import '../model/assets.dart';
import '../model/scene.dart';

typedef _Draw = void Function(Canvas c, Size s);

Future<Asset> _make(AssetStore assets, int w, int h, _Draw draw) async {
  final rec = PictureRecorder();
  draw(Canvas(rec), Size(w.toDouble(), h.toDouble()));
  final img = await rec.endRecording().toImage(w, h);
  return assets.addImage(img);
}

void _text(Canvas c, String s, Offset at, double size, Color color, {FontWeight weight = FontWeight.w700, double? maxWidth, double spacing = 0}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
}

Future<Asset> _storefront(AssetStore assets) => _make(assets, 1200, 800, (c, s) {
      // Brick wall.
      c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFC4785A));
      final mortar = Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = 2;
      for (double y = 0; y < 640; y += 26) {
        c.drawLine(Offset(0, y), Offset(s.width, y), mortar);
        final off = ((y / 26).floor() % 2) * 30.0;
        for (double x = off; x < s.width; x += 60) {
          c.drawLine(Offset(x, y), Offset(x, y + 26), mortar);
        }
      }
      // Upper windows.
      for (final x in [150.0, 520.0, 890.0]) {
        final r = Rect.fromLTWH(x, 40, 160, 150);
        c.drawRect(r.inflate(10), Paint()..color = const Color(0xFFF1E6D3));
        c.drawRect(r, Paint()..color = const Color(0xFF9CC3DD));
        c.drawLine(r.topCenter, r.bottomCenter, Paint()..color = const Color(0xFFF1E6D3)..strokeWidth = 6);
        c.drawLine(r.centerLeft, r.centerRight, Paint()..color = const Color(0xFFF1E6D3)..strokeWidth = 6);
      }
      // Sign board.
      final sign = RRect.fromRectAndRadius(const Rect.fromLTWH(70, 235, 1060, 80), const Radius.circular(8));
      c.drawRRect(sign, Paint()..color = const Color(0xFF1F3D2E));
      c.drawRRect(sign.deflate(6), Paint()..color = const Color(0x00000000)..style = PaintingStyle.stroke..strokeWidth = 3);
      _text(c, 'CORNER BAKERY', const Offset(600, 275), 52, const Color(0xFFE8C26A), spacing: 8);
      // Shop window and door.
      const glass =  Rect.fromLTWH(90, 350, 640, 300);
      c.drawRect(glass.inflate(10), Paint()..color = const Color(0xFF3A2A22));
      c.drawRect(
        glass,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFB9DDF0), Color(0xFF6E9CB8)]).createShader(glass),
      );
      // Bread on the shelf.
      for (int i = 0; i < 6; i++) {
        c.drawOval(Rect.fromLTWH(150.0 + i * 95, 560, 70, 34), Paint()..color = const Color(0xFFD9A25B));
      }
      c.drawRect(const Rect.fromLTWH(110, 592, 600, 10), Paint()..color = const Color(0xFF6B4A33));
      const door =  Rect.fromLTWH(790, 350, 260, 300);
      c.drawRect(door.inflate(10), Paint()..color = const Color(0xFF3A2A22));
      c.drawRect(door, Paint()..color = const Color(0xFF4F7D63));
      c.drawRect(door.deflate(36), Paint()..color = const Color(0xFFA9D1E3));
      c.drawCircle(const Offset(1010, 520), 9, Paint()..color = const Color(0xFFE8C26A));
      // Pavement.
      c.drawRect(const Rect.fromLTWH(0, 665, 1200, 135), Paint()..color = const Color(0xFF9A9CA3));
      for (double x = 0; x < 1200; x += 150) {
        c.drawLine(Offset(x, 665), Offset(x - 40, 800), Paint()..color = const Color(0x33000000)..strokeWidth = 3);
      }
    });

Future<Asset> _awning(AssetStore assets, Color a, Color b) => _make(assets, 640, 190, (c, s) {
      final path = Path()..moveTo(60, 0);
      path.lineTo(580, 0);
      path.lineTo(640, 150);
      // Scalloped hem along the bottom edge.
      const n = 10;
      const w = 640 / n;
      for (int i = n - 1; i >= 0; i--) {
        path.arcToPoint(Offset(i * w, 150), radius: const Radius.circular(w / 2), clockwise: true);
      }
      path.lineTo(60, 0);
      path.close();
      c.save();
      c.clipPath(path);
      for (int i = 0; i < n; i++) {
        c.drawRect(Rect.fromLTWH(i * w, 0, w + 1, 200), Paint()..color = i.isEven ? a : b);
      }
      c.drawRect(
        const Rect.fromLTWH(0, 0, 640, 190),
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x40000000), Color(0x00000000), Color(0x22000000)]).createShader(const Rect.fromLTWH(0, 0, 640, 190)),
      );
      c.restore();
    });

Future<Asset> _plant(AssetStore assets) => _make(assets, 220, 300, (c, s) {
      final leaf = Paint()..color = const Color(0xFF3F8F4F);
      for (int i = 0; i < 9; i++) {
        final a = -math.pi / 2 + (i - 4) * 0.28;
        final tip = Offset(110 + math.cos(a) * 120, 170 + math.sin(a) * 150);
        final p = Path()
          ..moveTo(110, 200)
          ..quadraticBezierTo((110 + tip.dx) / 2 + 24, (200 + tip.dy) / 2, tip.dx, tip.dy)
          ..quadraticBezierTo((110 + tip.dx) / 2 - 24, (200 + tip.dy) / 2, 110, 200);
        c.drawPath(p, leaf..color = Color.lerp(const Color(0xFF2E7040), const Color(0xFF63B36E), i / 9)!);
      }
      final pot = Path()
        ..moveTo(60, 195)
        ..lineTo(160, 195)
        ..lineTo(145, 290)
        ..lineTo(75, 290)
        ..close();
      c.drawPath(pot, Paint()..color = const Color(0xFFB5603A));
      c.drawRect(const Rect.fromLTWH(54, 188, 112, 16), Paint()..color = const Color(0xFFC97048));
    });

/// A small shop-front scene: one photo, two overlapping awnings on their own
/// layers, a note and an arrow. Used for demos and for testing by agents.
Future<void> loadStorefrontSample(EditorController c) async {
  c.assets.clear();
  final photo = await _storefront(c.assets);
  final striped = await _awning(c.assets, const Color(0xFFC62828), const Color(0xFFFFFFFF));
  final navy = await _awning(c.assets, const Color(0xFF1B3A6B), const Color(0xFFF3EBDD));
  final green = await _awning(c.assets, const Color(0xFF2E7D4F), const Color(0xFFF4F1E4));
  final plant = await _plant(c.assets);

  final d = Document(canvasSize: const Size(1200, 800), gridSize: 40);
  Layer layer(String name) => Layer(id: d.newId('l'), name: name);
  final base = layer('Storefront');
  final l1 = layer('Striped awnings');
  final l2 = layer('Navy awnings');
  final notes = layer('Notes');

  base.objects.add(ImageObject(id: d.newId('o'), name: 'storefront_photo', assetId: photo.id, center: const Offset(600, 400), size: const Size(1200, 800)));
  l1.objects.add(ImageObject(id: d.newId('o'), name: 'awning_01', assetId: striped.id, center: const Offset(410, 420), size: const Size(640, 190)));
  l2.objects.add(ImageObject(id: d.newId('o'), name: 'awning_02', assetId: navy.id, center: const Offset(560, 440), size: const Size(640, 190), rotation: 0.05, opacity: 0.85));
  notes.objects.add(TextObject(
    id: d.newId('o'),
    name: 'question',
    text: 'Which awning?',
    center: const Offset(930, 140),
    size: const Size(380, 70),
    fontSize: 48,
    bold: true,
    color: 0xFFFFFFFF,
    background: 0xCC1F3D2E,
    align: TextAlign.center,
  ));
  notes.objects.add(LineObject(
    id: d.newId('o'),
    name: 'pointer',
    p1: const Offset(880, 190),
    p2: const Offset(640, 400),
    color: 0xFFFFD600,
    width: 8,
    headEnd: true,
  ));
  d.layers.addAll([base, l1, l2, notes]);
  d.collection.addAll([
    CollectionItem(id: d.newId('c'), name: 'green awning', assetId: green.id),
    CollectionItem(id: d.newId('c'), name: 'plant', assetId: plant.id),
  ]);
  await c.replaceDocument(d);
  c.showToast('Loaded the storefront sample');
}
