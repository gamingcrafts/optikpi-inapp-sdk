export let inAppDebugLogging = false;
export function setInAppDebugLogging(value) {
    inAppDebugLogging = value;
}
export function inAppLog(message) {
    if (!inAppDebugLogging)
        return;
    console.log(`[OptikpiInApp] ${message}`);
}
//# sourceMappingURL=log.js.map