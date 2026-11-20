import { fetchPopups, PopupHttpException, sendEvents } from "./http.js";
import { inAppLog } from "./log.js";
import { FetchThrottle, isPopupExpired, isRouteBlocked, pickPopupToShow } from "./rules.js";
import { claimShown, enqueueEvent, finalizeShown, loadShownIds, markShown, queuedFor, releaseShown, renewShown, removeQueued, withEventFlushLock, } from "./storage.js";
import { readPlayerTokenClaims } from "./token.js";
const IMAGE_WAIT_MS = 10000;
const FLUSH_DELAY_MS = 2000;
const LEASE_RENEW_MS = 20000;
const BATCH_SIZE = 50;
function rendersPopupImage(content) {
    if (!content.image)
        return false;
    switch (content.layout) {
        case "toast":
            return content.size === "md";
        case "bottomSheet":
            return content.size !== "sm";
        case "modal":
            return content.size !== "iab_300x250";
        case "banner":
        case "imageOnly":
            return true;
    }
}
function safeWebUrl(value) {
    try {
        const url = new URL(value, window.location.href);
        return url.protocol === "http:" || url.protocol === "https:" ? url.href : null;
    }
    catch {
        return null;
    }
}
export class OptikpiInAppController {
    constructor() {
        Object.defineProperty(this, "current", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: null
        });
        Object.defineProperty(this, "session", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: null
        });
        Object.defineProperty(this, "setup", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: null
        });
        Object.defineProperty(this, "lastPlayerKey", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: null
        });
        Object.defineProperty(this, "route", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: null
        });
        Object.defineProperty(this, "visit", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: 0
        });
        Object.defineProperty(this, "shownThisVisit", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: false
        });
        Object.defineProperty(this, "picking", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: false
        });
        Object.defineProperty(this, "pickAgain", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: false
        });
        /** Lease for `current` until `didDraw` finalizes it. Released if `current` is cleared first. */
        Object.defineProperty(this, "undrawnClaim", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: null
        });
        Object.defineProperty(this, "leaseRenewTimer", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: null
        });
        Object.defineProperty(this, "pendingRelease", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: Promise.resolve()
        });
        Object.defineProperty(this, "claimRetryTimer", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: null
        });
        Object.defineProperty(this, "flushTimer", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: null
        });
        Object.defineProperty(this, "testCount", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: 0
        });
        Object.defineProperty(this, "listeners", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: new Set()
        });
        Object.defineProperty(this, "lifecycleBound", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: false
        });
        Object.defineProperty(this, "resumeQueued", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: false
        });
        Object.defineProperty(this, "onVisibility", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: () => {
                if (typeof document !== "undefined" && document.visibilityState === "visible") {
                    this.queueResume();
                }
            }
        });
        Object.defineProperty(this, "onPageShow", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: (event) => {
                if (event.persisted)
                    this.queueResume();
            }
        });
    }
    get isPaused() {
        return this.session?.paused ?? false;
    }
    get currentRoute() {
        return this.route;
    }
    subscribe(listener) {
        this.listeners.add(listener);
        return () => {
            this.listeners.delete(listener);
        };
    }
    emit() {
        this.listeners.forEach((listener) => listener());
    }
    setCurrent(value) {
        const previous = this.current;
        this.current = value;
        this.emit();
        if (previous &&
            !previous.isTest &&
            previous.popup.id === this.undrawnClaim?.id &&
            value?.popup.id !== previous.popup.id) {
            this.requeueUndrawn(previous.popup);
            this.releaseUndrawn(previous.popup.id);
        }
    }
    requeueUndrawn(popup) {
        const session = this.session;
        if (!session || session.waiting.some((waiting) => waiting.id === popup.id))
            return;
        session.waiting = [...session.waiting, popup];
    }
    releaseUndrawn(id) {
        if (this.undrawnClaim?.id !== id)
            return;
        const claim = this.undrawnClaim;
        this.undrawnClaim = null;
        this.stopLeaseRenewal();
        inAppLog(`release ${id}: not drawn`);
        this.pendingRelease = releaseShown(claim);
    }
    holdLease(claim) {
        this.stopLeaseRenewal();
        this.undrawnClaim = claim;
        if (!claim)
            return;
        const renew = () => {
            if (this.undrawnClaim?.token !== claim.token)
                return;
            void renewShown(claim).then((kept) => {
                if (this.undrawnClaim?.token !== claim.token)
                    return;
                if (!kept) {
                    this.undrawnClaim = null;
                    this.stopLeaseRenewal();
                    if (this.current?.popup.id === claim.id && !this.current.isTest) {
                        inAppLog(`drop ${claim.id}: another page owns its claim`);
                        this.setCurrent(null);
                    }
                    return;
                }
                this.leaseRenewTimer = setTimeout(renew, LEASE_RENEW_MS);
            });
        };
        this.leaseRenewTimer = setTimeout(renew, LEASE_RENEW_MS);
    }
    stopLeaseRenewal() {
        if (!this.leaseRenewTimer)
            return;
        clearTimeout(this.leaseRenewTimer);
        this.leaseRenewTimer = null;
    }
    async init(options) {
        const setup = {
            apiKey: options.apiKey,
            baseUrl: options.baseUrl,
            onDeepLink: options.onDeepLink,
            onCustomAction: options.onCustomAction,
            blockedRoutes: options.blockedRoutes ?? [],
        };
        const context = this.contextFor(setup, options.playerToken);
        if (!context) {
            inAppLog("player token unreadable: not fetching");
            this.endSession(false);
            this.setup = setup;
            return;
        }
        await this.startSession(context, setup);
    }
    setPlayerToken(playerToken) {
        const setup = this.setup;
        if (!setup) {
            inAppLog("setPlayerToken before init: ignored");
            return;
        }
        const context = this.contextFor(setup, playerToken);
        if (!context) {
            inAppLog("player token unreadable: not fetching");
            if (this.session)
                this.session.paused = true;
            return;
        }
        const session = this.session;
        if (!session ||
            session.context.playerId !== context.playerId ||
            session.context.workspaceId !== context.workspaceId) {
            void this.startSession(context, setup);
            return;
        }
        session.context = context;
        session.paused = false;
        inAppLog("player token replaced");
        void this.flush(session);
        this.fetchMoment();
    }
    async logout() {
        inAppLog("logout");
        const finalFlush = this.endSession(!(this.session?.paused ?? false));
        this.setup = null;
        this.unbindLifecycle();
        await finalFlush;
    }
    didChangeRoute(route) {
        if (!route || route === this.route)
            return;
        this.route = route;
        this.visit += 1;
        this.shownThisVisit = false;
        inAppLog(`route ${route}`);
        const active = this.current;
        const session = this.session;
        if (active &&
            !active.isTest &&
            session &&
            isRouteBlocked(route, session.blockedRoutes)) {
            inAppLog(`hide ${active.popup.id}: ${route} is blocked`);
            this.setCurrent(null);
        }
        const released = this.pendingRelease;
        void released.then(() => {
            if (this.route !== route)
                return;
            this.showMoment();
            this.fetchMoment();
        });
    }
    onForeground() {
        const session = this.session;
        if (!session)
            return;
        void this.flush(session);
        this.fetchMoment();
        this.showMoment();
    }
    /**
     * A hidden tab skips fetch, popup selection and flush. The page resumes all three
     * when it is shown again, or restored from the back-forward cache. Both events
     * in one turn resume once.
     */
    bindLifecycle() {
        if (this.lifecycleBound || typeof document === "undefined" || typeof window === "undefined") {
            return;
        }
        document.addEventListener("visibilitychange", this.onVisibility);
        window.addEventListener("pageshow", this.onPageShow);
        this.lifecycleBound = true;
    }
    unbindLifecycle() {
        if (!this.lifecycleBound || typeof document === "undefined" || typeof window === "undefined") {
            return;
        }
        document.removeEventListener("visibilitychange", this.onVisibility);
        window.removeEventListener("pageshow", this.onPageShow);
        this.lifecycleBound = false;
    }
    queueResume() {
        if (this.resumeQueued)
            return;
        this.resumeQueued = true;
        queueMicrotask(() => {
            this.resumeQueued = false;
            this.onForeground();
        });
    }
    showTest(content) {
        this.testCount += 1;
        const popup = {
            id: `test-${this.testCount}`,
            trackingId: `test-${this.testCount}`,
            createdAt: new Date(),
            content,
        };
        this.setCurrent({
            popup,
            context: null,
            onDeepLink: this.session?.onDeepLink,
            onCustomAction: this.session?.onCustomAction,
            isTest: true,
        });
    }
    didDraw(active) {
        if (this.current !== active)
            return;
        if (active.isTest) {
            inAppLog(`test pop-up drawn (${active.popup.content.layout})`);
            return;
        }
        if (isPopupExpired(active.popup, new Date())) {
            inAppLog(`drop ${active.popup.id}: expired before it was drawn`);
            this.setCurrent(null);
            if (this.session) {
                this.session.waiting = this.session.waiting.filter((popup) => popup.id !== active.popup.id);
            }
            this.shownThisVisit = false;
            this.showMoment();
            return;
        }
        const at = new Date().toISOString();
        if (this.undrawnClaim?.id === active.popup.id) {
            const claim = this.undrawnClaim;
            this.undrawnClaim = null;
            this.stopLeaseRenewal();
            void this.finishDraw(active, claim, at);
            return;
        }
        // Storage may have been unavailable when selection ran.
        markShown(active.popup.id);
        this.track(active, "impression", undefined, at);
    }
    async finishDraw(active, claim, at) {
        const owned = await finalizeShown(claim);
        if (!owned) {
            inAppLog(`drop ${claim.id}: its claim was replaced before draw`);
            if (this.current === active)
                this.setCurrent(null);
            return;
        }
        this.track(active, "impression", undefined, at);
    }
    close(active, dismissed) {
        if (this.current !== active)
            return false;
        this.setCurrent(null);
        if (dismissed)
            this.track(active, "dismiss");
        return true;
    }
    tapButton(active, index) {
        if (index < 0 || index >= active.popup.content.buttons.length)
            return;
        if (!this.close(active, false))
            return;
        this.track(active, "click", index);
        this.perform(active, active.popup.content.buttons[index].action);
    }
    tapImage(active) {
        const action = active.popup.content.image?.tapAction;
        if (!action && active.popup.content.layout !== "imageOnly")
            return;
        if (!this.close(active, false))
            return;
        this.track(active, "click");
        if (action)
            this.perform(active, action);
    }
    reset() {
        this.endSession(false);
        this.setup = null;
        this.lastPlayerKey = null;
        this.setCurrent(null);
        this.route = null;
        this.visit = 0;
        this.shownThisVisit = false;
        this.picking = false;
        this.pickAgain = false;
        this.unbindLifecycle();
    }
    contextFor(setup, playerToken) {
        const claims = readPlayerTokenClaims(playerToken);
        if (!claims)
            return null;
        return {
            baseUrl: setup.baseUrl,
            workspaceId: claims.workspaceId,
            playerId: claims.playerId,
            apiKey: setup.apiKey,
            playerToken,
        };
    }
    async startSession(context, setup) {
        const previous = this.session;
        const switching = previous != null &&
            (previous.context.playerId !== context.playerId ||
                previous.context.workspaceId !== context.workspaceId);
        this.endSession(switching && !previous.paused);
        const session = {
            context,
            onDeepLink: setup.onDeepLink,
            onCustomAction: setup.onCustomAction,
            blockedRoutes: [...setup.blockedRoutes],
            throttle: new FetchThrottle(),
            waiting: [],
            fetching: false,
            paused: false,
            flushing: false,
            flushAgain: false,
            flushPromise: null,
        };
        this.session = session;
        this.setup = setup;
        const playerKey = `${context.workspaceId}/${context.playerId}`;
        if (playerKey !== this.lastPlayerKey)
            this.shownThisVisit = false;
        this.lastPlayerKey = playerKey;
        inAppLog(`init workspace ${context.workspaceId} player ${context.playerId}`);
        this.bindLifecycle();
        void this.flush(session);
        this.fetchMoment();
    }
    endSession(flush) {
        const session = this.session;
        this.session = null;
        if (this.flushTimer) {
            clearTimeout(this.flushTimer);
            this.flushTimer = null;
        }
        if (this.claimRetryTimer) {
            clearTimeout(this.claimRetryTimer);
            this.claimRetryTimer = null;
        }
        this.stopLeaseRenewal();
        if (this.current && !this.current.isTest)
            this.setCurrent(null);
        else if (this.undrawnClaim)
            this.releaseUndrawn(this.undrawnClaim.id);
        if (!session)
            return Promise.resolve();
        // A paused or hidden session must not start another POST, but logout still
        // has to wait for the one already in flight.
        if (flush)
            return this.flush(session);
        return session.flushPromise ?? Promise.resolve();
    }
    fetchMoment() {
        const session = this.session;
        if (!session)
            return;
        void this.maybeFetch(session);
    }
    inForeground() {
        if (typeof document === "undefined")
            return true;
        return document.visibilityState !== "hidden";
    }
    async maybeFetch(session) {
        if (session.paused ||
            session.fetching ||
            !this.inForeground() ||
            !session.throttle.canFetch(new Date())) {
            return;
        }
        session.fetching = true;
        const context = session.context;
        let tokenChanged = false;
        try {
            const result = await fetchPopups(context);
            if (this.session !== session)
                return;
            session.throttle.recordResponse(new Date(), result.nextCheckAfterSec);
            session.waiting = result.popups;
            inAppLog(`fetched ${result.popups.length} pop-up(s), next check in ${Math.round(session.throttle.intervalMs / 1000)} s`);
            void this.flush(session);
            this.showMoment();
        }
        catch (error) {
            inAppLog(`fetch failed: ${error}`);
            if (error instanceof PopupHttpException && error.isAuthFailure) {
                tokenChanged = !this.pauseIfCurrent(session, context);
            }
        }
        finally {
            session.fetching = false;
        }
        if (tokenChanged && this.session === session)
            this.fetchMoment();
    }
    pauseIfCurrent(session, context) {
        if (context !== session.context)
            return false;
        inAppLog("player token refused: paused until setPlayerToken");
        session.paused = true;
        return true;
    }
    showMoment() {
        const session = this.session;
        if (!session)
            return;
        void this.maybeShow(session);
    }
    retryClaimAtExpiry(session, retryAfterMs) {
        if (this.claimRetryTimer)
            clearTimeout(this.claimRetryTimer);
        this.claimRetryTimer = setTimeout(() => {
            this.claimRetryTimer = null;
            if (this.session === session)
                this.showMoment();
        }, Math.max(0, Math.ceil(retryAfterMs)) + 25);
    }
    async maybeShow(session) {
        if (this.picking) {
            this.pickAgain = true;
            return;
        }
        if (!this.inForeground())
            return;
        if (this.shownThisVisit || this.current)
            return;
        this.picking = true;
        this.pickAgain = false;
        const visit = this.visit;
        let next = null;
        let claim = null;
        // True while nothing has changed since this pick began. Checked before the claim
        // and again inside its lock, where a wait for another tab can span a route change.
        const stillValid = () => this.session === session &&
            visit === this.visit &&
            !this.pickAgain &&
            !this.shownThisVisit &&
            !this.current &&
            this.inForeground();
        let claimed = null;
        const giveBack = () => {
            if (!claimed)
                return;
            const claimToRelease = claimed;
            claimed = null;
            inAppLog(`release ${claimToRelease.id}: not shown`);
            void releaseShown(claimToRelease);
        };
        try {
            next = pickPopupToShow({
                waiting: session.waiting,
                shownIds: loadShownIds(),
                route: this.route,
                blockedRoutes: session.blockedRoutes,
                now: new Date(),
            });
            const image = next?.content.image;
            if (next && image && rendersPopupImage(next.content) && !image.url.startsWith("gradient:")) {
                await Promise.race([
                    preloadImage(image.url),
                    new Promise((resolve) => setTimeout(resolve, IMAGE_WAIT_MS)),
                ]);
            }
            if (next && isPopupExpired(next, new Date())) {
                inAppLog(`skip ${next.id}: expired while its image loaded`);
                session.waiting = session.waiting.filter((popup) => popup.id !== next.id);
                next = null;
                this.pickAgain = true;
            }
            if (next && stillValid()) {
                const selected = next;
                claim = await claimShown(selected.id, stillValid);
                if (isPopupExpired(selected, new Date())) {
                    inAppLog(`skip ${selected.id}: expired while its claim was acquired`);
                    if (claim.status === "claimed")
                        void releaseShown(claim.claim);
                    session.waiting = session.waiting.filter((popup) => popup.id !== selected.id);
                    next = null;
                    claim = { status: "stale" };
                    this.pickAgain = true;
                }
                else if (claim.status === "claimed")
                    claimed = claim.claim;
                else if (claim.status === "shown") {
                    inAppLog(`skip ${selected.id}: already shown`);
                    session.waiting = session.waiting.filter((popup) => popup.id !== selected.id);
                    next = null;
                    this.pickAgain = true;
                }
                else if (claim.status === "leased") {
                    inAppLog(`retry ${selected.id}: another page holds a temporary claim`);
                    this.retryClaimAtExpiry(session, claim.retryAfterMs);
                    next = null;
                }
            }
        }
        catch (error) {
            inAppLog(`pick failed: ${error}`);
            next = null;
            giveBack();
        }
        finally {
            this.picking = false;
        }
        if (this.session !== session) {
            giveBack();
            if (this.pickAgain)
                this.showMoment();
            return;
        }
        if (visit !== this.visit || this.pickAgain) {
            giveBack();
            return this.maybeShow(session);
        }
        if (!next ||
            (claim?.status !== "claimed" && claim?.status !== "unstored") ||
            this.shownThisVisit ||
            this.current ||
            !this.inForeground()) {
            giveBack();
            return;
        }
        const held = claim.status === "claimed" ? claimed : null;
        claimed = null;
        if (this.undrawnClaim && this.undrawnClaim.token !== held?.token) {
            this.releaseUndrawn(this.undrawnClaim.id);
        }
        this.holdLease(held);
        if (this.claimRetryTimer) {
            clearTimeout(this.claimRetryTimer);
            this.claimRetryTimer = null;
        }
        this.shownThisVisit = true;
        session.waiting = session.waiting.filter((popup) => popup.id !== next.id);
        inAppLog(`show ${next.id} (${next.content.layout}) on ${this.route}`);
        this.setCurrent({
            popup: next,
            context: session.context,
            onDeepLink: session.onDeepLink,
            onCustomAction: session.onCustomAction,
            isTest: false,
        });
    }
    perform(active, action) {
        switch (action.type) {
            case "dismiss":
                return;
            case "deeplink":
                if (action.value)
                    active.onDeepLink?.(action.value);
                return;
            case "custom":
                if (action.customData) {
                    active.onCustomAction?.(Object.fromEntries(action.customData.map((pair) => [pair.key, pair.value])));
                }
                return;
            case "url": {
                if (!action.value)
                    return;
                const url = safeWebUrl(action.value);
                if (!url) {
                    inAppLog(`blocked unsafe URL action: ${action.value}`);
                    return;
                }
                try {
                    window.open(url, "_blank", "noopener,noreferrer");
                }
                catch (error) {
                    inAppLog(`could not open ${url}: ${error}`);
                }
            }
        }
    }
    track(active, type, buttonIndex, at = new Date().toISOString()) {
        if (active.isTest) {
            inAppLog(`test ${type}${buttonIndex != null ? ` button ${buttonIndex}` : ""}`);
            return;
        }
        const context = active.context;
        const event = {
            trackingId: active.popup.trackingId,
            type,
            at,
            buttonIndex,
        };
        if (enqueueEvent(event, context.workspaceId, context.playerId)) {
            this.scheduleFlush();
        }
    }
    scheduleFlush() {
        const session = this.session;
        if (!session)
            return;
        if (this.flushTimer)
            clearTimeout(this.flushTimer);
        this.flushTimer = setTimeout(() => {
            if (this.session === session)
                void this.flush(session);
        }, FLUSH_DELAY_MS);
    }
    flush(session) {
        const canStart = !session.paused && this.inForeground();
        if (session.flushing) {
            if (canStart)
                session.flushAgain = true;
            return session.flushPromise ?? Promise.resolve();
        }
        if (!canStart)
            return Promise.resolve();
        session.flushing = true;
        const promise = this.runFlush(session);
        session.flushPromise = promise;
        return promise;
    }
    async runFlush(session) {
        try {
            do {
                session.flushAgain = false;
                if (session.paused || !this.inForeground())
                    return;
                if (!(await this.flushPass(session)))
                    return;
            } while (session.flushAgain);
        }
        finally {
            const retry = session.flushAgain;
            session.flushAgain = false;
            session.flushing = false;
            session.flushPromise = null;
            if (retry && this.session === session)
                this.scheduleFlush();
        }
    }
    /** One queue snapshot. A trigger during this pass sets `flushAgain` for a fresh snapshot. */
    async flushPass(session) {
        const context = session.context;
        try {
            return await withEventFlushLock(context.workspaceId, context.playerId, async () => {
                const items = queuedFor(context.workspaceId, context.playerId);
                for (let start = 0; start < items.length; start += BATCH_SIZE) {
                    const batch = items.slice(start, start + BATCH_SIZE);
                    try {
                        await sendEvents(context, batch.map((item) => item.event));
                    }
                    catch (error) {
                        inAppLog(`event send failed, will retry: ${error}`);
                        if (error instanceof PopupHttpException && error.isAuthFailure) {
                            this.pauseIfCurrent(session, context);
                        }
                        return false;
                    }
                    removeQueued(batch.map((item) => item.raw));
                }
                return true;
            });
        }
        catch (error) {
            inAppLog(`flush failed: ${error}`);
            return false;
        }
    }
}
function preloadImage(url) {
    return new Promise((resolve) => {
        const image = new Image();
        image.onload = () => resolve();
        image.onerror = () => resolve();
        image.src = url;
    });
}
export const controller = new OptikpiInAppController();
//# sourceMappingURL=controller.js.map