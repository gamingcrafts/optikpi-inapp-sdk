import { inAppLog } from "./log.js";
/** One shown popup id. The suffix is the id, so two tabs never share a list. */
const SHOWN_PREFIX = "optikpi_inapp.s.";
/** A temporary pre-draw claim. It becomes a shown record only after `didDraw`. */
const SHOWN_CLAIM_PREFIX = "optikpi_inapp.c.";
/** Earlier builds stored shown ids as one JSON list. Read once, then drop. */
const LEGACY_SHOWN_KEY = "optikpi_inapp.shown";
/** One pending event. The suffix is the dedupe key, so two tabs never share a list. */
const PENDING_PREFIX = "optikpi_inapp.q.";
/** One dedupe key. Kept after the event is sent so it is queued only once. */
const SEEN_PREFIX = "optikpi_inapp.t.";
/** Earlier builds stored both of those as JSON lists. Read once, then drop. */
const LEGACY_QUEUE_KEY = "optikpi_inapp.events";
const LEGACY_TRACKED_KEY = "optikpi_inapp.tracked";
const MAX_SHOWN = 500;
/** Serializes check-and-set of a shown id so two tabs cannot both claim it. */
const SHOWN_LOCK = "optikpi_inapp.shown";
const EVENT_FLUSH_LOCK_PREFIX = "optikpi_inapp.flush.";
const LOCK_DB_NAME = "optikpi_inapp_locks";
const LOCK_STORE = "locks";
const LOCK_LEASE_MS = 30000;
const LOCK_RENEW_MS = 10000;
/** Long enough for React to paint; short enough to recover after a terminated page. */
const SHOWN_CLAIM_LEASE_MS = 60000;
const MAX_QUEUED = 500;
const MAX_TRACKED = 2000;
/** Fallback for denied or quota-full localStorage. It lasts for this page session. */
const memoryPending = new Map();
const memorySeen = new Map();
const memoryShown = new Map();
let lockDbPromise = null;
function readList(key) {
    if (typeof window === "undefined")
        return [];
    try {
        const raw = window.localStorage.getItem(key);
        if (!raw)
            return [];
        const parsed = JSON.parse(raw);
        return Array.isArray(parsed) ? parsed.filter((item) => typeof item === "string") : [];
    }
    catch {
        return [];
    }
}
function shownKey(id) {
    return SHOWN_PREFIX + encodeURIComponent(id);
}
function shownClaimKey(id) {
    return SHOWN_CLAIM_PREFIX + encodeURIComponent(id);
}
/**
 * A JSON list is one read-modify-write. Two tabs can read the same snapshot and the
 * later setItem drops the other tab's shown id, so that popup can appear again.
 * Each id is its own key, so one tab's write cannot replace the other's.
 */
function migrateShown(storage) {
    if (storage.getItem(LEGACY_SHOWN_KEY) != null) {
        readList(LEGACY_SHOWN_KEY).forEach((id, index) => {
            remember(storage, shownKey(id), String(index).padStart(8, "0"));
        });
        storage.removeItem(LEGACY_SHOWN_KEY);
    }
    trimOldest(storage, SHOWN_PREFIX, MAX_SHOWN, (key) => storage.getItem(key) ?? "", "");
}
export function loadShownIds() {
    const ids = new Set(memoryShown.keys());
    const storage = localStorageOrNull();
    if (!storage)
        return ids;
    try {
        migrateShown(storage);
        for (const key of keysWithPrefix(storage, SHOWN_PREFIX)) {
            ids.add(decodeURIComponent(key.slice(SHOWN_PREFIX.length)));
        }
    }
    catch (error) {
        inAppLog(`could not read shown ids: ${error}`);
    }
    return ids;
}
function writeShown(storage, id) {
    migrateShown(storage);
    const key = shownKey(id);
    if (storage.getItem(key) != null)
        return false;
    storage.setItem(key, new Date().toISOString());
    trimOldest(storage, SHOWN_PREFIX, MAX_SHOWN, (item) => storage.getItem(item) ?? "", key);
    return true;
}
function rememberShownInMemory(id) {
    if (!id || memoryShown.has(id))
        return;
    memoryShown.set(id, new Date().toISOString());
    trimMemory(memoryShown, MAX_SHOWN, (at) => at);
}
export function markShown(id) {
    rememberShownInMemory(id);
    const storage = localStorageOrNull();
    if (!storage)
        return;
    try {
        writeShown(storage, id);
    }
    catch (error) {
        inAppLog(`could not remember shown id: ${error}`);
    }
}
function openLockDb() {
    if (lockDbPromise)
        return lockDbPromise;
    if (typeof indexedDB === "undefined") {
        return Promise.reject(new Error("cross-tab locking is unavailable"));
    }
    lockDbPromise = new Promise((resolve, reject) => {
        const request = indexedDB.open(LOCK_DB_NAME, 1);
        request.onupgradeneeded = () => {
            if (!request.result.objectStoreNames.contains(LOCK_STORE)) {
                request.result.createObjectStore(LOCK_STORE);
            }
        };
        request.onsuccess = () => {
            request.result.onversionchange = () => request.result.close();
            resolve(request.result);
        };
        request.onerror = () => reject(request.error ?? new Error("could not open lock database"));
        request.onblocked = () => reject(new Error("lock database upgrade was blocked"));
    });
    lockDbPromise.catch(() => {
        lockDbPromise = null;
    });
    return lockDbPromise;
}
async function changeFallbackLock(name, owner, operation) {
    const db = await openLockDb();
    return new Promise((resolve, reject) => {
        const transaction = db.transaction(LOCK_STORE, "readwrite");
        const store = transaction.objectStore(LOCK_STORE);
        const request = store.get(name);
        let changed = false;
        request.onsuccess = () => {
            const current = request.result;
            const owned = current?.owner === owner;
            if (operation === "acquire" && (!current || current.expiresAt <= Date.now() || owned)) {
                store.put({ owner, expiresAt: Date.now() + LOCK_LEASE_MS }, name);
                changed = true;
            }
            else if (operation === "renew" && owned) {
                store.put({ owner, expiresAt: Date.now() + LOCK_LEASE_MS }, name);
                changed = true;
            }
            else if (operation === "release" && owned) {
                store.delete(name);
                changed = true;
            }
        };
        transaction.oncomplete = () => resolve(changed);
        transaction.onerror = () => reject(transaction.error ?? new Error(`could not ${operation} cross-tab lock`));
        transaction.onabort = () => reject(transaction.error ?? new Error(`could not ${operation} cross-tab lock`));
    });
}
function waitForLockRetry() {
    return new Promise((resolve) => setTimeout(resolve, 50));
}
async function withIndexedDbLock(name, run) {
    const owner = claimToken();
    while (!(await changeFallbackLock(name, owner, "acquire"))) {
        await waitForLockRetry();
    }
    const heartbeat = setInterval(() => {
        void changeFallbackLock(name, owner, "renew").catch((error) => {
            inAppLog(`could not renew cross-tab lock: ${error}`);
        });
    }, LOCK_RENEW_MS);
    try {
        return await run();
    }
    finally {
        clearInterval(heartbeat);
        await changeFallbackLock(name, owner, "release").catch((error) => {
            inAppLog(`could not release cross-tab lock: ${error}`);
        });
    }
}
async function withCrossTabLock(name, run) {
    const locks = typeof navigator !== "undefined" ? navigator.locks : undefined;
    if (locks) {
        try {
            return await locks.request(name, run);
        }
        catch (error) {
            inAppLog(`web lock failed: ${error}`);
        }
    }
    try {
        return await withIndexedDbLock(name, run);
    }
    catch (error) {
        inAppLog(`cross-tab lock unavailable: ${error}`);
        return run();
    }
}
function withShownLock(run) {
    return withCrossTabLock(SHOWN_LOCK, run);
}
export function withEventFlushLock(workspaceId, playerId, run) {
    const scope = encodeURIComponent(`${workspaceId}|${playerId}`);
    return withCrossTabLock(`${EVENT_FLUSH_LOCK_PREFIX}${scope}`, run);
}
function readShownClaim(storage, id) {
    const raw = storage.getItem(shownClaimKey(id));
    if (!raw)
        return null;
    try {
        const parsed = JSON.parse(raw);
        return typeof parsed.token === "string" &&
            typeof parsed.expiresAt === "number" &&
            Number.isFinite(parsed.expiresAt)
            ? { token: parsed.token, expiresAt: parsed.expiresAt }
            : null;
    }
    catch {
        return null;
    }
}
function claimToken() {
    if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
        return crypto.randomUUID();
    }
    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}
/**
 * Leases [id] before a popup is drawn. A lease is separate from the durable shown
 * record, so a reload or crash before `didDraw` can recover it after expiry.
 */
export function claimShown(id, stillValid = () => true) {
    if (memoryShown.has(id))
        return Promise.resolve({ status: "shown" });
    const storage = localStorageOrNull();
    if (!storage || !id) {
        return Promise.resolve({ status: stillValid() ? "unstored" : "stale" });
    }
    return withShownLock(() => {
        if (!stillValid())
            return { status: "stale" };
        try {
            migrateShown(storage);
            if (storage.getItem(shownKey(id)) != null)
                return { status: "shown" };
            const key = shownClaimKey(id);
            const existing = readShownClaim(storage, id);
            const now = Date.now();
            if (existing && existing.expiresAt > now) {
                return { status: "leased", retryAfterMs: existing.expiresAt - now };
            }
            // Invalid and expired leases are recoverable. This write replaces either one.
            const claim = { id, token: claimToken() };
            storage.setItem(key, JSON.stringify({ token: claim.token, expiresAt: now + SHOWN_CLAIM_LEASE_MS }));
            return { status: "claimed", claim };
        }
        catch (error) {
            inAppLog(`could not claim shown id: ${error}`);
            return { status: "unstored" };
        }
    });
}
/** Converts this lease into the durable shown record after the popup is drawn. */
export async function finalizeShown(claim) {
    const storage = localStorageOrNull();
    if (!claim.id)
        return false;
    if (!storage) {
        rememberShownInMemory(claim.id);
        return true;
    }
    try {
        return await withShownLock(() => {
            const stored = readShownClaim(storage, claim.id);
            if (stored?.token !== claim.token)
                return false;
            storage.removeItem(shownClaimKey(claim.id));
            rememberShownInMemory(claim.id);
            try {
                writeShown(storage, claim.id);
            }
            catch (error) {
                inAppLog(`could not store shown id, kept in memory: ${error}`);
            }
            return true;
        });
    }
    catch (error) {
        inAppLog(`could not finalize shown id: ${error}`);
        return false;
    }
}
/** Extends this tab's lease. A replacement owner's lease is left unchanged. */
export async function renewShown(claim) {
    const storage = localStorageOrNull();
    if (!claim.id)
        return false;
    if (!storage)
        return true;
    try {
        return await withShownLock(() => {
            const stored = readShownClaim(storage, claim.id);
            if (stored?.token !== claim.token)
                return false;
            storage.setItem(shownClaimKey(claim.id), JSON.stringify({ token: claim.token, expiresAt: Date.now() + SHOWN_CLAIM_LEASE_MS }));
            return true;
        });
    }
    catch (error) {
        inAppLog(`could not renew shown claim: ${error}`);
        return false;
    }
}
/** Takes back this lease if the popup was never drawn. A newer owner's lease is untouched. */
export async function releaseShown(claim) {
    const storage = localStorageOrNull();
    if (!storage || !claim.id)
        return;
    try {
        await withShownLock(() => {
            const stored = readShownClaim(storage, claim.id);
            if (stored?.token === claim.token)
                storage.removeItem(shownClaimKey(claim.id));
        });
    }
    catch (error) {
        inAppLog(`could not release shown id: ${error}`);
    }
}
function parseQueued(raw) {
    try {
        const json = JSON.parse(raw);
        const event = json.event;
        if (typeof json.workspaceId !== "string" ||
            typeof json.playerId !== "string" ||
            !event ||
            typeof event.trackingId !== "string" ||
            typeof event.type !== "string" ||
            typeof event.at !== "string") {
            return null;
        }
        return {
            raw,
            workspaceId: json.workspaceId,
            playerId: json.playerId,
            event,
        };
    }
    catch {
        return null;
    }
}
function eventDedupeKey(workspaceId, playerId, event) {
    return `${workspaceId}|${playerId}|${event.trackingId}|${event.type}`;
}
function enqueueInMemory(event, workspaceId, playerId, dedupeKey) {
    if (memorySeen.has(dedupeKey))
        return false;
    const raw = JSON.stringify({ workspaceId, playerId, event });
    memoryPending.set(dedupeKey, { raw, workspaceId, playerId, event });
    memorySeen.set(dedupeKey, event.at);
    trimMemory(memoryPending, MAX_QUEUED, (item) => item.event.at);
    trimMemory(memorySeen, MAX_TRACKED, (at) => at);
    inAppLog(`queued ${event.type} ${event.trackingId} in memory`);
    return true;
}
function trimMemory(map, max, stamp) {
    const extra = map.size - max;
    if (extra <= 0)
        return;
    const oldest = [...map.entries()]
        .sort((a, b) => stamp(a[1]).localeCompare(stamp(b[1])))
        .slice(0, extra);
    for (const [key] of oldest)
        map.delete(key);
}
function localStorageOrNull() {
    if (typeof window === "undefined")
        return null;
    try {
        return window.localStorage;
    }
    catch {
        return null;
    }
}
function pendingKey(dedupeKey) {
    return PENDING_PREFIX + encodeURIComponent(dedupeKey);
}
function seenKey(dedupeKey) {
    return SEEN_PREFIX + encodeURIComponent(dedupeKey);
}
function keysWithPrefix(storage, prefix) {
    const keys = [];
    for (let i = 0; i < storage.length; i++) {
        const key = storage.key(i);
        if (key != null && key.startsWith(prefix))
            keys.push(key);
    }
    return keys;
}
function remember(storage, key, value) {
    if (storage.getItem(key) == null)
        storage.setItem(key, value);
}
/**
 * A JSON list is one read-modify-write. Two tabs can read the same snapshot and the
 * later setItem drops the other tab's impression or click. Each event is its own key,
 * so one tab's write cannot replace the other's.
 */
function migrateLegacyLists(storage) {
    if (storage.getItem(LEGACY_TRACKED_KEY) != null) {
        for (const dedupeKey of readList(LEGACY_TRACKED_KEY)) {
            remember(storage, seenKey(dedupeKey), "1");
        }
        storage.removeItem(LEGACY_TRACKED_KEY);
    }
    if (storage.getItem(LEGACY_QUEUE_KEY) != null) {
        for (const raw of readList(LEGACY_QUEUE_KEY)) {
            const parsed = parseQueued(raw);
            if (!parsed)
                continue;
            const dedupeKey = eventDedupeKey(parsed.workspaceId, parsed.playerId, parsed.event);
            remember(storage, pendingKey(dedupeKey), raw);
            remember(storage, seenKey(dedupeKey), parsed.event.at || "1");
        }
        storage.removeItem(LEGACY_QUEUE_KEY);
    }
    trimOldest(storage, PENDING_PREFIX, MAX_QUEUED, (key) => pendingAt(storage.getItem(key)), "");
    trimOldest(storage, SEEN_PREFIX, MAX_TRACKED, (key) => storage.getItem(key) ?? "", "");
}
function pendingAt(raw) {
    return parseQueued(raw ?? "")?.event.at ?? "";
}
/** Drops the oldest keys past `max`. `keepKey` is the event just written and is left in place. */
function trimOldest(storage, prefix, max, stamp, keepKey) {
    const keys = keysWithPrefix(storage, prefix);
    const extra = keys.length - max;
    if (extra <= 0)
        return;
    const ranked = keys
        .filter((key) => key !== keepKey)
        .map((key) => ({ key, at: stamp(key) }))
        .sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : a.key < b.key ? -1 : 1));
    for (let i = 0; i < extra && i < ranked.length; i++) {
        storage.removeItem(ranked[i].key);
    }
}
export function enqueueEvent(event, workspaceId, playerId) {
    const dedupeKey = eventDedupeKey(workspaceId, playerId, event);
    if (memorySeen.has(dedupeKey))
        return false;
    const storage = localStorageOrNull();
    if (!storage)
        return enqueueInMemory(event, workspaceId, playerId, dedupeKey);
    try {
        migrateLegacyLists(storage);
        const seen = seenKey(dedupeKey);
        const pending = pendingKey(dedupeKey);
        if (storage.getItem(seen) != null || storage.getItem(pending) != null)
            return false;
        storage.setItem(pending, JSON.stringify({ workspaceId, playerId, event }));
        storage.setItem(seen, event.at);
        trimOldest(storage, PENDING_PREFIX, MAX_QUEUED, (key) => pendingAt(storage.getItem(key)), pending);
        trimOldest(storage, SEEN_PREFIX, MAX_TRACKED, (key) => storage.getItem(key) ?? "", seen);
        inAppLog(`queued ${event.type} ${event.trackingId}`);
        return true;
    }
    catch (error) {
        inAppLog(`could not queue ${event.type}: ${error}`);
        return enqueueInMemory(event, workspaceId, playerId, dedupeKey);
    }
}
export function queuedFor(workspaceId, playerId) {
    const storage = localStorageOrNull();
    const byDedupe = new Map();
    if (storage) {
        try {
            migrateLegacyLists(storage);
            for (const key of keysWithPrefix(storage, PENDING_PREFIX)) {
                const parsed = parseQueued(storage.getItem(key) ?? "");
                if (parsed == null)
                    continue;
                if (parsed.workspaceId !== workspaceId || parsed.playerId !== playerId)
                    continue;
                byDedupe.set(eventDedupeKey(workspaceId, playerId, parsed.event), parsed);
            }
        }
        catch (error) {
            inAppLog(`could not read event queue: ${error}`);
        }
    }
    for (const [dedupeKey, item] of memoryPending) {
        if (item.workspaceId !== workspaceId || item.playerId !== playerId)
            continue;
        if (!byDedupe.has(dedupeKey))
            byDedupe.set(dedupeKey, item);
    }
    const items = [...byDedupe.values()];
    items.sort((a, b) => (a.event.at < b.event.at ? -1 : a.event.at > b.event.at ? 1 : 0));
    return items;
}
export function removeQueued(raws) {
    const storage = localStorageOrNull();
    for (const raw of raws) {
        const parsed = parseQueued(raw);
        if (!parsed)
            continue;
        const dedupeKey = eventDedupeKey(parsed.workspaceId, parsed.playerId, parsed.event);
        memoryPending.delete(dedupeKey);
        if (storage) {
            try {
                storage.removeItem(pendingKey(dedupeKey));
            }
            catch (error) {
                inAppLog(`could not trim event queue: ${error}`);
            }
        }
    }
}
//# sourceMappingURL=storage.js.map