import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../log.dart';
import '../source/popup_source.dart';
import 'popup_event.dart';

/// Events wait here, in shared_preferences, until the server takes them. Each
/// `(trackingId, type)` gets in once, so it is sent once, however often the app reports it.
///
/// Every read-modify-write below does its read and its `set…` with no `await` in between.
/// SharedPreferences updates its in-memory copy synchronously, so the steps can't interleave
/// within the isolate.
class PopupEventQueue {
  PopupEventQueue({Future<SharedPreferences> Function()? prefs, this.batchSize = 50})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  static const String queueKey = 'optikpi_inapp.events';
  static const String trackedKey = 'optikpi_inapp.tracked';

  /// Oldest events drop off first when the device has been offline for a very long time.
  static const int maxQueued = 500;
  static const int maxTracked = 2000;

  final Future<SharedPreferences> Function() _prefs;
  final int batchSize;

  Future<void>? _flushing;
  (PopupSource, PopupRequestContext)? _next;

  /// False when this `(trackingId, type)` was queued before.
  Future<bool> enqueue(
    PopupEvent event, {
    required String workspaceId,
    required String playerId,
  }) async {
    final prefs = await _prefs();
    final tracked = prefs.getStringList(trackedKey) ?? <String>[];
    if (tracked.contains(event.dedupeKey)) return false;
    final queue = prefs.getStringList(queueKey) ?? <String>[];
    queue.add(
      jsonEncode({'workspaceId': workspaceId, 'playerId': playerId, 'event': event.toJson()}),
    );
    tracked.add(event.dedupeKey);
    final writes = [
      prefs.setStringList(
        queueKey,
        queue.length > maxQueued ? queue.sublist(queue.length - maxQueued) : queue,
      ),
      prefs.setStringList(
        trackedKey,
        tracked.length > maxTracked ? tracked.sublist(tracked.length - maxTracked) : tracked,
      ),
    ];
    await Future.wait(writes);
    inAppLog('queued ${event.type.name} ${event.trackingId}');
    return true;
  }

  Future<int> get length async => ((await _prefs()).getStringList(queueKey) ?? const []).length;

  /// Sends what is queued for [context]'s player, in batches: a player token speaks for one
  /// player, so another player's events wait for that player's next session. A network error or
  /// a refused batch stops the flush and the rest waits for the next call. A batch refused for
  /// its token or key throws the [PopupHttpException], from the last pass only, so the caller
  /// can pause. Calls made while a flush runs share it, and one more pass runs afterwards, with
  /// the latest caller's source and context, to pick up events queued in the meantime (a logout
  /// and a new login can both land mid-flush).
  Future<void> flush(PopupSource source, PopupRequestContext context) {
    if (_flushing != null) {
      _next = (source, context);
      return _flushing!;
    }
    final run = () async {
      try {
        var args = (source, context);
        while (true) {
          _next = null;
          try {
            await _flushOnce(args.$1, args.$2);
          } on PopupHttpException {
            // A newer token may be waiting in _next: it decides, not this one.
            if (_next == null) rethrow;
          }
          final next = _next;
          if (next == null) break;
          args = next;
        }
      } finally {
        _flushing = null;
      }
    }();
    _flushing = run;
    return run;
  }

  Future<void> _flushOnce(PopupSource source, PopupRequestContext context) async {
    final prefs = await _prefs();
    final items = [
      for (final raw in prefs.getStringList(queueKey) ?? const <String>[])
        if (_Queued.tryParse(raw) case final item?)
          if (item.workspaceId == context.workspaceId && item.playerId == context.playerId) item,
    ];
    for (var start = 0; start < items.length; start += batchSize) {
      final batch = items.sublist(start, (start + batchSize).clamp(0, items.length));
      try {
        await source.sendEvents(context, batch.map((q) => q.event).toList());
      } on PopupHttpException catch (error) {
        inAppLog('event send refused, will retry: $error');
        if (error.isAuthFailure) rethrow;
        return;
      } catch (error) {
        // Offline or timed out: nothing else will get through now.
        inAppLog('event send failed, will retry: $error');
        return;
      }
      final sent = batch.map((q) => q.raw).toSet();
      final remaining =
          (prefs.getStringList(queueKey) ?? const <String>[])
              .where((raw) => !sent.contains(raw))
              .toList();
      await prefs.setStringList(queueKey, remaining);
    }
  }
}

class _Queued {
  _Queued(this.raw, this.workspaceId, this.playerId, this.event);

  final String raw;
  final String workspaceId;
  final String playerId;
  final PopupEvent event;

  static _Queued? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final event = PopupEvent.tryParse(json['event']);
      final workspaceId = json['workspaceId'];
      final playerId = json['playerId'];
      if (event == null || workspaceId is! String || playerId is! String) return null;
      return _Queued(raw, workspaceId, playerId, event);
    } on FormatException {
      return null;
    }
  }
}
