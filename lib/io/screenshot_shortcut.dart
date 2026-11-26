import 'dart:io';

import 'package:flutter/services.dart' show LogicalKeyboardKey, MethodChannel;

/// Whether Thinkspace can take screenshots on this computer: through the
/// desktop's screenshot service on Linux, with its own overlay on Windows
/// (`windows/runner/screen_pick.cpp`).
bool get screenshotsHere => Platform.isLinux || Platform.isWindows;

/// The shortcut store for this computer.
ScreenshotShortcut screenshotShortcutForThisComputer() =>
    Platform.isWindows ? WindowsScreenshotShortcut() : ScreenshotShortcut();

/// The screenshot shortcut the person chooses: a GNOME custom keyboard
/// shortcut that runs `thinkspace --capture` (see `my_application.cc`).
///
/// It is changed only through GNOME's own tool, `gsettings`, and only our
/// own entry: one fixed path, which nothing else uses, added to the list of
/// custom shortcuts. Removing it takes that one entry out of the list and
/// resets its keys, so the person's other shortcuts are never touched.
/// `install.sh --remove` does the same (see `tool/package_linux.sh`).
class ScreenshotShortcut {
  ScreenshotShortcut({this.run = Process.run, String? executable})
    : executable = executable ?? Platform.resolvedExecutable;

  /// Runs a command; tests pass a stand-in.
  final Future<ProcessResult> Function(String, List<String>) run;
  final String executable;

  static const listSchema = 'org.gnome.settings-daemon.plugins.media-keys';
  static const path =
      '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/thinkspace-screenshot/';
  static const _entry = '$listSchema.custom-keybinding:$path';

  /// Whether the Super (Windows) key can be part of the shortcut.
  bool get superKey => true;

  /// What the shortcut runs. Quoted, since GNOME splits it like a shell.
  String get command => "'${executable.replaceAll("'", r"'\''")}' --capture";

  Future<String?> _get(String schema, String key) async {
    try {
      final r = await run('gsettings', ['get', schema, key]);
      return r.exitCode == 0 ? (r.stdout as String).trim() : null;
    } on ProcessException {
      return null;
    }
  }

  Future<bool> _set(String schema, String key, String value) async {
    try {
      final r = await run('gsettings', ['set', schema, key, value]);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<List<String>?> _list() async {
    final v = await _get(listSchema, 'custom-keybindings');
    return v == null ? null : parseStrings(v);
  }

  /// Whether this desktop takes custom shortcuts this way (GNOME does).
  Future<bool> available() async => await _list() != null;

  /// The keys now set, as a GTK accelerator such as `<Control>Print`, or
  /// null if there is no shortcut.
  Future<String?> current() async {
    final list = await _list();
    if (list == null || !list.contains(path)) return null;
    final v = await _get(_entry, 'binding');
    final keys = v == null ? const <String>[] : parseStrings(v);
    return keys.isEmpty || keys.first.isEmpty ? null : keys.first;
  }

  /// Set the shortcut to [accel]. The entry is filled in before it joins the
  /// list, so GNOME never sees half of it.
  Future<bool> set(String accel) async {
    final list = await _list();
    if (list == null) return false;
    final ok =
        await _set(_entry, 'name', quote('Thinkspace screenshot')) &&
        await _set(_entry, 'command', quote(command)) &&
        await _set(_entry, 'binding', quote(accel));
    if (!ok) return false;
    if (list.contains(path)) return true;
    return _set(listSchema, 'custom-keybindings', stringList([...list, path]));
  }

  /// Take the shortcut away: our entry leaves the list, the person's other
  /// shortcuts stay as they are, and our entry's keys go back to unset.
  Future<bool> remove() async {
    final list = await _list();
    if (list == null) return false;
    if (list.contains(path)) {
      final rest = [
        for (final p in list)
          if (p != path) p,
      ];
      if (!await _set(listSchema, 'custom-keybindings', stringList(rest))) {
        return false;
      }
    }
    for (final key in ['name', 'command', 'binding']) {
      try {
        await run('gsettings', ['reset', _entry, key]);
      } on ProcessException {
        return false;
      }
    }
    return true;
  }

  /// The strings in a GVariant text such as `['a', 'b']` or `@as []`.
  /// A string holding a single quote is printed in double quotes instead.
  static List<String> parseStrings(String text) => [
    for (final m in RegExp(
      "'((?:[^'\\\\]|\\\\.)*)'"
      r'|"((?:[^"\\]|\\.)*)"',
    ).allMatches(text))
      (m.group(1) ?? m.group(2)!).replaceAllMapped(
        RegExp(r'\\(.)'),
        (x) => x.group(1)!,
      ),
  ];

  /// A string as GVariant text.
  static String quote(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

  static String stringList(List<String> items) =>
      items.isEmpty ? '@as []' : '[${items.map(quote).join(', ')}]';
}

/// The screenshot shortcut on Windows: a "Thinkspace screenshot" entry in
/// the person's Start menu with shortcut keys on it, made by the window
/// (`windows/runner/capture.cpp`). Windows' own shortcut keys can't use the
/// Windows key. The installer's uninstaller removes the entry.
class WindowsScreenshotShortcut extends ScreenshotShortcut {
  WindowsScreenshotShortcut({
    Future<Object?> Function(String method, [Object? arg])? invoke,
    super.executable,
  }) : _invoke = invoke ?? _channel.invokeMethod<Object?>;

  static const _channel = MethodChannel('thinkspace/window');
  final Future<Object?> Function(String method, [Object? arg]) _invoke;

  @override
  bool get superKey => false;

  @override
  String get command => '"$executable" --capture';

  @override
  Future<bool> available() async => true;

  @override
  Future<String?> current() async {
    final v = await _invoke('getShortcut');
    return v is int ? accelForHotkey(v) : null;
  }

  @override
  Future<bool> set(String accel) async {
    final hotkey = hotkeyForAccel(accel);
    return hotkey != null && await _invoke('setShortcut', hotkey) == true;
  }

  @override
  Future<bool> remove() async => await _invoke('removeShortcut') == true;

  // Windows key codes (VK_*) for the keys a shortcut can use, by GTK name.
  static final _keyCodes = <String, int>{
    'Print': 0x2C,
    'Pause': 0x13,
    'Scroll_Lock': 0x91,
    'Insert': 0x2D,
    'Home': 0x24,
    'End': 0x23,
    'Page_Up': 0x21,
    'Page_Down': 0x22,
    'space': 0x20,
    for (var i = 1; i <= 12; i++) 'F$i': 0x6F + i,
    for (var i = 0; i < 26; i++) String.fromCharCode(0x61 + i): 0x41 + i, // a-z
    for (var i = 0; i < 10; i++) '$i': 0x30 + i,
  };
  static const _shift = 0x100, _control = 0x200, _alt = 0x400;

  /// An accelerator such as `<Control>Print` as a Start menu shortcut's
  /// hotkey: the key code, and Shift, Ctrl and Alt in the byte above. Null
  /// for what Windows can't use (the Windows key, or an unknown key).
  static int? hotkeyForAccel(String accel) {
    final mods = RegExp(r'<(\w+)>').allMatches(accel).map((m) => m.group(1)!);
    final code = _keyCodes[accel.replaceAll(RegExp(r'<\w+>'), '')];
    if (code == null) return null;
    var hotkey = code;
    for (final m in mods) {
      switch (m) {
        case 'Control' || 'Primary' || 'Ctrl':
          hotkey |= _control;
        case 'Alt':
          hotkey |= _alt;
        case 'Shift':
          hotkey |= _shift;
        default:
          return null;
      }
    }
    return hotkey;
  }

  /// The other way round; null for a key code Thinkspace doesn't offer.
  static String? accelForHotkey(int hotkey) {
    final code = hotkey & 0xFF;
    final name = _keyCodes.entries
        .where((e) => e.value == code)
        .map((e) => e.key)
        .firstOrNull;
    if (name == null) return null;
    return '${hotkey & _control != 0 ? '<Control>' : ''}'
        '${hotkey & _alt != 0 ? '<Alt>' : ''}'
        '${hotkey & _shift != 0 ? '<Shift>' : ''}$name';
  }
}

/// A key press as a shortcut: the GTK accelerator GNOME stores and the key
/// caps to show. Null for a key that cannot be one, such as a modifier alone,
/// or a letter, digit or space without Ctrl, Alt or Super, which would fire
/// while typing.
({String accel, List<String> caps})? shortcutFor(
  LogicalKeyboardKey key, {
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
  bool meta = false,
}) {
  final named = <LogicalKeyboardKey, (String, String)>{
    // GTK reports the Print Screen key as `print`.
    LogicalKeyboardKey.print: ('Print', 'Print'),
    LogicalKeyboardKey.printScreen: ('Print', 'Print'),
    LogicalKeyboardKey.pause: ('Pause', 'Pause'),
    LogicalKeyboardKey.scrollLock: ('Scroll_Lock', 'Scroll Lock'),
    LogicalKeyboardKey.insert: ('Insert', 'Insert'),
    LogicalKeyboardKey.home: ('Home', 'Home'),
    LogicalKeyboardKey.end: ('End', 'End'),
    LogicalKeyboardKey.pageUp: ('Page_Up', 'Page Up'),
    LogicalKeyboardKey.pageDown: ('Page_Down', 'Page Down'),
    LogicalKeyboardKey.space: ('space', 'Space'),
  };
  final fKeys = [
    LogicalKeyboardKey.f1,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5,
    LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7,
    LogicalKeyboardKey.f8,
    LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10,
    LogicalKeyboardKey.f11,
    LogicalKeyboardKey.f12,
  ];
  String name, cap;
  var typing = false;
  final label = key.keyLabel;
  if (named[key] case final n?) {
    (name, cap) = n;
    typing = key == LogicalKeyboardKey.space;
  } else if (fKeys.contains(key)) {
    name = cap = 'F${fKeys.indexOf(key) + 1}';
  } else if (label.length == 1 && RegExp(r'[A-Za-z0-9]').hasMatch(label)) {
    name = label.toLowerCase();
    cap = label.toUpperCase();
    typing = true;
  } else {
    return null;
  }
  if (typing && !ctrl && !alt && !meta) return null;
  return (
    accel:
        '${ctrl ? '<Control>' : ''}${alt ? '<Alt>' : ''}'
        '${shift ? '<Shift>' : ''}${meta ? '<Super>' : ''}$name',
    caps: [
      if (ctrl) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Super',
      cap,
    ],
  );
}

/// Key caps for a stored accelerator such as `<Control><Shift>s`.
List<String> capsForAccel(String accel) {
  final mods = RegExp(r'<(\w+)>').allMatches(accel).map((m) => m.group(1)!);
  final key = accel.replaceAll(RegExp(r'<\w+>'), '');
  const modCaps = {
    'Control': 'Ctrl',
    'Primary': 'Ctrl',
    'Ctrl': 'Ctrl',
    'Alt': 'Alt',
    'Shift': 'Shift',
    'Super': 'Super',
  };
  const keyCaps = {
    'Print': 'Print',
    'Scroll_Lock': 'Scroll Lock',
    'Page_Up': 'Page Up',
    'Page_Down': 'Page Down',
    'space': 'Space',
  };
  return [
    for (final m in mods) modCaps[m] ?? m,
    keyCaps[key] ?? (key.length == 1 ? key.toUpperCase() : key),
  ];
}
