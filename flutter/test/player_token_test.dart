import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optikpi_inapp/optikpi_inapp.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_source.dart';

String encode(Object? value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

String tokenFor(String sub, {String wid = 'ws1', String tag = 'a'}) =>
    '${encode({'alg': 'ES256', 'kid': 'k'})}.${encode({'sub': sub, 'wid': wid, 'exp': 1})}.$tag';

PopupFetchResult waiting(String id, DateTime createdAt) => PopupFetchResult(
  popups: [
    InAppPopup(
      id: id,
      trackingId: 'trk-$id',
      createdAt: createdAt,
      content: content(PopupLayout.modal),
    ),
  ],
);

void main() {
  final now = DateTime.utc(2026, 10, 10, 12);
  late FakeSource source;
  late OptikpiInAppController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    source = FakeSource(result: waiting('a', now));
    controller = OptikpiInAppController(
      clock: () => now,
      flushDelay: const Duration(milliseconds: 10),
    );
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => PopupHost(controller: controller, child: child!),
        home: const Scaffold(body: Text('screen')),
      ),
    );
    controller.didChangeRoute('/home');
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await controller.lastInit;
    await controller.lastFetch;
    await controller.lastShow;
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> start(WidgetTester tester, String token) async {
    await pumpApp(tester);
    await controller.initWithToken(
      apiKey: 'key',
      playerToken: token,
      baseUrl: 'https://inapp.test',
      source: source,
    );
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    controller.reset();
    await tester.pumpWidget(const SizedBox());
  }

  Future<int> queueLength() => controller.events.length;

  Future<void> queueEvent(String trackingId, String playerId) => controller.events.enqueue(
    PopupEvent(trackingId: trackingId, type: PopupEventType.impression, at: now),
    workspaceId: 'ws1',
    playerId: playerId,
  );

  testWidgets('sub and wid come from the token, and the token goes on the fetch', (tester) async {
    await start(tester, tokenFor('p1'));
    expect(source.fetchTokens, [tokenFor('p1')]);
    expect(controller.current.value?.context?.playerId, 'p1');
    expect(controller.current.value?.context?.workspaceId, 'ws1');
    await finish(tester);
  });

  for (final status in [401, 403]) {
    testWidgets('a $status stops fetching, keeps the queue, and a new token resumes', (
      tester,
    ) async {
      await queueEvent('t1', 'p1');
      source.refuseWith = status;
      await start(tester, tokenFor('p1'));
      expect(controller.isPaused, isTrue);
      final refused = source.fetches + source.sendTokens.length;

      controller.didChangeRoute('/next');
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle(tester);
      expect(source.fetches + source.sendTokens.length, refused, reason: 'paused: nothing sent');
      expect(await queueLength(), 1, reason: 'never dropped');

      source.refuseWith = null;
      final fresh = tokenFor('p1', tag: 'fresh');
      controller.setPlayerToken(fresh);
      await settle(tester);
      expect(controller.isPaused, isFalse);
      expect(source.fetchTokens.last, fresh);
      expect(source.sendTokens.last, fresh);
      expect(await queueLength(), 0);
      expect(source.sentEvents.map((e) => e.trackingId), contains('t1'));
      await finish(tester);
    });
  }

  testWidgets('a 500 does not pause', (tester) async {
    source.refuseWith = 500;
    await start(tester, tokenFor('p1'));
    expect(controller.isPaused, isFalse);
    await finish(tester);
  });

  testWidgets('a refused send alone pauses too', (tester) async {
    await start(tester, tokenFor('p1'));
    source.refuseWith = 403;
    await queueEvent('t1', 'p1');
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle(tester);
    expect(controller.isPaused, isTrue);
    expect(await queueLength(), 1);
    await finish(tester);
  });

  testWidgets('a 401 for the old token, landing after setPlayerToken, does not pause the new', (
    tester,
  ) async {
    final gate = Completer<void>();
    source
      ..fetchGate = gate.future
      ..refuseWith = 401;
    await pumpApp(tester);
    await controller.initWithToken(
      apiKey: 'key',
      playerToken: tokenFor('p1'),
      baseUrl: 'https://inapp.test',
      source: source,
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(source.fetches, 1);

    controller.setPlayerToken(tokenFor('p1', tag: 'fresh'));
    source
      ..refuseWith = null
      ..fetchGate = null;
    gate.complete();
    await settle(tester);
    expect(controller.isPaused, isFalse);
    expect(
      source.fetchTokens.last,
      tokenFor('p1', tag: 'fresh'),
      reason: 'the blocked fetch re-ran',
    );
    await finish(tester);
  });

  testWidgets('another player: nothing carries over, and queued events stay with their player', (
    tester,
  ) async {
    await start(tester, tokenFor('p1'));
    expect(controller.current.value?.popup.id, 'a');
    await queueEvent('from-p1', 'p1');
    source
      ..refuseWith = 403
      ..result = waiting('b', now);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle(tester);
    expect(controller.isPaused, isTrue);

    source.refuseWith = null;
    final sentBefore = source.sentEvents.length;
    controller.setPlayerToken(tokenFor('p2'));
    await settle(tester);
    expect(controller.isPaused, isFalse);
    expect(controller.current.value?.popup.id, 'b', reason: 'p1 on-screen state is gone');
    expect(controller.current.value?.context?.playerId, 'p2');
    expect(
      source.sentEvents.skip(sentBefore).map((e) => e.trackingId),
      isNot(contains('from-p1')),
      reason: "p2's token cannot speak for p1",
    );
    expect(await queueLength(), greaterThanOrEqualTo(1));

    controller.setPlayerToken(tokenFor('p1'));
    await settle(tester);
    expect(source.sentEvents.map((e) => e.trackingId), contains('from-p1'));
    await finish(tester);
  });

  testWidgets('an unreadable token logs, fetches nothing, and a good one starts the session', (
    tester,
  ) async {
    await start(tester, 'not-a-jwt');
    expect(source.fetches, 0);
    expect(controller.isActive, isFalse);

    controller.setPlayerToken('still-not-a-jwt');
    await settle(tester);
    expect(source.fetches, 0);

    controller.setPlayerToken(tokenFor('p1'));
    await settle(tester);
    expect(source.fetches, 1);
    expect(controller.current.value?.popup.id, 'a');
    await finish(tester);
  });

  testWidgets('an unreadable replacement pauses a running session', (tester) async {
    await start(tester, tokenFor('p1'));
    controller.setPlayerToken('nope');
    expect(controller.isPaused, isTrue);
    await finish(tester);
  });

  testWidgets('setPlayerToken after logout starts nothing', (tester) async {
    await start(tester, tokenFor('p1'));
    await controller.logout();
    final fetches = source.fetches;
    controller.setPlayerToken(tokenFor('p1'));
    await settle(tester);
    expect(source.fetches, fetches);
    expect(controller.isActive, isFalse);
    await finish(tester);
  });

  testWidgets('a session started by setPlayerToken keeps the init callbacks', (tester) async {
    final received = <Map<String, String>>[];
    source.result = PopupFetchResult(popups: const []);
    await pumpApp(tester);
    await controller.initWithToken(
      apiKey: 'key',
      playerToken: tokenFor('p1'),
      baseUrl: 'https://inapp.test',
      source: source,
      onCustomAction: received.add,
    );
    await settle(tester);
    controller.setPlayerToken(tokenFor('p2'));
    await settle(tester);

    controller.showTest(
      const PopupContent(
        layout: PopupLayout.modal,
        size: PopupSize.md,
        buttons: [
          PopupButton(
            label: 'Go',
            style: PopupButtonStyle.primary,
            action: PopupAction(type: PopupActionType.custom, customData: {'type': 'wallet'}),
          ),
        ],
      ),
    );
    await tester.pump();
    controller.tapButton(controller.current.value!, 0);
    expect(received, [
      {'type': 'wallet'},
    ]);
    await finish(tester);
  });

  testWidgets('another workspace with the same player id is another player', (tester) async {
    await start(tester, tokenFor('p1'));
    controller.setPlayerToken(tokenFor('p1', wid: 'ws2'));
    await settle(tester);
    expect(source.fetchTokens.last, tokenFor('p1', wid: 'ws2'));
    expect(controller.current.value, isNull, reason: 'the old session ended, with its pop-up');
    await finish(tester);
  });

  testWidgets('a running session sends its queue at logout', (tester) async {
    await start(tester, tokenFor('p1'));
    await queueEvent('t1', 'p1');
    await controller.logout();
    await settle(tester);
    expect(await queueLength(), 0);
    await finish(tester);
  });

  testWidgets('a paused session sends nothing at logout', (tester) async {
    await queueEvent('t1', 'p1');
    source.refuseWith = 403;
    await start(tester, tokenFor('p1'));
    final tries = source.sendTokens.length;
    await controller.logout();
    await settle(tester);
    expect(source.sendTokens.length, tries);
    expect(await queueLength(), 1);
    await finish(tester);
  });

  testWidgets('a switch to another workspace with the same id sends the old queue first', (
    tester,
  ) async {
    await start(tester, tokenFor('p1'));
    await queueEvent('t1', 'p1');
    controller.setPlayerToken(tokenFor('p1', wid: 'ws2'));
    await settle(tester);
    expect(source.sendTokens, contains(tokenFor('p1')));
    expect(await queueLength(), 0);
    await finish(tester);
  });

  testWidgets('a switch sends what the old player earned, with the old token', (tester) async {
    await start(tester, tokenFor('p1'));
    await queueEvent('from-p1', 'p1');
    controller.setPlayerToken(tokenFor('p2'));
    await settle(tester);
    expect(source.sentEvents.map((e) => e.trackingId), contains('from-p1'));
    expect(source.sendTokens, contains(tokenFor('p1')));
    expect(source.sendTokens.where((t) => t == tokenFor('p2')), isEmpty);
    await finish(tester);
  });

  testWidgets('a resume with a throttled fetch still sends the queue', (tester) async {
    await queueEvent('t1', 'p1');
    source.refuseWith = 403;
    await start(tester, tokenFor('p1'));
    source
      ..refuseWith = null
      ..result = const PopupFetchResult(popups: [], nextCheckAfterSec: 3600);
    controller.setPlayerToken(tokenFor('p1', tag: 'fresh'));
    await settle(tester);
    await queueEvent('t2', 'p1');
    final fetches = source.fetches;
    controller.setPlayerToken(tokenFor('p1', tag: 'again'));
    await settle(tester);
    expect(source.fetches, fetches, reason: 'throttled');
    expect(await queueLength(), 0);
    await finish(tester);
  });

  testWidgets('PopupSource.mock() works with no real token', (tester) async {
    await pumpApp(tester);
    await controller.initWithToken(
      apiKey: 'mock',
      playerToken: '',
      baseUrl: 'https://inapp.test',
      source: PopupSource.mock(),
    );
    await settle(tester);
    expect(controller.isActive, isTrue);
    expect(controller.current.value, isNotNull);
    await finish(tester);
  });
}
