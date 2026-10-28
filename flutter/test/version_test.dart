import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optikpi_inapp/optikpi_inapp.dart';

void main() {
  test('optikpiInAppVersion matches pubspec.yaml and CHANGELOG.md', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(optikpiInAppVersion, version);
    expect(File('CHANGELOG.md').readAsStringSync(), contains('## $version'));
  });
}
