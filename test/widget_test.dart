import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/editor/image_ops.dart' show HoleFill;
import 'package:thinkspace/io/samples.dart';
import 'package:thinkspace/model/scene.dart';
import 'package:thinkspace/ui/kit.dart';
import 'package:thinkspace/ui/shell.dart';
import 'package:thinkspace/ui/widgets.dart';

import 'helpers.dart';

Future<EditorController> pumpApp(WidgetTester tester) async {
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

/// Like testWidgets, but lets the toast timer run out so nothing is pending.
void appTest(String name, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pump(const Duration(seconds: 4));
    });

Rect canvasRect(WidgetTester tester) {
  // The canvas fills the space between the two side panels.
  final size = tester.view.physicalSize;
  return Rect.fromLTRB(278, 46, size.width - 292, size.height);
}

void main() {
  smallWindowTests();
  appTest(
    'after a crash, the unsaved work is offered back and can be restored',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync(
        'thinkspace_widget_recovery',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/recovery.thinkspace');
      // A previous session that never saved.
      final old = newEditor();
      old.recoveryFile = file;
      old.addObject(
        ShapeObject(
          id: old.doc.newId('o'),
          name: 'survivor',
          ellipse: false,
          center: const Offset(10, 10),
          size: const Size(50, 50),
        ),
      );
      await tester.runAsync(old.autosaveNow);
      expect(file.existsSync(), isTrue);

      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = EditorController();
      await tester.pumpWidget(
        MaterialApp(
          home: EditorShell(
            controller: c,
            startInspector: false,
            enableRecovery: true,
            recoveryFile: file,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Pick up where you left off?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restore')));
      // File reads finish in real time; give them turns between frames.
      for (int i = 0; i < 12 && c.doc.allObjects.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(c.doc.allObjects.single.name, 'survivor');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('survivor'), findsWidgets);
      c.dispose();
    },
  );

  appTest('declining the offer clears it, so it never nags twice', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync(
      'thinkspace_widget_recovery2',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/recovery.thinkspace')
      ..writeAsStringSync('{}');
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = EditorController();
    await tester.pumpWidget(
      MaterialApp(
        home: EditorShell(
          controller: c,
          startInspector: false,
          enableRecovery: true,
          recoveryFile: file,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Start fresh'));
    await tester.pump();
    expect(file.existsSync(), isFalse);
    c.dispose();
  });

  appTest(
    'opens on an empty page with the tools, layers and collection in view',
    (tester) async {
      await pumpApp(tester);
      for (final t in [
        'select',
        'line',
        'arrow',
        'rect',
        'ellipse',
        'text',
        'pen',
        'cutout',
      ]) {
        expect(find.byKey(ValueKey('tool-$t')), findsOneWidget, reason: t);
      }
      expect(find.text('LAYERS'), findsOneWidget);
      expect(find.text('Layer 1'), findsOneWidget);
      expect(find.text('COLLECTION'), findsOneWidget);
      expect(find.textContaining('Keep images here'), findsOneWidget);
      expect(find.text('PAGE'), findsOneWidget);
      expect(find.byKey(const ValueKey('canvas-w')), findsOneWidget);
    },
  );

  appTest('the active tool shows its shortcut key underneath', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('tool-key-select')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-key-arrow')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tool-arrow')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-key-arrow')), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-key-select')), findsNothing);
    // A slim key: it hugs its letter rather than filling the space around it.
    final cap = tester.getSize(find.byKey(const ValueKey('tool-key-arrow')));
    expect(cap.width, lessThan(20));
    expect(cap.height, lessThan(15));
  });

  appTest('picking a font changes the selected text', (tester) async {
    final c = await pumpApp(tester);
    final t = c.createText(const Offset(100, 100));
    c.currentLayer.objects.add(t);
    c.select([t.id]);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('font-mono')));
    await tester.pump();
    expect(t.font, TextFont.mono);
    expect(c.textFont, TextFont.mono, reason: 'new text follows the last pick');
    c.undo();
    await tester.pump();
    expect((c.doc.allObjects.single as TextObject).font, TextFont.sans);
  });

  appTest('bold, italic, alignment and backdrop carry over to new text', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    final t = c.createText(const Offset(100, 100));
    c.currentLayer.objects.add(t);
    c.select([t.id]);
    await tester.pump();
    final backdrop = find.descendant(
      of: find.widgetWithText(PropRow, 'Backdrop'),
      matching: find.byType(ColorRow),
    );
    await tester.tap(find.byTooltip('Bold'));
    await tester.tap(find.byTooltip('Italic'));
    await tester.tap(find.byTooltip('Centre'));
    tester.widget<ColorRow>(backdrop).onChanged(0xFFFFF200);
    await tester.pump();
    expect(
      [t.bold, t.italic, t.align, t.background],
      [true, true, TextAlign.center, 0xFFFFF200],
    );
    final next = c.createText(const Offset(400, 400));
    expect(
      [next.bold, next.italic, next.align, next.background],
      [true, true, TextAlign.center, 0xFFFFF200],
    );

    // The text tool's own settings show the same choices and change them.
    c.select([]);
    c.setTool(Tool.text);
    await tester.pump();
    await tester.tap(find.byTooltip('Bold'));
    await tester.tap(find.byTooltip('Align right'));
    tester.widget<ColorRow>(backdrop).onChanged(0);
    await tester.pump();
    final last = c.createText(const Offset(400, 400));
    expect(
      [last.bold, last.italic, last.align, last.background],
      [false, true, TextAlign.right, 0],
    );
    expect(c.styleIsDefault(Tool.text), isFalse);
    c.resetToolStyle(Tool.text);
    expect(c.styleIsDefault(Tool.text), isTrue);
  });

  appTest('? opens the shortcut sheet, with keys drawn as keys', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.byType(KeyCap), findsWidgets);
    expect(find.text('Numbered marker'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsNothing);
  });

  appTest('the pan hint shows only when there is somewhere to pan to', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    c.fitToView();
    await tester.pump();
    expect(find.byKey(const ValueKey('pan-hint')), findsNothing);
    c.zoomTo(c.zoom * 4);
    await tester.pump();
    expect(find.byKey(const ValueKey('pan-hint')), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
  });

  appTest('shortcuts work again right after typing in a panel field', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('canvas-w')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('canvas-w')), '1700');
    await tester.pump();
    // Clicking a toolbar button is the natural next move.
    await tester.tap(find.byKey(const ValueKey('tool-select')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(c.tool, Tool.line);
  });

  appTest('the layer menu offers Duplicate layer', (tester) async {
    final c = await pumpApp(tester);
    c.addObject(
      ShapeObject(
        id: c.doc.newId('o'),
        name: 'box',
        ellipse: false,
        center: const Offset(100, 100),
        size: const Size(50, 50),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Layer 1').first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate layer'));
    await tester.pumpAndSettle();
    expect(c.doc.layers.length, 2);
  });

  appTest('a merged picture offers Unmerge, which brings the pieces back', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    for (final (n, x) in [('left', 200.0), ('right', 400.0)]) {
      c.addObject(
        ShapeObject(
          id: c.doc.newId('o'),
          name: n,
          ellipse: false,
          center: Offset(x, 200),
          size: const Size(100, 60),
          fill: 0xFF3366FF,
        ),
      );
    }
    c.selectAll();
    await tester.runAsync(c.flattenSelection);
    await tester.pump();
    expect(c.doc.allObjects.length, 1);
    expect(find.byKey(const ValueKey('unmerge-button')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('unmerge-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('unmerge-button')));
    await tester.pump();
    expect(c.doc.allObjects.length, 2);
    expect(find.byKey(const ValueKey('unmerge-button')), findsNothing);
  });

  appTest('a selection of several things offers Merge beside it', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    for (final (n, x) in [('left', 200.0), ('right', 400.0)]) {
      c.addObject(
        ShapeObject(
          id: c.doc.newId('o'),
          name: n,
          ellipse: false,
          center: Offset(x, 200),
          size: const Size(100, 60),
          fill: 0xFF3366FF,
        ),
      );
    }
    const pill = ValueKey('selection-actions');
    c.select([c.doc.allObjects.first.id]);
    await tester.pump();
    expect(
      find.byKey(pill),
      findsNothing,
      reason: 'one shape: nothing to merge',
    );
    c.selectAll();
    await tester.pump();
    expect(find.byKey(pill), findsOneWidget);
    expect(find.text('Merge into one image'), findsWidgets);
    // It sits below the selection, inside the canvas.
    final at = tester.getTopLeft(find.byKey(pill));
    expect(at.dy, greaterThan(canvasRect(tester).top));

    // Clicking it merges, and the same spot then offers Unmerge.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('quick-merge')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(c.doc.allObjects.length, 1);
    expect(find.byKey(const ValueKey('quick-unmerge')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-unmerge')));
    await tester.pump();
    expect(c.doc.allObjects.length, 2);
    expect(find.byKey(const ValueKey('quick-unmerge')), findsNothing);
  });

  appTest('M merges the selection and U takes it apart', (tester) async {
    final c = await pumpApp(tester);
    for (final x in [200.0, 400.0]) {
      c.addObject(
        ShapeObject(
          id: c.doc.newId('o'),
          name: 's$x',
          ellipse: false,
          center: Offset(x, 200),
          size: const Size(100, 60),
          fill: 0xFF3366FF,
        ),
      );
    }
    c.selectAll();
    await tester.pump();
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(c.doc.allObjects.length, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pump();
    expect(c.doc.allObjects.length, 2);
  });

  appTest('the Merge pill stays out of the way while drawing or typing', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    for (final x in [200.0, 400.0]) {
      c.addObject(
        ShapeObject(
          id: c.doc.newId('o'),
          name: 's$x',
          ellipse: false,
          center: Offset(x, 200),
          size: const Size(100, 60),
          fill: 0xFF3366FF,
        ),
      );
    }
    c.selectAll();
    await tester.pump();
    expect(find.byKey(const ValueKey('selection-actions')), findsOneWidget);
    c.setTool(Tool.arrow);
    await tester.pump();
    expect(find.byKey(const ValueKey('selection-actions')), findsNothing);
  });

  Future<List<String>> shelf(WidgetTester tester, EditorController c) async {
    final ids = <String>[];
    for (final n in ['one', 'two', 'three']) {
      final a = await tester.runAsync(
        () => makeAsset(c, w: 40, h: 40, color: 0xFF3366FF),
      );
      final item = CollectionItem(
        id: c.doc.newId('c'),
        name: n,
        assetId: a!.id,
      );
      c.doc.collection.add(item);
      ids.add(item.id);
    }
    c.notify();
    await tester.pump();
    return ids;
  }

  appTest('clicking a collection item selects it, with a border', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    final ids = await shelf(tester, c);
    c.addObject(
      ShapeObject(
        id: c.doc.newId('o'),
        name: 's',
        ellipse: false,
        center: const Offset(300, 300),
        size: const Size(50, 50),
      ),
    );
    c.select([c.doc.allObjects.single.id]);
    await tester.tap(find.byKey(ValueKey('collection-${ids[1]}')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.selectedCollectionId, ids[1]);
    expect(c.selection, isEmpty, reason: 'one thing is selected at a time');
    // Delete removes it and the highlight moves on to a neighbour.
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(c.doc.collection.map((i) => i.id), [ids[0], ids[2]]);
    expect(c.selectedCollectionId, ids[2]);
    expect(c.doc.allObjects.length, 1, reason: 'the page was not touched');
    // Esc lets go; picking something on the page does too.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(c.selectedCollectionId, isNull);
    c.selectCollectionItem(ids[0]);
    c.select([c.doc.allObjects.single.id]);
    expect(c.selectedCollectionId, isNull);
  });

  appTest('[ and ] move the selected collection item along the shelf', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    final ids = await shelf(tester, c);
    c.selectCollectionItem(ids[0]);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(c.doc.collection.map((i) => i.id), [ids[1], ids[0], ids[2]]);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.doc.collection.first.id, ids[0], reason: 'stops at the start');
    c.undo();
    expect(c.doc.collection.length, 3);
  });

  appTest('dragging one collection item onto another rearranges the shelf', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    final ids = await shelf(tester, c);
    final from = tester.getCenter(find.byKey(ValueKey('collection-${ids[0]}')));
    final to = tester.getCenter(find.byKey(ValueKey('collection-${ids[2]}')));
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(10, 10));
    await g.moveTo(to);
    await tester.pump();
    expect(find.byKey(const ValueKey('collection-drop-bar')), findsOneWidget);
    await g.up();
    await tester.pump();
    expect(c.doc.collection.map((i) => i.id), [ids[1], ids[2], ids[0]]);
    expect(c.selectedCollectionId, ids[0]);
    expect(find.byKey(const ValueKey('collection-drop-bar')), findsNothing);
    c.undo();
    expect(c.doc.collection.map((i) => i.id), ids);
  });

  appTest('F2 renames the selected collection item in place', (tester) async {
    final c = await pumpApp(tester);
    final ids = await shelf(tester, c);
    await tester.tap(find.byKey(ValueKey('collection-${ids[0]}')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    expect(find.byKey(const ValueKey('collection-rename')), findsOneWidget);
    // The old name is selected, so typing replaces it.
    await tester.enterText(
      find.byKey(const ValueKey('collection-rename')),
      'Hero shot',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.doc.collection.first.name, 'Hero shot');
    expect(find.byKey(const ValueKey('collection-rename')), findsNothing);
    // Back to one-key shortcuts straight away.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(c.tool, Tool.line);
    // Esc leaves the name alone.
    c.setTool(Tool.select);
    c.selectCollectionItem(ids[1]);
    c.beginCollectionRename();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('collection-rename')),
      'Nope',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(c.doc.collection[1].name, 'two');
    expect(c.renamingCollectionId, isNull);
  });

  appTest('the divider between Layers and the settings can be dragged', (
    tester,
  ) async {
    await pumpApp(tester);
    final divider = find.byKey(const ValueKey('layers-splitter'));
    expect(divider, findsOneWidget);
    double layersBottom() => tester.getTopLeft(divider).dy;
    final before = layersBottom();
    await tester.drag(divider, const Offset(0, -80));
    await tester.pump();
    expect(layersBottom(), lessThan(before - 40));
    // It cannot squeeze the Layers list to nothing.
    await tester.drag(divider, const Offset(0, -2000));
    await tester.pump();
    expect(layersBottom(), greaterThan(100));
    // A double-click puts it back.
    await tester.tap(divider);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(divider);
    await tester.pump(const Duration(milliseconds: 400));
    expect(layersBottom(), closeTo(before, 1));
  });

  appTest('the colour picker mixes a colour from a hex code', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('custom-colour')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('color-popover')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('color-hex')), '12ab34');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.doc.background, 0xFF12AB34);
    // Picking in the square also settles a colour.
    final square = find.byKey(const ValueKey('color-square'));
    await tester.tapAt(tester.getTopLeft(square) + const Offset(10, 10));
    await tester.pump();
    expect(c.doc.background, isNot(0xFF12AB34));
    // The mixed colour is offered again next time.
    await tester.tapAt(const Offset(5, 5)); // outside: closes
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('color-popover')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('custom-colour')));
    await tester.pumpAndSettle();
    expect(find.text('Recent'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  });

  appTest('after Remove background a bar fine-tunes it as one undo step', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    final a = await tester.runAsync(
      () => makeAsset(
        c,
        w: 80,
        h: 80,
        color: 0xFFFFFFFF,
        centerColor: 0xFF1B7A2B,
      ),
    );
    final img = ImageObject(
      id: c.doc.newId('o'),
      name: 'pic',
      assetId: a!.id,
      center: const Offset(300, 300),
      size: const Size(160, 160),
    );
    c.addObject(img);
    c.select([img.id]);
    await tester.pump();
    expect(find.byKey(const ValueKey('background-bar')), findsNothing);
    final before = c.undoDepth;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('remove-bg-button')));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('background-bar')), findsOneWidget);
    expect(c.undoDepth, before + 1);
    final removed = c.doc.allObjects.whereType<ImageObject>().single.assetId;
    // Switching "enclosed areas" redoes the removal without adding steps.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('background-enclosed')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    expect(c.undoDepth, before + 1);
    expect(
      c.doc.allObjects.whereType<ImageObject>().single.assetId,
      isNot(removed),
    );
    expect(find.byKey(const ValueKey('background-bar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('background-done')));
    await tester.pump();
    expect(find.byKey(const ValueKey('background-bar')), findsNothing);
    // One undo takes the whole thing back.
    c.undo();
    expect(c.doc.allObjects.whereType<ImageObject>().single.assetId, a.id);
  });

  appTest('the bar goes away when something else is done', (tester) async {
    final c = await pumpApp(tester);
    final a = await tester.runAsync(
      () => makeAsset(
        c,
        w: 60,
        h: 60,
        color: 0xFFFFFFFF,
        centerColor: 0xFF1B7A2B,
      ),
    );
    final img = ImageObject(
      id: c.doc.newId('o'),
      name: 'pic',
      assetId: a!.id,
      center: const Offset(300, 300),
      size: const Size(120, 120),
    );
    c.addObject(img);
    c.select([img.id]);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('remove-bg-button')));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('background-bar')), findsOneWidget);
    c.clearSelection();
    await tester.pump();
    expect(find.byKey(const ValueKey('background-bar')), findsNothing);
  });

  appTest('the menu opens with grouped, labelled sections', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('main-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Save as…'), findsOneWidget);
    expect(find.text('WHEN I PASTE AN IMAGE'), findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
  });

  appTest('cut out opens a card that asks its questions in order', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    const card = ValueKey('cutout-card');
    expect(find.byKey(card), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tool-cutout')));
    await tester.pump();
    expect(find.byKey(card), findsOneWidget);
    // Cut or copy first; the gap question only exists once it is a cut.
    expect(find.byKey(const ValueKey('cut-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('cut-fill-empty')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('cut-cut')));
    await tester.pump();
    expect(c.cutoutLeavesHole, isTrue);
    expect(find.byKey(const ValueKey('cut-fill-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cut-fill-colour')));
    await tester.pump();
    expect(c.cutoutFill, HoleFill.color);
    // "Blend in" is gone.
    expect(find.text('Blend in'), findsNothing);
    // Picking a colour replaces those questions with the colour ones.
    await tester.tap(find.byKey(const ValueKey('cut-mode-wand')));
    await tester.pump();
    expect(c.cutoutMode, CutoutMode.wand);
    expect(find.byKey(const ValueKey('cut-copy')), findsNothing);
    expect(find.byKey(const ValueKey('cut-match')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cut-mode-box')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cut-start')));
    await tester.pump();
    expect(find.byKey(card), findsNothing);
    expect(find.byKey(const ValueKey('cutout-bar')), findsOneWidget);
    // Options can be brought back; Esc leaves the tool.
    await tester.tap(find.byKey(const ValueKey('cutout-options')));
    await tester.pump();
    expect(find.byKey(card), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(c.tool, Tool.select);
    expect(find.byKey(card), findsNothing);
  });

  appTest('Enter starts cutting, and so does starting to draw', (tester) async {
    final c = await pumpApp(tester);
    c.setTool(Tool.cutout);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.cutoutOptionsOpen, isFalse);
    c.setTool(Tool.select);
    c.setTool(Tool.cutout);
    await tester.pump();
    expect(c.cutoutOptionsOpen, isTrue);
    final r = canvasRect(tester);
    final g = await tester.startGesture(
      r.topLeft + const Offset(40, 40),
      kind: PointerDeviceKind.mouse,
    );
    await g.up();
    await tester.pump();
    expect(c.cutoutOptionsOpen, isFalse);
  });

  appTest('the empty-page hint is centred on the page, wherever it is', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    final hint = find.textContaining('Paste an image');
    Offset pageCentre() => c.toScreen(
      Offset(c.doc.canvasSize.width / 2, c.doc.canvasSize.height / 2),
    );
    // The hint lives in the canvas area; compare in the same space.
    final origin = canvasRect(tester).topLeft;
    expect((tester.getCenter(hint) - origin).dx, closeTo(pageCentre().dx, 2));
    expect((tester.getCenter(hint) - origin).dy, closeTo(pageCentre().dy, 2));
    // Move the page about: the hint follows it.
    c.panBy(const Offset(-40, 50));
    await tester.pump();
    final moved = tester.getCenter(hint) - origin;
    expect(moved.dx, closeTo(pageCentre().dx, 2));
    expect(moved.dy, closeTo(pageCentre().dy, 2));
  });

  appTest('the page-edge handles light up under the pointer and when dragged', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    final r = canvasRect(tester);
    final grip = r.topLeft + c.toScreen(c.gripPositions[CanvasGrip.right]!);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(grip);
    await tester.pump();
    expect(c.hoverGrip, CanvasGrip.right);
    await mouse.moveTo(r.center);
    await tester.pump();
    expect(c.hoverGrip, isNull);
    await mouse.moveTo(grip);
    await mouse.down(grip);
    await mouse.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(c.draggingGrip, CanvasGrip.right);
    await mouse.up();
    await tester.pump();
    expect(c.draggingGrip, isNull);
  });

  appTest(
    'the marker tool shows a size, and a marker offers to match the rest',
    (tester) async {
      final c = await pumpApp(tester);
      c.setTool(Tool.badge);
      await tester.pump();
      expect(find.text('Size'), findsOneWidget);
      c.setTool(Tool.select);
      for (final (n, size) in [(1, 44.0), (2, 90.0)]) {
        c.addObject(
          BadgeObject(
            id: c.doc.newId('o'),
            name: 'm$n',
            number: n,
            center: Offset(100.0 * n, 100),
            size: Size(size, size),
          ),
        );
      }
      c.select([c.doc.allObjects.last.id]);
      await tester.pump();
      expect(find.byKey(const ValueKey('marker-size')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('match-markers')));
      await tester.tap(find.byKey(const ValueKey('match-markers')));
      await tester.pump();
      expect(
        c.doc.allObjects.every((o) => (o as BadgeObject).size.width == 90),
        isTrue,
      );
      expect(find.byKey(const ValueKey('match-markers')), findsNothing);
    },
  );

  appTest('the divider follows a drag even when events arrive in a burst', (
    tester,
  ) async {
    await pumpApp(tester);
    final divider = find.byKey(const ValueKey('layers-splitter'));
    final home = tester.getTopLeft(divider).dy;

    Future<double> drag4({required bool frames}) async {
      final g = await tester.startGesture(tester.getCenter(divider));
      for (int i = 0; i < 4; i++) {
        await g.moveBy(const Offset(0, -25));
        if (frames) await tester.pump();
      }
      await g.up();
      await tester.pump();
      return tester.getTopLeft(divider).dy;
    }

    final burst = await drag4(frames: false);
    expect(burst, lessThan(home - 30));
    // Back to the start, then the same drag with a frame between each event.
    await tester.tap(divider);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(divider);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getTopLeft(divider).dy, closeTo(home, 1));
    expect(await drag4(frames: true), closeTo(burst, 2));
  });

  appTest('the lock button locks and unlocks a mixed selection predictably', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    for (final (n, locked) in [('a', true), ('b', false)]) {
      c.addObject(
        ShapeObject(
          id: c.doc.newId('o'),
          name: n,
          ellipse: false,
          center: Offset(100.0 + n.codeUnitAt(0), 100),
          size: const Size(40, 40),
          locked: locked,
        ),
      );
    }
    c.select(c.doc.allObjects.map((o) => o.id).toList());
    await tester.pump();
    Future<void> lockButton() async {
      final b = find.byTooltip('Unlock so it can be grabbed again  Ctrl+L');
      final alt = find.byTooltip('Lock so it can’t be grabbed  Ctrl+L');
      await tester.tap(b.evaluate().isNotEmpty ? b : alt);
      await tester.pump();
    }

    // Some are locked: the first press unlocks everything…
    await lockButton();
    expect(c.doc.allObjects.every((o) => !o.locked), isTrue);
    // …and the next locks everything.
    await lockButton();
    expect(c.doc.allObjects.every((o) => o.locked), isTrue);
  });

  group('touch', () {
    Offset at(WidgetTester tester, EditorController c, Offset scene) =>
        canvasRect(tester).topLeft + c.toScreen(scene);

    appTest('one finger draws like the mouse does', (tester) async {
      final c = await pumpApp(tester);
      c.setTool(Tool.pen);
      await tester.pump();
      final from = at(tester, c, const Offset(300, 300));
      final g = await tester.startGesture(from, kind: PointerDeviceKind.touch);
      for (int i = 1; i <= 8; i++) {
        await g.moveBy(const Offset(12, 4));
      }
      await g.up();
      await tester.pump();
      expect(c.touchInput, isTrue);
      expect(c.doc.allObjects.single, isA<StrokeObject>());
    });

    appTest('a second finger moves and zooms the page, and the first '
        'finger\'s stroke is taken back', (tester) async {
      final c = await pumpApp(tester);
      c.setTool(Tool.pen);
      await tester.pump();
      final zoom = c.zoom, pan = c.pan;
      final a = await tester.startGesture(
        at(tester, c, const Offset(400, 300)),
        kind: PointerDeviceKind.touch,
        pointer: 1,
      );
      await a.moveBy(const Offset(30, 0));
      await a.moveBy(const Offset(30, 0));
      expect(c.doc.allObjects, hasLength(1), reason: 'drawing so far');
      final b = await tester.startGesture(
        at(tester, c, const Offset(500, 300)),
        kind: PointerDeviceKind.touch,
        pointer: 2,
      );
      await tester.pump();
      expect(c.doc.allObjects, isEmpty, reason: 'the stray stroke is undone');
      // Spread the fingers apart: zoom in. Then slide both: pan.
      await b.moveBy(const Offset(100, 0));
      await a.moveBy(const Offset(-100, 0));
      await tester.pump();
      expect(c.zoom, greaterThan(zoom * 1.5));
      final panned = c.pan;
      await a.moveBy(const Offset(40, 30));
      await b.moveBy(const Offset(40, 30));
      await tester.pump();
      expect(c.pan.dx, greaterThan(panned.dx + 30));
      expect(c.pan.dy, greaterThan(panned.dy + 20));
      expect(c.pan, isNot(pan));
      await a.up();
      // The finger that is left does not start drawing.
      await b.moveBy(const Offset(50, 50));
      await b.up();
      await tester.pump();
      expect(c.doc.allObjects, isEmpty);
      expect(c.undoDepth, 0);
    });

    appTest('holding a finger down opens the menu for what is under it', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      c.addObject(
        ShapeObject(
          id: c.doc.newId('o'),
          name: 'box',
          ellipse: false,
          center: const Offset(300, 300),
          size: const Size(160, 100),
          fill: 0xFF3366FF,
        ),
      );
      c.clearSelection();
      await tester.pump();
      final g = await tester.startGesture(
        at(tester, c, const Offset(300, 300)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('Duplicate'), findsOneWidget);
      expect(c.selection, isNotEmpty);
      await g.up();
      await tester.pumpAndSettle();
    });

    appTest('a finger can hit a thin line a mouse would miss', (tester) async {
      final c = await pumpApp(tester);
      c.addObject(
        LineObject(
          id: c.doc.newId('o'),
          name: 'rule',
          p1: const Offset(200, 300),
          p2: const Offset(500, 300),
          width: 2,
        ),
      );
      c.clearSelection();
      await tester.pump();
      final near = at(tester, c, Offset(350, 300 + 10 / c.zoom));
      // Mouse: ten pixels away misses.
      await tester.tapAt(near, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.selection, isEmpty);
      // Finger: the same spot hits.
      await tester.tapAt(near, kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.selection, hasLength(1));
    });
  });

  appTest('the highlighter has its own tool, key and panel', (tester) async {
    final c = await pumpApp(tester);
    expect(find.byKey(const ValueKey('tool-highlight')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(c.tool, Tool.highlight);
    expect(find.byKey(const ValueKey('tool-key-highlight')), findsOneWidget);
    // Marker or box, colours, width and the text-readable switch.
    expect(find.byKey(const ValueKey('hl-marker')), findsOneWidget);
    expect(find.text('Width'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hl-box')));
    await tester.pump();
    expect(c.hlBox, isTrue);
    expect(find.text('Width'), findsNothing, reason: 'a box has no width');
    await tester.tap(find.byKey(const ValueKey('hl-keep-text')));
    await tester.pump();
    expect(c.hlKeepText, isFalse);
  });

  appTest('a drawn highlight can be recoloured and switched to plain', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    c.setTool(Tool.highlight);
    final r = canvasRect(tester);
    final g = await tester.startGesture(
      r.topLeft + const Offset(100, 200),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(120, 0));
    await g.moveBy(const Offset(120, 0));
    await g.up();
    await tester.pump();
    final s = c.doc.allObjects.single as StrokeObject;
    expect(find.text('HIGHLIGHT'), findsOneWidget, reason: 'the panel header');
    c.setTool(Tool.select);
    c.select([s.id]);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('hl-keep-text')));
    await tester.tap(find.byKey(const ValueKey('hl-keep-text')));
    await tester.pump();
    final live = c.doc.allObjects.single as StrokeObject;
    expect(live.highlight, HighlightStyle.plain);
    expect(live.opacity, lessThan(0.5));
  });

  appTest(
    'drawing an arrow with the mouse lists it, selects it, and undo removes it',
    (tester) async {
      final c = await pumpApp(tester);
      await tester.tap(find.byKey(const ValueKey('tool-arrow')));
      await tester.pump();
      final r = canvasRect(tester);
      final g = await tester.startGesture(
        r.center - const Offset(120, 40),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveTo(r.center);
      await g.moveTo(r.center + const Offset(120, 60));
      await g.up();
      await tester.pump();

      expect(c.doc.allObjects.single, isA<LineObject>());
      expect(
        find.text('arrow 1'),
        findsWidgets,
        reason: 'object list and selection label',
      );
      expect(
        find.text('ARROW'),
        findsOneWidget,
        reason: 'properties panel names the selection',
      );

      await tester.tap(find.byKey(const ValueKey('undo')));
      await tester.pump();
      expect(c.doc.allObjects, isEmpty);
      await tester.tap(find.byKey(const ValueKey('redo')));
      await tester.pump();
      expect(c.doc.allObjects.length, 1);
    },
  );

  appTest('keyboard: tool letters, undo/redo, delete, escape', (tester) async {
    final c = await pumpApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    expect(c.tool, Tool.rect);
    final r = canvasRect(tester);
    final g = await tester.startGesture(
      r.center,
      kind: PointerDeviceKind.mouse,
    );
    await g.moveTo(r.center + const Offset(100, 80));
    await g.up();
    await tester.pump();
    expect(c.doc.allObjects.length, 1);
    expect(c.tool, Tool.select);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(c.doc.allObjects, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(c.doc.allObjects.length, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(c.tool, Tool.arrow);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(c.tool, Tool.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(c.selection, isEmpty);
  });

  appTest('layer eye hides a layer and what is on it', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tool-rect')));
    await tester.pump();
    final r = canvasRect(tester);
    final g = await tester.startGesture(
      r.center,
      kind: PointerDeviceKind.mouse,
    );
    await g.moveTo(r.center + const Offset(100, 80));
    await g.up();
    await tester.pump();

    final layerId = c.doc.layers.first.id;
    await tester.tap(find.byKey(ValueKey('layer-eye-$layerId')));
    await tester.pump();
    expect(c.doc.layers.first.visible, isFalse);
    expect(c.selection, isEmpty);
    await tester.tap(find.byKey(ValueKey('layer-eye-$layerId')));
    await tester.pump();
    expect(c.doc.layers.first.visible, isTrue);
  });

  appTest('adding a layer and picking it makes new drawings land there', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await tester.tap(find.byTooltip('Add layer'));
    await tester.pump();
    expect(c.doc.layers.length, 2);
    expect(c.currentLayer.name, 'Layer 2');
    await tester.tap(find.byKey(const ValueKey('tool-ellipse')));
    final r = canvasRect(tester);
    final g = await tester.startGesture(
      r.center,
      kind: PointerDeviceKind.mouse,
    );
    await g.moveTo(r.center + const Offset(80, 80));
    await g.up();
    await tester.pump();
    expect(c.doc.layerOf(c.selection.single)!.name, 'Layer 2');
  });

  appTest('a new layer opens its name for typing; Escape keeps it', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await tester.tap(find.byTooltip('Add layer'));
    await tester.pumpAndSettle();
    final id = c.currentLayerId;
    final field = find.byKey(ValueKey('layer-name-$id'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Notes');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.currentLayer.name, 'Notes');
    expect(field, findsNothing);
    // The keys are the editor's again.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.tool, Tool.rect);

    await tester.tap(find.byTooltip('Add layer'));
    await tester.pumpAndSettle();
    final again = find.byKey(ValueKey('layer-name-${c.currentLayerId}'));
    await tester.enterText(again, 'Oops');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(again, findsNothing);
    expect(c.currentLayer.name, 'Layer 3');
  });

  appTest('text tool: click, type on the page, click away', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tool-text')));
    await tester.pump();
    final r = canvasRect(tester);
    final g = await tester.startGesture(
      r.center,
      kind: PointerDeviceKind.mouse,
    );
    await g.up();
    await tester.pump();
    await tester.pump();
    expect(c.editingTextId, isNotNull);
    expect(find.byType(TextField), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('text-editor')),
      'Which one?',
    );
    await tester.pump();
    // Click on empty canvas to finish.
    final g2 = await tester.startGesture(
      r.bottomRight - const Offset(40, 40),
      kind: PointerDeviceKind.mouse,
    );
    await g2.up();
    await tester.pump();
    expect(c.editingTextId, isNull);
    expect((c.doc.allObjects.single as TextObject).text, 'Which one?');
  });

  appTest('pasting an image asks where it should go', (tester) async {
    final c = await pumpApp(tester);
    final asset = await tester.runAsync(() => makeAsset(c, w: 640, h: 480));
    c.pendingPaste = PendingPaste(asset!.id, 'pasted image');
    c.notify();
    await tester.pump();
    expect(find.byKey(const ValueKey('paste-chooser')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paste-to-collection')));
    await tester.pump();
    expect(c.doc.collection.length, 1);
    expect(find.byKey(const ValueKey('paste-chooser')), findsNothing);
    expect(
      find.byKey(ValueKey('collection-${c.doc.collection.first.id}')),
      findsOneWidget,
    );

    c.pendingPaste = PendingPaste(asset.id, 'pasted image');
    c.notify();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.doc.allObjects.whereType<ImageObject>().length, 1);
  });

  appTest(
    'the storefront sample shows layers, objects and a labelled selection',
    (tester) async {
      final c = await pumpApp(tester);
      await tester.runAsync(() => loadStorefrontSample(c));
      await tester.pump();
      for (final n in [
        'Notes',
        'Navy awnings',
        'Striped awnings',
        'Storefront',
      ]) {
        expect(find.text(n), findsWidgets, reason: n);
      }
      expect(find.text('awning_01'), findsOneWidget);
      expect(find.text('awning_02'), findsOneWidget);

      await tester.tap(find.text('awning_02'));
      await tester.pump();
      expect(c.single!.name, 'awning_02');
      expect(
        find.text('awning_02 · Navy awnings'),
        findsNothing,
        reason: 'the label is painted, not a widget',
      );
      expect(find.text('IMAGE'), findsOneWidget);
      expect(find.byKey(const ValueKey('opacity')), findsOneWidget);
      expect(find.byKey(const ValueKey('cutout-button')), findsOneWidget);

      // Hiding one awning's layer and showing the other is a single click each.
      final navy = c.doc.layers.firstWhere((l) => l.name == 'Navy awnings');
      await tester.tap(find.byKey(ValueKey('layer-eye-${navy.id}')));
      await tester.pump();
      expect(navy.visible, isFalse);
    },
  );

  appTest('moving an object to another layer from the properties panel', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await tester.runAsync(() => loadStorefrontSample(c));
    await tester.pump();
    c.select([c.doc.allObjects.firstWhere((o) => o.name == 'awning_01').id]);
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();
    expect(c.doc.layerOf(c.selection.single)!.name, 'Notes');
  });

  appTest('grid and snap toggles live in the toolbar', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('grid')));
    await tester.tap(find.byKey(const ValueKey('snap')));
    await tester.pump();
    expect(c.showGrid, isTrue);
    expect(c.snapOn, isTrue);
  });

  appTest('canvas size can be typed', (tester) async {
    final c = await pumpApp(tester);
    await tester.enterText(find.byKey(const ValueKey('canvas-h')), '3000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.doc.canvasSize.height, 3000);
    expect(c.doc.canvasSize.width, 1600);
  });

  appTest('the collection can be hidden to give the canvas room', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('COLLECTION'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toggle-collection')));
    await tester.pump();
    expect(find.text('COLLECTION'), findsNothing);
  });

  appTest('the padlock on the name tag and Ctrl+L lock in place', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    c.addObject(
      ShapeObject(
        id: 'pic',
        name: 'pic',
        ellipse: false,
        center: const Offset(300, 300),
        size: const Size(120, 80),
        fill: 0xFF43A047,
      ),
    );
    c.select(['pic']);
    await tester.pump();
    final lock = find.byKey(const ValueKey('tag-lock'));
    expect(lock, findsOneWidget);
    await tester.tap(lock);
    await tester.pump();
    expect(c.doc.objectById('pic')!.locked, isTrue);
    expect(c.selection, ['pic'], reason: 'still there to unlock');
    expect(find.byKey(const ValueKey('tag-lock')), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.doc.objectById('pic')!.locked, isFalse);
    // The line tool's L still works after.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(c.tool, Tool.line);
  });

  appTest('a changed tool look offers a way back to the default', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    c.setTool(Tool.arrow);
    await tester.pump();
    final reset = find.byKey(const ValueKey('reset-tool-style'));
    bool enabled() => tester.widget<TextButton>(reset).onPressed != null;
    expect(enabled(), isFalse, reason: 'shown, greyed: nothing to reset');
    c.styleOf(Tool.arrow).width = 20;
    c.notify();
    await tester.pump();
    expect(enabled(), isTrue);
    await tester.tap(reset);
    await tester.pump();
    expect(c.styleOf(Tool.arrow).width, 5);
    expect(enabled(), isFalse);
  });

  appTest(
    'picking a drawing tool shows its settings, not the last thing drawn',
    (tester) async {
      final c = await pumpApp(tester);
      final box = ShapeObject(
        id: 'b',
        name: 'box',
        ellipse: false,
        center: const Offset(300, 300),
        size: const Size(80, 60),
      );
      c.currentLayer.objects.add(box);
      final reset = find.byKey(const ValueKey('reset-tool-style'));
      for (final t in [
        Tool.arrow,
        Tool.text,
        Tool.pen,
        Tool.badge,
        Tool.hide,
      ]) {
        c.select([box.id]);
        c.setTool(t);
        await tester.pump();
        expect(c.selection, isEmpty, reason: '$t');
        expect(reset, findsOneWidget, reason: '$t');
      }
      for (final t in [Tool.select, Tool.cutout]) {
        c.select([box.id]);
        c.setTool(t);
        await tester.pump();
        expect(c.selection, [box.id], reason: '$t keeps the selection');
      }
      expect(c.doc.allObjects, [box], reason: 'nothing on the page changes');
    },
  );

  appTest('F11 asks the window for full screen and back; Esc does not', (
    tester,
  ) async {
    final asked = <Object?>[];
    const channel = MethodChannel('thinkspace/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'setFullscreen') return null;
      asked.add(call.arguments);
      return call.arguments;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final c = await pumpApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pump();
    expect(asked, [true]);
    expect(c.toastMessage, contains('F11'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(asked, [true], reason: 'Esc is for tools and selections');
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pump();
    expect(asked, [true, false]);
  });

  appTest('F2 renames the selected object, or the layer just clicked', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    c.addObject(
      ShapeObject(
        id: 'box',
        name: 'box',
        ellipse: false,
        center: const Offset(200, 200),
        size: const Size(80, 60),
      ),
    );
    c.select(['box']);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.pump();
    final field = find.byKey(const ValueKey('object-name-box'));
    expect(field, findsOneWidget);
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(TextField)),
      'door',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.doc.objectById('box')!.name, 'door');
    expect(c.renamingId, isNull);
    // The keyboard is back with the editor: R picks the rectangle tool.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.tool, Tool.rect);
    c.setTool(Tool.select);

    // Clicking a layer's row, then F2, renames the layer.
    final layer = c.doc.layers.first;
    await tester.tap(find.byKey(ValueKey('layer-${layer.id}')));
    await tester.pump();
    expect(c.pickedLayer, layer.id);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.pump();
    final lf = find.byKey(ValueKey('layer-name-${layer.id}'));
    expect(lf, findsOneWidget);
    await tester.enterText(
      find.descendant(of: lf, matching: find.byType(TextField)),
      'Shop',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(layer.name, 'Shop');

    // Escape keeps the old name.
    c.select(['box']);
    c.beginRename('box');
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(c.doc.objectById('box')!.name, 'door');
    expect(c.renamingId, isNull);
  });

  appTest('a slider takes a typed value, as one undo step', (tester) async {
    final c = await pumpApp(tester);
    c.addObject(
      ShapeObject(
        id: 'box',
        name: 'box',
        ellipse: false,
        center: const Offset(200, 200),
        size: const Size(80, 60),
      ),
    );
    c.select(['box']);
    await tester.pump();
    final before = c.undoDepth;
    final box = find.descendant(
      of: find.byKey(const ValueKey('opacity')),
      matching: find.byType(TextField),
    );
    await tester.tap(box);
    await tester.enterText(box, '50');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.doc.objectById('box')!.opacity, closeTo(0.5, 1e-9));
    expect(c.undoDepth, before + 1);
    // Out of range is held to the slider's ends.
    await tester.tap(box);
    await tester.enterText(box, '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.doc.objectById('box')!.opacity, closeTo(0.05, 1e-9));
  });

  appTest('Hide details sits with Cut out and has no key', (tester) async {
    final c = await pumpApp(tester);
    final hide = find.byKey(const ValueKey('tool-hide'));
    final cut = find.byKey(const ValueKey('tool-cutout'));
    expect(tester.getCenter(hide).dx, greaterThan(tester.getCenter(cut).dx));
    await tester.tap(hide);
    await tester.pump();
    expect(c.tool, Tool.hide);
    expect(find.byKey(const ValueKey('tool-key-hide')), findsNothing);
    expect(find.byKey(const ValueKey('hide-pixelate')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hide-solid')));
    await tester.pump();
    expect(c.styleOf(Tool.hide).solid, isTrue);
  });

  appTest('a kept tool shows its padlock under its own button', (tester) async {
    final c = await pumpApp(tester);
    final undoX = tester.getCenter(find.byKey(const ValueKey('undo'))).dx;
    c.setTool(Tool.ellipse, lock: true);
    await tester.pump();
    final lock = find.byKey(const ValueKey('tool-lock'));
    final tool = find.byKey(const ValueKey('tool-ellipse'));
    expect(lock, findsOneWidget);
    expect(tester.getCenter(lock).dx, closeTo(tester.getCenter(tool).dx, 12));
    expect(
      tester.getTopLeft(lock).dy,
      greaterThan(tester.getBottomLeft(tool).dy),
    );
    // The rest of the bar stays where it was.
    expect(tester.getCenter(find.byKey(const ValueKey('undo'))).dx, undoX);
    c.setTool(Tool.select);
    await tester.pump();
    expect(lock, findsNothing);
  });
}

// Smaller windows (a laptop with the panels open) must still lay out cleanly.
void smallWindowTests() {
  for (final size in const [
    Size(1024, 640),
    Size(900, 600),
    Size(1280, 720),
    Size(900, 560),
  ]) {
    appTest(
      'lays out without overflow at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = EditorController();
        await tester.pumpWidget(
          MaterialApp(home: EditorShell(controller: c, startInspector: false)),
        );
        await tester.pump();
        await tester.runAsync(() => loadStorefrontSample(c));
        await tester.pump();
        // A selection exercises the properties panel, text exercises its extras.
        for (final name in ['awning_01', 'question', 'pointer']) {
          c.select([c.doc.allObjects.firstWhere((o) => o.name == name).id]);
          await tester.pump();
        }
        c.setTool(Tool.cutout);
        c.pendingPaste = PendingPaste(c.assets.all.first.id, 'pasted');
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
