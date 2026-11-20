# optikpi_inapp (Web JS)

The web SDK of [optikpi-inapp-sdk](../README.md): OptiKPI in-app pop-ups for websites. It fetches
the player's waiting pop-ups, draws them over the page, and reports impression, click and dismiss.
It follows [`API.md`](../API.md). The Flutter SDK is in [`flutter/`](../flutter/).

The web SDK draws five layouts: modal, bottom sheet, banner, toast and image-only. It does not draw
`fullscreen`. A popup with that layout is rejected while parsing, so it is not shown and it sends
no impression, click or dismiss. The Flutter SDK still draws fullscreen.

It is plain TypeScript apart from one React component, `OptikpiInAppOverlay`. Any site can call the
core API from `optikpi_inapp`. That entry does not load React or CSS. React 18 or newer is needed
only to mount the overlay, which is a separate entry, `optikpi_inapp/overlay`.

## Integration

The package name is `optikpi_inapp`. It is not on npm yet. `js/package.json` names it.
`optikpi_inapp` resolves to `dist/index.js` (types in `dist/index.d.ts`). Relative imports in
`dist/` end in `.js`, so Node can load this entry. `optikpi_inapp/overlay` resolves to
`dist/overlay.js`, which imports React and `dist/overlay.css`, so that entry needs a bundler
such as Next.js, Vite or webpack.

**1. Install this folder as a dependency.** From the app that will show pop-ups:

```json
{
  "dependencies": {
    "optikpi_inapp": "file:../optikpi-inapp-sdk/js"
  }
}
```

The path is relative to the app's `package.json`. Run `npm install`. Copying `js/` into the app
works the same way only when the copy keeps `package.json` and `dist/` together and the app
depends on that directory with `file:`. A bare `optikpi_inapp` import does not resolve from a
copied folder on its own.

**2. Mount the overlay once**, near the root of the site, on every page:

```tsx
import { OptikpiInAppOverlay } from "optikpi_inapp/overlay";

export default function Root({ children }) {
  return (
    <>
      {children}
      <OptikpiInAppOverlay />
    </>
  );
}
```

**3. Call `init` after the player signs in**, with a `playerToken` from your server. Your server signs
it; see [`docs/player-token-server.md`](../docs/player-token-server.md).

```ts
import { OptikpiInApp } from "optikpi_inapp";

await OptikpiInApp.init({
  apiKey: "...",                       // the workspace's in-app key, sent as a Bearer token
  playerToken: loginResponse.optikpiPlayerToken,
  baseUrl: "https://app.optikpi.com/apigw",
  blockedRoutes: ["/checkout", "/login"],
  onDeepLink: (link) => router.push(link),              // optional
  onCustomAction: (data) => handleMessageClick(data),   // optional
});
OptikpiInApp.didChangeRoute(location.pathname);         // on each page change
```

**4. Call `setPlayerToken` when the server gives you a new token**, and `logout` on sign-out:

```ts
OptikpiInApp.setPlayerToken(newToken);
await OptikpiInApp.logout();
```

Notes:
- Browsers can't call the OptiKPI gateway directly from your domain without CORS. Either allow your
  origin on the gateway, or proxy `GET /v1/inapp/popups` and `POST /ingest/popup` through your server
  and pass that proxy as `baseUrl`.
- `OptikpiInApp.debug = true` logs what the SDK does with the prefix `[OptikpiInApp]`.
- A hidden tab does not fetch, show a popup, or send events. When it becomes visible, or the
  page is restored from the back-forward cache, the SDK does all three. You do not call
  `onForeground` for that.

## Files

| File | |
|---|---|
| `package.json` | Package name `optikpi_inapp`, version, and the `exports` entry. |
| `index.ts` | Core API: `OptikpiInApp`. No React. |
| `dist/index.js` | Built core entry. `npm run build` inside `js/` regenerates `dist/` from the TypeScript. |
| `overlay.tsx` | React overlay. Import it from `optikpi_inapp/overlay`, not from the core entry. |
| `controller.ts` | Fetch, show, taps, queue and pause logic. |
| `http.ts` | The two OptiKPI calls. |
| `parse.ts` | Parses popups and applies the contract's fallbacks. |
| `rules.ts` | Blocked routes, which popup to show, fetch throttle. |
| `token.ts` | Reads `sub` and `wid` from the player token, unverified. |
| `storage.ts` | `localStorage`: one key per shown id, queued event, and dedupe key. |
| `overlay.css` | Layout for the overlay. `overlay.tsx` imports it. |
| `log.ts`, `version.ts` | Debug logging and SDK version. |

See [`CHANGELOG.md`](CHANGELOG.md) for releases.
