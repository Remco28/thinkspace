import 'dart:convert';
import 'dart:io';

/// The few things remembered between sessions that are not part of any
/// project, such as where the divider between Layers and the settings panel
/// sits, each tool's last look and the projects opened lately. A missing,
/// unreadable or odd file just means "use the defaults": a preference is
/// never worth an error.
class Prefs {
  Prefs(this.file) {
    final f = file;
    if (f == null) return;
    try {
      final j = jsonDecode(f.readAsStringSync());
      final v = (j['layersFraction'] as num?)?.toDouble();
      if (v != null && v >= 0.1 && v <= 0.8) layersFraction = v;
      if (j['toolStyles'] is Map) toolStyles = j['toolStyles'];
      if (j['recentFiles'] is List) {
        recentFiles = [
          for (final p in j['recentFiles'])
            if (p is String) p,
        ];
      }
    } catch (_) {}
  }

  final File? file;

  /// The share of the right-hand column the Layers list takes.
  double? layersFraction;

  /// Each tool's last look, as the editor writes it.
  Map<dynamic, dynamic>? toolStyles;

  /// Projects opened or saved lately, newest first.
  List<String> recentFiles = [];

  void save() {
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({
          'layersFraction': layersFraction,
          'toolStyles': toolStyles,
          'recentFiles': recentFiles,
        }),
      );
    } catch (_) {}
  }
}
