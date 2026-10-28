import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:optikpi_inapp/optikpi_inapp.dart';
import 'package:optikpi_inapp/src/source/mock_templates.dart';

import 'support/contract_fixtures.dart';

void main() {
  group('contract/fixtures/content-cases.json', () {
    final fixture = readFixture('content-cases.json') as Map<String, dynamic>;
    final base = fixture['base'] as Map<String, dynamic>;
    for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final content = PopupContent.tryParse(contentCaseInput(base, c));
        if (c['expect'] == null) {
          expect(content, isNull);
        } else {
          expect(content, isNotNull);
          expectMatchesFixture(content!.toJson(), c['expect']);
        }
      });
    }
  });

  group('contract/fixtures/layouts', () {
    final files =
        Directory('${contractFixtures.path}/layouts').listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    test('one file per layout', () {
      expect(
        files.map((f) => f.uri.pathSegments.last).toSet(),
        PopupLayout.values.map((l) => '${l.name}.json').toSet(),
      );
    });

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      test('$name parses and matches the bundled template of its layout', () {
        final json = readFixture('layouts/$name') as Map<String, dynamic>;
        final content = PopupContent.tryParse(json);
        expect(content, isNotNull);
        expect(content!.layout.name, json['layout']);
        // The mock source serves these, so a fixture edit must reach the templates too.
        final template = mockPopupTemplates.firstWhere(
          (t) => t.content['layout'] == json['layout'],
        );
        expect(template.content, json);
      });
    }
  });

  group('contract/fixtures/fetch-response-cases.json', () {
    final fixture = readFixture('fetch-response-cases.json') as Map<String, dynamic>;
    for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final result = PopupFetchResult.fromJson(c['response']);
        expect(result.popups.map((p) => p.id).toList(), c['expectIds']);
        expect(result.nextCheckAfterSec, c['expectNextCheckAfterSec']);
      });
    }
  });

  test('gradient image colours', () {
    final image = PopupImage.tryParse({'url': 'gradient:#7F56D9,#F04438'})!;
    expect(image.isGradient, isTrue);
    expect(image.gradientColors, [const Color(0xFF7F56D9), const Color(0xFFF04438)]);
    final bad = PopupImage.tryParse({'url': 'gradient:nope'})!;
    expect(bad.gradientColors, hasLength(2));
  });

  test('isDarkBackground matches the reference rule', () {
    expect(const PopupTheme(background: Color(0xFF101828)).isDarkBackground, isTrue);
    expect(const PopupTheme(background: Color(0xFFFFFFFF)).isDarkBackground, isFalse);
  });

  test('toJson round-trips', () {
    final content = PopupContent.tryParse(readFixture('layouts/modal.json'))!;
    final again = PopupContent.tryParse(content.toJson())!;
    expect(again.toJson(), content.toJson());
  });

  test('every bundled template parses, and all 6 layouts are covered', () {
    final parsed = mockPopupTemplates.map((t) => PopupContent.tryParse(t.content)).toList();
    expect(parsed, everyElement(isNotNull));
    expect(parsed.map((c) => c!.layout).toSet(), PopupLayout.values.toSet());
  });

  test('InAppPopup dates parse to UTC; expiry is exclusive of the end', () {
    final popup =
        InAppPopup.tryParse({
          'id': 'a',
          'trackingId': 't',
          'createdAt': '2026-10-01T12:00:00+02:00',
          'expiresAt': '2026-10-02T00:00:00Z',
          'content': {'layout': 'modal'},
        })!;
    expect(popup.createdAt, DateTime.utc(2026, 10, 1, 10));
    expect(popup.isExpiredAt(DateTime.utc(2026, 10, 1, 23, 59)), isFalse);
    expect(popup.isExpiredAt(DateTime.utc(2026, 10, 2)), isTrue);
  });

  test('mock pop-up ids are per player, like the server\'s', () async {
    PopupRequestContext player(String id) => PopupRequestContext(
      baseUrl: defaultInAppBaseUrl,
      workspaceId: 'ws1',
      playerId: id,
      apiKey: 'key',
    );
    final a = await PopupSource.mock().fetch(player('p1'));
    final b = await PopupSource.mock().fetch(player('p2'));
    expect(
      a.popups.map((p) => p.id).toSet().intersection(b.popups.map((p) => p.id).toSet()),
      isEmpty,
    );
    expect(
      a.popups
          .map((p) => p.trackingId)
          .toSet()
          .intersection(b.popups.map((p) => p.trackingId).toSet()),
      isEmpty,
    );
  });
}
