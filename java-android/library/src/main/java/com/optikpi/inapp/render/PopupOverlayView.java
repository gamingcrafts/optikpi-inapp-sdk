package com.optikpi.inapp.render;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import com.optikpi.inapp.model.PopupButton;
import com.optikpi.inapp.model.PopupClose;
import com.optikpi.inapp.model.PopupContent;
import com.optikpi.inapp.model.PopupEnums.PopupButtonStyle;
import com.optikpi.inapp.model.PopupEnums.PopupClosePosition;
import com.optikpi.inapp.model.PopupEnums.PopupPosition;
import com.optikpi.inapp.model.PopupEnums.PopupSize;
import com.optikpi.inapp.model.PopupImage;

/**
 * Draws one {@link PopupContent} over the whole screen. The layouts, sizes and spacing follow the
 * Flutter package's {@code popup_view.dart} (itself a port of the web renderer): widths use the
 * reference's mobile values below 600 dp and its desktop values above, and every layout takes its
 * dimensions from {@code content.size}.
 *
 * <p>Blocking layouts (modal, fullscreen, bottom sheet, image only) take every touch on the screen.
 * A banner or toast leaves the page usable: only its card takes touches, the rest of the overlay
 * lets them through to the app below.
 *
 * <p>This view only draws and reports taps. Tracking and actions live in the controller.
 */
public final class PopupOverlayView extends FrameLayout {
  /** The breakpoint between the reference's mobile and desktop surfaces, in dp. */
  public static final int DESKTOP_BREAKPOINT_DP = 600;

  public interface Callbacks {
    /** Index into {@code content.buttons}. */
    void onButton(int index);

    /** The image was tapped where it is a tap target (always for imageOnly, else with a tapAction). */
    void onImageTap();

    /** The close button. */
    void onClose();

    /** A tap on the dimmed area, only when {@code close.tapOutsideToClose}. */
    void onOutsideTap();
  }

  private final PopupContent content;
  private final Callbacks callbacks;
  private final PopupImageLoader images;
  private final boolean blocking;
  private final float density;
  /** The window's size, and the part of it the system bars and a display cutout leave free. */
  private int rawW;
  private int rawH;
  private int insetL;
  private int insetT;
  private int insetR;
  private int insetB;
  private int screenW;
  private int screenH;

  public PopupOverlayView(
      Context context, PopupContent content, PopupImageLoader images, Callbacks callbacks) {
    super(context);
    this.content = content;
    this.images = images;
    this.callbacks = callbacks;
    this.blocking = PopupBlocksPage.blocksPage(content);
    DisplayMetrics metrics = getResources().getDisplayMetrics();
    this.density = metrics.density;
    this.rawW = metrics.widthPixels;
    this.rawH = metrics.heightPixels;
    updateUsableSize();
    // An edge-to-edge window (always, on Android 15 with target SDK 35) runs under the status,
    // navigation and cutout areas: keep the card and its controls out of them.
    ViewCompat.setOnApplyWindowInsetsListener(
        this,
        (v, windowInsets) -> {
          // The overlay sits at the top of the window, where a parent may already have consumed
          // the insets it passes down: the window's own are the truth when we are attached.
          WindowInsetsCompat real = ViewCompat.getRootWindowInsets(v);
          WindowInsetsCompat effective = real != null ? real : windowInsets;
          Insets bars =
              effective.getInsets(
                  WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
          // A banner or toast leaves the keyboard open, and the keyboard is not part of the system
          // bars: lift a bottom card over it. A blocking pop-up closes the keyboard instead.
          int bottom = bars.bottom;
          if (!blocking) {
            bottom = Math.max(bottom, effective.getInsets(WindowInsetsCompat.Type.ime()).bottom);
          }
          if (bars.left != insetL
              || bars.top != insetT
              || bars.right != insetR
              || bottom != insetB) {
            insetL = bars.left;
            insetT = bars.top;
            insetR = bars.right;
            insetB = bottom;
            updateUsableSize();
            build();
          }
          return windowInsets;
        });
    // A banner or toast must not swallow touches outside its card.
    setClickable(blocking);
    setFocusable(blocking);
    // So the host can move focus here, in touch mode too, when a blocking pop-up appears.
    setFocusableInTouchMode(blocking);
    build();
  }

  @Override
  protected void onSizeChanged(int w, int h, int oldw, int oldh) {
    super.onSizeChanged(w, h, oldw, oldh);
    // Rotation and split-screen change the window: lay the card out again for the real size.
    if (w > 0 && h > 0 && (w != rawW || h != rawH)) {
      rawW = w;
      rawH = h;
      updateUsableSize();
      post(this::build);
    }
  }

  @Override
  protected void onAttachedToWindow() {
    super.onAttachedToWindow();
    ViewCompat.requestApplyInsets(this);
  }

  private void updateUsableSize() {
    screenW = Math.max(1, rawW - insetL - insetR);
    screenH = Math.max(1, rawH - insetT - insetB);
  }

  /**
   * Adds a card clear of the system bars and the display cutout.
   *
   * <p>On an axis where the card is centered, {@code FrameLayout} shifts it by {@code leftMargin -
   * rightMargin}, not by half of that, so full margins would push it twice as far as needed (and
   * off the screen on the far side when the insets differ, as with a one-sided cutout). Half the
   * difference centers it in the inset-safe area. Elsewhere the margins pin the card to its edge or
   * stretch it, so the full insets apply.
   */
  private void addCard(View card, LayoutParams params) {
    int gravity = params.gravity;
    boolean centeredX = false;
    boolean centeredY = false;
    if (gravity != -1) {
      int absolute = Gravity.getAbsoluteGravity(gravity, getLayoutDirection());
      centeredX = (absolute & Gravity.HORIZONTAL_GRAVITY_MASK) == Gravity.CENTER_HORIZONTAL;
      centeredY = (gravity & Gravity.VERTICAL_GRAVITY_MASK) == Gravity.CENTER_VERTICAL;
    }
    if (centeredX) {
      int shift = insetL - insetR;
      if (shift >= 0) {
        params.leftMargin += shift / 2;
      } else {
        params.rightMargin += -shift / 2;
      }
    } else {
      params.leftMargin += insetL;
      params.rightMargin += insetR;
    }
    if (centeredY) {
      int shift = insetT - insetB;
      if (shift >= 0) {
        params.topMargin += shift / 2;
      } else {
        params.bottomMargin += -shift / 2;
      }
    } else {
      params.topMargin += insetT;
      params.bottomMargin += insetB;
    }
    addView(card, params);
  }

  // ---- sizing ---------------------------------------------------------------------------------

  private int dp(float value) {
    return Math.round(value * density);
  }

  private boolean desktop() {
    return screenW >= dp(DESKTOP_BREAKPOINT_DP);
  }

  /** A modal-style card's width (the reference's {@code MODAL_WIDTH}). */
  private int cardWidth(PopupSize size) {
    boolean desktop = desktop();
    switch (size) {
      case sm:
        return desktop ? dp(320) : Math.round(screenW * 0.72f);
      case lg:
        return desktop ? dp(520) : Math.round(screenW * 0.92f);
      case iab_300x250:
        return desktop ? dp(300) : Math.min(dp(300), Math.round(screenW * 0.92f));
      default:
        return desktop ? dp(400) : Math.round(screenW * 0.84f);
    }
  }

  private int maxCardHeight() {
    return Math.round(screenH * 0.9f);
  }

  /** Shrinks a fixed-ratio card to fit the screen height (landscape phones). */
  private int[] fitRatio(int width, double ratio) {
    int maxHeight = maxCardHeight();
    int height = (int) Math.round(width / ratio);
    if (height <= maxHeight) {
      return new int[] {width, height};
    }
    return new int[] {(int) Math.round(maxHeight * ratio), maxHeight};
  }

  // ---- building -------------------------------------------------------------------------------

  private void build() {
    removeAllViews();
    switch (content.layout) {
      case modal:
        buildModal();
        break;
      case fullscreen:
        buildFullscreen();
        break;
      case bottomSheet:
        buildBottomSheet();
        break;
      case banner:
        buildBanner();
        break;
      case toast:
        buildToast();
        break;
      case imageOnly:
        buildImageOnly();
        break;
    }
  }

  private void addScrim() {
    View scrim = new View(getContext());
    scrim.setBackgroundColor(
        Color.argb(
            Math.round(255 * (float) content.theme.overlayOpacity), 0, 0, 0));
    // Clickable even when tap-outside is off, so a tap never reaches the page under the pop-up.
    scrim.setClickable(true);
    if (content.close.tapOutsideToClose) {
      scrim.setOnClickListener(v -> callbacks.onOutsideTap());
    }
    addView(scrim, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
  }

  private GradientDrawable cardBackground(float topRadiusDp, float bottomRadiusDp) {
    GradientDrawable bg = new GradientDrawable();
    bg.setColor(content.theme.background);
    float top = dp(topRadiusDp);
    float bottom = dp(bottomRadiusDp);
    bg.setCornerRadii(new float[] {top, top, top, top, bottom, bottom, bottom, bottom});
    return bg;
  }

  private GradientDrawable cardBackground(float radiusDp) {
    return cardBackground(radiusDp, radiusDp);
  }

  private FrameLayout newCard(float radiusDp, float elevationDp) {
    FrameLayout card = new MaxHeightFrameLayout(getContext(), maxCardHeight());
    card.setBackground(cardBackground(radiusDp));
    card.setClipToOutline(true);
    card.setElevation(dp(elevationDp));
    // The card takes its own touches, so a tap on it never falls through to the page.
    card.setClickable(true);
    return card;
  }

  private void buildModal() {
    boolean iab = content.size == PopupSize.iab_300x250;
    int width = cardWidth(content.size);
    FrameLayout card = newCard((float) content.theme.radius, 24);
    LayoutParams params;
    if (iab) {
      int[] fixed = fitRatio(width, 300.0 / 250.0);
      LinearLayout inner = new LinearLayout(getContext());
      inner.setOrientation(LinearLayout.VERTICAL);
      inner.setPadding(dp(16), dp(16), dp(16), dp(16));
      ScrollView scroll = new ScrollView(getContext());
      scroll.addView(textBlock());
      inner.addView(scroll, new LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f));
      View buttons = buttons(limit(content.buttons, 1), false);
      if (buttons != null) {
        inner.addView(buttons);
      }
      card.addView(inner, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
      params = new LayoutParams(fixed[0], fixed[1]);
    } else {
      LinearLayout column = new LinearLayout(getContext());
      column.setOrientation(LinearLayout.VERTICAL);
      if (content.image != null) {
        column.addView(
            imageView(false),
            new LinearLayout.LayoutParams(
                LayoutParams.MATCH_PARENT, dp(content.size == PopupSize.sm ? 96 : 144)));
      }
      LinearLayout body = new LinearLayout(getContext());
      body.setOrientation(LinearLayout.VERTICAL);
      body.setPadding(dp(20), dp(20), dp(20), dp(20));
      addTextAndButtons(body, content.buttons);
      column.addView(body);
      ScrollView scroll = new ScrollView(getContext());
      scroll.addView(column);
      card.addView(scroll, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT));
      params = new LayoutParams(width, LayoutParams.WRAP_CONTENT);
    }
    addScrim();
    addCloseButton(card, content.theme.isDarkBackground() || content.image != null, 0);
    params.gravity = Gravity.CENTER;
    addCard(card, params);
  }

  private void buildFullscreen() {
    boolean hasImage = content.image != null;
    FrameLayout card = new FrameLayout(getContext());
    card.setBackgroundColor(content.theme.background);
    card.setClickable(true);
    // The background runs under the bars; the content and the close button stay clear of them.
    card.setPadding(insetL, insetT, insetR, insetB);
    LinearLayout column = new LinearLayout(getContext());
    column.setOrientation(LinearLayout.VERTICAL);
    if (hasImage) {
      column.addView(
          imageView(false),
          new LinearLayout.LayoutParams(
              LayoutParams.MATCH_PARENT, Math.round(screenH * 0.52f)));
    }
    LinearLayout body = new LinearLayout(getContext());
    body.setOrientation(LinearLayout.VERTICAL);
    body.setPadding(dp(24), dp(24), dp(24), dp(24));
    addTextAndButtons(body, content.buttons);
    column.addView(body);
    ScrollView scroll = new ScrollView(getContext());
    scroll.setFillViewport(true);
    scroll.addView(column);
    card.addView(scroll, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
    addCloseButton(card, true, 0);
    addView(card, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
  }

  private void buildBottomSheet() {
    float fraction;
    switch (content.size) {
      case sm:
        fraction = 0.34f;
        break;
      case lg:
        fraction = 0.72f;
        break;
      default:
        fraction = 0.50f;
    }
    int height = Math.round(screenH * fraction) + insetB;
    float radius = (float) content.theme.radius;
    FrameLayout sheet = new FrameLayout(getContext());
    sheet.setBackground(cardBackground(radius, 0));
    sheet.setClipToOutline(true);
    sheet.setElevation(dp(16));
    sheet.setClickable(true);
    // The sheet runs under the navigation bar; its content stays above it.
    sheet.setPadding(0, 0, 0, insetB);

    LinearLayout column = new LinearLayout(getContext());
    column.setOrientation(LinearLayout.VERTICAL);
    View handle = new View(getContext());
    GradientDrawable handleBg = new GradientDrawable();
    handleBg.setColor(0xFFD1D5DB);
    handleBg.setCornerRadius(dp(2));
    handle.setBackground(handleBg);
    LinearLayout.LayoutParams handleParams = new LinearLayout.LayoutParams(dp(40), dp(4));
    handleParams.gravity = Gravity.CENTER_HORIZONTAL;
    handleParams.topMargin = dp(8);
    column.addView(handle, handleParams);
    if (content.image != null && content.size != PopupSize.sm) {
      LinearLayout.LayoutParams imageParams =
          new LinearLayout.LayoutParams(
              LayoutParams.MATCH_PARENT, Math.round(height * 0.38f));
      imageParams.setMargins(dp(16), dp(12), dp(16), 0);
      column.addView(imageView(false, dp(8)), imageParams);
    }
    LinearLayout body = new LinearLayout(getContext());
    body.setOrientation(LinearLayout.VERTICAL);
    body.setPadding(dp(20), dp(20), dp(20), dp(20));
    addTextAndButtons(body, content.buttons);
    column.addView(body);
    ScrollView scroll = new ScrollView(getContext());
    scroll.setFillViewport(true);
    scroll.addView(column);
    sheet.addView(scroll, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
    addCloseButton(sheet, content.theme.isDarkBackground(), 0);

    addScrim();
    LayoutParams params = new LayoutParams(LayoutParams.MATCH_PARENT, height);
    params.gravity = Gravity.BOTTOM;
    params.leftMargin = insetL;
    params.rightMargin = insetR;
    addView(sheet, params);
  }

  private void buildBanner() {
    boolean iab = content.size == PopupSize.iab_320x50;
    int width = iab ? Math.min(dp(320), screenW) : screenW;
    float radius = !desktop() && !iab ? 0f : Math.min((float) content.theme.radius, 8f);
    FrameLayout card = newCard(radius, 8);

    LinearLayout row = new LinearLayout(getContext());
    row.setOrientation(LinearLayout.HORIZONTAL);
    row.setGravity(Gravity.CENTER_VERTICAL);
    row.setPadding(dp(12), dp(iab ? 0 : 10), dp(12), dp(iab ? 0 : 10));
    if (content.image != null) {
      int side = dp(iab ? 32 : 40);
      LinearLayout.LayoutParams imageParams = new LinearLayout.LayoutParams(side, side);
      imageParams.setMarginEnd(dp(12));
      row.addView(imageView(false, dp(6)), imageParams);
    }
    LinearLayout text = new LinearLayout(getContext());
    text.setOrientation(LinearLayout.VERTICAL);
    if (hasTitle()) {
      text.addView(title(iab ? 12 : 14, true));
    }
    if (hasBody() && !iab) {
      text.addView(body(12, true));
    }
    row.addView(text, new LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f));
    // The action takes at most 45% of the banner, as in the Flutter renderer, so a long label is
    // cut short and never squeezes out the text or pushes the close target off the card.
    View buttons = buttons(content.buttons, true, Math.round(width * 0.45f));
    if (buttons != null) {
      LinearLayout.LayoutParams buttonParams =
          new LinearLayout.LayoutParams(
              LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT);
      buttonParams.setMarginStart(dp(12));
      row.addView(buttons, buttonParams);
    }
    if (content.close.show) {
      LinearLayout.LayoutParams closeParams =
          new LinearLayout.LayoutParams(dp(40), dp(40));
      closeParams.setMarginStart(dp(4));
      row.addView(inlineCloseButton(), closeParams);
    }
    card.addView(row, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT));

    int height = iab ? Math.round(width * 50f / 320f) : LayoutParams.WRAP_CONTENT;
    LayoutParams params = new LayoutParams(width, height);
    params.gravity =
        (content.position == PopupPosition.bottom ? Gravity.BOTTOM : Gravity.TOP)
            | Gravity.CENTER_HORIZONTAL;
    addCard(card, params);
  }

  private void buildToast() {
    boolean bottom = content.position == PopupPosition.bottomRight;
    int margin = dp(12);
    int width =
        desktop()
            ? dp(content.size == PopupSize.sm ? 280 : 340)
            : screenW - dp(24);
    boolean showImage = content.image != null && content.size == PopupSize.md;
    FrameLayout card = newCard(Math.min((float) content.theme.radius, 12f), 12);

    LinearLayout row = new LinearLayout(getContext());
    row.setOrientation(LinearLayout.HORIZONTAL);
    if (showImage) {
      row.addView(
          imageView(false),
          new LinearLayout.LayoutParams(dp(64), LayoutParams.MATCH_PARENT));
    }
    LinearLayout text = new LinearLayout(getContext());
    text.setOrientation(LinearLayout.VERTICAL);
    text.setPadding(dp(12), dp(12), dp(32), dp(12));
    if (hasTitle()) {
      text.addView(title(14, false));
    }
    if (hasBody()) {
      View body = body(12, false);
      body.setPadding(0, dp(hasTitle() ? 2 : 0), 0, 0);
      text.addView(body);
    }
    View buttons = buttons(content.buttons, true);
    if (buttons != null) {
      buttons.setPadding(0, dp(8), 0, 0);
      text.addView(buttons);
    }
    // The card is capped at 90% of the screen: a long body (a large font, a short landscape
    // window) must scroll, not push the action off the card where it can't be reached.
    ScrollView scroll = new ScrollView(getContext());
    scroll.addView(text);
    row.addView(scroll, new LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f));
    card.addView(row, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT));
    addCloseButton(card, content.theme.isDarkBackground(), 0);

    LayoutParams params = new LayoutParams(width, LayoutParams.WRAP_CONTENT);
    // Physical right, as the contract's topRight and bottomRight name it: Gravity.END would move the
    // toast to the left under an RTL layout.
    params.gravity = (bottom ? Gravity.BOTTOM : Gravity.TOP) | Gravity.RIGHT;
    params.setMargins(margin, margin, margin, margin);
    addCard(card, params);
  }

  private void buildImageOnly() {
    boolean iab = content.size == PopupSize.iab_300x250;
    int[] size = fitRatio(cardWidth(content.size), iab ? 300.0 / 250.0 : 4.0 / 5.0);
    FrameLayout card = newCard((float) content.theme.radius, 24);
    if (content.image != null) {
      card.addView(
          imageView(true), new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
    }
    addCloseButton(card, true, 0);
    addScrim();
    LayoutParams params = new LayoutParams(size[0], size[1]);
    params.gravity = Gravity.CENTER;
    addCard(card, params);
  }

  // ---- pieces ---------------------------------------------------------------------------------

  private static <T> java.util.List<T> limit(java.util.List<T> list, int max) {
    return list.size() <= max ? list : list.subList(0, max);
  }

  private boolean hasTitle() {
    return content.title != null && !content.title.isEmpty();
  }

  private boolean hasBody() {
    return content.body != null && !content.body.isEmpty();
  }

  private void addTextAndButtons(LinearLayout parent, java.util.List<PopupButton> buttons) {
    if (hasTitle() || hasBody()) {
      parent.addView(textBlock());
    }
    View row = buttons(buttons, false);
    if (row != null) {
      parent.addView(row);
    }
  }

  private View textBlock() {
    LinearLayout column = new LinearLayout(getContext());
    column.setOrientation(LinearLayout.VERTICAL);
    if (hasTitle()) {
      column.addView(title(16, false));
    }
    if (hasBody()) {
      View body = body(14, false);
      body.setPadding(0, dp(hasTitle() ? 6 : 0), 0, 0);
      column.addView(body);
    }
    return column;
  }

  private TextView title(float sp, boolean singleLine) {
    TextView title = new TextView(getContext());
    title.setText(content.title);
    title.setTextColor(content.theme.text);
    title.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
    title.setTypeface(title.getTypeface(), Typeface.BOLD);
    if (singleLine) {
      title.setMaxLines(1);
      title.setEllipsize(TextUtils.TruncateAt.END);
    }
    return title;
  }

  private TextView body(float sp, boolean singleLine) {
    TextView body = new TextView(getContext());
    body.setText(content.body);
    body.setTextColor(withAlpha(content.theme.text, 0.8f));
    body.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
    if (singleLine) {
      body.setMaxLines(1);
      body.setEllipsize(TextUtils.TruncateAt.END);
    }
    return body;
  }

  private static int withAlpha(int color, float factor) {
    int alpha = Math.round(Color.alpha(color) * factor);
    return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color));
  }

  /** Stacked full width for a card, or a compact row for a banner or toast. Null with none. */
  private View buttons(java.util.List<PopupButton> list, boolean compact) {
    return buttons(list, compact, 0);
  }

  /** As above; a positive [maxWidth] caps how wide the row of buttons can get. */
  private View buttons(java.util.List<PopupButton> list, boolean compact, int maxWidth) {
    if (list.isEmpty()) {
      return null;
    }
    LinearLayout container =
        maxWidth > 0 ? new MaxWidthLinearLayout(getContext(), maxWidth) : new LinearLayout(getContext());
    container.setOrientation(compact ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
    if (!compact) {
      container.setPadding(0, dp(16), 0, 0);
    }
    for (int i = 0; i < list.size(); i++) {
      int index = content.buttons.indexOf(list.get(i));
      LinearLayout.LayoutParams lp =
          compact
              ? new LinearLayout.LayoutParams(
                  LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
              : new LinearLayout.LayoutParams(
                  LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT);
      if (i > 0) {
        if (compact) {
          lp.setMarginStart(dp(8));
        } else {
          lp.topMargin = dp(8);
        }
      }
      container.addView(buttonView(list.get(i), index, compact), lp);
    }
    return container;
  }

  private TextView buttonView(PopupButton button, int index, boolean compact) {
    boolean primary = button.style == PopupButtonStyle.primary;
    TextView view = new TextView(getContext());
    view.setText(button.label.isEmpty() ? "Button" : button.label);
    view.setTextSize(TypedValue.COMPLEX_UNIT_SP, compact ? 12 : 14);
    view.setTypeface(view.getTypeface(), Typeface.BOLD);
    view.setGravity(Gravity.CENTER);
    view.setMaxLines(1);
    view.setEllipsize(TextUtils.TruncateAt.END);
    view.setPadding(dp(compact ? 12 : 16), dp(compact ? 6 : 10), dp(compact ? 12 : 16), dp(compact ? 6 : 10));
    GradientDrawable bg = new GradientDrawable();
    bg.setCornerRadius(dp(8));
    if (primary) {
      bg.setColor(content.theme.primary);
      view.setTextColor(0xFFFFFFFF);
    } else {
      bg.setStroke(dp(1), withAlpha(content.theme.text, 0x33 / 255f));
      view.setTextColor(content.theme.text);
    }
    view.setBackground(bg);
    view.setClickable(true);
    view.setOnClickListener(v -> callbacks.onButton(index));
    return view;
  }

  /** Fills the area it is given; a faint wash of the text colour until the bitmap arrives. */
  private View imageView(boolean tappable) {
    return imageView(tappable, 0);
  }

  private View imageView(boolean tappable, int cornerRadiusPx) {
    PopupImage image = content.image;
    if (image == null) {
      return new View(getContext());
    }
    ImageView view = new ImageView(getContext());
    view.setScaleType(ImageView.ScaleType.CENTER_CROP);
    if (cornerRadiusPx > 0) {
      GradientDrawable mask = new GradientDrawable();
      mask.setCornerRadius(cornerRadiusPx);
      view.setClipToOutline(true);
      view.setBackground(mask);
    }
    if (image.isGradient()) {
      GradientDrawable gradient =
          new GradientDrawable(GradientDrawable.Orientation.TL_BR, image.gradientColors());
      gradient.setCornerRadius(cornerRadiusPx);
      view.setBackground(gradient);
    } else {
      view.setBackgroundColor(withAlpha(content.theme.text, 0.08f));
      android.graphics.Bitmap bitmap = images != null ? images.getCached(image.url) : null;
      if (bitmap != null) {
        view.setImageBitmap(bitmap);
      } else if (images != null) {
        images.loadAsync(
            image.url,
            loaded -> {
              if (loaded != null) {
                view.setImageBitmap(loaded);
              }
            });
      }
    }
    if (tappable || image.tapAction != null) {
      view.setClickable(true);
      view.setOnClickListener(v -> callbacks.onImageTap());
    }
    view.setContentDescription(image.alt);
    return view;
  }

  /** The reference's CloseButton: a 24 dp circle 8 dp in from the corner, in a 40 dp tap target. */
  private void addCloseButton(FrameLayout card, boolean dark, int topMarginPx) {
    PopupClose close = content.close;
    if (!close.show) {
      return;
    }
    FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(dp(40), dp(40));
    // Physical sides: the contract's topLeft and topRight do not swap under an RTL layout.
    lp.gravity =
        close.position == PopupClosePosition.topLeft
            ? (Gravity.TOP | Gravity.LEFT)
            : (Gravity.TOP | Gravity.RIGHT);
    lp.topMargin = topMarginPx;
    card.addView(closeTarget(dark), lp);
  }

  private View closeTarget(boolean dark) {
    FrameLayout target = new FrameLayout(getContext());
    target.setClickable(true);
    target.setContentDescription("Close");
    target.setOnClickListener(v -> callbacks.onClose());
    TextView glyph = new TextView(getContext());
    glyph.setText("\u2715");
    glyph.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
    glyph.setGravity(Gravity.CENTER);
    glyph.setTextColor(dark ? 0xFFFFFFFF : 0xFF374151);
    GradientDrawable bg = new GradientDrawable();
    bg.setShape(GradientDrawable.OVAL);
    bg.setColor(dark ? 0x66000000 : 0xCCFFFFFF);
    glyph.setBackground(bg);
    FrameLayout.LayoutParams glyphParams = new FrameLayout.LayoutParams(dp(24), dp(24));
    glyphParams.gravity = Gravity.CENTER;
    target.addView(glyph, glyphParams);
    return target;
  }

  /** A banner's close button sits in its row, in the text colour, with no circle. */
  private View inlineCloseButton() {
    FrameLayout target = new FrameLayout(getContext());
    target.setClickable(true);
    target.setContentDescription("Close");
    target.setOnClickListener(v -> callbacks.onClose());
    TextView glyph = new TextView(getContext());
    glyph.setText("\u2715");
    glyph.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
    glyph.setGravity(Gravity.CENTER);
    glyph.setTextColor(withAlpha(content.theme.text, 0.7f));
    target.addView(
        glyph, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
    return target;
  }

  /** A row that sizes to its content, up to {@code maxWidth}. */
  private static final class MaxWidthLinearLayout extends LinearLayout {
    private final int maxWidth;

    MaxWidthLinearLayout(Context context, int maxWidth) {
      super(context);
      this.maxWidth = maxWidth;
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
      int mode = MeasureSpec.getMode(widthMeasureSpec);
      int size = MeasureSpec.getSize(widthMeasureSpec);
      if (mode == MeasureSpec.UNSPECIFIED) {
        widthMeasureSpec = MeasureSpec.makeMeasureSpec(maxWidth, MeasureSpec.AT_MOST);
      } else if (size > maxWidth) {
        widthMeasureSpec = MeasureSpec.makeMeasureSpec(maxWidth, MeasureSpec.AT_MOST);
      }
      super.onMeasure(widthMeasureSpec, heightMeasureSpec);
    }
  }

  /** A card that sizes to its content, up to {@code maxHeight}, then scrolls inside. */
  private static final class MaxHeightFrameLayout extends FrameLayout {
    private final int maxHeight;

    MaxHeightFrameLayout(Context context, int maxHeight) {
      super(context);
      this.maxHeight = maxHeight;
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
      int mode = MeasureSpec.getMode(heightMeasureSpec);
      if (mode == MeasureSpec.UNSPECIFIED || mode == MeasureSpec.AT_MOST) {
        int size = MeasureSpec.getSize(heightMeasureSpec);
        int cap = mode == MeasureSpec.AT_MOST && size > 0 ? Math.min(size, maxHeight) : maxHeight;
        heightMeasureSpec = MeasureSpec.makeMeasureSpec(cap, MeasureSpec.AT_MOST);
      }
      super.onMeasure(widthMeasureSpec, heightMeasureSpec);
    }
  }
}
