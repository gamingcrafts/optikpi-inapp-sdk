package com.optikpi.inapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.view.View;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import android.widget.TextView;
import org.json.JSONArray;
import android.view.ViewGroup;
import com.optikpi.inapp.model.PopupContent;
import com.optikpi.inapp.render.PopupOverlayView;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
public class PopupOverlayViewTest {
  private final Context context = RuntimeEnvironment.getApplication();

  private static final PopupOverlayView.Callbacks NO_OP =
      new PopupOverlayView.Callbacks() {
        @Override
        public void onButton(int index) {}

        @Override
        public void onImageTap() {}

        @Override
        public void onClose() {}

        @Override
        public void onOutsideTap() {}
      };

  private PopupOverlayView view(String layout, String size) throws Exception {
    JSONObject json =
        new JSONObject()
            .put("version", 1)
            .put("layout", layout)
            .put("size", size)
            .put("title", "Hello")
            .put("body", "Body");
    PopupContent content = PopupContent.tryParse(json);
    assertNotNull(content);
    return new PopupOverlayView(context, content, null, NO_OP);
  }

  /** The card is the last child: a scrim, when the layout has one, comes before it. */
  private static ViewGroup.LayoutParams cardParams(PopupOverlayView view) {
    View card = view.getChildAt(view.getChildCount() - 1);
    return card.getLayoutParams();
  }

  @Test
  public void aModalTakesItsWidthFromItsSize() throws Exception {
    int sm = cardParams(view("modal", "sm")).width;
    int md = cardParams(view("modal", "md")).width;
    int lg = cardParams(view("modal", "lg")).width;
    assertTrue("sm < md", sm < md);
    assertTrue("md < lg", md < lg);
  }

  @Test
  public void aFixedRatioModalKeepsItsAspectRatio() throws Exception {
    ViewGroup.LayoutParams params = cardParams(view("modal", "iab_300x250"));
    assertEquals(300.0 / 250.0, (double) params.width / params.height, 0.02);
  }

  @Test
  public void aBottomSheetTakesItsHeightFromItsSize() throws Exception {
    int sm = cardParams(view("bottomSheet", "sm")).height;
    int md = cardParams(view("bottomSheet", "md")).height;
    int lg = cardParams(view("bottomSheet", "lg")).height;
    assertTrue("sm < md", sm < md);
    assertTrue("md < lg", md < lg);
  }

  @Test
  public void aBannerOfTheSmallSizeIsNarrowerThanTheScreen() throws Exception {
    int md = cardParams(view("banner", "md")).width;
    int iab = cardParams(view("banner", "iab_320x50")).width;
    assertTrue(iab <= md);
    ViewGroup.LayoutParams params = cardParams(view("banner", "iab_320x50"));
    assertEquals(320.0 / 50.0, (double) params.width / params.height, 0.1);
  }

  @Test
  public void blockingLayoutsTakeEveryTouch() throws Exception {
    for (String layout : new String[] {"modal", "fullscreen", "bottomSheet"}) {
      assertTrue(layout + " takes touches", view(layout, "lg").isClickable());
    }
  }

  @Test
  public void aBannerOrToastLetsTouchesReachThePage() throws Exception {
    PopupOverlayView banner = view("banner", "md");
    PopupOverlayView toast = view("toast", "md");
    assertFalse("banner overlay must not swallow touches", banner.isClickable());
    assertFalse("toast overlay must not swallow touches", toast.isClickable());
    // Only the card takes touches.
    assertTrue(banner.getChildAt(banner.getChildCount() - 1).isClickable());
    assertTrue(toast.getChildAt(toast.getChildCount() - 1).isClickable());
    // And they have no full-screen scrim in front of the page.
    assertEquals(1, banner.getChildCount());
    assertEquals(1, toast.getChildCount());
  }

  // WindowInsets.Builder and the Type constants only exist from API 30.
  private static WindowInsets bars(int left, int top, int right, int bottom) {
    return new WindowInsets.Builder()
        .setInsets(WindowInsets.Type.systemBars(), android.graphics.Insets.of(left, top, right, bottom))
        .build();
  }

  /**
   * Applies [insets] and lays the overlay out at [w] x [h]. The test's display must be that size
   * (see the {@code qualifiers} on the tests): the overlay builds for the display it is made on.
   */
  private PopupOverlayView laidOut(String layout, String size, int w, int h, WindowInsets insets)
      throws Exception {
    PopupOverlayView view = view(layout, size);
    view.dispatchApplyWindowInsets(insets);
    view.measure(
        View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY));
    view.layout(0, 0, w, h);
    return view;
  }

  @Test
  @Config(sdk = 34, qualifiers = "w800dp-h480dp")
  public void aBannerAndAToastStayClearOfTheSystemBars() throws Exception {
    for (String layout : new String[] {"banner", "toast"}) {
      PopupOverlayView view = laidOut(layout, "md", 800, 480, bars(10, 48, 20, 32));
      View card = view.getChildAt(view.getChildCount() - 1);
      assertTrue(layout + " left", card.getLeft() >= 10);
      assertTrue(layout + " top", card.getTop() >= 48);
      assertTrue(layout + " right", card.getRight() <= 800 - 20);
      assertTrue(layout + " bottom", card.getBottom() <= 480 - 32);
    }
  }

  @Test
  @Config(sdk = 34, qualifiers = "w800dp-h480dp")
  public void aCardIsCenteredInTheSafeAreaWhenOnlyOneSideHasAnInset() throws Exception {
    // A cutout on the left of a landscape screen: the safe area is x = 80..800.
    PopupOverlayView banner = laidOut("banner", "md", 800, 480, bars(80, 0, 0, 0));
    View card = banner.getChildAt(banner.getChildCount() - 1);
    assertEquals("full-width banner starts at the safe edge", 80, card.getLeft());
    assertEquals("and ends at the screen edge, not past it", 800, card.getRight());

    PopupOverlayView modal = laidOut("modal", "md", 800, 480, bars(80, 0, 0, 0));
    View sheet = modal.getChildAt(modal.getChildCount() - 1);
    int safeCenter = (80 + 800) / 2;
    assertEquals(
        "modal centered in the safe area", safeCenter, (sheet.getLeft() + sheet.getRight()) / 2, 1);

    // Asymmetric bars top and bottom: the same, vertically.
    PopupOverlayView tall = laidOut("modal", "md", 800, 480, bars(0, 48, 0, 0));
    View tallCard = tall.getChildAt(tall.getChildCount() - 1);
    assertEquals(
        "modal centered below the status bar",
        (48 + 480) / 2,
        (tallCard.getTop() + tallCard.getBottom()) / 2,
        1);
  }

  @Test
  @Config(sdk = 34)
  public void aFullscreenPopupKeepsItsContentClearOfTheSystemBars() throws Exception {
    PopupOverlayView view = view("fullscreen", "md");
    view.dispatchApplyWindowInsets(bars(0, 48, 0, 32));
    View card = view.getChildAt(view.getChildCount() - 1);
    assertEquals(48, card.getPaddingTop());
    assertEquals(32, card.getPaddingBottom());
  }

  @Test
  @Config(sdk = 34)
  public void aBottomSheetKeepsItsContentAboveTheNavigationBar() throws Exception {
    PopupOverlayView view = view("bottomSheet", "md");
    int before = cardParams(view).height;
    view.dispatchApplyWindowInsets(bars(0, 0, 0, 32));
    View sheet = view.getChildAt(view.getChildCount() - 1);
    assertEquals(32, sheet.getPaddingBottom());
    // The usable height shrank by the inset, and the sheet grew back by it to run under the bar.
    assertTrue(sheet.getLayoutParams().height >= before - 32);
  }

  private static TextView findText(View view, String text) {
    if (view instanceof TextView && text.contentEquals(((TextView) view).getText())) {
      return (TextView) view;
    }
    if (view instanceof ViewGroup) {
      ViewGroup group = (ViewGroup) view;
      for (int i = 0; i < group.getChildCount(); i++) {
        TextView found = findText(group.getChildAt(i), text);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }

  @Test
  public void aLongBannerActionCannotCrowdOutTheTextOrTheCloseButton() throws Exception {
    String label = "A very long call to action label that goes on and on and on";
    JSONObject json =
        new JSONObject()
            .put("version", 1)
            .put("layout", "banner")
            .put("size", "md")
            .put("title", "Weekend offer")
            .put(
                "buttons",
                new JSONArray()
                    .put(
                        new JSONObject()
                            .put("label", label)
                            .put("style", "primary")
                            .put("action", new JSONObject().put("type", "dismiss"))));
    PopupOverlayView view = new PopupOverlayView(context, PopupContent.tryParse(json), null, NO_OP);
    int width = 600;
    view.measure(
        View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(400, View.MeasureSpec.AT_MOST));
    view.layout(0, 0, width, view.getMeasuredHeight());

    TextView action = findText(view, label);
    TextView title = findText(view, "Weekend offer");
    assertNotNull(action);
    assertNotNull(title);
    assertTrue("action capped at 45%", action.getWidth() <= Math.round(width * 0.45f));
    assertTrue("title keeps room", title.getWidth() > 0);
  }

  @Test
  public void aToastAndItsCloseButtonStayOnTheirPhysicalSideUnderRtl() throws Exception {
    JSONObject json =
        new JSONObject()
            .put("version", 1)
            .put("layout", "toast")
            .put("size", "md")
            .put("position", "topRight")
            .put("title", "Hello")
            .put("body", "Body")
            .put("close", new JSONObject().put("show", true).put("position", "topRight"));
    PopupContent content = PopupContent.tryParse(json);
    assertNotNull(content);
    PopupOverlayView view = new PopupOverlayView(context, content, null, NO_OP);
    view.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
    view.measure(
        View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY));
    view.layout(0, 0, 800, 480);

    View card = view.getChildAt(view.getChildCount() - 1);
    FrameLayout cardFrame = (FrameLayout) card;
    View close = cardFrame.getChildAt(cardFrame.getChildCount() - 1);
    assertTrue("toast sits on the right", card.getLeft() > 800 / 2);
    assertTrue("topRight close is on the right", close.getLeft() > card.getWidth() / 2);
  }

  private static WindowInsets keyboard(int bottom) {
    return new WindowInsets.Builder()
        .setInsets(WindowInsets.Type.ime(), android.graphics.Insets.of(0, 0, 0, bottom))
        .build();
  }

  @Test
  @Config(sdk = 34, qualifiers = "w800dp-h480dp")
  public void aBottomBannerStaysAboveTheKeyboardAndAModalDoesNotMove() throws Exception {
    JSONObject json =
        new JSONObject()
            .put("version", 1)
            .put("layout", "banner")
            .put("size", "md")
            .put("position", "bottom")
            .put("title", "Hello");
    PopupOverlayView banner =
        new PopupOverlayView(context, PopupContent.tryParse(json), null, NO_OP);
    banner.dispatchApplyWindowInsets(keyboard(200));
    banner.measure(
        View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY));
    banner.layout(0, 0, 800, 480);
    View card = banner.getChildAt(banner.getChildCount() - 1);
    assertTrue("banner is above the keyboard", card.getBottom() <= 480 - 200);

    // A blocking pop-up closes the keyboard, so it does not make room for it.
    PopupOverlayView modal = laidOut("modal", "md", 800, 480, keyboard(200));
    View sheet = modal.getChildAt(modal.getChildCount() - 1);
    assertEquals(480 / 2, (sheet.getTop() + sheet.getBottom()) / 2, 1);
  }

  @Test
  @Config(sdk = 34, qualifiers = "w400dp-h300dp")
  public void aLongToastScrollsAndKeepsItsActionReachable() throws Exception {
    // Explicit line breaks: Robolectric does not wrap text by width, so this is what makes the body
    // taller than the card is allowed to be.
    StringBuilder longBody = new StringBuilder();
    for (int i = 0; i < 80; i++) {
      longBody.append("A line of toast text\n");
    }
    JSONObject json =
        new JSONObject()
            .put("version", 1)
            .put("layout", "toast")
            .put("size", "md")
            .put("position", "bottomRight")
            .put("title", "Hello")
            .put("body", longBody.toString())
            .put(
                "buttons",
                new JSONArray()
                    .put(
                        new JSONObject()
                            .put("label", "Claim")
                            .put("style", "primary")
                            .put(
                                "action",
                                new JSONObject().put("type", "dismiss"))));
    PopupOverlayView view =
        new PopupOverlayView(context, PopupContent.tryParse(json), null, NO_OP);
    view.measure(
        View.MeasureSpec.makeMeasureSpec(400, View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY));
    view.layout(0, 0, 400, 300);

    View card = view.getChildAt(view.getChildCount() - 1);
    assertTrue("the card respects its cap", card.getHeight() <= 300 * 0.9 + 1);
    android.widget.ScrollView scroll = findScroll(card);
    assertNotNull("long content scrolls", scroll);
    assertTrue(
        "there is more content than fits, so the action is reached by scrolling",
        scroll.getChildAt(0).getHeight() > scroll.getHeight());
    assertNotNull("the action is in the scrolling content", findText(scroll, "Claim"));
  }

  private static android.widget.ScrollView findScroll(View root) {
    if (root instanceof android.widget.ScrollView) {
      return (android.widget.ScrollView) root;
    }
    if (root instanceof ViewGroup) {
      ViewGroup group = (ViewGroup) root;
      for (int i = 0; i < group.getChildCount(); i++) {
        android.widget.ScrollView found = findScroll(group.getChildAt(i));
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }
}
