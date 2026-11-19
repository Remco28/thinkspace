import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/io/screenshot_shortcut.dart';
import 'package:thinkspace/ui/shell.dart';
import 'package:thinkspace/ui/shortcut_dialog.dart';

/// GNOME's keyboard settings, kept in memory.
class _Store extends ScreenshotShortcut {
  _Store({this.works = true, this.binding})
    : super(executable: '/opt/thinkspace/thinkspace');
  final bool works;
  String? binding;
  final calls = <String>[];

  @override
  Future<bool> available() async => works;
  @override
  Future<String?> current() async => binding;
  @override
  Future<bool> set(String accel) async {
    calls.add('set $accel');
    binding = accel;
    return true;
  }

  @override
  Future<bool> remove() async {
    calls.add('remove');
    binding = null;
    return true;
  }
}

void main() {
  Future<EditorController> open(WidgetTester tester, _Store store) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    screenshotShortcutStore = () => store;
    addTearDown(() => screenshotShortcutStore = ScreenshotShortcut.new);
    final c = EditorController();
    await tester.pumpWidget(
      MaterialApp(home: EditorShell(controller: c, startInspector: false)),
    );
    await tester.pump();
    showScreenshotShortcut(tester.element(find.byType(EditorShell)), c);
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> press(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
    for (final k in keys) {
      await tester.sendKeyDownEvent(k);
    }
    for (final k in keys.reversed) {
      await tester.sendKeyUpEvent(k);
    }
    await tester.pump();
  }

  Finder save() => find.widgetWithText(FilledButton, 'Save');

  testWidgets('pressing keys picks them, and Save stores them', (tester) async {
    final store = _Store();
    final c = await open(tester, store);
    expect(find.text('Press the keys you want'), findsOneWidget);
    expect(tester.widget<FilledButton>(save()).onPressed, isNull);

    // A plain letter would fire while typing.
    await press(tester, [LogicalKeyboardKey.keyK]);
    expect(find.textContaining('Add Ctrl, Alt or Super'), findsOneWidget);
    expect(tester.widget<FilledButton>(save()).onPressed, isNull);

    await press(tester, [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.printScreen,
    ]);
    expect(find.text('Ctrl'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);
    await tester.tap(save());
    await tester.pumpAndSettle();
    expect(store.calls, ['set <Control>Print']);
    expect(c.toastMessage, 'Screenshot shortcut: Ctrl + Print');
    expect(find.text('Screenshot shortcut'), findsNothing, reason: 'closed');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a shortcut already set shows, and can be removed', (
    tester,
  ) async {
    final store = _Store(binding: '<Super><Shift>s');
    final c = await open(tester, store);
    expect(find.text('Super'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    await tester.tap(find.text('Remove shortcut'));
    await tester.pumpAndSettle();
    expect(store.calls, ['remove']);
    expect(c.toastMessage, 'Screenshot shortcut removed');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('elsewhere than GNOME it shows the command to bind', (
    tester,
  ) async {
    final store = _Store(works: false);
    await open(tester, store);
    expect(
      tester
          .widget<SelectableText>(find.byKey(const ValueKey('capture-command')))
          .data,
      "'/opt/thinkspace/thinkspace' --capture",
    );
    expect(save(), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(store.calls, isEmpty);
  });
}
