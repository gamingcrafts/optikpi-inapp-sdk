# In-app pop-up pull API (v1): the contract

One contract for every OptiKPI in-app SDK in this repo. The Flutter SDK (`optikpi_inapp` 0.3.1)
calls it. `PopupSource.mock()` serves the bundled templates with no server, for demos and tests.

Design rules come from the in-app pop-ups spec ("Delivery: pull"). The server stores each pop-up a
campaign or workflow sends, and the app fetches it. The pop-up content is the `PopupContent`
contract (`app/shared/popup/popup.types.ts` in app_next), unchanged. Its JSON Schema is
[`contract/popup-content.schema.json`](contract/popup-content.schema.json), and
[`contract/fixtures/`](contract/fixtures/) holds sample content for each layout and the cases every
SDK must read the same way.

## Common

| | |
|---|---|
| Base URL | per environment, `https://{dev\|qa\|app}.optikpi.com/apigw`, passed to the SDK's init (Flutter: `OptikpiInApp.init(baseUrl: …)`) |
| `Authorization` | `Bearer {apiKey}`, the workspace's in-app integration key (required). The key carries the workspace, so no workspace header is sent. |
| `x-player-token` | The player token, a JWT signed by the operator's server (see below). |
| `x-sdk-version` | `{package}-{platform}/{version}`, e.g. `optikpi_inapp-flutter/0.3.1` (sent always, for support and metrics) |

Both calls send the same headers. The server resolves the workspace from the key and the player from
the token.

### Player token

The operator's login server signs it with a private key that OptiKPI never sees, and returns it to
the app as `optikpiPlayerToken`. [`docs/player-token-server.md`](docs/player-token-server.md) is the
operator's guide.

- Header: `alg: ES256`, `typ: JWT`, `kid`.
- Payload: `sub` (player ID, string), `wid` (workspace ID), `exp` (whole seconds, at most 90 days ahead).

A token that is present must verify, whatever the workspace's settings. With no token, the request
is refused if the workspace has **Require player token** on, and otherwise takes the older path,
where `playerId` in the query or body names the player. SDKs from 0.2.0 always send a token.

An SDK reads `sub` and `wid` from the payload, without verifying, to key its on-device state. If it
can't read them it logs that and doesn't fetch. [`contract/fixtures/player-token-cases.json`](contract/fixtures/player-token-cases.json)
has the cases.

### Refusals

| Status | Means |
|---|---|
| `401` | No `Authorization` header. |
| `403` | A bad key, or a token that is refused, missing while required, or for another player than the `playerId` sent. |

On a `401` or `403` the app stops fetching and sending, keeps its queued events, and resumes when it
is given a new token. On every other non-2xx it tries again at the next fetch moment. It never shows
an error.

## `GET {baseUrl}/v1/inapp/popups`

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
| `popups[].kind` | string, optional | Reserved for message types after pop-ups. Absent (or null) means `popup`, the only kind in v1. An SDK skips an entry whose kind it doesn't know, so new kinds can be added without breaking older apps. |
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
- An entry with an unknown `kind`, a missing `id` or `trackingId`, an unknown `layout`, or `content.version` other than `1` is skipped. The others still show.
- Unknown fields are ignored, so fields can be added without a new version.
- Anything else that is missing or invalid (a size the layout doesn't allow, a bad colour, a 3rd button) falls back to the web builder's defaults.
- [`contract/fixtures/content-cases.json`](contract/fixtures/content-cases.json) and [`fetch-response-cases.json`](contract/fixtures/fetch-response-cases.json) spell these rules out case by case. Every SDK's tests run them.

### Actions

A button's `action` and an image's `tapAction` have one of these types:

| `type` | Carries | The app |
|---|---|---|
| `url` | `value`, a link | Opens it externally. |
| `deeplink` | `value`, an app link | Hands it to the app. |
| `custom` | `customData`, an array of `{ "key": string, "value": string }` | Hands the pairs to the app's own click handler. |
| `dismiss` | nothing | Only closes. |

```json
{ "type": "custom", "customData": [ { "key": "screen", "value": "offers" }, { "key": "offerId", "value": "42" } ] }
```

- The pairs mean whatever the operator's app gives them. They are the same shape as a push template's `customData`, so an app can pass both to one handler. SDKs don't read the keys.
- Merge tags in the `value`s are filled by the server, like the rest of the content.
- An SDK drops an entry without a non-blank string `key` and a string `value`. A `custom` action left with no pairs acts as `dismiss`, like a `deeplink` with a blank `value`.
- On a tap: close, then track the click, then perform the action. With no handler set, the tap only closes.
- An SDK that doesn't know `custom` (Flutter 0.2.0 and earlier) doesn't draw a button that has it. Upgrade before sending it.

## `POST {baseUrl}/ingest/popup`

Events go to the shared ingest webhook (`/apigw/ingest/{provider}`) with provider `popup`. There is
no pop-up events endpoint of its own.

```json
{
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
- Events stay queued across logout and go at the next session of the player they were recorded for. A token speaks for one player, so another player's session can't send them. The queue holds 500 events on a device, across all players: past that, the oldest go first.

Mapping to campaign statuses (ticket 1c): `impression` → Delivered/Open, `click` → Click, `dismiss` → a new Dismissed status.

The record stored carries the player from the token. A `playerId` in the body is optional, and one
naming another player gets `403`.

## What changed from the brief's proposal
- **The player comes from a signed token** (`x-player-token`), not from `playerId`, and `x-device-key` is gone. (Puru, 2026-10-31.)
- **Events go to `POST {baseUrl}/ingest/popup`**, the shared ingest webhook, instead of `POST /v1/inapp/events`. The body is unchanged. (Puru, 2026-10-28.)
- **Auth is `Authorization: Bearer {apiKey}`** on both calls, instead of `x-api-key` plus `x-workspace-id`. (Puru, 2026-10-28.)
- **Added `x-sdk-version`** for support and metrics.
- **Added the optional `popups[].kind`**, so later message types can share the endpoint. Older SDKs skip kinds they don't know. (Puru, 2026-10-28.)
- **`buttonIndex` is 0-based** and absent for an image tap, so an image click and a button click can be told apart.
- **Spelled out at-least-once delivery.** Server-side dedupe on `(trackingId, type)` is required.
- **Spelled out "re-send replaces, with a new id".** A replaced pop-up the player already saw must show again, so it can't keep the old `id`.
- **Spelled out the `nextCheckAfterSec` clamp** of 30 s to 24 h.
