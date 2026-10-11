import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/io/clipboard.dart';
import 'package:thinkspace/io/paths.dart';

void main() {
  group('file names', () {
    test('both kinds of slash are understood', () {
      expect(fileNameOf(r'C:\Users\kid\Pictures\cat.png'), 'cat.png');
      expect(fileNameOf('/home/kid/cat.png'), 'cat.png');
      expect(fileNameOf('cat.png'), 'cat.png');
      expect(baseNameOf(r'C:\a\b\my.drawing.thinkspace'), 'my.drawing');
      expect(baseNameOf('/x/y/noext'), 'noext');
    });
  });

  group('where the app keeps its data', () {
    test('Windows uses the roaming app data folder', () {
      expect(
        appDataDir({'APPDATA': r'C:\Users\kid\AppData\Roaming'}, windows: true),
        r'C:\Users\kid\AppData\Roaming\Thinkspace',
      );
      expect(
        appDataDir({'USERPROFILE': r'C:\Users\kid'}, windows: true),
        r'C:\Users\kid\AppData\Roaming\Thinkspace',
      );
      expect(appDataDir({}, windows: true), isNull);
    });

    test('Linux follows XDG, then HOME', () {
      expect(
        appDataDir({
          'XDG_DATA_HOME': '/data',
          'HOME': '/home/x',
        }, windows: false),
        '/data/thinkspace',
      );
      expect(
        appDataDir({'HOME': '/home/x'}, windows: false),
        '/home/x/.local/share/thinkspace',
      );
      expect(appDataDir({'HOME': ''}, windows: false), isNull);
      expect(appDataDir({}, windows: false), isNull);
    });

    test('an explicit folder wins everywhere, which makes a portable copy', () {
      for (final win in [true, false]) {
        expect(
          appDataDir({
            'THINKSPACE_DATA_DIR': 'D:/portable',
            'APPDATA': 'x',
            'HOME': 'y',
          }, windows: win),
          'D:/portable',
        );
      }
    });
  });

  group('copied files', () {
    test('file addresses become paths, anything else is ignored', () {
      expect(
        SystemClipboard.parseFileList(
          'copy\nfile:///home/kid/a%20cat.png\r\nfile:///tmp/b.jpg\nhttp://x/y.png\n',
        ),
        [
          // Windows spells the same address with backslashes and a drive.
          Uri.parse('file:///home/kid/a%20cat.png').toFilePath(),
          Uri.parse('file:///tmp/b.jpg').toFilePath(),
        ],
      );
      expect(SystemClipboard.parseFileList(''), isEmpty);
      expect(SystemClipboard.parseFileList('file://%zz'), isEmpty);
    });
  });
}
