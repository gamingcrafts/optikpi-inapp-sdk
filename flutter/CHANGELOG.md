# Changelog

## 0.1.0

First pilot release.
- Renders all 6 layouts of the `PopupContent` contract: modal, fullscreen, bottomSheet, banner, toast and imageOnly.
- Fetches from the pull API (`API.md`) on init, on foreground and on screen change, throttled by `nextCheckAfterSec`.
- Shows one pop-up per screen visit, newest first. Skips blocked routes and expired pop-ups. Shows each pop-up once per device.
- Tracks impression, click and dismiss through a persistent queue that dedupes and retries. Events go to the `popup` ingest webhook.
- Authenticates both calls with `Authorization: Bearer {apiKey}`.
- `PopupSource.mock()` serves the bundled templates until the backend exists.
