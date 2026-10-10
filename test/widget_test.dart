import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/io/samples.dart';
import 'package:thinkspace/model/scene.dart';
import 'package:thinkspace/ui/shell.dart';

import 'helpers.dart';

Future<EditorController> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = EditorController();
  await tester.pumpWidget(MaterialApp(home: EditorShell(controller: c, startInspector: false)));
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
  appTest('opens on an empty page with the tools, layers and collection in view', (tester) async {
    await pumpApp(tester);
    for (final t in ['select', 'line', 'arrow', 'rect', 'ellipse', 'text', 'pen', 'cutout']) {
      expect(find.byKey(ValueKey('tool-$t')), findsOneWidget, reason: t);
    }
    expect(find.text('LAYERS'), findsOneWidget);
    expect(find.text('Layer 1'), findsOneWidget);
    expect(find.text('COLLECTION'), findsOneWidget);
    expect(find.textContaining('Keep images here'), findsOneWidget);
    expect(find.text('PAGE'), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-w')), findsOneWidget);
  });

  appTest('drawing an arrow with the mouse lists it, selects it, and undo removes it', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tool-arrow')));
    await tester.pump();
    final r = canvasRect(tester);
    final g = await tester.startGesture(r.center - const Offset(120, 40), kind: PointerDeviceKind.mouse);
    await g.moveTo(r.center);
    await g.moveTo(r.center + const Offset(120, 60));
    await g.up();
    await tester.pump();

    expect(c.doc.allObjects.single, isA<LineObject>());
    expect(find.text('arrow 1'), findsWidgets, reason: 'object list and selection label');
    expect(find.text('ARROW'), findsOneWidget, reason: 'properties panel names the selection');

    await tester.tap(find.byKey(const ValueKey('undo')));
    await tester.pump();
    expect(c.doc.allObjects, isEmpty);
    await tester.tap(find.byKey(const ValueKey('redo')));
    await tester.pump();
    expect(c.doc.allObjects.length, 1);
  });

  appTest('keyboard: tool letters, undo/redo, delete, escape', (tester) async {
    final c = await pumpApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    expect(c.tool, Tool.rect);
    final r = canvasRect(tester);
    final g = await tester.startGesture(r.center, kind: PointerDeviceKind.mouse);
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
    final g = await tester.startGesture(r.center, kind: PointerDeviceKind.mouse);
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

  appTest('adding a layer and picking it makes new drawings land there', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.byTooltip('Add layer'));
    await tester.pump();
    expect(c.doc.layers.length, 2);
    expect(c.currentLayer.name, 'Layer 2');
    await tester.tap(find.byKey(const ValueKey('tool-ellipse')));
    final r = canvasRect(tester);
    final g = await tester.startGesture(r.center, kind: PointerDeviceKind.mouse);
    await g.moveTo(r.center + const Offset(80, 80));
    await g.up();
    await tester.pump();
    expect(c.doc.layerOf(c.selection.single)!.name, 'Layer 2');
  });

  appTest('text tool: click, type on the page, click away', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tool-text')));
    await tester.pump();
    final r = canvasRect(tester);
    final g = await tester.startGesture(r.center, kind: PointerDeviceKind.mouse);
    await g.up();
    await tester.pump();
    await tester.pump();
    expect(c.editingTextId, isNotNull);
    expect(find.byType(TextField), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('text-editor')), 'Which one?');
    await tester.pump();
    // Click on empty canvas to finish.
    final g2 = await tester.startGesture(r.bottomRight - const Offset(40, 40), kind: PointerDeviceKind.mouse);
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
    expect(find.byKey(ValueKey('collection-${c.doc.collection.first.id}')), findsOneWidget);

    c.pendingPaste = PendingPaste(asset.id, 'pasted image');
    c.notify();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.doc.allObjects.whereType<ImageObject>().length, 1);
  });

  appTest('the storefront sample shows layers, objects and a labelled selection', (tester) async {
    final c = await pumpApp(tester);
    await tester.runAsync(() => loadStorefrontSample(c));
    await tester.pump();
    for (final n in ['Notes', 'Navy awnings', 'Striped awnings', 'Storefront']) {
      expect(find.text(n), findsWidgets, reason: n);
    }
    expect(find.text('awning_01'), findsOneWidget);
    expect(find.text('awning_02'), findsOneWidget);

    await tester.tap(find.text('awning_02'));
    await tester.pump();
    expect(c.single!.name, 'awning_02');
    expect(find.text('awning_02 · Navy awnings'), findsNothing, reason: 'the label is painted, not a widget');
    expect(find.text('IMAGE'), findsOneWidget);
    expect(find.byKey(const ValueKey('opacity')), findsOneWidget);
    expect(find.byKey(const ValueKey('cutout-button')), findsOneWidget);

    // Hiding one awning's layer and showing the other is a single click each.
    final navy = c.doc.layers.firstWhere((l) => l.name == 'Navy awnings');
    await tester.tap(find.byKey(ValueKey('layer-eye-${navy.id}')));
    await tester.pump();
    expect(navy.visible, isFalse);
  });

  appTest('moving an object to another layer from the properties panel', (tester) async {
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

  appTest('the collection can be hidden to give the canvas room', (tester) async {
    await pumpApp(tester);
    expect(find.text('COLLECTION'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toggle-collection')));
    await tester.pump();
    expect(find.text('COLLECTION'), findsNothing);
  });
}
