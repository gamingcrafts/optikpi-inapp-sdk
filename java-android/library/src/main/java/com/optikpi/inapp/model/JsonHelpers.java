package com.optikpi.inapp.model;

import org.json.JSONArray;
import org.json.JSONObject;

final class JsonHelpers {
  private JsonHelpers() {}

  static String string(Object value) {
    return value instanceof String ? (String) value : null;
  }

  static JSONObject map(Object value) {
    return value instanceof JSONObject ? (JSONObject) value : null;
  }

  static JSONArray list(Object value) {
    return value instanceof JSONArray ? (JSONArray) value : null;
  }
}