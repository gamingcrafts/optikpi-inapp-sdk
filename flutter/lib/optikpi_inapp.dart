/// OptiKPI in-app pop-ups. See README.md for the five-step integration.
library;

import 'package:flutter/widgets.dart';

import 'src/controller.dart';
import 'src/log.dart';
import 'src/model/popup_content.dart';
import 'src/render/popup_host.dart';
import 'src/route_observer.dart';
import 'src/source/mock_popup_source.dart';
import 'src/source/mock_templates.dart';
import 'src/source/popup_source.dart';

export 'src/controller.dart' show ActivePopup, OptikpiInAppController, PopupDeepLinkHandler;
export 'src/events/popup_event.dart' show PopupEvent, PopupEventType;
export 'src/model/inapp_popup.dart' show InAppPopup, PopupFetchResult;
export 'src/model/popup_content.dart';
export 'src/render/popup_host.dart' show PopupHost;
export 'src/render/popup_view.dart' show PopupKeys, PopupView;
export 'src/source/popup_source.dart' show PopupHttpException, PopupRequestContext, PopupSource;
export 'src/version.dart' show optikpiInAppVersion;

abstract final class OptikpiInApp {
  static final OptikpiInAppController _controller = OptikpiInAppController();
  static final PopupRouteObserver _routeObserver = PopupRouteObserver(
    _controller.didChangeRoute,
    controller: _controller,
  );

  /// Logs with the `[OptikpiInApp]` prefix. Off by default; the package logs nothing else.
  static bool get debug => inAppDebugLogging;
  static set debug(bool value) => inAppDebugLogging = value;

  /// The controller behind the static API, for tests and advanced use.
  static OptikpiInAppController get controller => _controller;

  /// Pass to `MaterialApp.builder` (or call from your own builder): draws pop-ups over every
  /// screen.
  static Widget builder(BuildContext context, Widget? child) =>
      PopupHost(controller: _controller, child: child ?? const SizedBox.shrink());

  /// Add to the navigator's observers (`GoRouter(observers: [...])`,
  /// `MaterialApp(navigatorObservers: [...])`). Each new page is a screen visit, and Android
  /// back closes a blocking pop-up rather than the page under it.
  static NavigatorObserver get routeObserver => _routeObserver;

  /// For apps that track the location themselves instead of using [routeObserver].
  static void didChangeRoute(String route) => _controller.didChangeRoute(route);

  /// Call on login, and at app start when a stored session is restored, with the `playerToken`
  /// your server signed for this player. Fetches at once, then on foreground and screen changes,
  /// at most once per the server's `nextCheckAfterSec`.
  ///
  /// [baseUrl] is your environment's API gateway. [source] defaults to the pull API there;
  /// `PopupSource.mock()` serves the bundled templates instead, and needs no real token.
  /// [blockedRoutes] never show a pop-up (a path blocks itself and everything under it).
  /// [onDeepLink] receives a button's `deeplink` value; without it the pop-up just closes.
  ///
  /// The player and workspace are read from the token. If it can't be read, the package logs
  /// that and fetches nothing until [setPlayerToken].
  static Future<void> init({
    required String apiKey,
    required String playerToken,
    required String baseUrl,
    PopupDeepLinkHandler? onDeepLink,
    List<String> blockedRoutes = const [],
    PopupSource? source,
  }) {
    return _controller.initWithToken(
      apiKey: apiKey,
      playerToken: playerToken,
      baseUrl: baseUrl,
      source: source ?? PopupSource.http(),
      onDeepLink: onDeepLink,
      blockedRoutes: blockedRoutes,
    );
  }

  /// Call whenever your server gives you a new token. If the server refused the old one, fetching
  /// and sending were paused, with events kept: this resumes them. A token for another player
  /// starts that player from nothing.
  static void setPlayerToken(String playerToken) => _controller.setPlayerToken(playerToken);

  /// Call on logout: stops fetching and drops this player's waiting pop-ups. Events that can't
  /// go now stay queued and are sent at this player's next session.
  static Future<void> logout() => _controller.logout();

  /// Draws [content] at once, past every rule, with no events. For a debug menu.
  static void showTest(PopupContent content) => _controller.showTest(content);

  /// One sample per layout (modal, fullscreen, bottomSheet, banner, toast, imageOnly), from the
  /// bundled templates, with merge tags filled from [playerData]. Pair with [showTest].
  static List<PopupContent> sampleContents({Map<String, String> playerData = const {}}) {
    final byLayout = <PopupLayout, PopupContent>{};
    for (final template in mockPopupTemplates) {
      final content = PopupContent.tryParse(fillMockMergeTags(template.content, playerData));
      if (content != null) byLayout.putIfAbsent(content.layout, () => content);
    }
    return PopupLayout.values.map((l) => byLayout[l]).whereType<PopupContent>().toList();
  }
}
