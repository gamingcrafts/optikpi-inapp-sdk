export let inAppDebugLogging = false;

export function setInAppDebugLogging(value: boolean) {
  inAppDebugLogging = value;
}

export function inAppLog(message: string) {
  if (!inAppDebugLogging) return;
  console.log(`[OptikpiInApp] ${message}`);
}
