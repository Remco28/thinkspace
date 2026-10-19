import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/editor/interactor.dart';
import 'package:thinkspace/editor/render.dart';
import 'package:thinkspace/io/clipboard.dart';
import 'package:thinkspace/io/prefs.dart';
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

  group('hide details', () {
    test('a drag makes one box in one undo step; a click makes none', () {
      c.setTool(Tool.hide);
      click(ix, const Offset(300, 300));
      expect(c.doc.allObjects, isEmpty);
      final before = c.undoDepth;
      drag(ix, const Offset(100, 100), const Offset(260, 140));
      final h = c.doc.allObjects.single as HideObject;
      expect(h.bounds, const Rect.fromLTRB(100, 100, 260, 140));
      expect(h.solid, isFalse);
      expect(c.undoDepth, before + 1);
      expect(c.undoLabel, 'hide details');
      expect(c.tool, Tool.select, reason: 'back to Select, like a rectangle');
      final back = SceneObject.fromJson(h.toJson()) as HideObject;
      expect(back.bounds, h.bounds);
      expect(back.block, h.block);
    });

    test('Remove marks sweeps past it', () {
      c.setTool(Tool.hide);
      drag(ix, const Offset(100, 100), const Offset(260, 140));
      c.setTool(Tool.remove);
      drag(ix, const Offset(180, 60), const Offset(180, 180));
      expect(c.doc.allObjects, hasLength(1));
    });

    test('pixelating averages what is underneath into blocks', () async {
      c.doc.background = 0xFFFFFFFF;
      c.doc.canvasSize = const Size(56, 28);
      // Black on the left half of the first tile, white elsewhere.
      c.currentLayer.objects.addAll([
        ShapeObject(
          id: 'black',
          name: 'black',
          ellipse: false,
          center: const Offset(7, 14),
          size: const Size(14, 28),
          fill: 0xFF000000,
          strokeWidth: 0,
        ),
        HideObject(
          id: 'h',
          name: 'h',
          center: const Offset(28, 14),
          size: const Size(56, 28),
          block: 28,
        ),
      ]);
      final img = await renderDocument(c.doc, c.assets);
      final px = (await img.toByteData())!;
      int red(int x, int y) => px.getUint8((y * img.width + x) * 4);
      // The whole first tile is one grey, the second plain white.
      for (final (x, y) in [(2, 2), (12, 25), (25, 2)]) {
        expect(red(x, y), inInclusiveRange(105, 150), reason: '($x, $y)');
      }
      expect(red(40, 14), greaterThan(245));
      // Solid covers it with one colour.
      (c.doc.objectById('h') as HideObject).solid = true;
      final img2 = await renderDocument(c.doc, c.assets);
      final px2 = (await img2.toByteData())!;
      expect(px2.getUint8((14 * 56 + 3) * 4), 0x22);
    });

    test('settings for the next box come from the tool', () {
      c.styleOf(Tool.hide)
        ..solid = true
        ..color = 0xFF1E88E5;
      c.setTool(Tool.hide);
      drag(ix, const Offset(100, 100), const Offset(200, 150));
      final h = c.doc.allObjects.single as HideObject;
      expect(h.solid, isTrue);
      expect(h.color, 0xFF1E88E5);
    });
  });

  group('copying never leaves hidden details behind', () {
    test('a picture copied on its own takes the boxes over it along', () async {
      final a = await makeAsset(c, w: 200, h: 100, centerColor: 0xFF0000FF);
      c.currentLayer.objects.addAll([
        ImageObject(
          id: 'shot',
          name: 'shot',
          assetId: a.id,
          center: const Offset(100, 50),
          size: const Size(200, 100),
        ),
        HideObject(
          id: 'h',
          name: 'h',
          center: const Offset(100, 50),
          size: const Size(200, 100),
          block: 100,
        ),
        // Off to the side: not over the picture, so not copied with it.
        HideObject(
          id: 'far',
          name: 'far',
          center: const Offset(900, 900),
          size: const Size(50, 50),
        ),
      ]);
      c.select(['shot']);
      final objs = c.withCovers(c.selectedObjects);
      expect(objs.map((o) => o.id), ['shot', 'h']);
      final img = await c.renderObjects(objs);
      final px = (await img.toByteData())!;
      // The blue middle is averaged into its tiles: nowhere pure blue.
      var blue = 0;
      for (var i = 0; i < img.width * img.height; i++) {
        final r = px.getUint8(i * 4), b = px.getUint8(i * 4 + 2);
        if (b > 240 && r < 15) blue++;
      }
      expect(blue, 0);
    });

    test('a box under the picture is not a cover', () async {
      final a = await makeAsset(c);
      c.currentLayer.objects.addAll([
        HideObject(
          id: 'h',
          name: 'h',
          center: const Offset(100, 50),
          size: const Size(200, 100),
        ),
        ImageObject(
          id: 'shot',
          name: 'shot',
          assetId: a.id,
          center: const Offset(100, 50),
          size: const Size(200, 100),
        ),
      ]);
      c.select(['shot']);
      expect(c.withCovers(c.selectedObjects).map((o) => o.id), ['shot']);
    });
  });

  // The Linux path: Windows has its own clipboard code and no /bin/sh.
  group('the clipboard is checked, not trusted', skip: Platform.isWindows, () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ts_clip'));
    tearDown(() {
      SystemClipboard.linuxToolsOverride = null;
      dir.deleteSync(recursive: true);
    });

    String script(String name, String body) {
      final f = File('${dir.path}/$name')
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', f.path]);
      return f.path;
    }

    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4, 5]);

    test('a copy that took is reported as copied', () async {
      final store = '${dir.path}/store';
      SystemClipboard.linuxToolsOverride = [
        ([script('put', 'cat > $store')], [script('get', 'cat $store')]),
      ];
      expect(await SystemClipboard.writeImage(png), isTrue);
    });

    test(
      'a tool that starts but fails is caught; the next one is tried',
      () async {
        final store = '${dir.path}/store';
        File(
          store,
        ).writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 9, 9]); // old copy
        final broken = (
          [script('lose', 'cat > /dev/null')],
          [script('old', 'cat $store')],
        );
        SystemClipboard.linuxToolsOverride = [broken];
        expect(await SystemClipboard.writeImage(png), isFalse);
        SystemClipboard.linuxToolsOverride = [
          broken,
          ([script('put', 'cat > $store')], [script('get', 'cat $store')]),
        ];
        expect(await SystemClipboard.writeImage(png), isTrue);
      },
    );

    test('no tool at all is a failure', () async {
      SystemClipboard.linuxToolsOverride = [
        (['/nonexistent/wl-copy'], ['/nonexistent/wl-paste']),
      ];
      expect(await SystemClipboard.writeImage(png), isFalse);
    });
  });

  group('each tool remembers its own look', () {
    test('a thick red arrow leaves the pen alone', () {
      c.styleOf(Tool.arrow)
        ..color = kPalette[0]
        ..width = 14;
      c.styleOf(Tool.pen).color = kPalette[4];
      c.setTool(Tool.arrow);
      drag(ix, const Offset(100, 100), const Offset(300, 100));
      c.setTool(Tool.pen);
      drag(ix, const Offset(100, 200), const Offset(300, 260));
      final arrow = c.doc.allObjects.whereType<LineObject>().single;
      final pen = c.doc.allObjects.whereType<StrokeObject>().single;
      expect(arrow.width, 14);
      expect(pen.width, 5);
      expect(pen.color, kPalette[4]);
    });

    test('changing something on the page changes its tool, then reset', () {
      c.setTool(Tool.arrow);
      drag(ix, const Offset(100, 100), const Offset(300, 100));
      expect(c.styleIsDefault(Tool.arrow), isTrue);
      c.rememberStyle(c.single!, (s) => s.color = kPalette[3]);
      expect(c.styleOf(Tool.arrow).color, kPalette[3]);
      expect(c.styleOf(Tool.line).color, kPalette[0]);
      expect(c.styleIsDefault(Tool.arrow), isFalse);
      c.resetToolStyle(Tool.arrow);
      expect(c.styleIsDefault(Tool.arrow), isTrue);
    });

    test('the looks survive a save and a bad file', () {
      c.styleOf(Tool.text).size = 60;
      c.hlBox = true;
      final fresh = EditorController();
      fresh.readToolStyles(c.toolStylesJson());
      expect(fresh.textSize, 60);
      expect(fresh.hlBox, isTrue);
      fresh.readToolStyles({
        'pen': {'width': 'thick', 'color': 7},
        'nonsense': 3,
      });
      expect(fresh.styleOf(Tool.pen).width, 5, reason: 'odd values ignored');
      expect(fresh.styleOf(Tool.pen).color, 7);
    });
  });

  group('locking', () {
    test('Ctrl+L style toggle: a mixed selection unlocks first', () {
      for (final (n, locked) in [('a', true), ('b', false)]) {
        c.addObject(
          ShapeObject(
            id: n,
            name: n,
            ellipse: false,
            center: const Offset(100, 100),
            size: const Size(40, 40),
            locked: locked,
          ),
        );
      }
      c.select(['a', 'b']);
      c.toggleLockSelection();
      expect(c.doc.allObjects.every((o) => !o.locked), isTrue);
      c.toggleLockSelection();
      expect(c.doc.allObjects.every((o) => o.locked), isTrue);
      expect(c.selection, ['a', 'b'], reason: 'still selected to unlock');
      c.undo();
      expect(c.doc.allObjects.every((o) => !o.locked), isTrue);
    });
  });

  group('recent files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ts_recent'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('saving and opening put a project first, once', () async {
      final a = '${dir.path}/a.thinkspace', b = '${dir.path}/b.thinkspace';
      await c.saveTo(a);
      await c.saveTo(b);
      await c.openFrom(a);
      expect(c.recentFiles, [a, b]);
      for (var i = 0; i < 12; i++) {
        c.noteRecent('${dir.path}/$i.thinkspace');
      }
      expect(c.recentFiles, hasLength(EditorController.maxRecentFiles));
      expect(c.recentFiles.first, '${dir.path}/11.thinkspace');
      c.forgetRecent(c.recentFiles.first);
      expect(c.recentFiles.first, '${dir.path}/10.thinkspace');
    });

    test('prefs keep the list and the looks, and shrug off junk', () {
      final f = File('${dir.path}/prefs.json');
      final p = Prefs(f)
        ..recentFiles = ['/x/a.thinkspace']
        ..toolStyles = {
          'pen': {'width': 9},
        };
      p.save();
      final back = Prefs(f);
      expect(back.recentFiles, ['/x/a.thinkspace']);
      expect(back.toolStyles?['pen']['width'], 9);
      f.writeAsStringSync(
        '{"recentFiles": [1, "/y.thinkspace"], "toolStyles": 4}',
      );
      final odd = Prefs(f);
      expect(odd.recentFiles, ['/y.thinkspace']);
      expect(odd.toolStyles, isNull);
    });
  });
}
