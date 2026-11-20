import { type PopupRequestContext } from "./http.js";
import type { InAppPopup, PopupContent } from "./parse.js";
export type PopupDeepLinkHandler = (link: string) => void;
export type PopupCustomActionHandler = (data: Record<string, string>) => void;
export type ActivePopup = {
    popup: InAppPopup;
    context: PopupRequestContext | null;
    onDeepLink?: PopupDeepLinkHandler;
    onCustomAction?: PopupCustomActionHandler;
    isTest: boolean;
};
export type InitOptions = {
    apiKey: string;
    playerToken: string;
    baseUrl: string;
    onDeepLink?: PopupDeepLinkHandler;
    onCustomAction?: PopupCustomActionHandler;
    blockedRoutes?: string[];
};
export declare class OptikpiInAppController {
    current: ActivePopup | null;
    private session;
    private setup;
    private lastPlayerKey;
    private route;
    private visit;
    private shownThisVisit;
    private picking;
    private pickAgain;
    /** Lease for `current` until `didDraw` finalizes it. Released if `current` is cleared first. */
    private undrawnClaim;
    private leaseRenewTimer;
    private pendingRelease;
    private claimRetryTimer;
    private flushTimer;
    private testCount;
    private listeners;
    private lifecycleBound;
    private resumeQueued;
    get isPaused(): boolean;
    get currentRoute(): string | null;
    subscribe(listener: () => void): () => void;
    private emit;
    private setCurrent;
    private requeueUndrawn;
    private releaseUndrawn;
    private holdLease;
    private stopLeaseRenewal;
    init(options: InitOptions): Promise<void>;
    setPlayerToken(playerToken: string): void;
    logout(): Promise<void>;
    didChangeRoute(route: string | null): void;
    onForeground(): void;
    /**
     * A hidden tab skips fetch, popup selection and flush. The page resumes all three
     * when it is shown again, or restored from the back-forward cache. Both events
     * in one turn resume once.
     */
    private bindLifecycle;
    private unbindLifecycle;
    private onVisibility;
    private onPageShow;
    private queueResume;
    showTest(content: PopupContent): void;
    didDraw(active: ActivePopup): void;
    private finishDraw;
    close(active: ActivePopup, dismissed: boolean): boolean;
    tapButton(active: ActivePopup, index: number): void;
    tapImage(active: ActivePopup): void;
    reset(): void;
    private contextFor;
    private startSession;
    private endSession;
    private fetchMoment;
    private inForeground;
    private maybeFetch;
    private pauseIfCurrent;
    private showMoment;
    private retryClaimAtExpiry;
    private maybeShow;
    private perform;
    private track;
    private scheduleFlush;
    private flush;
    private runFlush;
    /** One queue snapshot. A trigger during this pass sets `flushAgain` for a fresh snapshot. */
    private flushPass;
}
export declare const controller: OptikpiInAppController;
