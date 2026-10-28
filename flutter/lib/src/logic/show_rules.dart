import '../model/inapp_popup.dart';

/// A route is blocked when it equals a blocked path or sits under it:
/// `/dashboard/deposit` blocks `/dashboard/deposit` and `/dashboard/deposit/card`, not
/// `/dashboard/deposit-log`. Query strings and fragments are ignored.
bool isRouteBlocked(String? route, List<String> blockedRoutes) {
  if (route == null) return false;
  final path = _normalise(Uri.tryParse(route)?.path ?? route);
  for (final blocked in blockedRoutes) {
    final b = _normalise(blocked);
    if (b.isEmpty) continue;
    if (path == b || path.startsWith(b == '/' ? '/' : '$b/')) return true;
  }
  return false;
}

String _normalise(String path) {
  final trimmed = path.trim();
  return trimmed.length > 1 && trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// The pop-up to show now, or null: never before the first screen is known, never on a blocked
/// route, never one already shown on this device, never an expired one; otherwise the newest.
InAppPopup? pickPopupToShow({
  required List<InAppPopup> waiting,
  required Set<String> shownIds,
  required String? route,
  required List<String> blockedRoutes,
  required DateTime now,
}) {
  if (route == null || isRouteBlocked(route, blockedRoutes)) return null;
  InAppPopup? best;
  for (final popup in waiting) {
    if (shownIds.contains(popup.id) || popup.isExpiredAt(now)) continue;
    if (best == null || popup.createdAt.isAfter(best.createdAt)) best = popup;
  }
  return best;
}
