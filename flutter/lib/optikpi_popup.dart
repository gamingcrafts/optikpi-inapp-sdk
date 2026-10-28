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

export 'src/controller.dart' show ActivePopup, OptikpiPopupController, PopupDeepLinkHandler;
export 'src/events/popup_event.dart' show PopupEvent, PopupEventType;
export 'src/model/inapp_popup.dart' show InAppPopup, PopupFetchResult;
export 'src/model/popup_content.dart';
export 'src/render/popup_host.dart' show PopupHost;
export 'src/render/popup_view.dart' show PopupKeys, PopupView;
export 'src/source/popup_source.dart'
    show PopupHttpException, PopupRequestContext, PopupSource, defaultPopupBaseUrl;
export 'src/version.dart' show optikpiPopupVersion;

abstract final class OptikpiPopup {
  static final OptikpiPopupController _controller = OptikpiPopupController();
  static final PopupRouteObserver _routeObserver = PopupRouteObserver(
    _controller.didChangeRoute,
    controller: _controller,
  );

  /// Logs with the `[OptikpiPopup]` prefix. Off by default; the package logs nothing else.
  static bool get debug => popupDebugLogging;
  static set debug(bool value) => popupDebugLogging = value;

  /// The controller behind the static API, for tests and advanced use.
  static OptikpiPopupController get controller => _controller;

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

  /// Call on login, and at app start when a stored session is restored. Fetches at once, then
  /// on foreground and screen changes, at most once per the server's `nextCheckAfterSec`.
  ///
  /// [source] defaults to the pull API at [baseUrl]; `PopupSource.mock()` serves the bundled
  /// templates instead. [blockedRoutes] never show a pop-up (a path blocks itself and everything
  /// under it). [onDeepLink] receives a button's `deeplink` value; without it the pop-up just
  /// closes.
  static Future<void> init({
    required String workspaceId,
    required String playerId,
    required String apiKey,
    String? deviceKey,
    String baseUrl = defaultPopupBaseUrl,
    PopupSource? source,
    PopupDeepLinkHandler? onDeepLink,
    List<String> blockedRoutes = const [],
  }) {
    return _controller.init(
      context: PopupRequestContext(
        baseUrl: baseUrl,
        workspaceId: workspaceId,
        playerId: playerId,
        apiKey: apiKey,
        deviceKey: deviceKey,
      ),
      source: source ?? PopupSource.http(),
      onDeepLink: onDeepLink,
      blockedRoutes: blockedRoutes,
    );
  }

  /// Call on logout: stops fetching and drops this player's waiting pop-ups. Events already
  /// recorded stay queued and are sent at the next init.
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
