import { inAppLog } from "./log.js";
import { parseFetchResult } from "./parse.js";
import { SDK_VERSION_HEADER } from "./version.js";
const HTTP_TIMEOUT_MS = 15000;
export class PopupHttpException extends Error {
    constructor(statusCode, path) {
        super(`HTTP ${statusCode} from ${path}`);
        Object.defineProperty(this, "statusCode", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: statusCode
        });
        Object.defineProperty(this, "path", {
            enumerable: true,
            configurable: true,
            writable: true,
            value: path
        });
    }
    get isAuthFailure() {
        return this.statusCode === 401 || this.statusCode === 403;
    }
}
function headers(context, extra) {
    return {
        authorization: `Bearer ${context.apiKey}`,
        "x-player-token": context.playerToken,
        "x-sdk-version": SDK_VERSION_HEADER,
        accept: "application/json",
        ...extra,
    };
}
function uri(context, path) {
    const base = context.baseUrl.endsWith("/")
        ? context.baseUrl.slice(0, -1)
        : context.baseUrl;
    return `${base}${path}`;
}
async function withHttpTimeout(request) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), HTTP_TIMEOUT_MS);
    try {
        return await request(controller.signal);
    }
    finally {
        clearTimeout(timer);
    }
}
export async function fetchPopups(context) {
    const path = "/v1/inapp/popups";
    return withHttpTimeout(async (signal) => {
        const response = await fetch(uri(context, path), {
            method: "GET",
            headers: headers(context),
            cache: "no-store",
            signal,
        });
        if (response.status !== 200)
            throw new PopupHttpException(response.status, path);
        return parseFetchResult(await response.json());
    });
}
export async function sendEvents(context, events) {
    const path = "/ingest/popup";
    await withHttpTimeout(async (signal) => {
        const response = await fetch(uri(context, path), {
            method: "POST",
            headers: headers(context, { "content-type": "application/json" }),
            body: JSON.stringify({ events }),
            signal,
        });
        if (response.status < 200 || response.status >= 300) {
            throw new PopupHttpException(response.status, path);
        }
    });
    inAppLog(`sent ${events.length} event(s)`);
}
//# sourceMappingURL=http.js.map