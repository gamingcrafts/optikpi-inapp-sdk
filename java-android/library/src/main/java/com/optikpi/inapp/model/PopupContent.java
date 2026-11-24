package com.optikpi.inapp.model;

import static com.optikpi.inapp.model.JsonHelpers.list;
import static com.optikpi.inapp.model.JsonHelpers.map;
import static com.optikpi.inapp.model.JsonHelpers.string;
import static com.optikpi.inapp.model.PopupEnums.PopupLayout;
import static com.optikpi.inapp.model.PopupEnums.PopupPosition;
import static com.optikpi.inapp.model.PopupEnums.PopupSize;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

public final class PopupContent {
  public final int version;
  public final PopupLayout layout;
  public final PopupSize size;
  public final PopupPosition position;
  public final PopupImage image;
  public final String title;
  public final String body;
  public final List<PopupButton> buttons;
  public final PopupClose close;
  public final PopupTheme theme;
  public final Integer autoDismissSec;
  public final List<String> mergeTags;
  public final PopupDelivery delivery;

  public PopupContent(
      int version,
      PopupLayout layout,
      PopupSize size,
      PopupPosition position,
      PopupImage image,
      String title,
      String body,
      List<PopupButton> buttons,
      PopupClose close,
      PopupTheme theme,
      Integer autoDismissSec,
      List<String> mergeTags,
      PopupDelivery delivery) {
    this.version = version;
    this.layout = layout;
    this.size = size;
    this.position = position;
    this.image = image;
    this.title = title;
    this.body = body;
    this.buttons = buttons;
    this.close = close;
    this.theme = theme;
    this.autoDismissSec = autoDismissSec;
    this.mergeTags = mergeTags;
    this.delivery = delivery;
  }

  public PopupLayoutSpec getSpec() {
    return PopupLayoutSpec.ALL.get(layout);
  }

  public static PopupContent tryParse(Object json) {
    JSONObject map = map(json);
    if (map == null) {
      return null;
    }
    if (map.has("version")) {
      Object versionRaw = map.opt("version");
      if (!isExactlyOne(versionRaw)) {
        return null;
      }
    }
    PopupLayout layout = PopupEnums.enumByName(PopupLayout.class, map.opt("layout"));
    if (layout == null) {
      return null;
    }
    PopupLayoutSpec spec = PopupLayoutSpec.ALL.get(layout);
    PopupSize size = PopupEnums.enumByName(PopupSize.class, map.opt("size"));
    PopupPosition position = PopupEnums.enumByName(PopupPosition.class, map.opt("position"));

    List<PopupButton> buttons = new ArrayList<>();
    JSONArray buttonList = list(map.opt("buttons"));
    if (buttonList != null) {
      for (int i = 0; i < buttonList.length() && buttons.size() < spec.maxButtons; i++) {
        PopupButton button = PopupButton.tryParse(buttonList.opt(i), i);
        if (button != null) {
          buttons.add(button);
        }
      }
    }
    buttons = Collections.unmodifiableList(buttons);

    Integer autoDismissSec = null;
    if (spec.autoDismiss) {
      Object autoDismiss = map.opt("autoDismissSec");
      if (autoDismiss instanceof Number n && Double.isFinite(n.doubleValue()) && n.doubleValue() > 0) {
        autoDismissSec = (int) Math.ceil(n.doubleValue());
      }
    }

    List<String> mergeTags = null;
    Object mergeRaw = map.opt("mergeTags");
    if (mergeRaw instanceof JSONArray arr) {
      List<String> tags = new ArrayList<>();
      for (int i = 0; i < arr.length(); i++) {
        Object item = arr.opt(i);
        if (item instanceof String s) {
          tags.add(s);
        }
      }
      mergeTags = Collections.unmodifiableList(tags);
    }

    PopupSize resolvedSize =
        size != null && spec.sizes.contains(size) ? size : spec.sizes.get(0);
    PopupPosition resolvedPosition = null;
    if (spec.positions != null) {
      if (position != null && spec.positions.contains(position)) {
        resolvedPosition = position;
      } else {
        resolvedPosition = spec.positions.get(0);
      }
    }

    return new PopupContent(
        1,
        layout,
        resolvedSize,
        resolvedPosition,
        PopupImage.tryParse(map.opt("image")),
        spec.hasText ? string(map.opt("title")) : null,
        spec.hasText ? string(map.opt("body")) : null,
        buttons,
        PopupClose.parse(map.opt("close")),
        PopupTheme.parse(map.opt("theme")),
        autoDismissSec,
        mergeTags,
        PopupDelivery.tryParse(map.opt("delivery")));
  }

  /**
   * True only for a number that is exactly 1, compared in its own type: {@code intValue()} would
   * turn 1.5 or 4294967297 into 1, and narrowing a {@link BigDecimal} to a double would turn
   * 1.0000000000000001 into 1.0. (A parser that has already rounded the literal to a double
   * cannot be told apart, as in the JS and Dart SDKs.)
   */
  static boolean isExactlyOne(Object value) {
    if (value instanceof BigDecimal d) {
      return d.compareTo(BigDecimal.ONE) == 0;
    }
    if (value instanceof BigInteger i) {
      return i.equals(BigInteger.ONE);
    }
    if (value instanceof Double || value instanceof Float) {
      return ((Number) value).doubleValue() == 1.0;
    }
    if (value instanceof Long || value instanceof Integer || value instanceof Short
        || value instanceof Byte) {
      return ((Number) value).longValue() == 1L;
    }
    return false;
  }

  /**
   * Whether the selected layout and size draw {@link #image}. The renderer leaves it out of a
   * modal at {@code iab_300x250}, a bottom sheet at {@code sm} and a toast below {@code md}, so
   * nothing should wait for it there.
   */
  public boolean drawsImage() {
    if (image == null) {
      return false;
    }
    switch (layout) {
      case modal:
        return size != PopupSize.iab_300x250;
      case bottomSheet:
        return size != PopupSize.sm;
      case toast:
        return size == PopupSize.md;
      default:
        return true; // fullscreen, banner and imageOnly always draw it
    }
  }
}
