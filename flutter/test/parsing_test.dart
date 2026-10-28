import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:optikpi_popup/optikpi_popup.dart';
import 'package:optikpi_popup/src/source/mock_templates.dart';

Map<String, dynamic> base({Map<String, dynamic> overrides = const {}}) => {
  'version': 1,
  'layout': 'modal',
  'size': 'md',
  'title': 'Hello',
  'body': 'Body',
  'buttons': [
    {
      'label': 'Go',
      'style': 'primary',
      'action': {'type': 'deeplink', 'value': 'app://cashier'},
    },
  ],
  'close': {'show': true, 'position': 'topRight', 'tapOutsideToClose': true},
  'theme': {
    'background': '#101828',
    'text': '#FFFFFF',
    'primary': '#F79009',
    'overlayOpacity': 0.7,
    'radius': 16,
  },
  ...overrides,
};

void main() {
  group('PopupContent.tryParse: shapes', () {
    final cases = <(String, Object?, void Function(PopupContent?))>[
      (
        'a full modal',
        base(),
        (c) {
          expect(c!.layout, PopupLayout.modal);
          expect(c.size, PopupSize.md);
          expect(c.buttons.single.action.type, PopupActionType.deeplink);
          expect(c.theme.background, const Color(0xFF101828));
          expect(c.position, isNull);
          expect(c.autoDismissSec, isNull);
        },
      ),
      ('not a map', 'modal', (c) => expect(c, isNull)),
      ('null', null, (c) => expect(c, isNull)),
      ('unknown layout', base(overrides: {'layout': 'carousel'}), (c) => expect(c, isNull)),
      ('missing layout', base()..remove('layout'), (c) => expect(c, isNull)),
      ('version 2', base(overrides: {'version': 2}), (c) => expect(c, isNull)),
      ('missing version is 1', base()..remove('version'), (c) => expect(c, isNotNull)),
      (
        'unknown fields ignored',
        base(overrides: {'sparkle': true, 'theme2': {}}),
        (c) => expect(c, isNotNull),
      ),
      (
        'missing size takes the first allowed',
        base()..remove('size'),
        (c) => expect(c!.size, PopupSize.sm),
      ),
      (
        'size the layout does not allow',
        base(overrides: {'layout': 'fullscreen', 'size': 'sm'}),
        (c) => expect(c!.size, PopupSize.lg),
      ),
      ('missing buttons', base()..remove('buttons'), (c) => expect(c!.buttons, isEmpty)),
      ('buttons not a list', base(overrides: {'buttons': 'x'}), (c) => expect(c!.buttons, isEmpty)),
      (
        'three buttons keep two',
        base(
          overrides: {
            'buttons': List.generate(
              3,
              (i) => {
                'label': 'B$i',
                'style': 'primary',
                'action': {'type': 'dismiss'},
              },
            ),
          },
        ),
        (c) => expect(c!.buttons.map((b) => b.label), ['B0', 'B1']),
      ),
      (
        'banner keeps one button',
        base(
          overrides: {
            'layout': 'banner',
            'buttons': List.generate(
              2,
              (i) => {
                'label': 'B$i',
                'style': 'primary',
                'action': {'type': 'dismiss'},
              },
            ),
          },
        ),
        (c) => expect(c!.buttons, hasLength(1)),
      ),
      (
        'imageOnly drops buttons and text',
        base(overrides: {'layout': 'imageOnly'}),
        (c) {
          expect(c!.buttons, isEmpty);
          expect(c.title, isNull);
          expect(c.body, isNull);
        },
      ),
      (
        'unknown action type drops the button',
        base(
          overrides: {
            'buttons': [
              {
                'label': 'X',
                'style': 'primary',
                'action': {'type': 'teleport'},
              },
              {
                'label': 'Y',
                'style': 'primary',
                'action': {'type': 'dismiss'},
              },
            ],
          },
        ),
        (c) => expect(c!.buttons.map((b) => b.label), ['Y']),
      ),
      (
        'deeplink without a value acts as dismiss',
        base(
          overrides: {
            'buttons': [
              {
                'label': 'X',
                'style': 'primary',
                'action': {'type': 'deeplink', 'value': ' '},
              },
            ],
          },
        ),
        (c) => expect(c!.buttons.single.action.type, PopupActionType.dismiss),
      ),
      (
        'unknown button style is primary',
        base(
          overrides: {
            'buttons': [
              {
                'label': 'X',
                'style': 'ghost',
                'action': {'type': 'dismiss'},
              },
            ],
          },
        ),
        (c) => expect(c!.buttons.single.style, PopupButtonStyle.primary),
      ),
      (
        'bad colours fall back one by one',
        base(
          overrides: {
            'theme': {
              'background': 'red',
              'text': '#12',
              'primary': '#GGGGGG',
              'overlayOpacity': 3,
              'radius': -4,
            },
          },
        ),
        (c) {
          const fallback = PopupTheme();
          expect(c!.theme.background, fallback.background);
          expect(c.theme.text, fallback.text);
          expect(c.theme.primary, fallback.primary);
          expect(c.theme.overlayOpacity, 1.0);
          expect(c.theme.radius, fallback.radius);
        },
      ),
      (
        'short and alpha hex colours',
        base(
          overrides: {
            'theme': {'background': '#fff', 'text': '#10182880', 'primary': '#7F56D9'},
          },
        ),
        (c) {
          expect(c!.theme.background, const Color(0xFFFFFFFF));
          expect(c.theme.text, const Color(0x80101828));
        },
      ),
      (
        'missing theme and close get defaults',
        base()
          ..remove('theme')
          ..remove('close'),
        (c) {
          expect(c!.theme.background, const PopupTheme().background);
          expect(c.close.show, isTrue);
          expect(c.close.tapOutsideToClose, isTrue);
        },
      ),
      (
        'banner without position is top, autoDismiss defaults to 8',
        base(overrides: {'layout': 'banner'}),
        (c) {
          expect(c!.position, PopupPosition.top);
          expect(c.autoDismissSec, 8);
        },
      ),
      (
        'toast with a banner position takes topRight',
        base(overrides: {'layout': 'toast', 'size': 'sm', 'position': 'bottom'}),
        (c) => expect(c!.position, PopupPosition.topRight),
      ),
      (
        'autoDismissSec 0 means stay up',
        base(overrides: {'layout': 'toast', 'autoDismissSec': 0}),
        (c) => expect(c!.autoDismissSec, isNull),
      ),
      (
        'autoDismissSec on a modal is ignored',
        base(overrides: {'autoDismissSec': 5}),
        (c) => expect(c!.autoDismissSec, isNull),
      ),
      (
        'image without url is no image',
        base(
          overrides: {
            'image': {'alt': 'x'},
          },
        ),
        (c) => expect(c!.image, isNull),
      ),
      (
        'image tapAction parsed',
        base(
          overrides: {
            'image': {
              'url': 'https://cdn.example/a.png',
              'tapAction': {'type': 'url', 'value': 'https://example.com'},
            },
          },
        ),
        (c) => expect(c!.image!.tapAction!.type, PopupActionType.url),
      ),
      (
        'wrong types everywhere still parse',
        base(
          overrides: {
            'title': 5,
            'body': ['x'],
            'close': 'yes',
            'mergeTags': 'x',
          },
        ),
        (c) {
          expect(c!.title, isNull);
          expect(c.body, isNull);
          expect(c.close.show, isTrue);
          expect(c.mergeTags, isNull);
        },
      ),
      (
        'delivery is carried',
        base(
          overrides: {
            'delivery': {
              'availableFor': {'value': 3, 'unit': 'days'},
              'timeZone': 'UTC',
            },
          },
        ),
        (c) => expect(c!.delivery!.unit, PopupDeliveryUnit.days),
      ),
    ];

    for (final (name, json, check) in cases) {
      test(name, () => check(PopupContent.tryParse(json)));
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
    final content = PopupContent.tryParse(base())!;
    final again = PopupContent.tryParse(content.toJson())!;
    expect(again.toJson(), content.toJson());
  });

  test('every bundled template parses, and all 6 layouts are covered', () {
    final parsed = mockPopupTemplates.map((t) => PopupContent.tryParse(t.content)).toList();
    expect(parsed, everyElement(isNotNull));
    expect(parsed.map((c) => c!.layout).toSet(), PopupLayout.values.toSet());
  });

  group('InAppPopup / PopupFetchResult', () {
    final content = base();

    test('skips entries without id, trackingId or valid content, keeps the rest', () {
      final result = PopupFetchResult.fromJson({
        'popups': [
          {'id': 'a', 'trackingId': 't', 'createdAt': '2026-10-01T00:00:00Z', 'content': content},
          {'trackingId': 't', 'content': content},
          {'id': 'b', 'content': content},
          {
            'id': 'c',
            'trackingId': 't',
            'content': {...content, 'layout': 'nope'},
          },
          'garbage',
        ],
        'nextCheckAfterSec': 120,
      });
      expect(result.popups.map((p) => p.id), ['a']);
      expect(result.nextCheckAfterSec, 120);
    });

    test('empty or wrong body is an empty result', () {
      expect(PopupFetchResult.fromJson(null).popups, isEmpty);
      expect(PopupFetchResult.fromJson({'popups': 'x'}).popups, isEmpty);
      expect(PopupFetchResult.fromJson({}).nextCheckAfterSec, isNull);
    });

    test('dates parse to UTC; expiry is exclusive of the end', () {
      final popup =
          InAppPopup.tryParse({
            'id': 'a',
            'trackingId': 't',
            'createdAt': '2026-10-01T12:00:00+02:00',
            'expiresAt': '2026-10-02T00:00:00Z',
            'content': content,
          })!;
      expect(popup.createdAt, DateTime.utc(2026, 10, 1, 10));
      expect(popup.isExpiredAt(DateTime.utc(2026, 10, 1, 23, 59)), isFalse);
      expect(popup.isExpiredAt(DateTime.utc(2026, 10, 2)), isTrue);
    });
  });

  test('mock pop-up ids are per player, like the server\'s', () async {
    PopupRequestContext player(String id) => PopupRequestContext(
      baseUrl: defaultPopupBaseUrl,
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
