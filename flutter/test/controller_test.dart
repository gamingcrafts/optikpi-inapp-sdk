import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optikpi_popup/optikpi_popup.dart';
import 'package:optikpi_popup/src/render/popup_image_cache.dart';
import 'package:optikpi_popup/src/route_observer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_source.dart';

const ctx = PopupRequestContext(
  baseUrl: 'https://inapp.test',
  workspaceId: 'ws1',
  playerId: 'p1',
  apiKey: 'key',
);

class Harness {
  Harness(this.tester, {FakeSource? source, this.images}) : source = source ?? FakeSource();

  final PopupImageCache? images;

  final WidgetTester tester;
  final FakeSource source;
  DateTime now = DateTime.utc(2026, 10, 10, 12);
  final List<String> deepLinks = [];
  final List<Uri> launched = [];
  late final OptikpiPopupController controller = OptikpiPopupController(
    images: images,
    clock: () => now,
    launchUrl: (uri) async {
      launched.add(uri);
      return true;
    },
    flushDelay: const Duration(milliseconds: 100),
  );

  Future<void> pumpApp({Widget? home}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => PopupHost(controller: controller, child: child!),
        home: home ?? const Scaffold(body: Text('screen')),
      ),
    );
  }

  Future<void> init({List<String> blockedRoutes = const []}) async {
    await controller.init(
      context: ctx,
      source: source,
      onDeepLink: deepLinks.add,
      blockedRoutes: blockedRoutes,
    );
    await settle();
  }

  /// Lets fetches, prefs writes, post-frame callbacks and the event flush timer finish.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await controller.lastFetch;
    await controller.lastShow;
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> route(String route) async {
    controller.didChangeRoute(route);
    await settle();
  }

  String? get shownId => controller.current.value?.popup.id;

  Future<void> tap(Key key) async {
    await tester.tap(find.byKey(key));
    await settle();
  }

  Future<void> dispose() async {
    controller.reset();
    await tester.pumpWidget(const SizedBox());
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('fetch', () {
    testWidgets('on init, then at most once per nextCheckAfterSec on route changes', (
      tester,
    ) async {
      final h = Harness(
        tester,
        source: FakeSource(result: const PopupFetchResult(popups: [], nextCheckAfterSec: 120)),
      );
      await h.pumpApp();
      await h.route('/dashboard');
      await h.init();
      expect(h.source.fetches, 1);

      h.now = h.now.add(const Duration(seconds: 119));
      await h.route('/dashboard/games');
      expect(h.source.fetches, 1);

      h.now = h.now.add(const Duration(seconds: 1));
      await h.route('/dashboard/profile');
      expect(h.source.fetches, 2);
      await h.dispose();
    });

    testWidgets('a failed fetch is silent and retried at the next fetch moment', (tester) async {
      final h = Harness(tester, source: FakeSource()..failFetches = 1);
      await h.pumpApp();
      await h.init();
      expect(h.source.fetches, 1);
      await h.route('/dashboard/games');
      expect(h.source.fetches, 2);
      await h.route('/dashboard/profile');
      expect(h.source.fetches, 2, reason: 'the second fetch succeeded, so the throttle applies');
      await h.dispose();
    });

    testWidgets('on return to the foreground, never in the background', (tester) async {
      final h = Harness(tester);
      await h.pumpApp();
      await h.init();
      expect(h.source.fetches, 1);
      h.now = h.now.add(const Duration(minutes: 10));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await h.route('/dashboard/games'); // a route change while paused
      expect(h.source.fetches, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await h.settle();
      expect(h.source.fetches, 2);
      await h.dispose();
    });

    testWidgets('a logout while a fetch is in flight drops its result', (tester) async {
      final gate = Completer<void>();
      final h = Harness(
        tester,
        source: FakeSource(result: PopupFetchResult(popups: [inApp('a')]))..fetchGate = gate.future,
      );
      await h.pumpApp();
      await h.route('/dashboard');
      unawaited(h.controller.init(context: ctx, source: h.source));
      await tester.pump();
      await h.controller.logout();
      gate.complete();
      await h.settle();
      expect(h.shownId, isNull);
      await h.dispose();
    });
  });

  group('show', () {
    testWidgets('one per screen visit, newest first', (tester) async {
      final h = Harness(
        tester,
        source: FakeSource(
          result: PopupFetchResult(
            popups: [
              inApp('old', createdAt: DateTime.utc(2026, 10, 1)),
              inApp('new', createdAt: DateTime.utc(2026, 10, 2)),
            ],
          ),
        ),
      );
      await h.pumpApp();
      await h.route('/dashboard');
      await h.init();
      expect(h.shownId, 'new');
      await h.tap(PopupKeys.close);
      expect(h.shownId, isNull, reason: 'one per visit: the second waits for the next screen');

      await h.route('/dashboard/games');
      expect(h.shownId, 'old');
      await h.dispose();
    });

    testWidgets('never on a blocked route; shows on the next allowed one', (tester) async {
      final h = Harness(tester, source: FakeSource(result: PopupFetchResult(popups: [inApp('a')])));
      await h.pumpApp();
      await h.route('/dashboard/games/play');
      await h.init(blockedRoutes: ['/dashboard/games/play']);
      expect(h.shownId, isNull);
      await h.route('/dashboard');
      expect(h.shownId, 'a');
      await h.dispose();
    });

    testWidgets('skips expired pop-ups', (tester) async {
      final h = Harness(tester);
      h.source.result = PopupFetchResult(
        popups: [inApp('gone', expiresAt: h.now.subtract(const Duration(minutes: 1)))],
      );
      await h.pumpApp();
      await h.route('/dashboard');
      await h.init();
      expect(h.shownId, isNull);
      await h.dispose();
    });

    testWidgets('a pop-up shown once is never shown again, even after a restart', (tester) async {
      final source = FakeSource(result: PopupFetchResult(popups: [inApp('a')]));
      final first = Harness(tester, source: source);
      await first.pumpApp();
      await first.route('/dashboard');
      await first.init();
      expect(first.shownId, 'a');
      await first.tap(PopupKeys.close);
      await first.dispose();

      final second = Harness(tester, source: source); // new controller, same prefs
      await second.pumpApp();
      await second.route('/dashboard');
      await second.init();
      expect(second.shownId, isNull);
      await second.dispose();
    });

    testWidgets('logout closes the pop-up and drops the waiting ones', (tester) async {
      final h = Harness(
        tester,
        source: FakeSource(result: PopupFetchResult(popups: [inApp('a'), inApp('b')])),
      );
      await h.pumpApp();
      await h.route('/dashboard');
      await h.init();
      expect(h.shownId, isNotNull);
      await h.controller.logout();
      await h.settle();
      expect(h.shownId, isNull);
      await h.route('/dashboard/games');
      expect(h.shownId, isNull);
      await h.dispose();
    });
  });

  group('act and track', () {
    Future<Harness> showing(WidgetTester tester, InAppPopup popup) async {
      final h = Harness(tester, source: FakeSource(result: PopupFetchResult(popups: [popup])));
      await h.pumpApp();
      await h.route('/dashboard');
      await h.init();
      expect(h.shownId, popup.id);
      return h;
    }

    testWidgets('impression on draw, click with buttonIndex, deeplink to onDeepLink', (
      tester,
    ) async {
      final h = await showing(tester, inApp('a'));
      expect(h.source.sentEvents.map((e) => e.type), [PopupEventType.impression]);
      await h.tap(PopupKeys.button(0));
      expect(h.shownId, isNull);
      expect(h.deepLinks, ['app://cashier']);
      final click = h.source.sentEvents.last;
      expect(click.type, PopupEventType.click);
      expect(click.buttonIndex, 0);
      expect(click.trackingId, 'trk-a');
      await h.dispose();
    });

    testWidgets('a dismiss button is a click, not a dismiss', (tester) async {
      final h = await showing(tester, inApp('a'));
      await h.tap(PopupKeys.button(1));
      expect(h.source.sentEvents.map((e) => e.type), [
        PopupEventType.impression,
        PopupEventType.click,
      ]);
      expect(h.deepLinks, isEmpty);
      await h.dispose();
    });

    testWidgets('tap outside is a dismiss', (tester) async {
      final h = await showing(tester, inApp('a'));
      await tester.tapAt(const Offset(5, 5));
      await h.settle();
      expect(h.shownId, isNull);
      expect(h.source.sentEvents.last.type, PopupEventType.dismiss);
      await h.dispose();
    });

    testWidgets('a url action opens externally', (tester) async {
      final popup = InAppPopup(
        id: 'u',
        trackingId: 'trk-u',
        createdAt: DateTime.utc(2026),
        content: const PopupContent(
          layout: PopupLayout.modal,
          size: PopupSize.md,
          title: 'T',
          buttons: [
            PopupButton(
              label: 'Open',
              style: PopupButtonStyle.primary,
              action: PopupAction(type: PopupActionType.url, value: 'https://example.com/vip'),
            ),
          ],
        ),
      );
      final h = await showing(tester, popup);
      await h.tap(PopupKeys.button(0));
      expect(h.launched, [Uri.parse('https://example.com/vip')]);
      await h.dispose();
    });

    testWidgets('auto-dismiss reports a dismiss after autoDismissSec', (tester) async {
      final h = await showing(tester, inApp('t', layout: PopupLayout.toast, autoDismissSec: 3));
      await tester.pump(const Duration(seconds: 2));
      expect(h.shownId, 't');
      await tester.pump(const Duration(seconds: 1));
      await h.settle();
      expect(h.shownId, isNull);
      expect(h.source.sentEvents.last.type, PopupEventType.dismiss);
      await h.dispose();
    });

    testWidgets('an auto-dismiss timer never closes the pop-up that replaced it', (tester) async {
      final h = await showing(tester, inApp('t', layout: PopupLayout.toast, autoDismissSec: 3));
      final stale = h.controller.current.value!;
      h.controller.showTest(content(PopupLayout.modal));
      await tester.pump();
      expect(h.controller.close(stale, dismissed: true), isFalse);
      await tester.pump(const Duration(seconds: 4));
      expect(h.controller.current.value?.isTest, isTrue);
      await h.dispose();
    });

    testWidgets('events are queued while offline and sent once back online', (tester) async {
      final h = Harness(
        tester,
        source: FakeSource(result: PopupFetchResult(popups: [inApp('a')]))..failSends = 1,
      );
      await h.pumpApp();
      await h.route('/dashboard');
      await h.init();
      expect(h.source.sentEvents, isEmpty);
      await h.tap(PopupKeys.close);
      final events = h.source.sentEvents.map((e) => e.dedupeKey).toList();
      expect(events, ['trk-a|impression', 'trk-a|dismiss']);
      await h.dispose();
    });

    testWidgets('Android back closes a modal and stays on the page', (tester) async {
      final h = Harness(tester, source: FakeSource(result: PopupFetchResult(popups: [inApp('a')])));
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          // Registered with the binding before the pop-up's controller, as in a real app.
          navigatorObservers: [
            PopupRouteObserver(h.controller.didChangeRoute, controller: h.controller),
          ],
          builder: (context, child) => PopupHost(controller: h.controller, child: child!),
          home: const Text('first'),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/second'),
          builder: (_) => const Text('second'),
        ),
      );
      await tester.pumpAndSettle();
      await h.init();
      expect(h.shownId, 'a');

      await tester.binding.handlePopRoute();
      await h.settle();
      expect(h.shownId, isNull);
      expect(find.text('second'), findsOneWidget);
      expect(h.source.sentEvents.last.type, PopupEventType.dismiss);
      await h.dispose();
    });

    testWidgets('back goes to the page under a banner, and after a pop-up is closed', (
      tester,
    ) async {
      final h = Harness(
        tester,
        source: FakeSource(
          result: PopupFetchResult(
            popups: [
              inApp('m', createdAt: DateTime.utc(2026, 10, 9)),
              inApp('b', layout: PopupLayout.banner, createdAt: DateTime.utc(2026, 10, 8)),
            ],
          ),
        ),
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [
            PopupRouteObserver(h.controller.didChangeRoute, controller: h.controller),
          ],
          builder: (context, child) => PopupHost(controller: h.controller, child: child!),
          onGenerateRoute:
              (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => Text('page ${settings.name}'),
              ),
        ),
      );
      for (final name in ['/a', '/b']) {
        navigatorKey.currentState!.pushNamed(name);
        await tester.pumpAndSettle();
      }
      await h.init();
      expect(h.shownId, 'm');
      await h.tap(PopupKeys.close);
      expect(h.shownId, isNull);

      await tester.binding.handlePopRoute(); // nothing open: back leaves /b
      await h.settle();
      expect(find.text('page /a'), findsOneWidget);
      expect(h.shownId, 'b'); // the visit to /a shows the next one

      await tester.binding.handlePopRoute(); // a banner doesn't hold back
      await h.settle();
      expect(find.text('page /'), findsOneWidget);
      await h.dispose();
    });

    testWidgets('test pop-ups send nothing and are not remembered', (tester) async {
      final h = Harness(tester);
      await h.pumpApp();
      await h.init();
      h.controller.showTest(content(PopupLayout.modal));
      await h.settle();
      await h.tap(PopupKeys.button(0));
      expect(h.source.sentEvents, isEmpty);
      expect(h.deepLinks, ['app://cashier']);
      await h.dispose();
    });
  });

  group('review round 1', () {
    Future<GlobalKey<NavigatorState>> pumpNavigatorApp(
      WidgetTester tester,
      Harness h, {
      bool appBar = false,
    }) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [
            PopupRouteObserver(h.controller.didChangeRoute, controller: h.controller),
          ],
          builder: (context, child) => PopupHost(controller: h.controller, child: child!),
          onGenerateRoute:
              (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder:
                    (_) => Scaffold(
                      appBar: appBar ? AppBar(title: Text('bar ${settings.name}')) : null,
                      body: ElevatedButton(onPressed: () {}, child: Text('page ${settings.name}')),
                    ),
              ),
        ),
      );
      await tester.pumpAndSettle();
      return key;
    }

    testWidgets('a banner still up is hidden when the player moves to a blocked route', (
      tester,
    ) async {
      final h = Harness(
        tester,
        source: FakeSource(
          result: PopupFetchResult(popups: [inApp('b', layout: PopupLayout.banner)]),
        ),
      );
      await h.pumpApp();
      await h.route('/home');
      await h.init(blockedRoutes: ['/deposit']);
      expect(h.shownId, 'b');
      await h.route('/deposit');
      expect(h.shownId, isNull);
      // Hidden, not dismissed by the player.
      expect(h.source.sentEvents.map((e) => e.type), [PopupEventType.impression]);
      await h.dispose();
    });

    testWidgets(
      'a route change during an image load re-picks: no pop-up lands on a blocked route',
      (tester) async {
        final images = GatedImages();
        final h = Harness(
          tester,
          images: images,
          source: FakeSource(result: PopupFetchResult(popups: [inAppWithImage('a')])),
        );
        await h.pumpApp();
        await h.route('/home');
        unawaited(h.controller.init(context: ctx, source: h.source, blockedRoutes: ['/deposit']));
        for (var i = 0; i < 5 && images.loads == 0; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(images.loads, 1);
        h.controller.didChangeRoute('/deposit');
        images.release();
        await h.settle();
        expect(h.shownId, isNull);
        await h.dispose();
      },
    );

    testWidgets('a pick asked for by a new session while the old one loads an image still runs', (
      tester,
    ) async {
      final images = GatedImages();
      final h = Harness(
        tester,
        images: images,
        source: FakeSource(result: PopupFetchResult(popups: [inAppWithImage('old')])),
      );
      await h.pumpApp();
      await h.route('/home');
      unawaited(h.controller.init(context: ctx, source: h.source));
      for (var i = 0; i < 5 && images.loads == 0; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(images.loads, 1);
      await h.controller.logout();
      final next = FakeSource(result: PopupFetchResult(popups: [inApp('new')]));
      unawaited(h.controller.init(context: ctx, source: next));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      images.release();
      await h.settle();
      expect(h.shownId, 'new');
      await h.dispose();
    });

    testWidgets('a page pushed under a blocking pop-up keeps it; back then closes it', (
      tester,
    ) async {
      final h = Harness(tester, source: FakeSource(result: PopupFetchResult(popups: [inApp('a')])));
      final key = await pumpNavigatorApp(tester, h);
      await h.init();
      expect(h.shownId, 'a');
      key.currentState!.pushNamed('/next');
      await tester.pumpAndSettle();
      await h.settle();
      expect(h.shownId, 'a');
      await tester.binding.handlePopRoute();
      await h.settle();
      expect(h.shownId, isNull);
      expect(find.text('page /next'), findsOneWidget);
      await h.dispose();
    });

    testWidgets('screen readers reach the page under a banner, not under a modal', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness(tester);
      await pumpNavigatorApp(tester, h, appBar: true);
      await h.init();
      expect(find.semantics.byLabel('page /'), findsOneWidget);

      h.controller.showTest(content(PopupLayout.modal));
      await h.settle();
      expect(find.semantics.byLabel('page /'), findsNothing);
      // The back entry doesn't give the page's AppBar a back button.
      expect(find.byType(BackButton), findsNothing);

      h.controller.close(h.controller.current.value!, dismissed: false);
      h.controller.showTest(content(PopupLayout.banner));
      await h.settle();
      expect(find.semantics.byLabel('page /'), findsOneWidget);
      semantics.dispose();
      await h.dispose();
    });
  });

  testWidgets('the route observer reports page pushes and pops, not dialogs', (tester) async {
    final routes = <String>[];
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [PopupRouteObserver(routes.add)],
        onGenerateRoute:
            (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Text(settings.name ?? ''),
            ),
      ),
    );
    key.currentState!.pushNamed('/games');
    await tester.pumpAndSettle();
    showDialog<void>(context: key.currentContext!, builder: (_) => const Text('dialog'));
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(routes, ['/', '/games', '/games', '/']);
  });
}
