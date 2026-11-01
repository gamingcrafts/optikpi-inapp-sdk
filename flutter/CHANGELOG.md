# Changelog

## 0.2.0

The player now comes from a token signed by the operator's server, not from the app.
- **Breaking:** `init` takes `apiKey`, `playerToken` and `baseUrl`, all required. `workspaceId`, `playerId` and `deviceKey` are gone, along with the `defaultInAppBaseUrl` placeholder.
- New `setPlayerToken`, for session refresh.
- Sends `x-player-token` on fetch and events. `playerId` is no longer sent, and neither is `x-device-key`.
- Reads `sub` and `wid` from the token, unverified, for on-device keys. If it can't read them, it logs and doesn't fetch.
- On a `401` or `403`, stops fetching and sending and keeps queued events, until `setPlayerToken`. API Gateway answers a refused token with `403`.
- A token for another player starts that player from nothing. Queued events stay with the player they were recorded for, and go at that player's next session, since a token speaks for one player.
- `PopupSource.mock()` needs no real token.

## 0.1.0

First pilot release.
- Renders all 6 layouts of the `PopupContent` contract: modal, fullscreen, bottomSheet, banner, toast and imageOnly.
- Fetches from the pull API ([`API.md`](https://github.com/gamingcrafts/optikpi-inapp-sdk/blob/main/API.md)) on init, on foreground and on screen change, throttled by `nextCheckAfterSec`.
- Shows one pop-up per screen visit, newest first. Skips blocked routes and expired pop-ups. Shows each pop-up once per device.
- Tracks impression, click and dismiss through a persistent queue that dedupes and retries. Events go to the `popup` ingest webhook.
- Authenticates both calls with `Authorization: Bearer {apiKey}`.
- Skips server entries with a `kind` other than `popup`, so later message types don't break this version.
- `PopupSource.mock()` serves the bundled templates until the backend exists.
- Published as `optikpi_inapp` from `gamingcrafts/optikpi-inapp-sdk` (tag `flutter-v0.1.0`). It was built as `optikpi_popup` in the casino demo app, and the entry point is now `OptikpiInApp`. Its `shared_preferences` keys start `optikpi_inapp.`, so a device that ran an `optikpi_popup` build starts with no shown ids and an empty queue.
