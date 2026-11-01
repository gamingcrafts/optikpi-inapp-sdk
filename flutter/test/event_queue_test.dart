import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optikpi_inapp/optikpi_inapp.dart';
import 'package:optikpi_inapp/src/events/event_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_source.dart';

const ctx = PopupRequestContext(
  baseUrl: 'https://inapp.test',
  workspaceId: 'ws1',
  playerId: 'p1',
  apiKey: 'key',
  playerToken: 'token',
);

PopupEvent event(String trackingId, PopupEventType type, {int? buttonIndex}) => PopupEvent(
  trackingId: trackingId,
  type: type,
  at: DateTime.utc(2026, 10, 1),
  buttonIndex: buttonIndex,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('each (trackingId, type) is queued and sent once', () async {
    final queue = PopupEventQueue();
    final source = FakeSource();
    expect(
      await queue.enqueue(
        event('t1', PopupEventType.impression),
        workspaceId: 'ws1',
        playerId: 'p1',
      ),
      isTrue,
    );
    expect(
      await queue.enqueue(
        event('t1', PopupEventType.impression),
        workspaceId: 'ws1',
        playerId: 'p1',
      ),
      isFalse,
    );
    expect(
      await queue.enqueue(event('t1', PopupEventType.click), workspaceId: 'ws1', playerId: 'p1'),
      isTrue,
    );
    await queue.flush(source, ctx);
    expect(source.sent.expand((b) => b).map((e) => e.dedupeKey), ['t1|impression', 't1|click']);

    // Reported again after it was sent: still not sent twice.
    expect(
      await queue.enqueue(event('t1', PopupEventType.click), workspaceId: 'ws1', playerId: 'p1'),
      isFalse,
    );
    await queue.flush(source, ctx);
    expect(source.sent, hasLength(1));
  });

  test('dedupe survives a restart (a new queue over the same prefs)', () async {
    await PopupEventQueue().enqueue(
      event('t1', PopupEventType.dismiss),
      workspaceId: 'ws1',
      playerId: 'p1',
    );
    expect(
      await PopupEventQueue().enqueue(
        event('t1', PopupEventType.dismiss),
        workspaceId: 'ws1',
        playerId: 'p1',
      ),
      isFalse,
    );
  });

  test('a failed send keeps the events and the next flush retries them', () async {
    final queue = PopupEventQueue();
    final source = FakeSource()..failSends = 1;
    await queue.enqueue(event('t1', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p1');
    await queue.flush(source, ctx);
    expect(source.sent, isEmpty);
    expect(await queue.length, 1);

    await queue.flush(source, ctx);
    expect(source.sent.single.single.trackingId, 't1');
    expect(await queue.length, 0);
  });

  test('batches by size; other players and workspaces wait for their own session', () async {
    final queue = PopupEventQueue(batchSize: 2);
    final source = FakeSource();
    for (var i = 0; i < 3; i++) {
      await queue.enqueue(
        event('a$i', PopupEventType.impression),
        workspaceId: 'ws1',
        playerId: 'p1',
      );
    }
    await queue.enqueue(event('b', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p2');
    await queue.enqueue(event('c', PopupEventType.impression), workspaceId: 'ws2', playerId: 'p9');
    await queue.flush(source, ctx);
    expect(source.sent.map((b) => b.length), [2, 1]);
    expect(source.sentFor, ['p1', 'p1']);
    expect(await queue.length, 2); // a token speaks for one player
  });

  test('an event queued while a flush is in flight is sent by the same flush call', () async {
    final queue = PopupEventQueue();
    final gate = Completer<void>();
    final source = FakeSource()..sendGate = gate.future;
    await queue.enqueue(event('t1', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p1');
    final first = queue.flush(source, ctx);
    await queue.enqueue(event('t2', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p1');
    final second = queue.flush(source, ctx);
    gate.complete();
    await Future.wait([first, second]);
    expect(source.sent.expand((b) => b).map((e) => e.trackingId), ['t1', 't2']);
    expect(await queue.length, 0);
  });

  test('the HTTP source posts the contract body and headers', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('', 204);
    });
    await PopupSource.http(client: client).sendEvents(
      const PopupRequestContext(
        baseUrl: 'https://inapp.test/',
        workspaceId: 'ws1',
        playerId: 'p1',
        apiKey: 'key',
        playerToken: 'token',
      ),
      [event('t1', PopupEventType.click, buttonIndex: 1)],
    );
    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'https://inapp.test/ingest/popup');
    expect(captured.headers['authorization'], 'Bearer key');
    expect(captured.headers['x-player-token'], 'token');
    expect(captured.headers.keys, isNot(contains('x-device-key')));
    expect(captured.headers['x-sdk-version'], 'optikpi_inapp-flutter/$optikpiInAppVersion');
    expect(captured.headers.keys, isNot(contains('x-api-key')));
    expect(captured.headers.keys, isNot(contains('x-workspace-id')));
    expect(jsonDecode(captured.body), {
      'events': [
        {'trackingId': 't1', 'type': 'click', 'at': '2026-10-01T00:00:00.000Z', 'buttonIndex': 1},
      ],
    });
  });

  test(
    'the HTTP source fetches with the token, no playerId, and treats non-200 as failure',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'popups': [], 'nextCheckAfterSec': 60}), 200);
      });
      final result = await PopupSource.http(client: client).fetch(ctx);
      expect(result.nextCheckAfterSec, 60);
      expect(captured.url.path, '/v1/inapp/popups');
      expect(captured.url.queryParameters, isEmpty);
      expect(captured.headers['x-player-token'], 'token');
      expect(captured.headers['authorization'], 'Bearer key');
      expect(captured.headers.keys, isNot(contains('x-device-key')));
      expect(captured.headers.keys, isNot(contains('x-api-key')));
      expect(captured.headers.keys, isNot(contains('x-workspace-id')));

      final unauthorised = MockClient((_) async => http.Response('', 401));
      expect(PopupSource.http(client: unauthorised).fetch(ctx), throwsA(isA<PopupHttpException>()));

      final failing = MockClient((_) async => http.Response('nope', 503));
      expect(PopupSource.http(client: failing).fetch(ctx), throwsA(isA<PopupHttpException>()));
    },
  );

  for (final status in [401, 403]) {
    test('a $status on events throws for the caller to pause, and keeps them queued', () async {
      final queue = PopupEventQueue();
      await queue.enqueue(
        event('t1', PopupEventType.impression),
        workspaceId: 'ws1',
        playerId: 'p1',
      );
      var answer = status;
      final client = MockClient((_) async => http.Response('', answer));
      await expectLater(
        queue.flush(PopupSource.http(client: client), ctx),
        throwsA(isA<PopupHttpException>().having((e) => e.isAuthFailure, 'isAuthFailure', true)),
      );
      expect(await queue.length, 1);
      answer = 204;
      await queue.flush(PopupSource.http(client: client), ctx);
      expect(await queue.length, 0);
    });
  }

  test('any other refusal keeps the events and does not throw', () async {
    final queue = PopupEventQueue();
    await queue.enqueue(event('t1', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p1');
    final client = MockClient((_) async => http.Response('', 500));
    await queue.flush(PopupSource.http(client: client), ctx);
    expect(await queue.length, 1);
  });

  test('a flush joined mid-run re-runs with the latest caller, not the first', () async {
    final queue = PopupEventQueue();
    final gate = Completer<void>();
    final a = FakeSource()..sendGate = gate.future;
    final b = FakeSource();
    const ctxB = PopupRequestContext(
      baseUrl: 'https://inapp.test',
      workspaceId: 'ws2',
      playerId: 'p2',
      apiKey: 'key2',
      playerToken: 'token',
    );
    await queue.enqueue(event('t1', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p1');
    final first = queue.flush(a, ctx);
    await Future<void>.delayed(Duration.zero);
    await queue.enqueue(event('t2', PopupEventType.impression), workspaceId: 'ws2', playerId: 'p2');
    // Logout's last try joins first, then the new player's init flush: the latest one wins.
    final logoutTry = queue.flush(a, ctx);
    final second = queue.flush(b, ctxB);
    gate.complete();
    await Future.wait([first, logoutTry, second]);
    expect(a.sentEvents.map((e) => e.trackingId), ['t1']);
    expect(b.sentEvents.map((e) => e.trackingId), ['t2']);
    expect(await queue.length, 0);
  });

  test('a refusal for an old token, with a newer one waiting, does not reach the caller', () async {
    final queue = PopupEventQueue();
    final gate = Completer<void>();
    final old =
        FakeSource()
          ..sendGate = gate.future
          ..refuseWith = null;
    final fresh = FakeSource();
    await queue.enqueue(event('t1', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p1');
    final first = queue.flush(old, ctx);
    await Future<void>.delayed(Duration.zero);
    old.refuse.add('p1');
    final second = queue.flush(fresh, ctx);
    gate.complete();
    await Future.wait([first, second]);
    expect(fresh.sentEvents.map((e) => e.trackingId), ['t1']);
    expect(await queue.length, 0);
  });

  test('another workspace with the same player id waits', () async {
    final queue = PopupEventQueue();
    final source = FakeSource();
    await queue.enqueue(event('t1', PopupEventType.impression), workspaceId: 'ws2', playerId: 'p1');
    await queue.flush(source, ctx);
    expect(source.sent, isEmpty);
    expect(await queue.length, 1);
  });

  test('offline stops the flush and the batch stays', () async {
    final queue = PopupEventQueue(batchSize: 1);
    final source = FakeSource()..failSends = 1;
    await queue.enqueue(event('t1', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p1');
    await queue.enqueue(event('t2', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p1');
    await queue.flush(source, ctx);
    expect(source.sent, isEmpty);
    expect(await queue.length, 2);
    await queue.flush(source, ctx);
    expect(source.sentEvents.map((e) => e.trackingId), ['t1', 't2']);
  });
}
