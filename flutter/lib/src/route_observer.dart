import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'render/popup_view.dart';

/// Reports the top page's name as the current route. With go_router a page's name is the
/// route's `name`, or its `path` when it has none, so `blockedRoutes` are written as paths.
/// Dialogs and other non-page routes don't count as a new screen.
///
/// Given a [controller], it also makes Android back close a blocking pop-up instead of leaving
/// the page under it: while one is open, the top route holds a [LocalHistoryEntry], the way a
/// drawer does. Back pops that entry first, whichever observer the app registered first.
class PopupRouteObserver extends NavigatorObserver {
  PopupRouteObserver(this.onRoute, {this.controller}) {
    controller?.current.addListener(_syncBackEntry);
  }

  final void Function(String route) onRoute;
  final OptikpiPopupController? controller;

  ModalRoute<dynamic>? _top;
  LocalHistoryEntry? _entry;
  ModalRoute<dynamic>? _entryRoute;
  ActivePopup? _entryFor;

  void _report(Route<dynamic>? route) {
    if (route is! PageRoute) return;
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) onRoute(name);
  }

  void _setTop(Route<dynamic>? route) {
    _top = route is ModalRoute ? route : null;
    _syncBackEntry();
  }

  /// Keeps exactly one back entry, on the top route, while a blocking pop-up is open.
  void _syncBackEntry() {
    final active = controller?.current.value;
    final wanted = active != null && popupBlocksPage(active.content.layout) ? active : null;
    if (wanted != null && identical(wanted, _entryFor) && identical(_top, _entryRoute)) return;
    _dropBackEntry();
    final top = _top;
    if (wanted == null || top == null || !top.isActive) return;
    late final LocalHistoryEntry entry;
    entry = LocalHistoryEntry(
      // The page's AppBar must not grow a back button for it.
      impliesAppBarDismissal: false,
      onRemove: () {
        // Removed by back (or by the route going away), not by _dropBackEntry.
        if (!identical(_entry, entry)) return;
        _entry = null;
        _entryRoute = null;
        _entryFor = null;
        controller?.close(wanted, dismissed: true);
      },
    );
    _entry = entry;
    _entryRoute = top;
    _entryFor = wanted;
    top.addLocalHistoryEntry(entry);
  }

  void _dropBackEntry() {
    final entry = _entry;
    final route = _entryRoute;
    _entry = null;
    _entryRoute = null;
    _entryFor = null;
    if (entry != null && route != null && route.isActive) route.removeLocalHistoryEntry(entry);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _report(route);
    _setTop(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _report(previousRoute);
    _setTop(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, _top)) _setTop(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _report(newRoute);
    if (oldRoute == null || identical(oldRoute, _top)) _setTop(newRoute);
  }
}
