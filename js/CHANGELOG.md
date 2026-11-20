# Changelog

## Unreleased

- `optikpi_inapp` installs from `js/` and loads under Node's native ESM. The overlay and React stay on `optikpi_inapp/overlay`.
- Draws five layouts. `fullscreen` is rejected while parsing.
- Shown popups and queued events are stored per id, with a temporary shown lease that becomes durable only after a visible draw.
- A hidden tab does not fetch, select, claim, or record an impression. That work resumes when the tab is visible.
- Event flushes are serialized in the page and across tabs. `logout()` waits for the final attempt. Fetches and sends abort after 15 seconds.
- Banners, toasts, and bottom sheets stay inside the mobile safe area. Theme colors and custom-action data follow the shared content contract.

## 0.1.0

First release of the web SDK. It follows `API.md` the same way the Flutter SDK does.
- `OptikpiInApp.init` / `setPlayerToken` / `logout` / `didChangeRoute` / `onForeground`, with the same options as Flutter: `onDeepLink`, `onCustomAction`, `blockedRoutes`.
- Fetches `GET {baseUrl}/v1/inapp/popups` and sends events to `POST {baseUrl}/ingest/popup` with `Authorization: Bearer` and `x-player-token`.
- Draws five layouts (modal, bottom sheet, banner, toast, image-only) with `OptikpiInAppOverlay`, a React component. `fullscreen` is not supported. Modals are centered dialogs at 768px and wider, and full-width cards on phones.
- Events are queued in `localStorage`, deduplicated per workspace, player, `trackingId` and type, and retried until accepted. Storage failures never block a button's action.
- Pauses on `401` or `403` until `setPlayerToken`. A token for another player starts that player from nothing.
- Shown popup ids are remembered per device in `localStorage`.
