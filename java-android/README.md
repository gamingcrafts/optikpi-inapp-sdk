# optikpi_inapp

The Java Android SDK of [optikpi-inapp-sdk](https://github.com/gamingcrafts/optikpi-inapp-sdk): OptiKPI
in-app pop-ups for native Android apps (Java). Add the library and call it at login. From then on it:
- fetches the player's waiting pop-ups,
- draws them over your app,
- reports impression, click and dismiss.

You write no pop-up UI.

It depends on OkHttp, AndroidX Activity/AppCompat, and `SharedPreferences` for the event queue. Min SDK
24. Activities should extend `ComponentActivity` / `AppCompatActivity` so the system back key closes
blocking pop-ups.

## Integration in five steps

**1. Add the dependency**, pinned to a release tag. Check out the repo (or a submodule) and include the
`library` module as a project in your build:

```kotlin
// settings.gradle.kts
include(":optikpi-inapp")
project(":optikpi-inapp").projectDir =
    file("../path/to/optikpi-inapp-sdk/java-android/library")
```

```kotlin
// app/build.gradle.kts
android {
  compileOptions {
    // The library uses java.time. Required when your minSdk is below 26.
    isCoreLibraryDesugaringEnabled = true
  }
}

dependencies {
  implementation(project(":optikpi-inapp"))
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Pin the same commit as tag `java-android-v0.1.0` (or your chosen release) when you vendor or submodule
the repo. The `INTERNET` permission is declared by the library and merges into your manifest.

**2. Run a Gradle sync.**

**3. Register the hooks once**, in your `Application`, so pop-ups attach to every `Activity` (the overlay
goes on the window's decor view, so a blocking pop-up also covers an `ActionBar`):

```java
public class App extends Application {
  @Override
  public void onCreate() {
    super.onCreate();
    OptikpiInApp.install(this);
  }
}
```

`install` is optional if you pass an `Activity` to `init` (step 4): `init` registers the hooks itself and
attaches to that already-running `Activity`. **Call it anyway if you use custom routes or `blockedRoutes`**:
the hooks save your reported route when an `Activity` is recreated (rotation, process death) and can only
restore it for an `Activity` they saw being created, so registering late loses it. Call `OptikpiInApp.didChangeRoute` when you navigate if the
default route (the activity's class name) is not your path (recommended for all apps).

**4. Call `init` on login**, and at app start when you restore a saved session. `playerToken` comes from
your server: see
[`docs/player-token-server.md`](../docs/player-token-server.md).

```java
import com.optikpi.inapp.OptikpiInApp;

OptikpiInApp.init(
    this,
    "...",                         // the workspace's in-app key, sent as a Bearer token
    loginResponse.optikpiPlayerToken,
    "https://app.optikpi.com/apigw",
    link -> navigateTo(link),               // optional
    data -> handleMessageClick(data),     // optional
    List.of("/dashboard/games/play", "/dashboard/deposit"),
    null                                  // OptikpiInApp.mockSource(this) for demos
);
```

Whenever your server gives you a new token:

```java
OptikpiInApp.setPlayerToken(this, newToken);
```

Report screen paths on navigation:

```java
OptikpiInApp.didChangeRoute(this, "/dashboard/home");
```

**5. Call `logout` on logout:**

```java
OptikpiInApp.logout(this);   // stops fetching, drops this player's waiting pop-ups
```

Pass your current `Activity` (or the `Application`, with `install` in `Application.onCreate`) to `init`.
An `Activity` that is already on screen when `init` runs, as after a login, is picked up straight away.

## Options

| `init` argument | Default | |
|---|---|---|
| `onDeepLink` | none | Receives a `deeplink` action value. Without it, the pop-up just closes. |
| `onCustomAction` | none | Receives a `custom` action's key/value pairs after close and click tracking. |
| `blockedRoutes` | `[]` | Screens that never show a pop-up. A path blocks itself and everything under it. |
| `source` | the pull API | `OptikpiInApp.mockSource(context)` serves bundled layout templates; needs no real token. |

The handlers are held until `logout`, so do not let them capture an `Activity` (a lambda calling an instance
method of your login screen would leak it across rotation and call into the destroyed instance). Route them
through your application (a navigator, an event bus), or bind them from an `Activity` with
`OptikpiInApp.setHandlers(context, onDeepLink, onCustomAction)` and unbind them with
`OptikpiInApp.clearHandlers(context, onDeepLink, onCustomAction)` (the same instances, kept in fields) in
`onDestroy`: it only removes handlers that are still installed, so an `Activity` destroyed after the next
one has bound its own does not take those down. `setHandlers(context, null, null)` clears unconditionally.

`baseUrl` is required: your environment's API gateway, `https://{dev\|qa\|app}.optikpi.com/apigw`.

Other members:
- `OptikpiInApp.setDebug(true)` logs with the `[OptikpiInApp]` prefix.
- `OptikpiInApp.showTest(context, content)` draws a pop-up immediately, ignoring every rule, and sends no events.

## What the package does

- **Fetches** on `init`, when the app comes back to the foreground, and on each screen change, at most once per `nextCheckAfterSec` (default 5 min). It never fetches in the background.
- **Reads the token** for the player and workspace, without verifying it (the server does). If it can't read them, it logs that and fetches nothing until `setPlayerToken`.
- **Pauses on a refused token.** On a `401` or `403` it stops fetching and sending and keeps queued events, until `setPlayerToken`.
- **Shows** at most one pop-up per screen visit, newest first. It never shows one on a blocked route or after it expires.
- **Acts on taps:** `url` opens externally; `deeplink` and `custom` call your handlers; Android back closes blocking layouts when the activity uses `ComponentActivity`.
- **Tracks** impression, click and dismiss through a persistent queue; events go to the `popup` ingest webhook.

## Development

From `java-android/`:

```bash
./gradlew :library:testDebugUnitTest    # unit tests, including ../contract/fixtures
```

The parsing tests read the shared fixtures in `../contract/fixtures`, so they run from a checkout of the
whole repo.

[`API.md`](../API.md) is the backend contract. `CHANGELOG.md` lists releases.

## License

MIT, see [`LICENSE`](../LICENSE).