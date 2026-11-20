import { controller } from "./controller.js";
import { inAppDebugLogging, setInAppDebugLogging } from "./log.js";
export { parsePopupContent } from "./parse.js";
export { OPTIKPI_INAPP_JS_VERSION } from "./version.js";
export const OptikpiInApp = {
    get debug() {
        return inAppDebugLogging;
    },
    set debug(value) {
        setInAppDebugLogging(value);
    },
    get controller() {
        return controller;
    },
    init(options) {
        return controller.init(options);
    },
    setPlayerToken(playerToken) {
        controller.setPlayerToken(playerToken);
    },
    logout() {
        return controller.logout();
    },
    didChangeRoute(route) {
        controller.didChangeRoute(route);
    },
    showTest(content) {
        controller.showTest(content);
    },
    onForeground() {
        controller.onForeground();
    },
};
//# sourceMappingURL=index.js.map