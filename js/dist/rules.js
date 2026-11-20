function normalise(path) {
    const trimmed = path.trim();
    return trimmed.length > 1 && trimmed.endsWith("/")
        ? trimmed.slice(0, -1)
        : trimmed;
}
export function isRouteBlocked(route, blockedRoutes) {
    if (!route)
        return false;
    let path = route;
    try {
        path = new URL(route, "https://local.invalid").pathname;
    }
    catch {
        path = route.split("?")[0].split("#")[0];
    }
    path = normalise(path);
    for (const blocked of blockedRoutes) {
        const b = normalise(blocked);
        if (!b)
            continue;
        if (path === b || path.startsWith(b === "/" ? "/" : `${b}/`))
            return true;
    }
    return false;
}
/** True when `expiresAt` is set and `now` is not still before it. */
export function isPopupExpired(popup, now) {
    return popup.expiresAt != null && !(now < popup.expiresAt);
}
export function pickPopupToShow(args) {
    const { waiting, shownIds, route, blockedRoutes, now } = args;
    if (!route || isRouteBlocked(route, blockedRoutes))
        return null;
    let best = null;
    for (const popup of waiting) {
        if (shownIds.has(popup.id))
            continue;
        if (isPopupExpired(popup, now))
            continue;
        if (!best || popup.createdAt > best.createdAt)
            best = popup;
    }
    return best;
}
export class FetchThrottle {
    constructor() {
        Object.defineProperty(this, "lastResponseAt", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: null
        });
        Object.defineProperty(this, "intervalMs", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: FetchThrottle.defaultIntervalMs
        });
    }
    canFetch(now) {
        return this.lastResponseAt == null || now.getTime() - this.lastResponseAt >= this.intervalMs;
    }
    recordResponse(at, nextCheckAfterSec) {
        this.lastResponseAt = at.getTime();
        this.intervalMs =
            nextCheckAfterSec == null
                ? FetchThrottle.defaultIntervalMs
                : Math.min(FetchThrottle.maxIntervalSec, Math.max(FetchThrottle.minIntervalSec, nextCheckAfterSec)) * 1000;
    }
}
Object.defineProperty(FetchThrottle, "defaultIntervalMs", {
    enumerable: true,
    configurable: true,
    writable: true,
    value: 300000
});
Object.defineProperty(FetchThrottle, "minIntervalSec", {
    enumerable: true,
    configurable: true,
    writable: true,
    value: 30
});
Object.defineProperty(FetchThrottle, "maxIntervalSec", {
    enumerable: true,
    configurable: true,
    writable: true,
    value: 24 * 60 * 60
});
//# sourceMappingURL=rules.js.map