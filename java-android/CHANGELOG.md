# Changelog

## 0.1.0

First Java Android release.
- Renders all 6 layouts of the `PopupContent` contract: modal, fullscreen, bottomSheet, banner, toast and imageOnly.
- Fetches from the pull API ([`API.md`](../API.md)) on init, on foreground and on screen change, throttled by `nextCheckAfterSec`.
- Shows one pop-up per screen visit, newest first. Skips blocked routes and expired pop-ups. Shows each pop-up once per device.
- Tracks impression, click and dismiss through a persistent queue that dedupes and retries. Events go to the `popup` ingest webhook.
- Authenticates both calls with `Authorization: Bearer {apiKey}`.
- Skips server entries with a `kind` other than `popup`.
- `OptikpiInApp.mockSource()` serves bundled templates until the backend exists.
- Published from `gamingcrafts/optikpi-inapp-sdk` (`java-android/`, tag `java-android-v0.1.0`). Maven namespace `com.optikpi.inapp`; metrics header `x-sdk-version: optikpi_inapp-java-android/0.1.0`.