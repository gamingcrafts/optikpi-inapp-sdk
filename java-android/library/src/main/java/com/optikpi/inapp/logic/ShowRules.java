package com.optikpi.inapp.logic;

import android.net.Uri;
import com.optikpi.inapp.model.InAppPopup;
import java.time.Instant;
import java.util.List;
import java.util.Set;

public final class ShowRules {
  private ShowRules() {}

  public static boolean isRouteBlocked(String route, List<String> blockedRoutes) {
    if (route == null) {
      return false;
    }
    String path = normalise(Uri.parse(route).getPath() != null ? Uri.parse(route).getPath() : route);
    for (String blocked : blockedRoutes) {
      if (blocked == null) {
        continue;
      }
      String b = normalise(blocked);
      if (b.isEmpty()) {
        continue;
      }
      if (path.equals(b) || path.startsWith(b.equals("/") ? "/" : b + "/")) {
        return true;
      }
    }
    return false;
  }

  private static String normalise(String path) {
    if (path == null) {
      return "";
    }
    String trimmed = path.trim();
    if (trimmed.length() > 1 && trimmed.endsWith("/")) {
      return trimmed.substring(0, trimmed.length() - 1);
    }
    return trimmed;
  }

  public static InAppPopup pickPopupToShow(
      List<InAppPopup> waiting,
      Set<String> shownIds,
      String route,
      List<String> blockedRoutes,
      Instant now) {
    if (route == null || isRouteBlocked(route, blockedRoutes)) {
      return null;
    }
    InAppPopup best = null;
    for (InAppPopup popup : waiting) {
      if (shownIds.contains(popup.id) || popup.isExpiredAt(now)) {
        continue;
      }
      if (best == null || popup.createdAt.isAfter(best.createdAt)) {
        best = popup;
      }
    }
    return best;
  }
}