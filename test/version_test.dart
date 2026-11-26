import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thinkspace/version.dart';

void main() {
  test('the version shown is the one in pubspec.yaml', () {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final version = line.split(':')[1].trim().split('+').first;
    expect(
      appVersion,
      version,
      reason: 'raise appVersion in lib/version.dart with pubspec.yaml',
    );
  });
}
