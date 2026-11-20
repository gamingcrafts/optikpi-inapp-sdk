import { type InitOptions } from "./controller.js";
import type { PopupContent } from "./parse.js";
export type { InitOptions, PopupCustomActionHandler, PopupDeepLinkHandler } from "./controller.js";
export { parsePopupContent } from "./parse.js";
export type { PopupContent, PopupDelivery } from "./parse.js";
export { OPTIKPI_INAPP_JS_VERSION } from "./version.js";
export declare const OptikpiInApp: {
    debug: boolean;
    readonly controller: import("./controller.js").OptikpiInAppController;
    init(options: InitOptions): Promise<void>;
    setPlayerToken(playerToken: string): void;
    logout(): Promise<void>;
    didChangeRoute(route: string): void;
    showTest(content: PopupContent): void;
    onForeground(): void;
};
