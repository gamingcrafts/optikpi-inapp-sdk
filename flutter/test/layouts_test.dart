import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optikpi_inapp/optikpi_inapp.dart';

class Taps {
  final List<String> log = [];
}

Future<Taps> pumpView(
  WidgetTester tester,
  PopupContent content, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final taps = Taps();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      home: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.white)),
          Positioned.fill(
            child: PopupView(
              content: content,
              onButton: (i) => taps.log.add('button $i'),
              onImageTap: () => taps.log.add('image'),
              onClose: () => taps.log.add('close'),
              onOutsideTap: () => taps.log.add('outside'),
            ),
          ),
        ],
      ),
    ),
  );
  return taps;
}

void main() {
  final samples = {for (final c in OptikpiInApp.sampleContents()) c.layout: c};

  test('one sample per layout', () {
    expect(samples.keys.toSet(), PopupLayout.values.toSet());
  });

  for (final layout in PopupLayout.values) {
    testWidgets('${layout.name}: draws without overflow and reports every tap', (tester) async {
      final content = samples[layout]!;
      final taps = await pumpView(tester, content);
      expect(tester.takeException(), isNull);
      expect(find.byKey(PopupKeys.card), findsOneWidget);
      if (content.title != null) expect(find.text(content.title!), findsOneWidget);

      for (var i = 0; i < content.buttons.length; i++) {
        await tester.tap(find.byKey(PopupKeys.button(i)));
        expect(find.text(content.buttons[i].label), findsOneWidget);
      }
      if (layout == PopupLayout.imageOnly) {
        await tester.tap(find.byKey(PopupKeys.image));
      }
      if (content.close.show) await tester.tap(find.byKey(PopupKeys.close));

      expect(taps.log, [
        for (var i = 0; i < content.buttons.length; i++) 'button $i',
        if (layout == PopupLayout.imageOnly) 'image',
        if (content.close.show) 'close',
      ]);
    });
  }

  testWidgets('tap outside closes only when tapOutsideToClose', (tester) async {
    final modal = samples[PopupLayout.modal]!;
    var taps = await pumpView(tester, modal);
    await tester.tapAt(const Offset(5, 5));
    expect(taps.log, ['outside']);

    final sticky =
        PopupContent.tryParse({
          ...modal.toJson(),
          'close': {'show': true, 'position': 'topLeft', 'tapOutsideToClose': false},
        })!;
    taps = await pumpView(tester, sticky);
    await tester.tapAt(const Offset(5, 5));
    expect(taps.log, isEmpty);
  });

  testWidgets('banner and toast leave the rest of the screen usable', (tester) async {
    for (final layout in [PopupLayout.banner, PopupLayout.toast]) {
      var behind = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => behind++,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
              Positioned.fill(
                child: PopupView(
                  content: samples[layout]!,
                  onButton: (_) {},
                  onImageTap: () {},
                  onClose: () {},
                  onOutsideTap: () {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.tapAt(const Offset(200, 500));
      expect(behind, 1, reason: layout.name);
    }
  });

  testWidgets('every size of every layout draws on a phone, a landscape phone and a tablet, '
      'with long text and large text', (tester) async {
    for (final screen in const [Size(360, 640), Size(800, 360), Size(1024, 1366)]) {
      for (final textScale in const [1.0, 2.0]) {
        for (final spec in PopupLayoutSpec.all.values) {
          for (final size in spec.sizes) {
            for (final position in spec.positions ?? const <PopupPosition?>[null]) {
              final json = samples[spec.layout]!.toJson();
              final content =
                  PopupContent.tryParse({
                    ...json,
                    'size': size.name,
                    if (position != null) 'position': position.name,
                    'title': 'A long title that goes on and on',
                    'body': 'A long body. ' * 20,
                    'buttons': [
                      for (final button in json['buttons'] as List)
                        {
                          ...button as Map<String, dynamic>,
                          'label': 'Claim your 100% welcome bonus now',
                        },
                    ],
                  })!;
              await pumpView(tester, content, size: screen, textScale: textScale);
              expect(
                tester.takeException(),
                isNull,
                reason: '${spec.layout.name} ${size.name} ${position?.name} on $screen x$textScale',
              );
            }
          }
        }
      }
    }
  });

  testWidgets('modal sizes follow MODAL_WIDTH on a phone', (tester) async {
    for (final (size, width) in [
      (PopupSize.sm, 390 * 0.72),
      (PopupSize.md, 390 * 0.84),
      (PopupSize.lg, 390 * 0.92),
      (PopupSize.iab_300x250, 300.0),
    ]) {
      final content =
          PopupContent.tryParse({...samples[PopupLayout.modal]!.toJson(), 'size': size.name})!;
      await pumpView(tester, content);
      final box = tester.getSize(find.byKey(PopupKeys.card));
      expect(box.width, moreOrLessEquals(width), reason: size.name);
      if (size == PopupSize.iab_300x250) expect(box.height, moreOrLessEquals(250));
    }
  });

  testWidgets('bottom sheet heights are 34 / 50 / 72 % of the screen', (tester) async {
    for (final (size, fraction) in [
      (PopupSize.sm, 0.34),
      (PopupSize.md, 0.50),
      (PopupSize.lg, 0.72),
    ]) {
      final content =
          PopupContent.tryParse({
            ...samples[PopupLayout.bottomSheet]!.toJson(),
            'size': size.name,
          })!;
      await pumpView(tester, content);
      expect(tester.getSize(find.byKey(PopupKeys.card)).height, moreOrLessEquals(844 * fraction));
    }
  });
}
