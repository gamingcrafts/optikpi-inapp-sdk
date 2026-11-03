import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optikpi_inapp/src/render/popup_image_cache.dart';

// The real PopupImageCache against a fake server. The controller tests stub `load`, which is
// how a load that never completed reached 0.3.0: every pop-up with an image URL waited forever.

const url = 'https://img.test/a.avif';

// A regression makes a load never complete: fail in seconds, not at the 30 s default.
const fast = Timeout(Duration(seconds: 3));

void main() {
  late int requests;
  late Completer<void>? gate;

  PopupImageCache cache({int status = 200, Object? error}) => PopupImageCache(
    client: MockClient((request) async {
      requests++;
      if (gate != null) await gate!.future;
      if (error != null) throw error;
      return http.Response.bytes(status == 200 ? [1, 2, 3] : const [], status);
    }),
  );

  setUp(() {
    requests = 0;
    gate = null;
  });

  test('a load completes with the bytes and keeps them', () async {
    final images = cache();
    expect(await images.load(url), [1, 2, 3]);
    expect(images.peek(url), [1, 2, 3]);
    expect(await images.load(url), [1, 2, 3]);
    expect(requests, 1, reason: 'the second load is served from memory');
  }, timeout: fast);

  test('loads of one URL in flight share one request, and all complete', () async {
    gate = Completer<void>();
    final images = cache();
    final first = images.load(url);
    final second = images.load(url);
    gate!.complete();
    expect(await Future.wait([first, second]), [
      [1, 2, 3],
      [1, 2, 3],
    ]);
    expect(requests, 1);
  }, timeout: fast);

  test('a failed load completes with null, and the next load asks again', () async {
    for (final images in [cache(status: 404), cache(error: Exception('offline'))]) {
      requests = 0;
      expect(await images.load(url), isNull);
      expect(await images.load(url), isNull);
      expect(requests, 2);
    }
  }, timeout: fast);

  test('a URL that is not http(s) is not requested', () async {
    final images = cache();
    expect(await images.load('data:image/png;base64,AAAA'), isNull);
    expect(requests, 0);
  }, timeout: fast);

  testWidgets('a load with no answer completes with null after the timeout', (tester) async {
    gate = Completer<void>();
    final images = cache();
    Object? result = 'pending';
    unawaited(images.load(url).then((bytes) => result = bytes));
    await tester.pump(PopupImageCache.timeout - const Duration(seconds: 1));
    expect(result, 'pending');
    await tester.pump(const Duration(seconds: 2));
    expect(result, isNull);
  });
}
