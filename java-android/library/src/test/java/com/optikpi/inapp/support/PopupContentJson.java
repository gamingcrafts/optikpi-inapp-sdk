package com.optikpi.inapp.support;

import com.optikpi.inapp.model.PopupAction;
import com.optikpi.inapp.model.PopupButton;
import com.optikpi.inapp.model.PopupContent;
import org.json.JSONArray;
import org.json.JSONObject;

/** Writes parsed PopupContent to JSON for fixture comparison (subset of Flutter toJson). */
public final class PopupContentJson {
  private PopupContentJson() {}

  public static JSONObject toJson(PopupContent content) throws Exception {
    JSONObject json = new JSONObject();
    json.put("version", content.version);
    json.put("layout", content.layout.name());
    json.put("size", content.size.name());
    if (content.position != null) {
      json.put("position", content.position.name());
    }
    if (content.image != null) {
      JSONObject image = new JSONObject();
      image.put("url", content.image.url);
      if (content.image.alt != null) {
        image.put("alt", content.image.alt);
      }
      if (content.image.tapAction != null) {
        actionJson(content.image.tapAction, image, "tapAction");
      }
      json.put("image", image);
    }
    if (content.title != null) {
      json.put("title", content.title);
    }
    if (content.body != null) {
      json.put("body", content.body);
    }
    JSONArray buttons = new JSONArray();
    for (PopupButton button : content.buttons) {
      JSONObject b = new JSONObject();
      b.put("label", button.label);
      b.put("style", button.style.name());
      actionJson(button.action, b, "action");
      buttons.put(b);
    }
    json.put("buttons", buttons);
    JSONObject close = new JSONObject();
    close.put("show", content.close.show);
    close.put("position", content.close.position.name());
    close.put("tapOutsideToClose", content.close.tapOutsideToClose);
    json.put("close", close);
    JSONObject theme = new JSONObject();
    theme.put("background", colorHex(content.theme.background));
    theme.put("text", colorHex(content.theme.text));
    theme.put("primary", colorHex(content.theme.primary));
    theme.put("overlayOpacity", content.theme.overlayOpacity);
    theme.put("radius", content.theme.radius);
    json.put("theme", theme);
    if (content.autoDismissSec != null) {
      json.put("autoDismissSec", content.autoDismissSec);
    } else if (content.getSpec().autoDismiss) {
      json.put("autoDismissSec", JSONObject.NULL);
    }
    if (content.delivery != null) {
      JSONObject delivery = new JSONObject();
      JSONObject availableFor = new JSONObject();
      availableFor.put("value", content.delivery.value);
      availableFor.put("unit", content.delivery.unit.name());
      delivery.put("availableFor", availableFor);
      if (content.delivery.customEndsAt != null) {
        delivery.put("customEndsAt", content.delivery.customEndsAt);
      }
      if (content.delivery.timeZone != null) {
        delivery.put("timeZone", content.delivery.timeZone);
      }
      json.put("delivery", delivery);
    }
    if (content.getSpec().positions != null) {
      json.put("position", content.position != null ? content.position.name() : JSONObject.NULL);
    }
    return json;
  }

  private static void actionJson(PopupAction action, JSONObject parent, String key)
      throws Exception {
    JSONObject json = new JSONObject();
    json.put("type", action.type.name());
    if (action.value != null) {
      json.put("value", action.value);
    }
    if (action.customData != null) {
      JSONArray pairs = new JSONArray();
      for (var entry : action.customData.entrySet()) {
        JSONObject pair = new JSONObject();
        pair.put("key", entry.getKey());
        pair.put("value", entry.getValue());
        pairs.put(pair);
      }
      json.put("customData", pairs);
    }
    parent.put(key, json);
  }

  private static String colorHex(int argb) {
    int rgb = argb & 0xFFFFFF;
    int alpha = (argb >>> 24) & 0xFF;
    String hex = String.format("#%06X", rgb);
    if (alpha == 0xFF) {
      return hex;
    }
    return hex + String.format("%02X", alpha);
  }
}