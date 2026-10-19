import 'dart:io';

/// Where one window keeps its unsaved work. Several windows can be open at
/// once, so each has a file of its own and holds a lock beside it for as long
/// as it runs. A file whose lock nobody holds was left by a window that never
/// closed properly (a crash, a power cut) and can be offered back; one that is
/// locked belongs to a window that is still open and is left alone.
class RecoverySlot {
  RecoverySlot._(this.file, this._lockFile, this._lock);

  /// This window's recovery copy.
  final File file;
  final File _lockFile;
  final RandomAccessFile _lock;

  static final String _sep = Platform.pathSeparator;

  /// Claim a new slot in [dir], or null if the folder cannot be written.
  static RecoverySlot? claim(Directory dir) {
    try {
      dir.createSync(recursive: true);
      final id = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final lockFile = File('${dir.path}$_sep$id.lock');
      final lock = lockFile.openSync(mode: FileMode.write)
        ..lockSync(FileLock.exclusive);
      return RecoverySlot._(
        File('${dir.path}$_sep$id.thinkspace'),
        lockFile,
        lock,
      );
    } catch (_) {
      return null;
    }
  }

  /// Let go of the slot when the window closes. (If it never gets here, the
  /// system drops the lock anyway when the process ends.)
  void release() {
    try {
      _lock.unlockSync();
      _lock.closeSync();
      _lockFile.deleteSync();
    } catch (_) {}
  }

  /// Recovery copies in [dir] that no running window holds, newest first.
  /// [legacy] is the single file older versions used, offered too if it is
  /// there. Leftover locks of windows that are gone are tidied away.
  static List<File> orphans(Directory dir, {File? legacy, RecoverySlot? mine}) {
    final out = <File>[];
    if (legacy != null && legacy.existsSync()) out.add(legacy);
    if (!dir.existsSync()) return out;
    final entries = dir.listSync().whereType<File>().toList();
    for (final f in entries) {
      final name = f.path.split(_sep).last;
      if (!name.endsWith('.thinkspace')) continue;
      if (mine != null && f.path == mine.file.path) continue;
      final lock = File(f.path.replaceAll(RegExp(r'\.thinkspace$'), '.lock'));
      if (_held(lock)) continue;
      out.add(f);
    }
    // Locks whose window is gone and whose copy was cleared: tidy them up.
    for (final f in entries) {
      if (!f.path.endsWith('.lock')) continue;
      if (mine != null && f.path == mine._lockFile.path) continue;
      final copy = File(f.path.replaceAll(RegExp(r'\.lock$'), '.thinkspace'));
      if (!copy.existsSync() && !_held(f)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    out.sort((a, b) => _modified(b).compareTo(_modified(a)));
    return out;
  }

  /// Whether a running window holds [lock].
  static bool _held(File lock) {
    if (!lock.existsSync()) return false;
    RandomAccessFile? raf;
    try {
      raf = lock.openSync(mode: FileMode.append);
      raf.lockSync(FileLock.exclusive);
      raf.unlockSync();
      return false;
    } catch (_) {
      return true;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  static DateTime _modified(File f) {
    try {
      return f.lastModifiedSync();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}
