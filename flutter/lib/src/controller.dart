import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import 'events/event_queue.dart';
import 'events/popup_event.dart';
import 'log.dart';
import 'logic/fetch_throttle.dart';
import 'logic/show_rules.dart';
import 'logic/shown_store.dart';
import 'model/inapp_popup.dart';
import 'model/popup_content.dart';
import 'render/popup_image_cache.dart';
import 'source/popup_source.dart';

typedef PopupDeepLinkHandler = void Function(String link);
typedef PopupUrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchExternal(Uri uri) =>
    launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);

/// The pop-up on screen, and who it was fetched for. Events and actions use this, not the
/// current session, so a logout while it is up can't send its events under another player.
class ActivePopup {
  ActivePopup._(this.popup, this.context, this.onDeepLink, {required this.isTest});

  final InAppPopup popup;
  final PopupRequestContext? context;
  final PopupDeepLinkHandler? onDeepLink;

  /// Shown from `OptikpiPopup.showTest`: no events, not remembered as shown.
  final bool isTest;

  PopupContent get content => popup.content;
}

/// Everything that belongs to one logged-in player. Replaced on init, dropped on logout; an
/// async step compares `identical(session, _session)` to know whether it is still wanted.
class _Session {
  _Session(this.context, this.source, this.onDeepLink, this.blockedRoutes);

  final PopupRequestContext context;
  final PopupSource source;
  final PopupDeepLinkHandler? onDeepLink;
  final List<String> blockedRoutes;
  final FetchThrottle throttle = FetchThrottle();
  List<InAppPopup> waiting = const [];
  bool fetching = false;
}

class OptikpiPopupController with WidgetsBindingObserver {
  OptikpiPopupController({
    PopupEventQueue? events,
    ShownStore? shown,
    PopupImageCache? images,
    DateTime Function()? clock,
    PopupUrlLauncher? launchUrl,
    this.flushDelay = const Duration(seconds: 2),
  }) : events = events ?? PopupEventQueue(),
       shown = shown ?? ShownStore(),
       images = images ?? PopupImageCache(),
       _clock = clock ?? DateTime.now,
       _launchUrl = launchUrl ?? _launchExternal;

  final PopupEventQueue events;
  final ShownStore shown;
  final PopupImageCache images;
  final DateTime Function() _clock;
  final PopupUrlLauncher _launchUrl;

  /// Events are sent this long after the last one is queued, so a click and the dismiss that
  /// often follows it go in one request.
  final Duration flushDelay;

  /// What the host draws. Null when nothing is on screen.
  final ValueNotifier<ActivePopup?> current = ValueNotifier(null);

  _Session? _session;
  bool _observing = false;
  Timer? _flushTimer;
  int _testCount = 0;

  String? _route;
  int _visit = 0;
  bool _shownThisVisit = false;
  bool _picking = false;
  bool _pickAgain = false;

  /// The fetch started by the last fetch moment, for tests.
  @visibleForTesting
  Future<void>? lastFetch;

  /// The show attempt started last, for tests.
  @visibleForTesting
  Future<void>? lastShow;

  bool get isActive => _session != null;
  String? get route => _route;

  Future<void> init({
    required PopupRequestContext context,
    required PopupSource source,
    PopupDeepLinkHandler? onDeepLink,
    List<String> blockedRoutes = const [],
  }) async {
    _endSession(flush: false);
    final session = _Session(context, source, onDeepLink, List.unmodifiable(blockedRoutes));
    _session = session;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    await shown.load();
    if (!identical(session, _session)) return;
    popupLog('init workspace ${context.workspaceId} player ${context.playerId}');
    unawaited(_flush(session));
    _fetchMoment();
  }

  Future<void> logout() async {
    popupLog('logout');
    _endSession(flush: true);
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  void _endSession({required bool flush}) {
    final session = _session;
    _session = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    final active = current.value;
    if (active != null && !active.isTest) current.value = null;
    // Events already earned still go: one last try now, the rest at the next init.
    if (flush && session != null) {
      unawaited(
        events
            .flush(session.source, session.context)
            .catchError((Object error) => popupLog('flush failed: $error')),
      );
    }
  }

  // ---- fetch moments --------------------------------------------------------------------------

  bool get _inForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _fetchMoment() {
    final session = _session;
    if (session == null) return;
    lastFetch = _maybeFetch(session);
  }

  Future<void> _maybeFetch(_Session session) async {
    if (session.fetching || !_inForeground || !session.throttle.canFetch(_clock())) return;
    session.fetching = true;
    try {
      final result = await session.source.fetch(session.context);
      if (!identical(session, _session)) return;
      session.throttle.recordResponse(_clock(), result.nextCheckAfterSec);
      session.waiting = result.popups;
      popupLog(
        'fetched ${result.popups.length} pop-up(s), next check in '
        '${session.throttle.interval.inSeconds} s',
      );
      unawaited(_flush(session));
      _showMoment();
    } catch (error) {
      // Silent by contract; the next fetch moment tries again.
      popupLog('fetch failed: $error');
    } finally {
      session.fetching = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final session = _session;
    if (session == null) return;
    unawaited(_flush(session));
    _fetchMoment();
  }

  /// A new screen visit. Called by the route observer, or by the app with its own routing.
  void didChangeRoute(String? route) {
    if (route == null || route == _route) return;
    _route = route;
    _visit++;
    _shownThisVisit = false;
    popupLog('route $route');
    // A banner or toast leaves the player free to move on; it must not follow them onto a
    // blocked screen. Not a dismiss: the player didn't close it.
    final active = current.value;
    final session = _session;
    if (active != null &&
        !active.isTest &&
        session != null &&
        isRouteBlocked(route, session.blockedRoutes)) {
      popupLog('hide ${active.popup.id}: $route is blocked');
      current.value = null;
    }
    _showMoment();
    _fetchMoment();
  }

  // ---- showing --------------------------------------------------------------------------------

  void _showMoment() {
    final session = _session;
    if (session == null) return;
    lastShow = _maybeShow(session);
  }

  Future<void> _maybeShow(_Session session) async {
    if (_picking) {
      // A fetch or a route change landed mid-pick: pick again once this one is done.
      _pickAgain = true;
      return;
    }
    if (_shownThisVisit || current.value != null) return;
    _picking = true;
    _pickAgain = false;
    final visit = _visit;
    InAppPopup? next;
    try {
      final shownIds = await shown.load();
      next = pickPopupToShow(
        waiting: session.waiting,
        shownIds: shownIds,
        route: _route,
        blockedRoutes: session.blockedRoutes,
        now: _clock(),
      );
      final image = next?.content.image;
      if (image != null && !image.isGradient) await images.load(image.url);
    } catch (error) {
      // Silent by contract (storage failed); the next show moment tries again.
      popupLog('pick failed: $error');
      next = null;
    } finally {
      _picking = false;
    }
    if (!identical(session, _session)) {
      // A newer session asked to pick while this stale one ran: honour it.
      if (_pickAgain) _showMoment();
      return;
    }
    if (visit != _visit || _pickAgain) {
      // The player moved on, or new pop-ups arrived, while this pick ran: decide again.
      return _maybeShow(session);
    }
    if (next == null || _shownThisVisit || current.value != null) return;
    final picked = next;
    _shownThisVisit = true;
    session.waiting = session.waiting.where((p) => p.id != picked.id).toList(growable: false);
    popupLog('show ${picked.id} (${picked.content.layout.name}) on $_route');
    current.value = ActivePopup._(picked, session.context, session.onDeepLink, isTest: false);
  }

  /// Draws [content] now, past every rule. For the app's debug menu: no events, not remembered.
  void showTest(PopupContent content, {PopupDeepLinkHandler? onDeepLink}) {
    _testCount++;
    final popup = InAppPopup(
      id: 'test-$_testCount',
      trackingId: 'test-$_testCount',
      createdAt: _clock().toUtc(),
      content: content,
    );
    current.value = ActivePopup._(popup, null, onDeepLink ?? _session?.onDeepLink, isTest: true);
  }

  // ---- what the host reports ------------------------------------------------------------------

  /// The pop-up's first frame is on screen.
  void didDraw(ActivePopup active) {
    if (!identical(current.value, active)) return;
    if (active.isTest) {
      popupLog('test pop-up drawn (${active.content.layout.name})');
      return;
    }
    unawaited(
      shown
          .markShown(active.popup.id)
          .catchError((Object error) => popupLog('could not remember ${active.popup.id}: $error')),
    );
    _track(active, PopupEventType.impression);
  }

  /// Closes [active] if it is still the one on screen. [dismissed] reports a dismiss: the close
  /// button, a tap outside, auto-dismiss or Android back.
  bool close(ActivePopup active, {required bool dismissed}) {
    if (!identical(current.value, active)) return false;
    current.value = null;
    if (dismissed) _track(active, PopupEventType.dismiss);
    return true;
  }

  void tapButton(ActivePopup active, int index) {
    if (index < 0 || index >= active.content.buttons.length) return;
    if (!close(active, dismissed: false)) return;
    _track(active, PopupEventType.click, buttonIndex: index);
    _perform(active, active.content.buttons[index].action);
  }

  void tapImage(ActivePopup active) {
    final action = active.content.image?.tapAction;
    if (action == null && active.content.layout != PopupLayout.imageOnly) return;
    if (!close(active, dismissed: false)) return;
    _track(active, PopupEventType.click);
    if (action != null) _perform(active, action);
  }

  void _perform(ActivePopup active, PopupAction action) {
    final value = action.value;
    switch (action.type) {
      case PopupActionType.dismiss:
        break;
      case PopupActionType.deeplink:
        if (value != null) active.onDeepLink?.call(value);
      case PopupActionType.url:
        final uri = value == null ? null : Uri.tryParse(value);
        if (uri == null) break;
        _launchUrl(uri).then(
          (opened) {
            if (!opened) popupLog('could not open $uri');
          },
          onError: (Object error) {
            popupLog('could not open $uri: $error');
          },
        );
    }
  }

  // ---- events ---------------------------------------------------------------------------------

  void _track(ActivePopup active, PopupEventType type, {int? buttonIndex}) {
    if (active.isTest) {
      popupLog('test ${type.name}${buttonIndex != null ? ' button $buttonIndex' : ''}');
      return;
    }
    final context = active.context!;
    final event = PopupEvent(
      trackingId: active.popup.trackingId,
      type: type,
      at: _clock().toUtc(),
      buttonIndex: buttonIndex,
    );
    events
        .enqueue(event, workspaceId: context.workspaceId, playerId: context.playerId)
        .then(
          (added) {
            if (added) _scheduleFlush();
          },
          onError: (Object error) {
            popupLog('could not queue ${type.name}: $error');
          },
        );
  }

  void _scheduleFlush() {
    final session = _session;
    if (session == null) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(flushDelay, () {
      if (identical(session, _session)) unawaited(_flush(session));
    });
  }

  Future<void> _flush(_Session session) async {
    if (!_inForeground) return;
    try {
      await events.flush(session.source, session.context);
    } catch (error) {
      popupLog('flush failed: $error');
    }
  }

  /// For tests and hot restart.
  @visibleForTesting
  void reset() {
    _endSession(flush: false);
    current.value = null;
    _route = null;
    _visit = 0;
    _shownThisVisit = false;
    _picking = false;
    _pickAgain = false;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }
}
