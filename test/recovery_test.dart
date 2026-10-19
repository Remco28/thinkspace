import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/io/recovery.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ts_recovery'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('each window claims its own copy, and never offers its own', () {
    final a = RecoverySlot.claim(dir)!;
    final b = RecoverySlot.claim(dir)!;
    expect(a.file.path, isNot(b.file.path));
    a.file.writeAsStringSync('a');
    expect(RecoverySlot.orphans(dir, mine: a), isEmpty);
    a.release();
    b.release();
  });

  test('a copy whose window is gone is offered; an old single file too', () {
    final legacy = File('${dir.path}/recovery.thinkspace')
      ..writeAsStringSync('old');
    final gone = RecoverySlot.claim(Directory('${dir.path}/r'))!;
    gone.file.writeAsStringSync('left behind');
    gone.release(); // as if its window had crashed: no one holds it now
    final found = RecoverySlot.orphans(
      Directory('${dir.path}/r'),
      legacy: legacy,
    );
    expect(
      found.map((f) => f.path),
      containsAll([gone.file.path, legacy.path]),
    );
  });

  test('a copy held by another running window is left alone', () async {
    final slots = Directory('${dir.path}/r')..createSync();
    final copy = File('${slots.path}/other.thinkspace')
      ..writeAsStringSync('in use');
    final lock = File('${slots.path}/other.lock')..writeAsStringSync('');
    // Another process holds the lock, the way a second window would.
    final holder = await Process.start('python3', [
      '-c',
      'import fcntl,sys,time\n'
          'f=open(sys.argv[1],"a"); fcntl.lockf(f, fcntl.LOCK_EX)\n'
          'print("held", flush=True); time.sleep(30)',
      lock.path,
    ]);
    await holder.stdout.first;
    try {
      expect(RecoverySlot.orphans(slots), isEmpty);
    } finally {
      holder.kill();
      await holder.exitCode;
    }
    expect(RecoverySlot.orphans(slots).single.path, copy.path);
  }, skip: Platform.isWindows ? 'uses a POSIX lock helper' : false);
}
