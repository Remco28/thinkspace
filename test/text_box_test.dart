import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/editor/controller.dart';
import 'package:thinkspace/editor/interactor.dart';
import 'package:thinkspace/editor/render.dart';
import 'package:thinkspace/model/scene.dart';

import 'helpers.dart';

// In tests every character is a square as wide as the font size (28), so a
// box hugging "Hello" is 5 * 28 + padding (6 a side) + room for the cursor.
const _hug = 12 + 4;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EditorController c;
  late CanvasInteractor ix;

  setUp(() {
    c = newEditor();
    ix = CanvasInteractor(c);
  });

  TextObject typeAt(Offset at, String text) {
    c.setTool(Tool.text);
    click(ix, at);
    c.updateEditingText(text);
    return c.doc.objectById(c.editingTextId!) as TextObject;
  }

  test('a click makes an empty box that grows as you type', () {
    c.setTool(Tool.text);
    click(ix, const Offset(200, 100));
    final t = c.doc.objectById(c.editingTextId!) as TextObject;
    expect(t.text, isEmpty);
    expect(t.autoWidth, isTrue);
    c.updateEditingText('Hello');
    expect(t.size.width, 5 * 28 + _hug);
    expect(t.bounds.left, closeTo(200, 1e-9), reason: 'left edge stays');
    expect(t.bounds.top, closeTo(100, 1e-9), reason: 'top edge stays');
    final oneLine = t.size.height;
    // Only Enter starts a new line; the box is as wide as the longest.
    c.updateEditingText('Hello\nHi');
    expect(t.size.width, 5 * 28 + _hug);
    expect(t.size.height, greaterThan(oneLine));
    expect(t.bounds.top, closeTo(100, 1e-9));
    c.finishTextEdit();
    expect(c.doc.allObjects.single, same(t));
  });

  test('a drag makes a box of that width, which wraps', () {
    c.setTool(Tool.text);
    drag(ix, const Offset(100, 100), const Offset(260, 100));
    final t = c.doc.objectById(c.editingTextId!) as TextObject;
    expect(t.autoWidth, isFalse);
    expect(t.size.width, 160);
    final oneLine = t.size.height;
    c.updateEditingText('Hello there');
    expect(t.size.width, 160);
    expect(t.size.height, greaterThan(oneLine), reason: 'it wraps');
  });

  test('a short text near the edge does not grow the page', () {
    final page = c.doc.canvasSize;
    typeAt(Offset(page.width - 100, 100), 'Hi');
    c.finishTextEdit();
    expect(c.doc.canvasSize, page);
  });

  test('centred text grows from its middle, right-aligned from its right', () {
    c.styleOf(Tool.text).align = TextAlign.center;
    final t = typeAt(const Offset(200, 100), 'A');
    final mid = t.center.dx;
    c.updateEditingText('ABCDE');
    expect(t.center.dx, closeTo(mid, 1e-9));
    c.finishTextEdit();
    c.styleOf(Tool.text).align = TextAlign.right;
    final r = typeAt(const Offset(200, 300), 'A');
    final right = r.bounds.right;
    c.updateEditingText('ABCDE');
    expect(r.bounds.right, closeTo(right, 1e-9));
  });

  test('a bigger font widens the box; dragging a side fixes its width', () {
    final t = typeAt(const Offset(200, 100), 'Hello');
    c.finishTextEdit();
    c.select([t.id]);
    c.editSelected('size', (o) => (o as TextObject).fontSize = 40);
    expect(t.size.width, 5 * 40 + _hug);
    expect(t.bounds.left, closeTo(200, 1e-9));
    // Drag the right side's handle in: the box keeps that width and wraps.
    final side = Offset(t.bounds.right, t.center.dy);
    drag(ix, side, side - const Offset(120, 0));
    expect(t.autoWidth, isFalse);
    expect(t.size.width, closeTo(5 * 40 + _hug - 120, 1e-6));
  });

  test('pasted text hugs short lines and wraps long ones', () async {
    String? clip;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': clip};
          return null;
        });
    clip = 'Short';
    await c.paste();
    final a = c.doc.allObjects.whereType<TextObject>().last;
    expect(a.autoWidth, isTrue);
    expect(a.size.width, 5 * 28 + _hug);
    clip = 'x' * 60;
    await c.paste();
    final b = c.doc.allObjects.whereType<TextObject>().last;
    expect(b.autoWidth, isFalse);
    expect(b.size.width, EditorController.maxPastedTextWidth);
  });

  test('auto width is kept in the file; older files are fixed', () {
    final t = typeAt(const Offset(200, 100), 'Hello');
    final j = jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>;
    expect(TextObject.fromJson(j).autoWidth, isTrue);
    j.remove('autoWidth');
    expect(TextObject.fromJson(j).autoWidth, isFalse);
  });

  test('an opened file\'s text is measured again, without a change', () async {
    final t = typeAt(const Offset(200, 100), 'Hello');
    c.finishTextEdit();
    final right = t.size.height;
    // As if measured on a computer with another font: too tall.
    t
      ..size = Size(t.size.width, right + 30)
      ..center += const Offset(0, 15);
    await c.loadProjectJson(c.projectJson());
    final back = c.doc.allObjects.single as TextObject;
    expect(back.size.height, right);
    expect(back.bounds.top, closeTo(100, 1e-9));
    expect(c.dirty, isFalse);
  });

  test('emoji are told apart from text by the Unicode rules', () {
    for (final e in [
      '😀',
      '❤️',
      '☀️',
      '⚠️',
      '⭐',
      '✅',
      '👍🏽',
      '🇺🇸',
      '👨‍👩‍👧',
      '1️⃣',
    ]) {
      expect(isEmoji(e), isTrue, reason: e);
    }
    // Plain symbols, and an emoji asked for as text, stay text.
    for (final e in ['A', '❤', '☀', '⚠', '→', '★', '✓', '⭐\uFE0E', ' ']) {
      expect(isEmoji(e), isFalse, reason: e);
    }
  });

  test('emoji get their own run, drawn from the emoji font', () {
    const base = TextStyle(fontFamily: 'Inter');
    final span = textSpanFor('Hi ❤️ there 🚀', base);
    final runs = [for (final r in span.children!) (r as TextSpan).text];
    expect(runs, ['Hi ', '❤️', ' there ', '🚀']);
    final heart = span.children![1] as TextSpan;
    expect(heart.style!.fontFamily, kEmojiFonts.first);
    expect((span.children![0] as TextSpan).style, isNull);
    // Plain text stays one simple span.
    expect(textSpanFor('Hello', base).children, isNull);
  });

  test('text tries the colour emoji fonts before any other', () {
    final t = typeAt(const Offset(200, 100), '❤️');
    expect(textStyleFor(t).fontFamilyFallback, kEmojiFonts);
    expect(kEmojiFonts.first, 'Noto Color Emoji');
    // Sans is the bundled Inter, not whatever the computer's default is.
    expect(textStyleFor(t).fontFamily, 'Inter');
  });
}
