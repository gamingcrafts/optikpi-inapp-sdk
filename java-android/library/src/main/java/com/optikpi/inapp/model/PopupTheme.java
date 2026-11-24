package com.optikpi.inapp.model;

import static com.optikpi.inapp.model.JsonHelpers.map;

import android.graphics.Color;
import org.json.JSONObject;

public final class PopupTheme {
  public static final int DEFAULT_BACKGROUND = Color.parseColor("#FFFFFFFF");
  public static final int DEFAULT_TEXT = Color.parseColor("#FF101828");
  public static final int DEFAULT_PRIMARY = Color.parseColor("#FF7F56D9");

  public final int background;
  public final int text;
  public final int primary;
  public final double overlayOpacity;
  public final double radius;

  public PopupTheme(int background, int text, int primary, double overlayOpacity, double radius) {
    this.background = background;
    this.text = text;
    this.primary = primary;
    this.overlayOpacity = overlayOpacity;
    this.radius = radius;
  }

  public static PopupTheme defaults() {
    return new PopupTheme(DEFAULT_BACKGROUND, DEFAULT_TEXT, DEFAULT_PRIMARY, 0.5, 16);
  }

  public static PopupTheme parse(Object json) {
    PopupTheme fallback = defaults();
    JSONObject map = map(json);
    if (map == null) {
      return fallback;
    }
    Integer background = PopupColor.parse(map.opt("background"));
    Integer text = PopupColor.parse(map.opt("text"));
    Integer primary = PopupColor.parse(map.opt("primary"));
    double opacity = fallback.overlayOpacity;
    Object opacityRaw = map.opt("overlayOpacity");
    if (opacityRaw instanceof Number n && Double.isFinite(n.doubleValue())) {
      opacity = Math.max(0, Math.min(1, n.doubleValue()));
    }
    double radius = fallback.radius;
    Object radiusRaw = map.opt("radius");
    if (radiusRaw instanceof Number n && Double.isFinite(n.doubleValue()) && n.doubleValue() >= 0) {
      radius = n.doubleValue();
    }
    return new PopupTheme(
        background != null ? background : fallback.background,
        text != null ? text : fallback.text,
        primary != null ? primary : fallback.primary,
        opacity,
        radius);
  }

  public boolean isDarkBackground() {
    return PopupColor.isDarkBackground(background);
  }
}