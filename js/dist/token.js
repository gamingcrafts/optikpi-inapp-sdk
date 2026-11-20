function decodeBase64Url(value) {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/");
    const pad = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
    const binary = atob(padded + pad);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++)
        bytes[i] = binary.charCodeAt(i);
    // atob is Latin-1. A UTF-8 `sub` such as "jugador-ñ" must be decoded before JSON.parse.
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}
/** `sub` and `wid` of a JWT payload, unverified — same as the Flutter SDK. */
export function readPlayerTokenClaims(token) {
    const parts = token.split(".");
    if (parts.length !== 3)
        return null;
    try {
        const claims = JSON.parse(decodeBase64Url(parts[1]));
        const sub = claims.sub;
        const wid = claims.wid;
        if (typeof sub !== "string" || !sub || typeof wid !== "string" || !wid) {
            return null;
        }
        return { playerId: sub, workspaceId: wid };
    }
    catch {
        return null;
    }
}
//# sourceMappingURL=token.js.map