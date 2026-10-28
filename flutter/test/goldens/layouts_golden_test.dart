@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optikpi_popup/optikpi_popup.dart';

/* Screenshots of the 6 layouts on a 390 × 844 phone, for the PR and the README.
   `flutter test --tags golden --update-goldens` writes them to test/goldens/<layout>.png.
   They use the Roboto that ships in the Flutter SDK cache so text is real text, not the
   test font's boxes; without it (FLUTTER_ROOT unset) the test is skipped. */

Future<bool> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return false;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return false;
  final loader = FontLoader('Roboto');
  for (final file in dir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.startsWith('Roboto-') && name.endsWith('.ttf')) {
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
  }
  await loader.load();
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
  return true;
}

void main() {
  final samples = OptikpiPopup.sampleContents(playerData: {'first_name': 'Carlos'});

  for (final content in samples) {
    testWidgets('golden: ${content.layout.name}', (tester) async {
      if (!await _loadRoboto()) {
        markTestSkipped('FLUTTER_ROOT not set: no real font to render with');
        return;
      }
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      tester.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
          home: RepaintBoundary(
            key: const ValueKey('screen'),
            child: Stack(
              children: [
                const Positioned.fill(child: _FakeScreen()),
                Positioned.fill(
                  child: PopupView(
                    content: content,
                    onButton: (_) {},
                    onImageTap: () {},
                    onClose: () {},
                    onOutsideTap: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await expectLater(
        find.byKey(const ValueKey('screen')),
        matchesGoldenFile('${content.layout.name}.png'),
      );
    });
  }
}

/// A stand-in casino lobby so the overlay and the non-blocking layouts read in context.
class _FakeScreen extends StatelessWidget {
  const _FakeScreen();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OptiKPI Casino',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              for (final colour in const [Color(0xFF7C3AED), Color(0xFF0EA5E9), Color(0xFFF59E0B)])
                Container(
                  height: 120,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(12)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
