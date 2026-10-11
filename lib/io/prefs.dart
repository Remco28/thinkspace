import 'dart:convert';
import 'dart:io';

/// The few things remembered between sessions that are not part of any
/// project, such as where the divider between Layers and the settings panel
/// sits. A missing, unreadable or odd file just means "use the defaults": a
/// preference is never worth an error.
class Prefs {
  Prefs(this.file) {
    final f = file;
    if (f == null) return;
    try {
      final j = jsonDecode(f.readAsStringSync());
      final v = (j['layersFraction'] as num?)?.toDouble();
      if (v != null && v >= 0.1 && v <= 0.8) layersFraction = v;
    } catch (_) {}
  }

  final File? file;

  /// The share of the right-hand column the Layers list takes.
  double? layersFraction;

  void save() {
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode({'layersFraction': layersFraction}));
    } catch (_) {}
  }
}
