package com.optikpi.inapp.model;

import static com.optikpi.inapp.model.JsonHelpers.map;
import static com.optikpi.inapp.model.JsonHelpers.string;
import static com.optikpi.inapp.model.PopupEnums.PopupActionType;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;

public final class PopupAction {
  public final PopupActionType type;
  public final String value;
  public final Map<String, String> customData;

  public PopupAction(PopupActionType type, String value, Map<String, String> customData) {
    this.type = type;
    this.value = value;
    this.customData = customData == null ? null : Collections.unmodifiableMap(customData);
  }

  private static Map<String, String> customData(Object json) {
    Map<String, String> data = new LinkedHashMap<>();
    if (!(json instanceof JSONArray array)) {
      return data;
    }
    for (int i = 0; i < array.length(); i++) {
      JSONObject entry = map(array.opt(i));
      if (entry == null) {
        continue;
      }
      String key = string(entry.opt("key"));
      String val = string(entry.opt("value"));
      if (key != null) {
        key = key.trim();
      }
      if (key != null && !key.isEmpty() && val != null) {
        data.put(key, val);
      }
    }
    return data;
  }

  public static PopupAction tryParse(Object json) {
    JSONObject map = map(json);
    if (map == null) {
      return null;
    }
    PopupActionType type = PopupEnums.enumByName(PopupActionType.class, map.opt("type"));
    if (type == null) {
      return null;
    }
    if (type == PopupActionType.custom) {
      Map<String, String> data = customData(map.opt("customData"));
      if (data.isEmpty()) {
        return new PopupAction(PopupActionType.dismiss, null, null);
      }
      return new PopupAction(type, null, data);
    }
    String value = string(map.opt("value"));
    if (value != null) {
      value = value.trim();
    }
    if (type != PopupActionType.dismiss && (value == null || value.isEmpty())) {
      return new PopupAction(PopupActionType.dismiss, null, null);
    }
    return new PopupAction(type, type == PopupActionType.dismiss ? null : value, null);
  }
}