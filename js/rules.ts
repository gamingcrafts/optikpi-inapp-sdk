import type { InAppPopup } from "./parse.js";

function normalise(path: string): string {
  const trimmed = path.trim();
  return trimmed.length > 1 && trimmed.endsWith("/")
    ? trimmed.slice(0, -1)
    : trimmed;
}

export function isRouteBlocked(route: string | null, blockedRoutes: string[]): boolean {
  if (!route) return false;
  let path = route;
  try {
    path = new URL(route, "https://local.invalid").pathname;
  } catch {
    path = route.split("?")[0].split("#")[0];
  }
  path = normalise(path);
  for (const blocked of blockedRoutes) {
    const b = normalise(blocked);
    if (!b) continue;
    if (path === b || path.startsWith(b === "/" ? "/" : `${b}/`)) return true;
  }
  return false;
}

/** True when `expiresAt` is set and `now` is not still before it. */
export function isPopupExpired(popup: InAppPopup, now: Date): boolean {
  return popup.expiresAt != null && !(now < popup.expiresAt);
}

export function pickPopupToShow(args: {
  waiting: InAppPopup[];
  shownIds: Set<string>;
  route: string | null;
  blockedRoutes: string[];
  now: Date;
}): InAppPopup | null {
  const { waiting, shownIds, route, blockedRoutes, now } = args;
  if (!route || isRouteBlocked(route, blockedRoutes)) return null;
  let best: InAppPopup | null = null;
  for (const popup of waiting) {
    if (shownIds.has(popup.id)) continue;
    if (isPopupExpired(popup, now)) continue;
    if (!best || popup.createdAt > best.createdAt) best = popup;
  }
  return best;
}

export class FetchThrottle {
  static readonly defaultIntervalMs = 300_000;
  static readonly minIntervalSec = 30;
  static readonly maxIntervalSec = 24 * 60 * 60;

  private lastResponseAt: number | null = null;
  intervalMs = FetchThrottle.defaultIntervalMs;

  canFetch(now: Date): boolean {
    return this.lastResponseAt == null || now.getTime() - this.lastResponseAt >= this.intervalMs;
  }

  recordResponse(at: Date, nextCheckAfterSec?: number) {
    this.lastResponseAt = at.getTime();
    this.intervalMs =
      nextCheckAfterSec == null
        ? FetchThrottle.defaultIntervalMs
        : Math.min(
            FetchThrottle.maxIntervalSec,
            Math.max(FetchThrottle.minIntervalSec, nextCheckAfterSec)
          ) * 1000;
  }
}
