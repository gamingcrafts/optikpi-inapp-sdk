package com.optikpi.inapp.integration;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.view.View;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleEventObserver;
import androidx.lifecycle.LifecycleOwner;
import com.optikpi.inapp.OptikpiInAppController;
import com.optikpi.inapp.render.PopupHost;
import java.lang.ref.WeakReference;
import java.util.Collections;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;

/**
 * Follows the app's activities: draws pop-ups over each started one, reports each start as a screen
 * visit, and tells the controller when the app goes to and from the foreground.
 *
 * <p>Callbacks only see activities that start after they are registered. Register them in
 * {@code Application.onCreate} (see {@code OptikpiInApp.install}), or pass the running activity to
 * {@code OptikpiInApp.init}, which hands it to {@link #adoptRunningActivity}.
 */
public final class OptikpiLifecycleCallbacks implements Application.ActivityLifecycleCallbacks {
  private final OptikpiInAppController controller;

  /** Where the route an activity reported rides through a recreation of that activity. */
  private static final String ROUTE_STATE_KEY = "com.optikpi.inapp.route";
  /** The activities between onStart and onStop. Weak, and a set: it can't go negative. */
  private final Set<Activity> started = Collections.newSetFromMap(new WeakHashMap<>());

  /**
   * The route each activity last reported, so an activity that comes back to the top (a dialog or
   * translucent activity closing over it never restarts it) gets its own route back, not the
   * covering activity's.
   */
  private final Map<Activity, String> routes = new WeakHashMap<>();

  private WeakReference<Activity> top = new WeakReference<>(null);

  /** Plain activities whose adoption is waiting for their window. Weak, and a set. */
  private final Set<Activity> awaitingWindow = Collections.newSetFromMap(new WeakHashMap<>());

  /**
   * Whether any activity has been seen. A cleared weak reference can't tell "never seen one" from
   * "the last one was collected", and only the first activity may inherit a route the app
   * reported before the callbacks existed.
   */
  private boolean observedActivity;

  public OptikpiLifecycleCallbacks(OptikpiInAppController controller) {
    this.controller = controller;
  }

  /**
   * An activity that was already started before these callbacks were registered, the normal case
   * when {@code init} runs after login: a single-activity app would otherwise get no overlay and no
   * foreground state until its next stop and start. Safe to call again for the same activity.
   */
  public synchronized void adoptRunningActivity(Activity activity) {
    if (!isOnScreen(activity)) {
      retryWhenWindowAttaches(activity);
      // The app is in the background as far as we can tell: don't fetch or report until it returns.
      if (started.isEmpty()) {
        controller.setForeground(false);
      }
      return;
    }
    boolean wasForeground = !started.isEmpty();
    started.add(activity);
    if (!wasForeground) {
      controller.setForeground(true);
    }
    if (!PopupHost.isAttached(activity)) {
      // Drawn only once it is in front: an adopted activity that is started but not resumed sits
      // under a translucent one.
      boolean inFront = isInFront(activity);
      PopupHost.attach(activity, controller, !inFront);
      if (!inFront) {
        showWhenResumed(activity);
      }
      String route = currentRoute(activity);
      markTop(activity);
      controller.didChangeRoute(route);
    }
  }

  /** The app reported a route: remember it for [activity], or for the top one when null. */
  public synchronized void routeReported(Activity activity, String route) {
    Activity target = activity != null ? activity : top.get();
    if (target != null && route != null) {
      routes.put(target, route);
    }
  }

  private void markTop(Activity activity) {
    top = new WeakReference<>(activity);
    observedActivity = true;
  }

  private String currentRoute(Activity activity) {
    String reported = routes.get(activity);
    if (reported == null && !observedActivity) {
      // No activity has been seen yet, so a route the controller already holds was reported by the
      // app itself (before install, or before this first adoption): keep it, don't replace it
      // with the activity's class name.
      reported = controller.getRoute();
      if (reported != null) {
        routes.put(activity, reported);
      }
    }
    return reported != null ? reported : routeOf(activity);
  }

  /**
   * Whether the activity is started and visible. A stopped activity (a login that finishes after the
   * user left the app) is neither finishing nor destroyed, but showing a pop-up on it would count an
   * impression nobody saw, and mark the app as foreground. The next {@code onActivityStarted}
   * picks it up when the user returns.
   */
  private static boolean isOnScreen(Activity activity) {
    if (activity.isFinishing() || activity.isDestroyed()) {
      return false;
    }
    if (activity instanceof LifecycleOwner) {
      return ((LifecycleOwner) activity)
          .getLifecycle()
          .getCurrentState()
          .isAtLeast(Lifecycle.State.STARTED);
    }
    // No lifecycle to ask: a stopped activity's window is hidden, but its decor keeps its own
    // visibility flag, so the window's visibility is the signal that says it is on screen.
    View decor = activity.getWindow().getDecorView();
    return decor.isAttachedToWindow()
        && decor.getVisibility() == View.VISIBLE
        && decor.getWindowVisibility() == View.VISIBLE;
  }

  /**
   * A plain {@code Activity} (no lifecycle to ask) adopted from inside its first {@code onResume}
   * has no window yet: the framework adds it after {@code onResume} returns, and the application's
   * resume notification went out before these callbacks existed. Try again once the window is
   * attached and has been made visible, or nothing would show until the next pause and resume.
   */
  private void retryWhenWindowAttaches(Activity activity) {
    if (activity instanceof LifecycleOwner
        || activity.isFinishing()
        || activity.isDestroyed()
        || !awaitingWindow.add(activity)) {
      return;
    }
    View decor = activity.getWindow().getDecorView();
    if (decor.isAttachedToWindow()) {
      // Attached but not visible: a stopped activity. Its next start is seen by the callbacks.
      awaitingWindow.remove(activity);
      return;
    }
    decor.addOnAttachStateChangeListener(
        new View.OnAttachStateChangeListener() {
          @Override
          public void onViewAttachedToWindow(View view) {
            view.removeOnAttachStateChangeListener(this);
            // The window's visibility is set later in the same traversal.
            view.post(
                () -> {
                  awaitingWindow.remove(activity);
                  adoptRunningActivity(activity);
                });
          }

          @Override
          public void onViewDetachedFromWindow(View view) {}
        });
  }

  /**
   * An activity adopted from inside its own {@code onResume} (the first {@code init}, with no
   * earlier {@code install}) still reads as started: the lifecycle reaches RESUMED only after that
   * method returns, and the application-level resume notification came before these callbacks
   * existed. Nothing would then lift the suspension, so wait for the lifecycle's own resume.
   */
  private static void showWhenResumed(Activity activity) {
    if (!(activity instanceof LifecycleOwner)) {
      return;
    }
    Lifecycle lifecycle = ((LifecycleOwner) activity).getLifecycle();
    lifecycle.addObserver(
        new LifecycleEventObserver() {
          @Override
          public void onStateChanged(LifecycleOwner source, Lifecycle.Event event) {
            if (event == Lifecycle.Event.ON_RESUME) {
              PopupHost.setTop(activity);
            }
            if (event == Lifecycle.Event.ON_RESUME || event == Lifecycle.Event.ON_DESTROY) {
              lifecycle.removeObserver(this);
            }
          }
        });
  }

  /** Resumed, as far as it can be told: an activity with no lifecycle to ask counts as in front. */
  private static boolean isInFront(Activity activity) {
    if (activity instanceof LifecycleOwner) {
      return ((LifecycleOwner) activity)
          .getLifecycle()
          .getCurrentState()
          .isAtLeast(Lifecycle.State.RESUMED);
    }
    return true;
  }

  private static String routeOf(Activity activity) {
    String data = activity.getIntent() != null ? activity.getIntent().getDataString() : null;
    return data != null ? data : "/" + activity.getClass().getSimpleName();
  }

  @Override
  public synchronized void onActivityCreated(Activity activity, Bundle savedInstanceState) {
    // A recreated activity (rotation, a configuration change) has no entry of its own: put back the
    // route its predecessor had reported, before its start is processed as a visit.
    if (savedInstanceState != null) {
      String route = savedInstanceState.getString(ROUTE_STATE_KEY);
      if (route != null) {
        routes.put(activity, route);
      }
    }
  }

  @Override
  public synchronized void onActivityStarted(Activity activity) {
    start(activity);
  }

  private void start(Activity activity) {
    boolean wasForeground = !started.isEmpty();
    started.add(activity);
    if (!wasForeground) {
      controller.setForeground(true);
    }
    PopupHost.attach(activity, controller);
    String route = currentRoute(activity);
    markTop(activity);
    controller.didChangeRoute(route);
  }

  @Override
  public synchronized void onActivityResumed(Activity activity) {
    // An activity adopted from inside its own onStart (the first init, with no earlier install)
    // was rejected as not yet started: the lifecycle only reaches STARTED after onStart returns,
    // and the application's start notification went out before these callbacks existed. Its
    // resume is the first thing seen, so take it in as a start here.
    if (!started.contains(activity) && !activity.isFinishing() && !activity.isDestroyed()) {
      start(activity);
    }
    // A dialog-themed or translucent activity closing leaves the one under it started, so it gets
    // no onStart: put its route back here, or the covering activity's route would stay in force.
    markTop(activity);
    // Only the activity in front draws the pop-up: the one it covers stays started, and would
    // draw the same pop-up under it.
    PopupHost.setTop(activity);
    controller.didChangeRoute(currentRoute(activity));
  }

  @Override
  public synchronized void onActivityPaused(Activity activity) {
    PopupHost.suspend(activity);
  }

  @Override
  public synchronized void onActivityStopped(Activity activity) {
    started.remove(activity);
    PopupHost.detach(activity);
    if (started.isEmpty()) {
      controller.setForeground(false);
    }
  }

  @Override
  public synchronized void onActivitySaveInstanceState(Activity activity, Bundle outState) {
    String route = routes.get(activity);
    if (route != null) {
      outState.putString(ROUTE_STATE_KEY, route);
    }
  }

  @Override
  public synchronized void onActivityDestroyed(Activity activity) {
    started.remove(activity);
    routes.remove(activity);
    PopupHost.detach(activity);
  }
}
