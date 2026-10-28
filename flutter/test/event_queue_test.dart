import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optikpi_popup/optikpi_popup.dart';
import 'package:optikpi_popup/src/events/event_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_source.dart';

const ctx = PopupRequestContext(
  baseUrl: 'https://inapp.test',
  workspaceId: 'ws1',
  playerId: 'p1',
  apiKey: 'key',
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

  test('batches by size and by player; other workspaces wait', () async {
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
    expect(source.sent.map((b) => b.length), [2, 1, 1]);
    expect(source.sentFor, ['p1', 'p1', 'p2']);
    expect(await queue.length, 1); // ws2 waits for a ws2 session
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
        deviceKey: 'dev',
      ),
      [event('t1', PopupEventType.click, buttonIndex: 1)],
    );
    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'https://inapp.test/ingest/popup');
    expect(captured.headers['authorization'], 'Bearer key');
    expect(captured.headers['x-device-key'], 'dev');
    expect(captured.headers['x-sdk-version'], 'optikpi_popup-flutter/$optikpiPopupVersion');
    expect(captured.headers.keys, isNot(contains('x-api-key')));
    expect(captured.headers.keys, isNot(contains('x-workspace-id')));
    expect(jsonDecode(captured.body), {
      'playerId': 'p1',
      'events': [
        {'trackingId': 't1', 'type': 'click', 'at': '2026-10-01T00:00:00.000Z', 'buttonIndex': 1},
      ],
    });
  });

  test('the HTTP source fetches with playerId and treats non-200 as failure', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      if (request.url.queryParameters['playerId'] != 'p1') return http.Response('', 400);
      return http.Response(jsonEncode({'popups': [], 'nextCheckAfterSec': 60}), 200);
    });
    final result = await PopupSource.http(client: client).fetch(ctx);
    expect(result.nextCheckAfterSec, 60);
    expect(captured.url.path, '/v1/inapp/popups');
    expect(captured.headers['authorization'], 'Bearer key');
    expect(captured.headers.keys, isNot(contains('x-device-key')));
    expect(captured.headers.keys, isNot(contains('x-api-key')));
    expect(captured.headers.keys, isNot(contains('x-workspace-id')));

    final unauthorised = MockClient((_) async => http.Response('', 401));
    expect(PopupSource.http(client: unauthorised).fetch(ctx), throwsA(isA<PopupHttpException>()));

    final failing = MockClient((_) async => http.Response('nope', 503));
    expect(PopupSource.http(client: failing).fetch(ctx), throwsA(isA<PopupHttpException>()));
  });

  test('a 401 on events keeps them queued, like any other failure', () async {
    final queue = PopupEventQueue();
    await queue.enqueue(event('t1', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p1');
    var status = 401;
    final client = MockClient((_) async => http.Response('', status));
    await queue.flush(PopupSource.http(client: client), ctx);
    expect(await queue.length, 1);
    status = 204;
    await queue.flush(PopupSource.http(client: client), ctx);
    expect(await queue.length, 0);
  });

  test('a flush joined mid-run re-runs with the latest caller, not the first', () async {
    final queue = PopupEventQueue();
    final a = FakeSource()..sendGate = Completer<void>().future;
    final gate = Completer<void>();
    a.sendGate = gate.future;
    final b = FakeSource();
    const ctxB = PopupRequestContext(
      baseUrl: 'https://inapp.test',
      workspaceId: 'ws2',
      playerId: 'p2',
      apiKey: 'key2',
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

  test('a refused batch holds back only that player; offline stops the flush', () async {
    final queue = PopupEventQueue();
    final source = FakeSource()..refuse.add('p1');
    await queue.enqueue(event('t1', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p1');
    await queue.enqueue(event('t2', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p2');
    await queue.flush(source, ctx);
    expect(source.sentFor, ['p2']);
    expect(await queue.length, 1);

    await queue.enqueue(event('t3', PopupEventType.impression), workspaceId: 'ws1', playerId: 'p3');
    source
      ..refuse.clear()
      ..failSends = 1;
    await queue.flush(source, ctx);
    expect(source.sentFor, ['p2'], reason: 'offline: nothing more is tried');
    await queue.flush(source, ctx);
    expect(source.sentFor, ['p2', 'p1', 'p3']);
  });
}
