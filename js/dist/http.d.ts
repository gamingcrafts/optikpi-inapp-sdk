import { type PopupFetchResult } from "./parse.js";
export type PopupRequestContext = {
    baseUrl: string;
    workspaceId: string;
    playerId: string;
    apiKey: string;
    playerToken: string;
};
export type PopupEventType = "impression" | "click" | "dismiss";
export type PopupEvent = {
    trackingId: string;
    type: PopupEventType;
    at: string;
    buttonIndex?: number;
};
export declare class PopupHttpException extends Error {
    readonly statusCode: number;
    readonly path: string;
    constructor(statusCode: number, path: string);
    get isAuthFailure(): boolean;
}
export declare function fetchPopups(context: PopupRequestContext): Promise<PopupFetchResult>;
export declare function sendEvents(context: PopupRequestContext, events: PopupEvent[]): Promise<void>;
