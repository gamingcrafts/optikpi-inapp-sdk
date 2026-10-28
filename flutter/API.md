# In-app pop-up pull API (v1): the contract

This is what `optikpi_popup` 0.1.0 calls. The backend ticket (OK-1amxvnb3b9e) builds the fetch
endpoint and the `popup` ingest provider. Until then the package runs against `PopupSource.mock()`,
and the default base URL is a placeholder that never resolves (`https://inapp.optikpi.invalid`).

Design rules come from the in-app pop-ups spec ("Delivery: pull"). The server stores each pop-up a
campaign or workflow sends, and the app fetches it. The pop-up content is the `PopupContent`
contract (`app/shared/popup/popup.types.ts` in app_next), unchanged.

## Common

| | |
|---|---|
| Base URL | per environment, `https://{dev\|qa\|app}.optikpi.com/apigw`, passed to `OptikpiPopup.init(baseUrl: …)` |
| `Authorization` | `Bearer {apiKey}`, the workspace's in-app integration key (required). The key carries the workspace, so no workspace header is sent. |
| `x-device-key` | FCM token in the app, OptiKPI device ID on the web (optional in v1, see below) |
| `x-sdk-version` | e.g. `optikpi_popup-flutter/0.1.0` (sent always, for support and metrics) |

Both calls send the same headers. The server resolves the workspace from the key and, when
`x-device-key` is sent, checks that the device belongs to the player. A failed check returns
`401`/`403`. The app treats a `401`, like every other non-2xx, as "try again at the next fetch
moment": it never shows an error, and unsent events stay queued.

## `GET {baseUrl}/v1/inapp/popups?playerId={playerId}`

Returns the player's waiting pop-ups.

```json
{
  "popups": [
    {
      "id": "pop_8f2c…",
      "trackingId": "trk_41d0…",
      "campaignId": "cmp_123",
      "createdAt": "2026-10-28T09:15:00Z",
      "expiresAt": "2026-10-31T09:15:00Z",
      "content": { "version": 1, "layout": "modal", "size": "md", "…": "PopupContent" }
    }
  ],
  "nextCheckAfterSec": 300
}
```

| Field | Type | Rule |
|---|---|---|
| `popups[].id` | string, required | Unique per stored pop-up. The app remembers it to show each pop-up once per device. A re-send of the same campaign replaces the waiting pop-up and gets a **new** `id`. |
| `popups[].trackingId` | string, required | Goes back on every event. Joins to `campaign_report`. |
| `popups[].campaignId` | string, optional | Campaign or workflow id, for logs only. |
| `popups[].createdAt` | ISO-8601, required | The app shows the newest first. |
| `popups[].expiresAt` | ISO-8601, optional | From the campaign's *Available for*. The server must not return expired pop-ups. The app also skips them, in case its clock is ahead. |
| `popups[].content` | `PopupContent` | **Merge tags already filled** for this player. The app shows text as it arrives. |
| `nextCheckAfterSec` | integer, optional | The app fetches again no sooner than this after the response. Default 300. The app clamps it to between 30 s and 24 h. |

Server-side rules:
- Never return a pop-up that has expired.
- Pop-ups already reported with `impression` may be left out (recommended). The app still dedupes by `id`.
- Return an empty list, not `404`, when nothing is waiting.

What the app does with the response:
- An entry with a missing `id` or `trackingId`, an unknown `layout`, or `content.version` other than `1` is skipped. The others still show.
- Unknown fields are ignored, so fields can be added without a new version.
- Anything else that is missing or invalid (a size the layout doesn't allow, a bad colour, a 3rd button) falls back to the web builder's defaults.

## `POST {baseUrl}/ingest/popup`

Events go to the shared ingest webhook (`/apigw/ingest/{provider}`) with provider `popup`. There is
no pop-up events endpoint of its own.

```json
{
  "playerId": "p_123",
  "events": [
    { "trackingId": "trk_41d0…", "type": "impression", "at": "2026-10-28T09:20:01.123Z" },
    { "trackingId": "trk_41d0…", "type": "click", "at": "2026-10-28T09:20:04.870Z", "buttonIndex": 0 }
  ]
}
```

| Field | Rule |
|---|---|
| `type` | `impression` when the pop-up is drawn. `click` on a button or image tap. `dismiss` on the close button, a tap outside, auto-dismiss or Android back. |
| `buttonIndex` | 0-based index into `content.buttons` for a button click. Absent for an image tap. |
| `at` | Device time, UTC. |

The server returns `204` (any 2xx counts) once it has stored the batch.

Delivery from the app:
- Events go into a queue on the device and are sent in batches of up to 50, about 2 s after the last one. They are also sent at init, on foreground and after each fetch.
- If a send fails, the batch stays queued and is sent again later. **Retries are at-least-once**, so the server must dedupe on `(trackingId, type)`. The app sends each pair once, but a lost `204` means the server sees it again.
- A dismiss button is a `click`, not a `dismiss`. A click on a button that also closes the pop-up sends no `dismiss`.
- Events stay queued across logout and are sent under the player they were recorded for.

Mapping to campaign statuses (ticket 1c): `impression` → Delivered/Open, `click` → Click, `dismiss` → a new Dismissed status.

## What changed from the brief's proposal
- **Events go to `POST {baseUrl}/ingest/popup`**, the shared ingest webhook, instead of `POST /v1/inapp/events`. The body is unchanged. (Puru, 2026-10-28.)
- **Auth is `Authorization: Bearer {apiKey}`** on both calls, instead of `x-api-key` plus `x-workspace-id`. (Puru, 2026-10-28.)
- **Added `x-sdk-version`** for support and metrics.
- **`buttonIndex` is 0-based** and absent for an image tap, so an image click and a button click can be told apart.
- **Spelled out at-least-once delivery.** Server-side dedupe on `(trackingId, type)` is required.
- **Spelled out "re-send replaces, with a new id".** A replaced pop-up the player already saw must show again, so it can't keep the old `id`.
- **Spelled out the `nextCheckAfterSec` clamp** of 30 s to 24 h.
