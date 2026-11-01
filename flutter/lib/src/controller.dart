import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import 'events/event_queue.dart';
import 'events/popup_event.dart';
import 'log.dart';
import 'logic/fetch_throttle.dart';
import 'logic/player_token.dart';
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

  /// Shown from `OptikpiInApp.showTest`: no events, not remembered as shown.
  final bool isTest;

  PopupContent get content => popup.content;
}

/// What init was given, so `setPlayerToken` can start a session from a new token alone.
class _Setup {
  const _Setup(this.apiKey, this.baseUrl, this.source, this.onDeepLink, this.blockedRoutes);

  final String apiKey;
  final String baseUrl;
  final PopupSource source;
  final PopupDeepLinkHandler? onDeepLink;
  final List<String> blockedRoutes;
}

/// Everything that belongs to one logged-in player. Replaced on init, dropped on logout; an
/// async step compares `identical(session, _session)` to know whether it is still wanted, and
/// `identical(context, session.context)` to know whether its token still is.
class _Session {
  _Session(this.context, this.source, this.onDeepLink, this.blockedRoutes);

  PopupRequestContext context;
  final PopupSource source;
  final PopupDeepLinkHandler? onDeepLink;
  final List<String> blockedRoutes;
  final FetchThrottle throttle = FetchThrottle();
  List<InAppPopup> waiting = const [];
  bool fetching = false;

  /// The server refused the token, or the token can't be read: no fetch and no send until
  /// `setPlayerToken`. Queued events stay queued.
  bool paused = false;
}

class OptikpiInAppController with WidgetsBindingObserver {
  OptikpiInAppController({
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
  _Setup? _setup;
  String? _lastPlayerKey;
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

  /// The init started by the last `setPlayerToken` that needed one, for tests.
  @visibleForTesting
  Future<void>? lastInit;

  bool get isActive => _session != null;

  /// True while the session waits for `setPlayerToken`.
  bool get isPaused => _session?.paused ?? false;
  String? get route => _route;

  /// Starts from a player token. An unreadable one logs and fetches nothing until
  /// [setPlayerToken] brings a good one; a source that talks to no server doesn't need one.
  Future<void> initWithToken({
    required String apiKey,
    required String playerToken,
    required String baseUrl,
    required PopupSource source,
    PopupDeepLinkHandler? onDeepLink,
    List<String> blockedRoutes = const [],
  }) async {
    final setup = _Setup(apiKey, baseUrl, source, onDeepLink, blockedRoutes);
    final context = _contextFor(setup, playerToken);
    if (context == null) {
      inAppLog('player token unreadable: not fetching');
      _endSession(flush: false);
      _setup = setup;
      return;
    }
    return init(
      context: context,
      source: source,
      onDeepLink: onDeepLink,
      blockedRoutes: blockedRoutes,
    );
  }

  PopupRequestContext? _contextFor(_Setup setup, String playerToken) {
    final claims = PlayerTokenClaims.tryRead(playerToken);
    if (claims == null && setup.source.needsPlayerToken) return null;
    return PopupRequestContext(
      baseUrl: setup.baseUrl,
      workspaceId: claims?.workspaceId ?? 'mock',
      playerId: claims?.playerId ?? 'mock',
      apiKey: setup.apiKey,
      playerToken: playerToken,
    );
  }

  /// A fresh token. The same player carries on, and a paused session resumes; another player
  /// starts from nothing, as after a logout. Queued events stay, each with its own player.
  void setPlayerToken(String playerToken) {
    final setup = _setup;
    if (setup == null) {
      inAppLog('setPlayerToken before init: ignored');
      return;
    }
    final session = _session;
    final context = _contextFor(setup, playerToken);
    if (context == null) {
      inAppLog('player token unreadable: not fetching');
      session?.paused = true;
      return;
    }
    if (session == null ||
        session.context.playerId != context.playerId ||
        session.context.workspaceId != context.workspaceId) {
      lastInit = init(
        context: context,
        source: setup.source,
        onDeepLink: setup.onDeepLink,
        blockedRoutes: setup.blockedRoutes,
      ).catchError((Object error) => inAppLog('init failed: $error'));
      return;
    }
    session.context = context;
    session.paused = false;
    inAppLog('player token replaced');
    unawaited(_flush(session));
    _fetchMoment();
  }

  Future<void> init({
    required PopupRequestContext context,
    required PopupSource source,
    PopupDeepLinkHandler? onDeepLink,
    List<String> blockedRoutes = const [],
  }) async {
    // Another player's token can't send what this one earned, so it goes now, if the server
    // still takes this token. What can't go waits for this player's next session.
    final previous = _session;
    final switching =
        previous != null &&
        (previous.context.playerId != context.playerId ||
            previous.context.workspaceId != context.workspaceId);
    _endSession(flush: switching && !previous.paused);
    final session = _Session(context, source, onDeepLink, List.unmodifiable(blockedRoutes));
    _session = session;
    _setup = _Setup(context.apiKey, context.baseUrl, source, onDeepLink, blockedRoutes);
    // The one-per-visit rule is about one player: a new one on the same screen starts fresh.
    final playerKey = '${context.workspaceId}/${context.playerId}';
    if (playerKey != _lastPlayerKey) _shownThisVisit = false;
    _lastPlayerKey = playerKey;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    await shown.load();
    if (!identical(session, _session)) return;
    inAppLog('init workspace ${context.workspaceId} player ${context.playerId}');
    unawaited(_flush(session));
    _fetchMoment();
  }

  Future<void> logout() async {
    inAppLog('logout');
    _endSession(flush: !(_session?.paused ?? false));
    _setup = null;
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
    // Events already earned still go: one last try now, the rest at this player's next session.
    if (flush && session != null) {
      unawaited(
        events
            .flush(session.source, session.context)
            .catchError((Object error) => inAppLog('flush failed: $error')),
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
    if (session.paused ||
        session.fetching ||
        !_inForeground ||
        !session.throttle.canFetch(_clock())) {
      return;
    }
    session.fetching = true;
    final context = session.context;
    var tokenChanged = false;
    try {
      final result = await session.source.fetch(context);
      if (!identical(session, _session)) return;
      session.throttle.recordResponse(_clock(), result.nextCheckAfterSec);
      session.waiting = result.popups;
      inAppLog(
        'fetched ${result.popups.length} pop-up(s), next check in '
        '${session.throttle.interval.inSeconds} s',
      );
      unawaited(_flush(session));
      _showMoment();
    } on PopupHttpException catch (error) {
      inAppLog('fetch failed: $error');
      if (error.isAuthFailure) tokenChanged = !_pauseIfCurrent(session, context);
    } catch (error) {
      // Silent by contract; the next fetch moment tries again.
      inAppLog('fetch failed: $error');
    } finally {
      session.fetching = false;
    }
    // Refused, but a new token arrived meanwhile and its fetch found this one running.
    if (tokenChanged && identical(session, _session)) _fetchMoment();
  }

  /// Stops fetching and sending until `setPlayerToken`. False when [context] is out of date, so
  /// its refusal says nothing about the token in use now.
  bool _pauseIfCurrent(_Session session, PopupRequestContext context) {
    if (!identical(context, session.context)) return false;
    inAppLog('player token refused: paused until setPlayerToken');
    session.paused = true;
    return true;
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
    inAppLog('route $route');
    // A banner or toast leaves the player free to move on; it must not follow them onto a
    // blocked screen. Not a dismiss: the player didn't close it.
    final active = current.value;
    final session = _session;
    if (active != null &&
        !active.isTest &&
        session != null &&
        isRouteBlocked(route, session.blockedRoutes)) {
      inAppLog('hide ${active.popup.id}: $route is blocked');
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
      inAppLog('pick failed: $error');
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
    inAppLog('show ${picked.id} (${picked.content.layout.name}) on $_route');
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
      inAppLog('test pop-up drawn (${active.content.layout.name})');
      return;
    }
    unawaited(
      shown
          .markShown(active.popup.id)
          .catchError((Object error) => inAppLog('could not remember ${active.popup.id}: $error')),
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
            if (!opened) inAppLog('could not open $uri');
          },
          onError: (Object error) {
            inAppLog('could not open $uri: $error');
          },
        );
    }
  }

  // ---- events ---------------------------------------------------------------------------------

  void _track(ActivePopup active, PopupEventType type, {int? buttonIndex}) {
    if (active.isTest) {
      inAppLog('test ${type.name}${buttonIndex != null ? ' button $buttonIndex' : ''}');
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
            inAppLog('could not queue ${type.name}: $error');
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
    if (session.paused || !_inForeground) return;
    final context = session.context;
    try {
      await events.flush(session.source, context);
    } on PopupHttpException catch (error) {
      if (error.isAuthFailure) _pauseIfCurrent(session, context);
    } catch (error) {
      inAppLog('flush failed: $error');
    }
  }

  /// For tests and hot restart.
  @visibleForTesting
  void reset() {
    _endSession(flush: false);
    _setup = null;
    _lastPlayerKey = null;
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
