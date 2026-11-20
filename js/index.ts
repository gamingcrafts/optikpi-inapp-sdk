import { controller, type InitOptions } from "./controller.js";
import { inAppDebugLogging, setInAppDebugLogging } from "./log.js";
import type { PopupContent } from "./parse.js";

export type { InitOptions, PopupCustomActionHandler, PopupDeepLinkHandler } from "./controller.js";
export { parsePopupContent } from "./parse.js";
export type { PopupContent, PopupDelivery } from "./parse.js";
export { OPTIKPI_INAPP_JS_VERSION } from "./version.js";

export const OptikpiInApp = {
  get debug() {
    return inAppDebugLogging;
  },
  set debug(value: boolean) {
    setInAppDebugLogging(value);
  },
  get controller() {
    return controller;
  },
  init(options: InitOptions) {
    return controller.init(options);
  },
  setPlayerToken(playerToken: string) {
    controller.setPlayerToken(playerToken);
  },
  logout() {
    return controller.logout();
  },
  didChangeRoute(route: string) {
    controller.didChangeRoute(route);
  },
  showTest(content: PopupContent) {
    controller.showTest(content);
  },
  onForeground() {
    controller.onForeground();
  },
};
