# optikpi_inapp

The Flutter SDK of [optikpi-inapp-sdk](https://github.com/gamingcrafts/optikpi-inapp-sdk): OptiKPI
in-app pop-ups for Flutter. Add the package and call it at login. From then on it:
- fetches the player's waiting pop-ups,
- draws them over your app,
- reports impression, click and dismiss.

You write no pop-up UI.

It is pure Dart/Flutter with no native code of its own. Dependencies: `http`, `shared_preferences`
and `url_launcher`. Android, iOS and the other Flutter platforms all work.

## Integration in five steps

**1. Add the dependency** in your app's `pubspec.yaml`, pinned to a release tag:

```yaml
dependencies:
  optikpi_inapp:
    git:
      url: https://github.com/gamingcrafts/optikpi-inapp-sdk.git
      path: flutter
      ref: flutter-v0.1.0
```

If your build can't reach GitHub, unzip `optikpi_inapp-0.1.0.zip` into your repo instead (for
example under `packages/optikpi_inapp/`) and use `path: packages/optikpi_inapp`.

**2. Run `flutter pub get`.**

**3. Add the builder and the route observer.** The builder draws pop-ups above every screen. The
observer tells the package when the player changes screens.

```dart
import 'package:optikpi_inapp/optikpi_inapp.dart';

final router = GoRouter(
  observers: [OptikpiInApp.routeObserver],
  routes: [...],
);

MaterialApp.router(routerConfig: router, builder: OptikpiInApp.builder);
```

Without go_router, use `MaterialApp(navigatorObservers: [OptikpiInApp.routeObserver], builder:
OptikpiInApp.builder)`. If your app tracks the location itself, call
`OptikpiInApp.didChangeRoute('/path')` instead of using the observer (Android back then
goes to the page, not the pop-up). If you already have a
`builder`, wrap its result: `builder: (context, child) => OptikpiInApp.builder(context,
yourBuilder(context, child))`.

**4. Call `init` on login**, and at app start when you restore a saved session:

```dart
await OptikpiInApp.init(
  workspaceId: '...',          // from OptiKPI (keys the on-device queue; not sent)
  playerId: user.id,           // the same id you send to OptiKPI
  apiKey: '...',               // the workspace's in-app key, sent as a Bearer token
  onDeepLink: (link) => router.go(link),               // optional
  blockedRoutes: ['/dashboard/games/play', '/dashboard/deposit'],
);
```

**5. Call `logout` on logout:**

```dart
await OptikpiInApp.logout();   // stops fetching, drops this player's waiting pop-ups
```

## Options

| `init` argument | Default | |
|---|---|---|
| `onDeepLink` | none | Receives a `deeplink` button's value (e.g. `app://cashier`). Map it to a route yourself. Without it, the pop-up just closes. |
| `blockedRoutes` | `[]` | Screens that never show a pop-up: game play, cashier, KYC. A path blocks itself and everything under it, so `/dashboard/deposit` blocks `/dashboard/deposit/card` but not `/dashboard/deposit-log`. Write paths, not go_router route names (see below). |
| `deviceKey` | none | Your FCM token. The server can check it against the player. |
| `baseUrl` | placeholder | Your environment's API gateway, `https://{dev\|qa\|app}.optikpi.com/apigw`. Pop-ups come from `{baseUrl}/v1/inapp/popups` and events go to `{baseUrl}/ingest/popup`. |
| `source` | the pull API | `PopupSource.mock()` serves the bundled sample pop-ups instead. It sends nothing and logs events when `debug` is on. |

Other members:
- `OptikpiInApp.debug = true` logs what the package does with the prefix `[OptikpiInApp]`. It logs nothing otherwise.
- `OptikpiInApp.showTest(content)` draws a pop-up immediately, ignoring every rule, and sends no events. Use it for a debug menu.
- `OptikpiInApp.sampleContents()` returns one sample per layout.

## What the package does

- **Fetches** on `init`, when the app comes back to the foreground, and on each screen change, at most once per `nextCheckAfterSec` (default 5 min). It never fetches in the background. A failed fetch is silent and retried at the next fetch moment.
- **Shows** at most one pop-up per screen visit, newest first. It never shows one on a blocked route or after it expires, and a banner or toast still up when the player moves to a blocked route is hidden. A hidden pop-up counts as shown (its impression was sent), so it doesn't come back, and no dismiss is sent for it. Each pop-up is shown once per device, even after a refetch.
- **Acts on taps:**
  - `url` opens in the external browser or app.
  - `deeplink` calls `onDeepLink`.
  - `dismiss` closes.
  - Android back closes a blocking pop-up and stays on the page (this needs the route observer).
    It works like a drawer: the pop-up adds an entry to the page's route. So on a page with
    `PopScope(canPop: false)`, back goes to the `PopScope`, not the pop-up. A
    `Navigator.pop()` from your code while a blocking pop-up is open closes the pop-up instead
    of the page.
  - Banners and toasts don't block the screen. They hide after `autoDismissSec`, or stay up until closed when it is missing or 0 (the builder's "Never").
- **Tracks** `impression` (drawn), `click` (any button or image tap) and `dismiss` (close button, tap outside, auto-dismiss, back). Events are queued on the device, sent in batches, retried when offline, and each one is sent once.
- **Merge tags** (`{{first_name}}`) are filled by the server. The package shows text as it arrives.

## Notes

- **Route names with go_router.** The observer reads each page's name. go_router names a page after the route's `name:`, or its `path:` when it has none. So for routes with a `name:`, or paths with parameters like `/game/:id`, list the name or the pattern in `blockedRoutes`, or call `didChangeRoute` yourself with the real location.
- **Other message types.** Only pop-ups exist today. A server entry with another `kind` is skipped, so an app on this version keeps working when new kinds arrive.
- **Images.** The package loads the image before it shows the pop-up, then keeps the bytes in a small in-memory cache. `gradient:#a,#b` placeholder URLs draw as gradients.
- **Storage.** In `shared_preferences`, under keys starting `optikpi_inapp.`: the ids already shown, the event queue, and the events already queued (for dedupe).

## Development

Run these from `flutter/`:

```bash
flutter test                                   # unit + widget tests, including ../contract/fixtures
flutter test --tags golden --update-goldens    # re-draws test/goldens/*.png
tool/make_zip.sh                               # builds dist/optikpi_inapp-<version>.zip
```

The parsing tests read the shared fixtures in `../contract/fixtures`, so they run from a checkout of
the whole repo, not from the zip. The zip leaves `test/` out.

[`API.md`](https://github.com/gamingcrafts/optikpi-inapp-sdk/blob/main/API.md) is the backend contract. `CHANGELOG.md` lists releases.
