package com.optikpi.inapp.model;

import static com.optikpi.inapp.model.JsonHelpers.map;
import static com.optikpi.inapp.model.JsonHelpers.string;

import android.graphics.Color;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONObject;

public final class PopupImage {
  public final String url;
  public final String alt;
  public final PopupAction tapAction;

  public PopupImage(String url, String alt, PopupAction tapAction) {
    this.url = url;
    this.alt = alt;
    this.tapAction = tapAction;
  }

  public static PopupImage tryParse(Object json) {
    JSONObject map = map(json);
    if (map == null) {
      return null;
    }
    String url = string(map.opt("url"));
    if (url != null) {
      url = url.trim();
    }
    if (url == null || url.isEmpty()) {
      return null;
    }
    return new PopupImage(url, string(map.opt("alt")), PopupAction.tryParse(map.opt("tapAction")));
  }

  public boolean isGradient() {
    return url.startsWith("gradient:");
  }

  public int[] gradientColors() {
    String rest = url.substring("gradient:".length());
    String[] parts = rest.split(",");
    int fallback = Color.parseColor("#FF98A2B3");
    Integer from = parts.length > 0 ? PopupColor.parse(parts[0]) : null;
    Integer to = parts.length > 1 ? PopupColor.parse(parts[1]) : null;
    if (from == null) {
      from = fallback;
    }
    if (to == null) {
      to = from;
    }
    return new int[] {from, to};
  }
}