# OptiKPI In-App SDK

Client SDKs that show OptiKPI in-app messages inside an operator's app or site. Today that means
pop-ups: a campaign or workflow sends one, the SDK fetches it when the player is on a safe screen,
draws it over the app, and reports impression, click and dismiss back to OptiKPI.

Every SDK speaks the same pull API and reads the same content, so a pop-up looks and behaves the
same everywhere.

## Platforms

| Platform | Folder | Status | Package |
|---|---|---|---|
| Flutter (Android, iOS and other Flutter targets) | [`flutter/`](flutter/) | Available | `optikpi_inapp` |
| React Native | `react-native/` | Planned | |
| Web JS | `js/` | Planned | |

## What's in the repo

| Path | |
|---|---|
| [`API.md`](API.md) | The pull API contract: fetch `GET {baseUrl}/v1/inapp/popups`, events `POST {baseUrl}/ingest/popup`, Bearer auth. One copy for every SDK. |
| [`contract/popup-content.schema.json`](contract/popup-content.schema.json) | JSON Schema of `PopupContent`, the content of one pop-up. |
| [`contract/fixtures/`](contract/fixtures/) | Shared test data: one sample per layout (`layouts/`), and the malformed content and responses every SDK must read the same way (`content-cases.json`, `fetch-response-cases.json`). Each SDK's tests run them. |
| [`flutter/`](flutter/) | The Flutter package. |

## Quick start

### Flutter

Add the dependency, pinned to a release tag:

```yaml
dependencies:
  optikpi_inapp:
    git:
      url: https://github.com/gamingcrafts/optikpi-inapp-sdk.git
      path: flutter
      ref: flutter-v0.2.0
```

Then add the builder and route observer, and call `init` at login:

```dart
import 'package:optikpi_inapp/optikpi_inapp.dart';

MaterialApp.router(
  routerConfig: GoRouter(observers: [OptikpiInApp.routeObserver], routes: [...]),
  builder: OptikpiInApp.builder,
);

await OptikpiInApp.init(
  apiKey: '...',
  playerToken: loginResponse.optikpiPlayerToken,   // signed by your server: docs/player-token-server.md
  baseUrl: 'https://app.optikpi.com/apigw',
);

await OptikpiInApp.logout();                          // on logout
```

The five integration steps, all options and the behaviour are in [`flutter/README.md`](flutter/README.md).

### React Native, Web JS

Planned. They will follow `API.md` and run `contract/fixtures` in their tests.

## Releases

Each SDK is versioned and tagged on its own, as `{platform}-v{version}`: `flutter-v0.1.0`, later
`react-native-v…` and `js-v…`. Apps pin the tag (`ref:` above). Every SDK has its own `CHANGELOG.md`
in its folder.

A release means: bump the version in the SDK's manifest (and `flutter/lib/src/version.dart` for
Flutter), add the `CHANGELOG.md` entry, merge, then tag the merge commit. Nothing is published to
pub.dev or npm yet. For apps that can't fetch from GitHub, `flutter/tool/make_zip.sh` builds a zip
of the package.

A change to `API.md` or `contract/` affects every SDK. Make it backward compatible (new optional
fields, new `kind`s), and update the fixtures with it.

## License

MIT, see [`LICENSE`](LICENSE).
