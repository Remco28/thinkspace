// Small path helpers that behave the same on Linux and Windows.

/// The last part of a path, with its extension: handles both `/` and `\`.
String fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

/// The file name without its extension.
String baseNameOf(String path) =>
    fileNameOf(path).replaceAll(RegExp(r'\.[^.]+$'), '');

/// Where the app keeps what is not part of any project (the recovery copy and
/// preferences), or null when the system gives no place to put it.
///
/// `THINKSPACE_DATA_DIR` wins, which also makes a portable copy possible.
/// Otherwise: `%APPDATA%\Thinkspace` on Windows, and `$XDG_DATA_HOME` or
/// `~/.local/share` (plus `thinkspace`) elsewhere.
String? appDataDir(Map<String, String> env, {required bool windows}) {
  String? set(String k) {
    final v = env[k];
    return v == null || v.isEmpty ? null : v;
  }

  final override = set('THINKSPACE_DATA_DIR');
  if (override != null) return override;
  if (windows) {
    final roaming = set('APPDATA');
    if (roaming != null) return '$roaming\\Thinkspace';
    final profile = set('USERPROFILE');
    return profile == null ? null : '$profile\\AppData\\Roaming\\Thinkspace';
  }
  final xdg = set('XDG_DATA_HOME');
  if (xdg != null) return '$xdg/thinkspace';
  final home = set('HOME');
  return home == null ? null : '$home/.local/share/thinkspace';
}
