package com.optikpi.inapp;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import com.optikpi.inapp.integration.OptikpiLifecycleCallbacks;
import com.optikpi.inapp.model.PopupContent;
import com.optikpi.inapp.source.MockPopupSource;
import com.optikpi.inapp.source.PopupSource;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/** OptiKPI in-app pop-ups for Java Android. See README.md for the five-step integration. */
public final class OptikpiInApp {
  private static volatile OptikpiLifecycleCallbacks lifecycle;

  private OptikpiInApp() {}

  public static boolean isDebug() {
    return InAppLog.isDebug();
  }

  public static void setDebug(boolean value) {
    InAppLog.setDebug(value);
  }

  public static OptikpiInAppController controller(Context context) {
    return OptikpiInAppController.getInstance(context);
  }

  /**
   * Registers the activity callbacks that draw pop-ups and follow screens. Call it once from {@code
   * Application.onCreate}, so every activity is seen from its first start. {@code init} calls it
   * too if you haven't, but it can only adopt the activity you pass it then. An activity created
   * before the hooks exist is never seen being created, so a screen the app reported with {@link
   * #didChangeRoute} cannot be carried through that activity's recreation (rotation, process
   * death): install early if you use custom routes or {@code blockedRoutes}.
   */
  public static synchronized void install(Application application) {
    ensureLifecycle(application, OptikpiInAppController.getInstance(application));
  }

  /**
   * Call on login, and at app start when a stored session is restored, with the {@code
   * playerToken} your server signed for this player.
   *
   * <p>{@code onDeepLink} and {@code onCustomAction} are kept until {@link #logout}: do not let
   * them capture an {@code Activity} (see {@link #setHandlers}).
   *
   * <p>Pass the current {@code Activity} as {@code context} (or call {@link #install} in {@code
   * Application.onCreate}): the overlay is attached to activities the callbacks have seen start, and
   * a running activity is only seen if it is passed here.
   */
  public static synchronized void init(
      Context context,
      String apiKey,
      String playerToken,
      String baseUrl,
      ActivePopup.DeepLinkHandler onDeepLink,
      ActivePopup.CustomActionHandler onCustomAction,
      List<String> blockedRoutes,
      PopupSource source) {
    Context app = context.getApplicationContext();
    OptikpiInAppController ctrl = OptikpiInAppController.getInstance(app);
    PopupSource resolved = source != null ? source : ctrl.defaultHttpSource();
    List<String> routes =
        blockedRoutes != null
            ? Collections.unmodifiableList(new ArrayList<>(blockedRoutes))
            : Collections.emptyList();
    OptikpiLifecycleCallbacks callbacks =
        app instanceof Application ? ensureLifecycle((Application) app, ctrl) : null;
    Activity running = activityOf(context);
    // init can be called from a login callback on an I/O thread: adopting the activity touches its
    // views, and starting the session must serialize with publish() on the main looper.
    ctrl.runOnMain(
        () -> {
          if (callbacks != null) {
            // With no activity to adopt, foreground stays as the lifecycle callbacks have seen it:
            // process importance is not used, since a receiver or a foreground service reports the
            // same importance as a visible app with no activity on screen.
            if (running != null) {
              callbacks.adoptRunningActivity(running);
            }
          }
          ctrl.initWithTokenOnMain(
              apiKey, playerToken, baseUrl, resolved, onDeepLink, onCustomAction, routes);
        });
  }

  public static void init(Context context, String apiKey, String playerToken, String baseUrl) {
    init(context, apiKey, playerToken, baseUrl, null, null, Collections.emptyList(), null);
  }

  /**
   * Replaces the deep-link and custom-action handlers, which {@code init} sets, without restarting
   * the session. The SDK holds them for the life of the process (until {@link #logout}), so a
   * handler that captures an {@code Activity} leaks it across rotation and calls into the
   * destroyed instance. Pass handlers that go through your application (a navigator, an event
   * bus), or bind them from an Activity and unbind them with {@link #clearHandlers} in {@code
   * onDestroy}. Passing {@code null} here clears unconditionally.
   */
  public static void setHandlers(
      Context context,
      ActivePopup.DeepLinkHandler onDeepLink,
      ActivePopup.CustomActionHandler onCustomAction) {
    OptikpiInAppController.getInstance(context).setHandlers(onDeepLink, onCustomAction);
  }

  /**
   * Unbinds the handlers you gave {@link #setHandlers}, but only those still installed: Android
   * can destroy one Activity after the next has bound its own, and a plain {@code setHandlers(null,
   * null)} would remove the live ones. Pass the same instances you installed (keep them in fields:
   * a method reference such as {@code this::open} is a new object each time it is written).
   */
  public static void clearHandlers(
      Context context,
      ActivePopup.DeepLinkHandler onDeepLink,
      ActivePopup.CustomActionHandler onCustomAction) {
    OptikpiInAppController.getInstance(context).clearHandlers(onDeepLink, onCustomAction);
  }

  public static void setPlayerToken(Context context, String playerToken) {
    OptikpiInAppController.getInstance(context).setPlayerToken(playerToken);
  }

  public static void logout(Context context) {
    OptikpiInAppController.getInstance(context).logout();
  }

  public static void didChangeRoute(Context context, String route) {
    Activity activity = activityOf(context);
    OptikpiInAppController ctrl = OptikpiInAppController.getInstance(context);
    ctrl.runOnMain(
        () -> {
          OptikpiLifecycleCallbacks callbacks = lifecycle;
          if (callbacks != null) {
            // So the activity gets this route back when it returns to the top (see onActivityResumed).
            callbacks.routeReported(activity, route);
          }
          ctrl.didChangeRouteOnMain(route);
        });
  }

  public static void showTest(Context context, PopupContent content) {
    OptikpiInAppController.getInstance(context).showTest(content);
  }

  public static PopupSource mockSource(Context context) {
    return new MockPopupSource(context);
  }

  public static PopupSource mockSource(Context context, Map<String, String> playerData) {
    return new MockPopupSource(context, playerData);
  }

  private static OptikpiLifecycleCallbacks ensureLifecycle(
      Application application, OptikpiInAppController controller) {
    if (lifecycle == null) {
      lifecycle = new OptikpiLifecycleCallbacks(controller);
      application.registerActivityLifecycleCallbacks(lifecycle);
    }
    return lifecycle;
  }

  /** The activity behind {@code context}, looking through wrappers such as a themed context. */
  private static Activity activityOf(Context context) {
    Context current = context;
    while (current instanceof android.content.ContextWrapper) {
      if (current instanceof Activity) {
        return (Activity) current;
      }
      current = ((android.content.ContextWrapper) current).getBaseContext();
    }
    return null;
  }
}
