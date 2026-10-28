import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fixtures every SDK in the repo shares, at `contract/fixtures` next to `flutter/`.
/// `flutter test` runs from the package directory.
final Directory contractFixtures = Directory('../contract/fixtures');

Object? readFixture(String path) =>
    jsonDecode(File('${contractFixtures.path}/$path').readAsStringSync());

/// The input of one `content-cases.json` case, built as its `about` describes.
Object? contentCaseInput(Map<String, dynamic> base, Map<String, dynamic> c) {
  if (c.containsKey('content')) return c['content'];
  return {...base, ...?c['set'] as Map<String, dynamic>?}
    ..removeWhere((key, _) => (c['remove'] as List? ?? const []).contains(key));
}

/// Fails unless [actual] matches [expected] the way the fixtures define it: objects on the keys
/// listed, arrays in length and element by element, null as absent or null.
void expectMatchesFixture(Object? actual, Object? expected, [String at = r'$']) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: '$at should be an object');
    final map = actual as Map;
    for (final MapEntry(:key, :value) in expected.entries) {
      expectMatchesFixture(map[key], value, '$at.$key');
    }
  } else if (expected is List) {
    expect(actual, isA<List>(), reason: '$at should be an array');
    final list = actual as List;
    expect(list, hasLength(expected.length), reason: '$at length');
    for (var i = 0; i < expected.length; i++) {
      expectMatchesFixture(list[i], expected[i], '$at[$i]');
    }
  } else {
    expect(actual, expected, reason: at);
  }
}
