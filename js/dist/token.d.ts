export type PlayerTokenClaims = {
    playerId: string;
    workspaceId: string;
};
/** `sub` and `wid` of a JWT payload, unverified — same as the Flutter SDK. */
export declare function readPlayerTokenClaims(token: string): PlayerTokenClaims | null;
