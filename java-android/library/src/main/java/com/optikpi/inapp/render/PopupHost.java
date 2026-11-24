package com.optikpi.inapp.render;

import android.app.Activity;
import android.content.Context;
import android.view.inputmethod.InputMethodManager;
import java.lang.ref.WeakReference;
import androidx.activity.ComponentActivity;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.widget.FrameLayout;
import androidx.activity.OnBackPressedCallback;
import com.optikpi.inapp.ActivePopup;
import com.optikpi.inapp.OptikpiInAppController;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.WeakHashMap;

public final class PopupHost {
  private static final WeakHashMap<Activity, HostBinding> BINDINGS = new WeakHashMap<>();

  private PopupHost() {}

  public static boolean isAttached(Activity activity) {
    return BINDINGS.containsKey(activity);
  }

  public static void attach(Activity activity, OptikpiInAppController controller) {
    attach(activity, controller, false);
  }

  /**
   * [suspended] starts the binding without drawing, for an activity that is not in front yet; it
   * draws once {@link #setTop} names it.
   */
  public static void attach(
      Activity activity, OptikpiInAppController controller, boolean suspended) {
    detach(activity);
    // The window's decor, not android.R.id.content: an ActionBar is a sibling of the content, and
    // a blocking pop-up has to cover its Up and menu controls too.
    View decor = activity.getWindow().getDecorView();
    if (!(decor instanceof ViewGroup root)) {
      return;
    }
    FrameLayout overlay = new FrameLayout(activity);
    overlay.setLayoutParams(
        new ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
    overlay.setClickable(false);
    root.addView(overlay);
    OnBackPressedCallback back =
        new OnBackPressedCallback(false) {
          @Override
          public void handleOnBackPressed() {
            ActivePopup active = controller.getCurrent();
            if (active != null && PopupBlocksPage.blocksPage(active.getContent())) {
              controller.close(active, true);
            }
          }
        };
    if (activity instanceof ComponentActivity componentActivity) {
      componentActivity.getOnBackPressedDispatcher().addCallback(componentActivity, back);
    }
    HostBinding binding = new HostBinding(controller, root, overlay, back);
    binding.suspended = suspended;
    BINDINGS.put(activity, binding);
    controller.addCurrentListener(binding.listener);
    binding.listener.onChanged(controller.getCurrent());
  }

  /**
   * Draws pop-ups only in the activity in front. Call it with the resumed activity: every other
   * attached one is suspended and clears its overlay, and this one picks the current pop-up up.
   */
  public static void setTop(Activity top) {
    for (Map.Entry<Activity, HostBinding> entry : new ArrayList<>(BINDINGS.entrySet())) {
      Activity activity = entry.getKey();
      if (activity != null) {
        entry.getValue().setSuspended(activity != top);
      }
    }
  }

  /** An activity that has been paused no longer shows the pop-up (it may be under a dialog). */
  public static void suspend(Activity activity) {
    HostBinding binding = BINDINGS.get(activity);
    if (binding != null) {
      binding.setSuspended(true);
    }
  }

  public static void detach(Activity activity) {
    HostBinding binding = BINDINGS.remove(activity);
    if (binding == null) {
      return;
    }
    binding.controller.removeCurrentListener(binding.listener);
    // Work already queued for this binding must not run against a root it has left.
    binding.detached = true;
    binding.handler.removeCallbacksAndMessages(null);
    binding.clearPending();
    binding.restorePage();
    ViewGroup parent = (ViewGroup) binding.overlay.getParent();
    if (parent != null) {
      parent.removeView(binding.overlay);
    }
    binding.back.remove();
  }

  private static final class HostBinding {
    final OptikpiInAppController controller;
    final ViewGroup root;
    final FrameLayout overlay;
    final OnBackPressedCallback back;
    final OptikpiInAppController.CurrentListener listener;

    final Handler handler = new Handler(Looper.getMainLooper());
    volatile boolean detached;

    /** Main thread. True while this activity is not the one in front. */
    boolean suspended;

    /** The page's views and what their accessibility importance was before a blocking pop-up. */
    private final Map<View, Integer> hidden = new HashMap<>();

    private final Map<ViewGroup, Integer> focusability = new HashMap<>();
    private WeakReference<View> focusBefore = new WeakReference<>(null);

    /**
     * A blocking pop-up covers the page, so neither a screen reader nor a keyboard (or the IME)
     * may reach what is behind it: hide it from accessibility, take focus off it and keep focus
     * from going back until the pop-up closes.
     */
    void hidePage() {
      if (hidden.isEmpty()) {
        focusBefore = new WeakReference<>(root.findFocus());
      }
      for (int i = 0; i < root.getChildCount(); i++) {
        View child = root.getChildAt(i);
        if (child == overlay || hidden.containsKey(child)) {
          continue;
        }
        hidden.put(child, child.getImportantForAccessibility());
        child.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        if (child instanceof ViewGroup) {
          ViewGroup group = (ViewGroup) child;
          focusability.put(group, group.getDescendantFocusability());
          group.setDescendantFocusability(ViewGroup.FOCUS_BLOCK_DESCENDANTS);
        }
        child.clearFocus();
      }
      InputMethodManager imm =
          (InputMethodManager) overlay.getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
      if (imm != null) {
        imm.hideSoftInputFromWindow(overlay.getWindowToken(), 0);
      }
    }

    /** The listeners waiting on the pop-up view's first frame, and that view. */
    private ViewTreeObserver.OnPreDrawListener pendingPreDraw;

    private ViewTreeObserver.OnDrawListener pendingDraw;
    private View pendingView;

    /**
     * Takes the pending listeners off every observer they can be on. A listener added while the
     * view was attached lives on the window's observer; once the view is removed, {@code
     * view.getViewTreeObserver()} is a detached one that never held it, so the overlay's and the
     * root's observers (the window's) are cleared too. Removing from one that does not hold it is
     * a no-op. Not to be called from inside {@code OnDrawListener.onDraw}.
     */
    private void clearPending() {
      ViewTreeObserver.OnPreDrawListener preDraw = pendingPreDraw;
      ViewTreeObserver.OnDrawListener draw = pendingDraw;
      View view = pendingView;
      pendingPreDraw = null;
      pendingDraw = null;
      pendingView = null;
      if (preDraw == null && draw == null) {
        return;
      }
      ViewTreeObserver[] observers = {
        view != null ? view.getViewTreeObserver() : null,
        overlay.getViewTreeObserver(),
        root.getViewTreeObserver()
      };
      for (ViewTreeObserver observer : observers) {
        if (observer == null || !observer.isAlive()) {
          continue;
        }
        if (preDraw != null) {
          observer.removeOnPreDrawListener(preDraw);
        }
        if (draw != null) {
          observer.removeOnDrawListener(draw);
        }
      }
    }

    /**
     * An impression is a pop-up the player could see: a frame that really was drawn with it in
     * the window, not one that was merely about to be (another pre-draw listener, such as a splash
     * screen's, can still cancel it). So the count comes from {@code OnDrawListener}, which only
     * runs for a frame that goes ahead. A pre-draw guard keeps a stale or suspended view off the
     * screen until then.
     */
    private void reportWhenDrawn(PopupOverlayView view, ActivePopup active) {
      clearPending();
      ViewTreeObserver.OnPreDrawListener guard =
          new ViewTreeObserver.OnPreDrawListener() {
            @Override
            public boolean onPreDraw() {
              if (detached || view.getParent() != overlay) {
                // The view was already taken out: this listener has nothing left to guard, and
                // one that stayed would keep cancelling traversals.
                if (pendingPreDraw == this) {
                  clearPending();
                }
                return true;
              }
              // The clearing of a stale view is only posted, so a frame can come first: a host
              // that is suspended (its activity was paused, so it may be under a translucent
              // one), or a pop-up that is no longer current (logout, another player, a blocked
              // screen), must not be drawn, let alone counted. Take the view out and skip it.
              if (suspended || controller.getCurrent() != active) {
                overlay.removeView(view);
                return false;
              }
              return true;
            }
          };
      ViewTreeObserver.OnDrawListener reporter =
          new ViewTreeObserver.OnDrawListener() {
            private boolean seen;

            @Override
            public void onDraw() {
              if (seen) {
                return;
              }
              seen = true;
              // Listeners and the view tree can't be changed from inside onDraw: decide once the
              // frame is done, and check again then that the pop-up is still the one on screen.
              handler.post(
                  () -> {
                    if (pendingDraw == this) {
                      clearPending();
                    }
                    if (detached
                        || suspended
                        || view.getParent() != overlay
                        || controller.getCurrent() != active) {
                      return;
                    }
                    // The frame itself proves the window was on screen; still make sure the view
                    // was part of it.
                    if (view.isAttachedToWindow() && view.isShown()) {
                      controller.didDraw(active);
                    }
                  });
            }
          };
      pendingPreDraw = guard;
      pendingDraw = reporter;
      pendingView = view;
      ViewTreeObserver observer = view.getViewTreeObserver();
      observer.addOnPreDrawListener(guard);
      observer.addOnDrawListener(reporter);
    }

    void restorePage() {
      for (Map.Entry<View, Integer> entry : hidden.entrySet()) {
        entry.getKey().setImportantForAccessibility(entry.getValue());
      }
      boolean wasHidden = !hidden.isEmpty();
      hidden.clear();
      for (Map.Entry<ViewGroup, Integer> entry : focusability.entrySet()) {
        entry.getKey().setDescendantFocusability(entry.getValue());
      }
      focusability.clear();
      View before = focusBefore.get();
      focusBefore = new WeakReference<>(null);
      // Still part of this page (not removed while the pop-up was up)?
      if (wasHidden && before != null && before.getRootView() == root.getRootView()) {
        before.requestFocus();
      }
    }

    void setSuspended(boolean value) {
      if (suspended == value) {
        return;
      }
      suspended = value;
      handler.post(() -> render(controller.getCurrent()));
    }

    /**
     * Shows [shown] (or clears the overlay when it is null). A binding that is suspended, because
     * its activity is not the one in front, shows nothing: a dialog-themed or translucent activity
     * leaves the one under it started, and drawing the same pop-up in both would stack scrims and
     * cards and let the covered one win the impression.
     */
    void render(ActivePopup shown) {
      ActivePopup active = suspended ? null : shown;
      if (detached) {
        return;
      }
      clearPending();
      overlay.removeAllViews();
      boolean blocks =
          active != null && PopupBlocksPage.blocksPage(active.getContent());
      back.setEnabled(blocks);
      // Banners and toasts leave the page usable, so it stays exposed for them.
      if (blocks) {
        hidePage();
      } else {
        restorePage();
      }
      if (active == null) {
        return;
      }
      PopupOverlayView view =
          new PopupOverlayView(
              overlay.getContext(),
              active.getContent(),
              controller.getImages(),
              new PopupOverlayView.Callbacks() {
                @Override
                public void onButton(int index) {
                  controller.tapButton(active, index);
                }

                @Override
                public void onImageTap() {
                  controller.tapImage(active);
                }

                @Override
                public void onClose() {
                  controller.close(active, true);
                }

                @Override
                public void onOutsideTap() {
                  controller.close(active, true);
                }
              });
      overlay.addView(
          view,
          new FrameLayout.LayoutParams(
              FrameLayout.LayoutParams.MATCH_PARENT,
              FrameLayout.LayoutParams.MATCH_PARENT));
      if (blocks) {
        view.requestFocus(); // keyboard focus belongs to the pop-up now
      }
      reportWhenDrawn(view, active);

    }

    HostBinding(
        OptikpiInAppController controller,
        ViewGroup root,
        FrameLayout overlay,
        OnBackPressedCallback back) {
      this.controller = controller;
      this.root = root;
      this.overlay = overlay;
      this.back = back;
      this.listener = active -> handler.post(() -> render(active));
    }
  }
}