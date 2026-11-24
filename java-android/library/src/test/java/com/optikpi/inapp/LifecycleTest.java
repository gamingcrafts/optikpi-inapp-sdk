package com.optikpi.inapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.app.Activity;
import androidx.activity.ComponentActivity;
import android.content.Intent;
import android.net.Uri;
import android.os.Looper;
import org.robolectric.android.controller.ActivityController;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.LinearLayout;
import com.optikpi.inapp.integration.OptikpiLifecycleCallbacks;
import com.optikpi.inapp.model.PopupContent;
import com.optikpi.inapp.render.PopupHost;
import com.optikpi.inapp.render.PopupOverlayView;
import org.json.JSONObject;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

@RunWith(RobolectricTestRunner.class)
public class LifecycleTest {
  /** The controller is a process-wide singleton: start each test with no route reported. */
  @Before
  public void forgetTheReportedRoute() throws Exception {
    java.lang.reflect.Field route = OptikpiInAppController.class.getDeclaredField("route");
    route.setAccessible(true);
    route.set(OptikpiInAppController.getInstance(RuntimeEnvironment.getApplication()), null);
  }

  private static PopupContent modal() throws Exception {
    return PopupContent.tryParse(
        new JSONObject()
            .put("version", 1)
            .put("layout", "modal")
            .put("size", "md")
            .put("title", "Hello"));
  }

  /** The window's original content: the host's overlay is added after it. */
  private static View pageRoot(Activity activity) {
    return ((ViewGroup) activity.getWindow().getDecorView()).getChildAt(0);
  }

  private static int overlays(Activity activity) {
    ViewGroup content = (ViewGroup) activity.getWindow().getDecorView();
    int count = 0;
    for (int i = 0; i < content.getChildCount(); i++) {
      View host = content.getChildAt(i);
      if (host instanceof ViewGroup) {
        ViewGroup group = (ViewGroup) host;
        for (int j = 0; j < group.getChildCount(); j++) {
          if (group.getChildAt(j) instanceof PopupOverlayView) {
            count++;
          }
        }
      }
    }
    return count;
  }

  @Test
  public void anActivityThatStartedBeforeInitGetsTheOverlay() throws Exception {
    // init runs after login, when the activity is long since started: the callbacks never saw it.
    Activity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);

    assertFalse(PopupHost.isAttached(activity));
    callbacks.adoptRunningActivity(activity);
    assertTrue(PopupHost.isAttached(activity));

    controller.showTest(modal());
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals(1, overlays(activity));

    // Adopting again is harmless: still one overlay host, not two.
    callbacks.adoptRunningActivity(activity);
    assertTrue(PopupHost.isAttached(activity));
    PopupHost.detach(activity);
  }

  @Test
  public void aStopWithoutAStartDoesNotBreakForegroundTracking() {
    Activity activity = Robolectric.buildActivity(Activity.class).create().get();
    OptikpiInAppController controller =
        OptikpiInAppController.getInstance(RuntimeEnvironment.getApplication());
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);
    // A stop that was never preceded by a start used to leave the counter negative.
    callbacks.onActivityStopped(activity);
    callbacks.onActivityStarted(activity);
    assertNotNull(activity);
    assertTrue(PopupHost.isAttached(activity));
    callbacks.onActivityStopped(activity);
    assertFalse(PopupHost.isAttached(activity));
  }

  @Test
  public void anActivityThatIsAlreadyStoppedIsNotAdopted() {
    // A login that finishes after the user left the app: stopped, but not finishing or destroyed.
    ActivityController<ComponentActivity> controllerOf =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume();
    ComponentActivity activity = controllerOf.get();
    controllerOf.pause().stop();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);

    callbacks.adoptRunningActivity(activity);

    assertFalse(PopupHost.isAttached(activity));
  }

  @Test
  public void aBlockingPopupHidesThePageFromScreenReadersAndABannerDoesNot() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    View page = new View(activity);
    activity.setContentView(page);
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    new OptikpiLifecycleCallbacks(controller).adoptRunningActivity(activity);
    int original = pageRoot(activity).getImportantForAccessibility();

    controller.showTest(modal());
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals(
        View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS, pageRoot(activity).getImportantForAccessibility());

    controller.showTest(
        PopupContent.tryParse(
            new JSONObject()
                .put("version", 1)
                .put("layout", "banner")
                .put("size", "md")
                .put("title", "Hi")));
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals(original, pageRoot(activity).getImportantForAccessibility());
    PopupHost.detach(activity);
  }

  private static ComponentActivity activityAt(String url) {
    return Robolectric.buildActivity(
            ComponentActivity.class, new Intent().setData(Uri.parse(url)))
        .create()
        .start()
        .resume()
        .get();
  }

  @Test
  public void anActivityBackOnTopGetsItsOwnRouteBack() {
    ComponentActivity first = activityAt("app://first");
    ComponentActivity second = activityAt("app://second");
    OptikpiInAppController controller = OptikpiInAppController.getInstance(first);
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);

    callbacks.onActivityStarted(first);
    callbacks.onActivityResumed(first);
    assertEquals("app://first", controller.getRoute());
    // A dialog-themed activity opens over it: the first stays started, and is not started again.
    callbacks.onActivityStarted(second);
    callbacks.onActivityResumed(second);
    assertEquals("app://second", controller.getRoute());
    callbacks.onActivityPaused(second);
    callbacks.onActivityStopped(second);
    callbacks.onActivityResumed(first);

    assertEquals("app://first", controller.getRoute());
  }

  @Test
  public void aRouteTheAppReportedIsTheOneRestored() {
    ComponentActivity first = activityAt("app://first");
    ComponentActivity second = activityAt("app://second");
    OptikpiInAppController controller = OptikpiInAppController.getInstance(first);
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);

    callbacks.onActivityStarted(first);
    callbacks.onActivityResumed(first);
    callbacks.routeReported(null, "/dashboard/home"); // the app's own path for the top activity
    controller.didChangeRoute("/dashboard/home");
    callbacks.onActivityStarted(second);
    callbacks.onActivityResumed(second);
    callbacks.onActivityStopped(second);
    callbacks.onActivityResumed(first);

    assertEquals("/dashboard/home", controller.getRoute());
  }

  @Test
  public void workQueuedBeforeDetachDoesNotHideThePageAfterwards() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    View page = new View(activity);
    activity.setContentView(page);
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    int original = pageRoot(activity).getImportantForAccessibility();
    PopupHost.attach(activity, controller);

    controller.showTest(modal()); // queues the host's work on the main looper
    PopupHost.detach(activity); // the activity stops before it runs
    shadowOf(Looper.getMainLooper()).idle();

    assertEquals(original, pageRoot(activity).getImportantForAccessibility());
  }

  @Test
  public void aRouteReportedBeforeTheFirstAdoptionIsKept() {
    ComponentActivity activity = activityAt("app://class-default");
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    // The app reports its own path before init, so no lifecycle callbacks exist yet.
    controller.didChangeRoute("/dashboard/blocked");

    new OptikpiLifecycleCallbacks(controller).adoptRunningActivity(activity);

    assertEquals("/dashboard/blocked", controller.getRoute());
  }

  @Test
  public void onlyTheFirstObservedActivityInheritsAPreReportedRoute() {
    ComponentActivity first = activityAt("app://first");
    ComponentActivity second = activityAt("app://second");
    OptikpiInAppController controller = OptikpiInAppController.getInstance(first);
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);
    controller.didChangeRoute("/reported-first");

    callbacks.onActivityStarted(first);
    assertEquals("/reported-first", controller.getRoute());
    callbacks.onActivityStopped(first);
    // The screen the controller still holds belongs to the first activity, not the second.
    callbacks.onActivityStarted(second);

    assertEquals("app://second", controller.getRoute());
  }

  @Test
  public void aBlockingPopupTakesKeyboardFocusOffThePageAndGivesItBack() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    LinearLayout page = new LinearLayout(activity);
    EditText field = new EditText(activity);
    page.addView(field);
    activity.setContentView(page);
    field.requestFocus();
    assertTrue(field.hasFocus());
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    new OptikpiLifecycleCallbacks(controller).adoptRunningActivity(activity);
    ViewGroup pageRoot = (ViewGroup) pageRoot(activity);
    int original = pageRoot.getDescendantFocusability();

    controller.showTest(modal());
    shadowOf(Looper.getMainLooper()).idle();
    assertFalse("the field lost focus", field.hasFocus());
    assertEquals(ViewGroup.FOCUS_BLOCK_DESCENDANTS, pageRoot.getDescendantFocusability());

    // A banner leaves the page usable again.
    controller.showTest(
        PopupContent.tryParse(
            new JSONObject()
                .put("version", 1)
                .put("layout", "banner")
                .put("size", "md")
                .put("title", "Hi")));
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals(original, pageRoot.getDescendantFocusability());
    assertTrue("focus went back to the field", field.hasFocus());
    PopupHost.detach(activity);
  }

  @Test
  public void aReportedRouteSurvivesTheActivityBeingRecreated() {
    ComponentActivity before = activityAt("app://home");
    OptikpiInAppController controller = OptikpiInAppController.getInstance(before);
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);
    callbacks.onActivityStarted(before);
    // A single-activity app reports its own path on navigation.
    callbacks.routeReported(before, "/dashboard/deposit");
    controller.didChangeRoute("/dashboard/deposit");

    // Rotation: the state is saved, the old instance goes, a new one is created from the state.
    android.os.Bundle state = new android.os.Bundle();
    callbacks.onActivitySaveInstanceState(before, state);
    callbacks.onActivityStopped(before);
    callbacks.onActivityDestroyed(before);
    ComponentActivity after = activityAt("app://home");
    callbacks.onActivityCreated(after, state);
    callbacks.onActivityStarted(after);

    assertEquals("/dashboard/deposit", controller.getRoute());
  }

  @Test
  public void anActivityCreatedFreshHasNoRouteToRestore() {
    ComponentActivity activity = activityAt("app://fresh");
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);
    callbacks.onActivityCreated(activity, null);
    callbacks.onActivityCreated(activity, new android.os.Bundle());
    callbacks.onActivityStarted(activity);
    assertEquals("app://fresh", controller.getRoute());
  }

  @Test
  public void onlyTheActivityInFrontDrawsThePopup() throws Exception {
    ComponentActivity under = activityAt("app://under");
    ComponentActivity front = activityAt("app://front");
    OptikpiInAppController controller = OptikpiInAppController.getInstance(under);
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);

    // A translucent activity starts over the first, which stays started but is paused.
    callbacks.onActivityStarted(under);
    callbacks.onActivityResumed(under);
    callbacks.onActivityPaused(under);
    callbacks.onActivityStarted(front);
    callbacks.onActivityResumed(front);

    controller.showTest(modal());
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals("the covered activity draws nothing", 0, overlays(under));
    assertEquals(1, overlays(front));

    // The covering activity closes: the one under it is back in front and draws the popup.
    callbacks.onActivityPaused(front);
    callbacks.onActivityStopped(front);
    callbacks.onActivityResumed(under);
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals(1, overlays(under));
    assertEquals(0, overlays(front));

    callbacks.onActivityStopped(under);
  }

  @Test
  public void aViewThatIsNoLongerCurrentIsNotDrawnInTheFrameThatFollows() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    new OptikpiLifecycleCallbacks(controller).adoptRunningActivity(activity);

    controller.showTest(modal());
    shadowOf(Looper.getMainLooper()).idle();
    ActivePopup active = controller.getCurrent();
    PopupOverlayView view = findOverlay(activity);
    assertNotNull(view);

    // The pop-up goes away (logout, a blocked screen), but the host's clearing is only posted.
    controller.close(active, false);
    java.lang.reflect.Method dispatch =
        android.view.ViewTreeObserver.class.getDeclaredMethod("dispatchOnPreDraw");
    dispatch.setAccessible(true);
    boolean cancelled = (boolean) dispatch.invoke(view.getViewTreeObserver());

    assertTrue("the stale frame is cancelled", cancelled);
    assertEquals("and the view is out of the window", 0, overlays(activity));
    PopupHost.detach(activity);
  }

  private static PopupOverlayView findOverlay(Activity activity) {
    ViewGroup decor = (ViewGroup) activity.getWindow().getDecorView();
    for (int i = 0; i < decor.getChildCount(); i++) {
      View host = decor.getChildAt(i);
      if (host instanceof ViewGroup) {
        ViewGroup group = (ViewGroup) host;
        for (int j = 0; j < group.getChildCount(); j++) {
          if (group.getChildAt(j) instanceof PopupOverlayView) {
            return (PopupOverlayView) group.getChildAt(j);
          }
        }
      }
    }
    return null;
  }

  @Test
  public void aRemovedPopupLeavesNoPreDrawListenerBehindToFreezeTheWindow() throws Exception {
    // Visible, so the decor is attached and its observer is the window's live one.
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().visible().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    new OptikpiLifecycleCallbacks(controller).adoptRunningActivity(activity);

    controller.showTest(modal());
    shadowOf(Looper.getMainLooper()).idle(); // rendered, first frame not drawn yet
    ActivePopup active = controller.getCurrent();
    assertEquals(1, overlays(activity));

    // Removed before its first frame (a logout, a replacement, a blocked screen).
    controller.close(active, false);
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals(0, overlays(activity));

    java.lang.reflect.Method dispatch =
        android.view.ViewTreeObserver.class.getDeclaredMethod("dispatchOnPreDraw");
    dispatch.setAccessible(true);
    View decor = activity.getWindow().getDecorView();
    for (int frame = 0; frame < 3; frame++) {
      boolean cancelled = (boolean) dispatch.invoke(decor.getViewTreeObserver());
      assertFalse("frame " + frame + " must not be cancelled by a leftover listener", cancelled);
    }
    PopupHost.detach(activity);
  }

  /** Runs a hidden ViewTreeObserver dispatch, as the framework does for a traversal. */
  private static boolean dispatch(android.view.ViewTreeObserver observer, String method)
      throws Exception {
    java.lang.reflect.Method m =
        android.view.ViewTreeObserver.class.getDeclaredMethod(method);
    m.setAccessible(true);
    Object result = m.invoke(observer);
    return result instanceof Boolean && (Boolean) result;
  }

  @Test
  public void aFrameThatIsCancelledDoesNotCountAsAnImpression() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().visible().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    new OptikpiLifecycleCallbacks(controller).adoptRunningActivity(activity);
    View decor = activity.getWindow().getDecorView();

    // Another listener, like a splash screen's keep-on-screen condition, cancels the frame.
    android.view.ViewTreeObserver.OnPreDrawListener splash = () -> false;
    decor.getViewTreeObserver().addOnPreDrawListener(splash);

    controller.showTest(modal());
    shadowOf(Looper.getMainLooper()).idle();
    ActivePopup active = controller.getCurrent();
    assertNotNull(active);

    boolean cancelled = dispatch(decor.getViewTreeObserver(), "dispatchOnPreDraw");
    shadowOf(Looper.getMainLooper()).idle();
    assertTrue("the splash listener cancelled the frame", cancelled);
    assertFalse("nothing was drawn, so nothing is counted", active.drawn);

    // The splash goes; the next frame is drawn, and that is the impression.
    decor.getViewTreeObserver().removeOnPreDrawListener(splash);
    assertFalse(dispatch(decor.getViewTreeObserver(), "dispatchOnPreDraw"));
    dispatch(decor.getViewTreeObserver(), "dispatchOnDraw");
    shadowOf(Looper.getMainLooper()).idle();
    assertTrue("a frame that was drawn counts", active.drawn);
    PopupHost.detach(activity);
  }

  @Test
  public void anActivityAdoptedBeforeItsResumeCompletesShowsWhenTheLifecycleResumes()
      throws Exception {
    // init called from inside onResume: the lifecycle still reads STARTED, and the application's
    // resume callback went out before the SDK's callbacks were registered.
    org.robolectric.android.controller.ActivityController<ComponentActivity> started =
        Robolectric.buildActivity(ComponentActivity.class).create().start();
    ComponentActivity activity = started.get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    new OptikpiLifecycleCallbacks(controller).adoptRunningActivity(activity);

    controller.showTest(modal());
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals("not shown while it is only started", 0, overlays(activity));

    started.resume();
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals("shown once the lifecycle resumes", 1, overlays(activity));
    PopupHost.detach(activity);
  }

  @Test
  public void anActivityAdoptedInsideItsOwnOnStartIsTakenInWhenItResumes() throws Exception {
    // init called from inside onStart: the lifecycle still reads CREATED, so adoption is refused,
    // and the application's start callback went out before the SDK's callbacks were registered.
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);
    callbacks.adoptRunningActivity(activity);
    assertFalse(PopupHost.isAttached(activity));

    callbacks.onActivityResumed(activity);
    shadowOf(Looper.getMainLooper()).idle();
    assertTrue("hosted once it resumes", PopupHost.isAttached(activity));

    controller.showTest(modal());
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals("and a campaign shows", 1, overlays(activity));
    callbacks.onActivityStopped(activity);
  }

  @Test
  public void aPlainActivityAdoptedInsideItsFirstResumeIsTakenInOnceItsWindowShows()
      throws Exception {
    // No lifecycle to ask, and the window is only added after onResume returns.
    ActivityController<Activity> built =
        Robolectric.buildActivity(Activity.class).create().start().resume();
    Activity activity = built.get();
    View decor = activity.getWindow().getDecorView();
    // Robolectric leaves the window's visibility GONE; on a device it is VISIBLE from the first
    // traversal on. Set it as the window attaches, ahead of the SDK's own listener.
    decor.addOnAttachStateChangeListener(
        new View.OnAttachStateChangeListener() {
          @Override
          public void onViewAttachedToWindow(View view) {
            try {
              java.lang.reflect.Field attachInfoField = View.class.getDeclaredField("mAttachInfo");
              attachInfoField.setAccessible(true);
              Object attachInfo = attachInfoField.get(view);
              java.lang.reflect.Field windowVisibility =
                  attachInfo.getClass().getDeclaredField("mWindowVisibility");
              windowVisibility.setAccessible(true);
              windowVisibility.setInt(attachInfo, View.VISIBLE);
            } catch (ReflectiveOperationException e) {
              throw new AssertionError(e);
            }
          }

          @Override
          public void onViewDetachedFromWindow(View view) {}
        });
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    OptikpiLifecycleCallbacks callbacks = new OptikpiLifecycleCallbacks(controller);

    callbacks.adoptRunningActivity(activity);
    assertFalse("no window yet", PopupHost.isAttached(activity));
    // Adopting again meanwhile must not stack a second wait.
    callbacks.adoptRunningActivity(activity);

    built.visible();
    shadowOf(Looper.getMainLooper()).idle();

    assertTrue("hosted once its window is up", PopupHost.isAttached(activity));
    controller.showTest(modal());
    shadowOf(Looper.getMainLooper()).idle();
    assertEquals(1, overlays(activity));
    callbacks.onActivityStopped(activity);
  }
}
