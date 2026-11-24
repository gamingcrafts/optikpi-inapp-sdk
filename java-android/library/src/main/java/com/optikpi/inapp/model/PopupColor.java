package com.optikpi.inapp.model;

import android.graphics.Color;

public final class PopupColor {
  private PopupColor() {}

  /** `#RGB`, `#RRGGBB` or `#RRGGBBAA` (CSS order). Anything else is null. */
  public static Integer parse(Object value) {
    if (!(value instanceof String)) {
      return null;
    }
    String hex = ((String) value).trim();
    if (!hex.startsWith("#")) {
      return null;
    }
    hex = hex.substring(1);
    if (!hex.matches("[0-9a-fA-F]+")) {
      return null;
    }
    if (hex.length() == 3) {
      StringBuilder expanded = new StringBuilder();
      for (char c : hex.toCharArray()) {
        expanded.append(c).append(c);
      }
      hex = expanded.toString();
    }
    if (hex.length() == 6) {
      return Color.parseColor("#FF" + hex);
    }
    if (hex.length() == 8) {
      String alpha = hex.substring(6, 8);
      String rgb = hex.substring(0, 6);
      return Color.parseColor("#" + alpha + rgb);
    }
    return null;
  }

  public static boolean isDarkBackground(int backgroundArgb) {
    int r = Color.red(backgroundArgb);
    int g = Color.green(backgroundArgb);
    int b = Color.blue(backgroundArgb);
    return r * 0.299 + g * 0.587 + b * 0.114 < 140;
  }
}