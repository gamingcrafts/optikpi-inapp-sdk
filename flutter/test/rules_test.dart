import 'package:flutter_test/flutter_test.dart';
import 'package:optikpi_inapp/optikpi_inapp.dart';
import 'package:optikpi_inapp/src/logic/fetch_throttle.dart';
import 'package:optikpi_inapp/src/logic/show_rules.dart';

InAppPopup popup(String id, {required DateTime createdAt, DateTime? expiresAt}) => InAppPopup(
  id: id,
  trackingId: 'trk-$id',
  createdAt: createdAt,
  expiresAt: expiresAt,
  content: const PopupContent(layout: PopupLayout.modal, size: PopupSize.md),
);

void main() {
  group('FetchThrottle', () {
    final t0 = DateTime.utc(2026, 10, 1);

    test('the first fetch is always allowed', () {
      expect(FetchThrottle().canFetch(t0), isTrue);
    });

    test('waits nextCheckAfterSec from the last response', () {
      final throttle = FetchThrottle()..recordResponse(t0, 120);
      expect(throttle.canFetch(t0.add(const Duration(seconds: 119))), isFalse);
      expect(throttle.canFetch(t0.add(const Duration(seconds: 120))), isTrue);
    });

    test('defaults to 300 s and clamps the server value', () {
      final throttle = FetchThrottle()..recordResponse(t0, null);
      expect(throttle.interval, const Duration(seconds: 300));
      throttle.recordResponse(t0, 1);
      expect(throttle.interval, const Duration(seconds: FetchThrottle.minIntervalSec));
      throttle.recordResponse(t0, 999999999);
      expect(throttle.interval, const Duration(seconds: FetchThrottle.maxIntervalSec));
    });
  });

  group('isRouteBlocked', () {
    const blocked = ['/dashboard/games/play', '/dashboard/deposit/'];
    for (final (route, expected) in [
      ('/dashboard/games/play', true),
      ('/dashboard/games/play?title=Coin', true),
      ('/dashboard/games/play/42', true),
      ('/dashboard/games', false),
      ('/dashboard/deposit', true),
      ('/dashboard/deposit-log', false),
      ('/dashboard', false),
      (null, false),
    ]) {
      test('$route → $expected', () => expect(isRouteBlocked(route, blocked), expected));
    }
  });

  group('pickPopupToShow', () {
    final now = DateTime.utc(2026, 10, 10);
    final older = popup('older', createdAt: DateTime.utc(2026, 10, 1));
    final newer = popup('newer', createdAt: DateTime.utc(2026, 10, 5));
    final expired = popup(
      'expired',
      createdAt: DateTime.utc(2026, 10, 9),
      expiresAt: DateTime.utc(2026, 10, 9, 12),
    );

    InAppPopup? pick({
      List<InAppPopup>? waiting,
      Set<String> shown = const {},
      String? route = '/dashboard',
    }) => pickPopupToShow(
      waiting: waiting ?? [older, newer, expired],
      shownIds: shown,
      route: route,
      blockedRoutes: const ['/dashboard/deposit'],
      now: now,
    );

    test('newest first, whatever the order received', () {
      expect(pick()!.id, 'newer');
      expect(pick(waiting: [newer, older])!.id, 'newer');
    });
    test('skips expired', () => expect(pick(waiting: [expired, older])!.id, 'older'));
    test('skips already shown', () => expect(pick(shown: {'newer'})!.id, 'older'));
    test('nothing on a blocked route', () => expect(pick(route: '/dashboard/deposit'), isNull));
    test('nothing before the first screen is known', () => expect(pick(route: null), isNull));
    test('nothing left', () => expect(pick(shown: {'newer', 'older'}), isNull));
  });
}
