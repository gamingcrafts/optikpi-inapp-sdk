import type { PopupEvent } from "./http.js";
export declare function loadShownIds(): Set<string>;
export declare function markShown(id: string): void;
export type ShownClaim = {
    id: string;
    token: string;
};
/**
 * - `claimed`: this call wrote a temporary lease. Finalize it after draw, or release it.
 * - `unstored`: nothing could be written (no storage, or a quota error). Show the popup anyway.
 * - `shown`: the id is already finalized as shown.
 * - `leased`: another page has a live lease; retry when `retryAfterMs` elapses.
 * - `stale`: `stillValid` was false once the lock was held, so nothing was written.
 */
export type ClaimResult = {
    status: "claimed";
    claim: ShownClaim;
} | {
    status: "leased";
    retryAfterMs: number;
} | {
    status: "unstored" | "shown" | "stale";
};
export declare function withEventFlushLock<T>(workspaceId: string, playerId: string, run: () => T | Promise<T>): Promise<T>;
/**
 * Leases [id] before a popup is drawn. A lease is separate from the durable shown
 * record, so a reload or crash before `didDraw` can recover it after expiry.
 */
export declare function claimShown(id: string, stillValid?: () => boolean): Promise<ClaimResult>;
/** Converts this lease into the durable shown record after the popup is drawn. */
export declare function finalizeShown(claim: ShownClaim): Promise<boolean>;
/** Extends this tab's lease. A replacement owner's lease is left unchanged. */
export declare function renewShown(claim: ShownClaim): Promise<boolean>;
/** Takes back this lease if the popup was never drawn. A newer owner's lease is untouched. */
export declare function releaseShown(claim: ShownClaim): Promise<void>;
export type QueuedEvent = {
    raw: string;
    workspaceId: string;
    playerId: string;
    event: PopupEvent;
};
export declare function enqueueEvent(event: PopupEvent, workspaceId: string, playerId: string): boolean;
export declare function queuedFor(workspaceId: string, playerId: string): QueuedEvent[];
export declare function removeQueued(raws: string[]): void;
