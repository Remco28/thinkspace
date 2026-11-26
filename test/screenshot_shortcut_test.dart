import 'dart:io';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/io/screenshot_shortcut.dart';

void main() {
  group('keys as a shortcut', () {
    test('a letter needs Ctrl, Alt or Super; Print and F-keys do not', () {
      expect(shortcutFor(LogicalKeyboardKey.keyS), isNull);
      expect(shortcutFor(LogicalKeyboardKey.keyS, shift: true), isNull);
      expect(shortcutFor(LogicalKeyboardKey.space), isNull);
      final s = shortcutFor(LogicalKeyboardKey.keyS, ctrl: true, shift: true)!;
      expect(s.accel, '<Control><Shift>s');
      expect(s.caps, ['Ctrl', 'Shift', 'S']);
      expect(shortcutFor(LogicalKeyboardKey.printScreen)!.accel, 'Print');
      // GTK's name for the same key.
      expect(shortcutFor(LogicalKeyboardKey.print)!.accel, 'Print');
      expect(shortcutFor(LogicalKeyboardKey.printScreen, ctrl: true)!.caps, [
        'Ctrl',
        'Print',
      ]);
      expect(
        shortcutFor(LogicalKeyboardKey.f9, meta: true)!.accel,
        '<Super>F9',
      );
      expect(shortcutFor(LogicalKeyboardKey.shiftLeft, ctrl: true), isNull);
    });

    test('stored keys read back as key caps', () {
      expect(capsForAccel('<Control>Print'), ['Ctrl', 'Print']);
      expect(capsForAccel('<Super><Shift>s'), ['Super', 'Shift', 'S']);
      expect(capsForAccel('Page_Down'), ['Page Down']);
    });

    test('GVariant text', () {
      expect(ScreenshotShortcut.parseStrings('@as []'), isEmpty);
      expect(ScreenshotShortcut.parseStrings("['/a/', '/b/']"), ['/a/', '/b/']);
      expect(ScreenshotShortcut.parseStrings(r"'it\'s'"), ["it's"]);
      expect(ScreenshotShortcut.parseStrings('"it\\\'s"'), ["it's"]);
      expect(ScreenshotShortcut.stringList([]), '@as []');
      expect(ScreenshotShortcut.quote("it's"), r"'it\'s'");
    });
  });

  // Against the real gsettings, kept in a throwaway file so nothing on this
  // computer changes. Needs GNOME's schemas, so it is skipped elsewhere.
  bool hasSchema;
  try {
    hasSchema =
        Process.runSync('gsettings', [
          'list-keys',
          ScreenshotShortcut.listSchema,
        ]).exitCode ==
        0;
  } on ProcessException {
    hasSchema = false; // no gsettings at all, as on Windows
  }
  group('with GNOME settings', () {
    late Directory home;
    late Future<ProcessResult> Function(String, List<String>) run;
    setUp(() {
      home = Directory.systemTemp.createTempSync('thinkspace_gsettings');
      final env = {
        'GSETTINGS_BACKEND': 'keyfile',
        'XDG_CONFIG_HOME': home.path,
      };
      run = (cmd, args) => Process.run(cmd, args, environment: env);
    });
    tearDown(() => home.deleteSync(recursive: true));

    Future<List<String>> list() async => ScreenshotShortcut.parseStrings(
      (await run('gsettings', [
            'get',
            ScreenshotShortcut.listSchema,
            'custom-keybindings',
          ])).stdout
          as String,
    );

    test('set, change and remove touch only our own entry', () async {
      const theirs =
          '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/';
      await run('gsettings', [
        'set',
        ScreenshotShortcut.listSchema,
        'custom-keybindings',
        "['$theirs']",
      ]);
      final s = ScreenshotShortcut(
        run: run,
        executable: "/home/someone/it's here/thinkspace",
      );
      expect(await s.available(), isTrue);
      expect(await s.current(), isNull);

      expect(await s.set('<Control>Print'), isTrue);
      expect(await list(), [theirs, ScreenshotShortcut.path]);
      expect(await s.current(), '<Control>Print');
      const entry =
          '${ScreenshotShortcut.listSchema}.custom-keybinding:${ScreenshotShortcut.path}';
      final command = ScreenshotShortcut.parseStrings(
        (await run('gsettings', ['get', entry, 'command'])).stdout as String,
      ).single;
      expect(command, s.command);

      expect(await s.set('<Super>F9'), isTrue);
      expect(await list(), [theirs, ScreenshotShortcut.path], reason: 'once');
      expect(await s.current(), '<Super>F9');

      expect(await s.remove(), isTrue);
      expect(await list(), [theirs]);
      expect(await s.current(), isNull);
      // Nothing of ours is left: every key of our entry is back to unset.
      // (This file store keeps an empty section header for a reset group,
      // which GNOME's own store does not, so values are compared, not text.)
      final keyfile = File('${home.path}/glib-2.0/settings/keyfile');
      final values = keyfile.readAsLinesSync().where(
        (l) => l.isNotEmpty && !l.startsWith('['),
      );
      expect(values.join('\n'), isNot(contains('thinkspace')));
      for (final key in ['name', 'command', 'binding']) {
        expect(
          (await run('gsettings', ['get', entry, key])).stdout,
          "''\n",
          reason: key,
        );
      }
      // Removing again changes nothing and does not fail.
      expect(await s.remove(), isTrue);
      expect(await list(), [theirs]);
    });
  }, skip: hasSchema ? false : 'GNOME settings schemas are not installed');

  group('on Windows', () {
    test('keys become a Start menu hotkey and back', () {
      const w = WindowsScreenshotShortcut.hotkeyForAccel;
      expect(w('<Control>Print'), 0x22C);
      expect(w('<Control><Alt>s'), 0x653);
      expect(w('<Shift>F9'), 0x178);
      expect(w('<Control>space'), 0x220);
      expect(w('<Super>s'), isNull, reason: 'no Windows key in a hotkey');
      expect(w('<Control>Menu'), isNull);
      for (final a in [
        '<Control>Print',
        '<Control><Alt>s',
        '<Shift>F9',
        '<Alt>7',
        '<Control><Shift>Page_Down',
      ]) {
        expect(WindowsScreenshotShortcut.accelForHotkey(w(a)!), a);
      }
      expect(WindowsScreenshotShortcut.accelForHotkey(0x2FF), isNull);
    });

    test('the window keeps the shortcut', () async {
      final calls = <String>[];
      Object? saved;
      final s = WindowsScreenshotShortcut(
        executable: r'C:\Program Files\Thinkspace\thinkspace.exe',
        invoke: (method, [arg]) async {
          calls.add('$method ${arg ?? ''}'.trim());
          switch (method) {
            case 'getShortcut':
              return saved;
            case 'setShortcut':
              saved = arg;
              return true;
            case 'removeShortcut':
              saved = null;
              return true;
          }
          return null;
        },
      );
      expect(s.superKey, isFalse);
      expect(await s.available(), isTrue);
      expect(await s.current(), isNull);
      expect(await s.set('<Control>Print'), isTrue);
      expect(await s.current(), '<Control>Print');
      expect(await s.set('<Super>s'), isFalse, reason: 'never sent');
      expect(await s.remove(), isTrue);
      expect(await s.current(), isNull);
      expect(calls, [
        'getShortcut',
        'setShortcut 556',
        'getShortcut',
        'removeShortcut',
        'getShortcut',
      ]);
      expect(
        s.command,
        r'"C:\Program Files\Thinkspace\thinkspace.exe" --capture',
      );
    });
  });
}
