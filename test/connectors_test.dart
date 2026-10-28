import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/editor/interactor.dart';
import 'package:thinkspace/model/connect.dart';
import 'package:thinkspace/model/geometry.dart';
import 'package:thinkspace/model/scene.dart';

import 'helpers.dart';

/// How far [p] is from the outline [t]'s ends ride, in the object's frame.
double offOutline(BoxObject t, Offset p) {
  final o = outlineOf(t);
  final l = t.toLocal(p);
  if (o.round) {
    final x = l.dx / o.hw, y = l.dy / o.hh;
    return (math.sqrt(x * x + y * y) - 1).abs() * math.min(o.hw, o.hh);
  }
  final dx = l.dx.abs() - o.hw, dy = l.dy.abs() - o.hh;
  return math.max(dx, dy).abs();
}

double distanceToLine(LineObject l, Offset p) {
  final pts = [for (int i = 0; i <= 200; i++) l.pointAt(i / 200)];
  var best = double.infinity;
  for (int i = 1; i < pts.length; i++) {
    best = math.min(best, distToSegment(p, pts[i - 1], pts[i]));
  }
  return best;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stored', () {
    test('attachments round-trip; a line without them saves as before', () {
      final l = LineObject(
        id: 'l',
        name: 'l',
        p1: Offset.zero,
        p2: const Offset(10, 0),
        start: const Attachment('a'),
        end: const Attachment('b', Offset(0.25, -0.5)),
        anchorBend: const Offset(0, 0.2),
      );
      final back = SceneObject.fromJson(l.toJson()) as LineObject;
      expect(back.start, const Attachment('a'));
      expect(back.end, const Attachment('b', Offset(0.25, -0.5)));
      expect(back.anchorBend, const Offset(0, 0.2));
      final plain = LineObject(
        id: 'p',
        name: 'p',
        p1: Offset.zero,
        p2: Offset.zero,
      );
      expect(
        plain.toJson().keys,
        isNot(
          anyOf(contains('start'), contains('end'), contains('anchorBend')),
        ),
      );
    });

    test('damaged notes load as free ends, not as a file that fails', () {
      final j = LineObject(
        id: 'l',
        name: 'l',
        p1: Offset.zero,
        p2: const Offset(10, 0),
      ).toJson();
      j['start'] = 'nonsense';
      j['end'] = {'to': 7};
      j['anchorBend'] = ['x'];
      final back = SceneObject.fromJson(j) as LineObject;
      expect(back.start, isNull);
      expect(back.end, isNull);
      expect(back.anchorBend, isNull);
    });
  });

  group('geometry', () {
    test('an end on a turned, bordered box touches the border outside', () {
      final t =
          TextObject(
              id: 't',
              name: 't',
              text: 'x',
              center: const Offset(100, 100),
              size: const Size(200, 60),
              rotation: 0.4,
            )
            ..border = 0xFF000000
            ..borderWidth = 10;
      for (final aim in [
        const Offset(400, 130),
        const Offset(120, 400),
        const Offset(-200, -60),
      ]) {
        // On the border's outside: 10 px beyond the box, round at the
        // corners (radius 6 + 10).
        final l = t.toLocal(rayExit(t, aim));
        final ax = l.dx.abs(), ay = l.dy.abs();
        final off = ax > 110 - 16 && ay > 40 - 16
            ? Offset(ax - 94, ay - 24).distance - 16
            : math.max(ax - 110, ay - 40);
        expect(off.abs(), lessThan(1e-6));
      }
    });

    test('an ellipse and a marker are ridden round', () {
      final e = ShapeObject(
        id: 'e',
        name: 'e',
        ellipse: true,
        center: Offset.zero,
        size: const Size(200, 100),
        strokeWidth: 8,
      );
      final p = rayExit(e, const Offset(300, 300));
      final x = p.dx / 104, y = p.dy / 54;
      expect(x * x + y * y, closeTo(1, 1e-9));
    });

    test('a pin follows its picture moved, resized, turned and flipped', () {
      final pic = ImageObject(
        id: 'p',
        name: 'p',
        assetId: 'a',
        center: const Offset(100, 100),
        size: const Size(200, 100),
      );
      final at = pinAt(pic, const Offset(150, 75));
      expect(at, const Offset(0.25, -0.25));
      pic
        ..center = const Offset(300, 300)
        ..size = const Size(400, 200)
        ..rotation = math.pi / 2;
      final q = pinPoint(pic, at);
      expect(q.dx, closeTo(350, 1e-9));
      expect(q.dy, closeTo(400, 1e-9));
      pic
        ..rotation = 0
        ..flipX = true;
      expect(pinPoint(pic, at), const Offset(200, 250));
    });

    test('paintBounds holds a turned picture\'s border corners', () {
      final pic =
          ImageObject(
              id: 'p',
              name: 'p',
              assetId: 'a',
              center: Offset.zero,
              size: const Size(100, 100),
              rotation: math.pi / 4,
            )
            ..border = 0xFF000000
            ..borderWidth = 20;
      const reach = (50 + 20) * math.sqrt2;
      expect(pic.paintBounds.right, closeTo(reach, 1e-6));
      expect(pic.bounds.right, closeTo(50 * math.sqrt2, 1e-6));
    });
  });

  group('on the page', () {
    late EditorController c;
    late CanvasInteractor ix;
    late ImageObject pic;
    late TextObject label;

    setUp(() async {
      c = newEditor();
      ix = CanvasInteractor(c);
      final a = await makeAsset(c, w: 300, h: 200);
      pic = ImageObject(
        id: 'pic',
        name: 'pic',
        assetId: a.id,
        center: const Offset(700, 400),
        size: const Size(300, 200),
      );
      label = TextObject(
        id: 'label',
        name: 'label',
        text: 'Look',
        center: const Offset(250, 150),
        size: const Size(200, 60),
        background: 0xFFFFF200,
      );
      c.currentLayer.objects.addAll([pic, label]);
      c.notify();
    });

    LineObject arrow(Offset a, Offset b, {Modifiers m = noMods}) {
      c.setTool(Tool.arrow);
      drag(ix, a, b, m: m);
      return c.doc.allObjects.whereType<LineObject>().last;
    }

    test('an arrow from a label to a picture stays on both as they move', () {
      final l = arrow(const Offset(250, 150), const Offset(650, 380));
      expect(l.start, const Attachment('label'));
      expect(l.end!.to, 'pic');
      expect(l.p2, const Offset(650, 380));
      expect(offOutline(label, l.p1), lessThan(l.width / 2 + 1e-6));
      // Move the label: the tail goes round with it.
      drag(ix, const Offset(200, 140), const Offset(200, 640));
      expect(label.center, const Offset(250, 650));
      expect(offOutline(label, l.p1), lessThan(l.width / 2 + 1e-6));
      expect(l.p1.dy, lessThan(650)); // the side facing the tip
      // Move the picture: the tip stays on its spot.
      drag(ix, const Offset(800, 450), const Offset(900, 450));
      expect(l.p2, const Offset(750, 380));
    });

    test('Ctrl draws a free arrow', () {
      final l = arrow(
        const Offset(250, 150),
        const Offset(650, 380),
        m: const Modifiers(ctrl: true),
      );
      expect(l.attached, isFalse);
    });

    test('a click on an attached end changes nothing; a drag off frees it', () {
      final l = arrow(const Offset(250, 150), const Offset(650, 380));
      c.select([l.id]);
      final depth = c.undoDepth;
      // Press on the handle a few pixels off the end, and let go.
      click(ix, l.p1 + const Offset(3, 3));
      expect(l.start, const Attachment('label'));
      expect(c.undoDepth, depth);
      // Drag the tip into empty space.
      drag(ix, l.p2, const Offset(1000, 100));
      expect(l.end, isNull);
      expect(l.p2, const Offset(1000, 100));
    });

    test('dragging an end follows the pointer while it is dragged', () {
      final l = arrow(const Offset(250, 150), const Offset(650, 380));
      c.select([l.id]);
      ix.pointerDown(l.p1, noMods);
      ix.pointerMove(const Offset(100, 700), noMods);
      expect(l.p1, const Offset(100, 700));
      ix.pointerUp(const Offset(100, 700), noMods);
      expect(l.start, isNull);
    });

    test('dragging a connector\'s middle bends it under the pointer', () {
      final l = arrow(const Offset(250, 150), const Offset(650, 380));
      c.select([l.id]);
      final m = l.pointAt(0.5);
      final to = m + const Offset(-60, 80);
      drag(ix, m, to);
      expect(l.anchorBend, isNotNull);
      expect(l.curved, isTrue);
      expect(distanceToLine(l, to), lessThan(2));
      expect(offOutline(label, l.p1), lessThan(l.width / 2 + 1e-6));
      // Moving what it connects keeps the bend; it stays on the outline.
      drag(ix, const Offset(200, 140), const Offset(100, 110));
      expect(l.curved, isTrue);
      expect(offOutline(label, l.p1), lessThan(l.width / 2 + 1e-3));
    });

    test('a mark on a picture moves by drag, keys and align, and re-pins', () {
      final l = arrow(const Offset(600, 350), const Offset(700, 420));
      expect(l.start!.pinned && l.end!.pinned, isTrue);
      c.select([l.id]);
      c.setTool(Tool.select);
      drag(ix, l.pointAt(0.25), l.pointAt(0.25) + const Offset(40, 0));
      expect(l.p1, const Offset(640, 350));
      expect(l.start!.to, 'pic');
      c.nudge(const Offset(0, 10));
      expect(l.p1, const Offset(640, 360));
      expect(l.end!.to, 'pic');
      // And the picture still carries it.
      c.select(['pic']);
      c.nudge(const Offset(5, 0));
      expect(l.p1, const Offset(645, 360));
    });

    test('aligned with its picture, a mark stays on its spot', () {
      final l = arrow(const Offset(600, 350), const Offset(700, 420));
      final caption = TextObject(
        id: 'cap',
        name: 'cap',
        text: 'Caption',
        center: const Offset(1000, 600),
        size: const Size(160, 40),
      );
      c.currentLayer.objects.add(caption);
      final p1 = l.p1, at = l.start!.at;
      for (final how in ['left', 'top', 'right']) {
        c.select(['pic', l.id, 'cap']);
        c.alignSelection(how);
        final moved = pic.center - const Offset(700, 400);
        expect(l.start!.at, at, reason: how);
        expect(l.p1, p1 + moved, reason: how);
      }
      // Aligned without its picture, it moves and pins where it lands.
      pic.center = const Offset(700, 400);
      c.notify();
      c.select([l.id, 'cap']);
      c.alignSelection('top');
      expect(l.start!.to, 'pic');
      expect(caption.bounds.top, closeTo(l.bounds.top, 1e-6));
    });

    test('a mark that need not move keeps its pins, even under another', () {
      final l = arrow(const Offset(600, 350), const Offset(700, 420));
      final caption = TextObject(
        id: 'cap',
        name: 'cap',
        text: 'Caption',
        center: const Offset(1000, 600),
        size: const Size(160, 40),
      );
      c.currentLayer.objects.add(caption);
      final at = l.end!.at;
      c.select([l.id, 'cap']);
      // The mark is the leftmost: Align left leaves it where it is.
      c.alignSelection('left');
      expect(l.end, Attachment('pic', at));
    });

    test('a mark dragged onto a label stays a mark on the picture', () {
      label.center = const Offset(700, 400); // over the picture
      c.notify();
      final l = arrow(const Offset(560, 310), const Offset(680, 330));
      expect(l.start!.to, 'pic');
      c.select([l.id]);
      drag(ix, l.pointAt(0.25), const Offset(700, 400));
      expect(l.connects, isFalse);
      expect(l.start!.to, 'pic');
      expect(l.end!.to, 'pic');
    });

    test('a group move keeps its pins, even over another picture', () async {
      final a = await makeAsset(c, w: 100, h: 100);
      final other = ImageObject(
        id: 'other',
        name: 'other',
        assetId: a.id,
        center: const Offset(700, 750),
        size: const Size(300, 200),
      );
      c.currentLayer.objects.add(other);
      final l = arrow(const Offset(600, 350), const Offset(700, 420));
      c.select(['pic', l.id]);
      c.setTool(Tool.select);
      drag(ix, const Offset(800, 450), const Offset(800, 800));
      expect(l.start!.to, 'pic');
      expect(l.end!.to, 'pic');
    });

    test('an end inside an unfilled frame reaches the picture under it', () {
      final frame = ShapeObject(
        id: 'frame',
        name: 'frame',
        ellipse: false,
        center: const Offset(700, 400),
        size: const Size(200, 150),
      );
      c.currentLayer.objects.add(frame);
      c.notify();
      final inside = arrow(const Offset(100, 600), const Offset(700, 400));
      expect(inside.end!.to, 'pic');
      final edge = arrow(const Offset(100, 700), const Offset(601, 400));
      expect(edge.end, const Attachment('frame'));
    });

    test('a locked picture takes a pin', () {
      pic.locked = true;
      final l = arrow(const Offset(100, 600), const Offset(700, 400));
      expect(l.end!.to, 'pic');
    });

    test('moving a target and its arrow is one undo step', () {
      final l = arrow(const Offset(250, 150), const Offset(650, 380));
      final before = l.p1;
      final depth = c.undoDepth;
      drag(ix, const Offset(200, 140), const Offset(200, 640));
      expect(c.undoDepth, depth + 1);
      c.undo();
      final back = c.doc.objectById(l.id) as LineObject;
      expect(back.p1, before);
      expect(
        (c.doc.objectById('label') as TextObject).center,
        const Offset(250, 150),
      );
    });

    test(
      'in step: running again, undo, redo and reopening change nothing',
      () async {
        arrow(const Offset(250, 150), const Offset(650, 380));
        final l = c.doc.allObjects.whereType<LineObject>().single;
        c.select([l.id]);
        drag(ix, l.pointAt(0.5), l.pointAt(0.5) + const Offset(0, 90));
        final sig = c.doc.signature();
        expect(relinkConnectors(c.doc), isFalse);
        c.undo();
        c.redo();
        expect(c.doc.signature(), sig);
        final json = c.projectJson();
        await c.loadProjectJson(json);
        expect(c.dirty, isFalse);
        expect(c.doc.signature(), sig);
        expect(relinkConnectors(c.doc), isFalse);
      },
    );

    test('deleting what an arrow is on leaves a free arrow where it was', () {
      final l = arrow(const Offset(250, 150), const Offset(650, 380));
      final p1 = l.p1;
      c.select(['label']);
      c.deleteSelection();
      final back = c.doc.objectById(l.id) as LineObject;
      expect(back.start, isNull);
      expect(back.p1, p1);
      expect(back.end!.to, 'pic');
    });

    test('a copy with its target is attached to the copy', () {
      final l = arrow(const Offset(250, 150), const Offset(650, 380));
      c.select(['label', l.id]);
      c.duplicateSelection();
      final copies = c.selectedObjects;
      final lc = copies.whereType<LineObject>().single;
      final tc = copies.whereType<TextObject>().single;
      expect(lc.start!.to, tc.id);
      expect(lc.end, isNull); // the picture was not copied
      c.select([l.id]);
      c.copySelection();
      c.pasteObjects();
      final pasted = c.selectedObjects.single as LineObject;
      expect(pasted.attached, isFalse);
    });

    test('a duplicated layer keeps its links inside itself', () {
      final l = arrow(const Offset(250, 150), const Offset(650, 380));
      c.duplicateLayer(c.currentLayer.id);
      final copy = c.doc.layers.last;
      final lc = copy.objects.whereType<LineObject>().single;
      final tc = copy.objects.whereType<TextObject>().single;
      final pc = copy.objects.whereType<ImageObject>().single;
      expect(lc.start!.to, tc.id);
      expect(lc.end!.to, pc.id);
      expect(l.start!.to, 'label');
    });

    test(
      'merging frees what was attached; unmerging restores links within',
      () async {
        final l = arrow(const Offset(250, 150), const Offset(650, 380));
        c.select(['pic']);
        await c.flattenSelection();
        final free = c.doc.objectById(l.id) as LineObject;
        expect(free.end, isNull);
        // Merge the label and its arrow together, then take them apart.
        c.select(['label', l.id]);
        await c.flattenSelection();
        final parts = c.unmerge();
        final lc = parts.whereType<LineObject>().single;
        final tc = parts.whereType<TextObject>().single;
        expect(lc.start!.to, tc.id);
      },
    );

    test('a hidden target freezes its end; a locked line still follows', () {
      final l = arrow(const Offset(250, 150), const Offset(650, 380));
      final p2 = l.p2;
      c.setObjectVisible('pic', false);
      pic.center += const Offset(100, 0);
      c.notify();
      expect(l.p2, p2);
      expect(l.end!.to, 'pic');
      c.setObjectVisible('pic', true);
      expect(l.p2, p2 + const Offset(100, 0));
      l.locked = true;
      c.select(['label']);
      c.nudge(const Offset(0, 40));
      expect(offOutline(label, l.p1), lessThan(l.width / 2 + 1e-6));
    });

    test('a mark on a hidden picture, nudged, stays on it', () {
      final l = arrow(const Offset(600, 350), const Offset(700, 420));
      c.setObjectVisible('pic', false);
      c.select([l.id]);
      c.nudge(const Offset(10, 0));
      expect(l.start!.to, 'pic');
      expect(l.p1, const Offset(610, 350));
      c.setObjectVisible('pic', true);
      expect(l.p1, const Offset(610, 350));
    });

    test('flipping a picture mirrors a curved mark on it', () {
      final l = arrow(const Offset(600, 350), const Offset(760, 350));
      c.select([l.id]);
      drag(ix, l.mid, l.mid + const Offset(0, -40));
      final top = l.mid.dy;
      expect(top, lessThan(350));
      c.select(['pic']);
      c.flipSelected();
      expect(l.p1, const Offset(800, 350));
      expect(l.mid.dy, closeTo(top, 1e-6));
    });

    test('an arrow tip on a thick rectangle touches its outside', () {
      final box = ShapeObject(
        id: 'box',
        name: 'box',
        ellipse: false,
        center: const Offset(300, 700),
        size: const Size(160, 100),
        fill: 0xFFFFFFFF,
        strokeWidth: 16,
      );
      c.currentLayer.objects.add(box);
      c.notify();
      final l = arrow(const Offset(700, 820), const Offset(300, 700));
      expect(l.end, const Attachment('box'));
      final local = box.toLocal(l.p2);
      expect(
        math.max(local.dx.abs() - 88, local.dy.abs() - 58).abs(),
        lessThan(1e-6),
      );
    });

    test(
      'a selected connector over a picture bends; a click picks beneath',
      () {
        final l = arrow(const Offset(250, 150), const Offset(650, 380));
        final pin = l.end;
        c.select([l.id]);
        final grab = l.pointAt(0.85); // over the picture
        expect(pic.hitTest(grab, 0, c.assets), isTrue);
        final depth = c.undoDepth;
        click(ix, grab);
        expect(c.selection, ['pic']);
        expect(c.undoDepth, depth);
        c.select([l.id]);
        drag(ix, grab, grab + const Offset(30, -60));
        expect(l.anchorBend, isNotNull);
        expect(l.end, pin);
        expect(distanceToLine(l, grab + const Offset(30, -60)), lessThan(2));
      },
    );

    test('a curved connector keeps its curve when a target goes', () {
      final other = TextObject(
        id: 'other',
        name: 'other',
        text: 'There',
        center: const Offset(250, 600),
        size: const Size(200, 60),
        background: 0xFFFFFFFF,
      );
      c.currentLayer.objects.add(other);
      c.notify();
      final l = arrow(const Offset(260, 160), const Offset(260, 600));
      expect(l.end, const Attachment('other'));
      c.select([l.id]);
      drag(ix, l.pointAt(0.5), l.pointAt(0.5) + const Offset(150, 0));
      final mid = l.mid;
      // Copied with only one of its boxes, the copy keeps the curve too.
      c.select(['label', l.id]);
      c.duplicateSelection();
      final copy = c.selectedObjects.whereType<LineObject>().single;
      expect((copy.mid - (mid + const Offset(24, 24))).distance, lessThan(0.5));
      c.select(['other']);
      c.deleteSelection();
      expect(l.end, isNull);
      expect((l.mid - mid).distance, lessThan(0.5));
    });

    test('an end aimed at a text box\'s round corner touches the arc', () {
      label.border = 0xFF000000;
      label.borderWidth = 6;
      final p = rayExit(label, label.center + const Offset(1000, 300));
      final l = label.toLocal(p);
      // The corner arc: radius 6 + border, centred inside the outer corner.
      const r = 12.0;
      const centre = Offset(106 - r, 36 - r);
      expect((Offset(l.dx, l.dy) - centre).distance, closeTo(r, 1e-6));
    });

    test('an end dropped on a picture\'s border band pins there', () {
      pic
        ..border = 0xFF000000
        ..borderWidth = 20;
      const at = Offset(700, 290); // 10 px out, on the border
      final l = arrow(const Offset(100, 100), at, m: noMods);
      expect(l.end!.to, 'pic');
      expect(l.p2, at);
    });
  });
}
