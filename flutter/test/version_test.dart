import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optikpi_popup/optikpi_popup.dart';

void main() {
  test('optikpiPopupVersion matches pubspec.yaml and CHANGELOG.md', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(optikpiPopupVersion, version);
    expect(File('CHANGELOG.md').readAsStringSync(), contains('## $version'));
  });
}
