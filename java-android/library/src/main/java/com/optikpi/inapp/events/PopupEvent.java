package com.optikpi.inapp.events;

import java.time.Instant;
import java.time.format.DateTimeParseException;
import org.json.JSONObject;

public final class PopupEvent {
  public final String trackingId;
  public final PopupEventType type;
  public final Instant at;
  public final Integer buttonIndex;

  public PopupEvent(String trackingId, PopupEventType type, Instant at, Integer buttonIndex) {
    this.trackingId = trackingId;
    this.type = type;
    this.at = at;
    this.buttonIndex = buttonIndex;
  }

  public String getDedupeKey() {
    return trackingId + "|" + type.name();
  }

  public JSONObject toJson() {
    JSONObject json = new JSONObject();
    try {
      json.put("trackingId", trackingId);
      json.put("type", type.name());
      json.put("at", at.toString());
      if (buttonIndex != null) {
        json.put("buttonIndex", buttonIndex);
      }
    } catch (Exception ignored) {
    }
    return json;
  }

  public static PopupEvent tryParse(Object json) {
    if (!(json instanceof JSONObject jsonObject)) {
      return null;
    }
    String trackingId =
        jsonObject.opt("trackingId") instanceof String s ? s : null;
    String atRaw = jsonObject.opt("at") instanceof String s ? s : null;
    PopupEventType type = null;
    for (PopupEventType candidate : PopupEventType.values()) {
      if (candidate.name().equals(jsonObject.optString("type"))) {
        type = candidate;
        break;
      }
    }
    Instant at = null;
    if (atRaw != null) {
      try {
        at = Instant.parse(atRaw);
      } catch (DateTimeParseException ignored) {
      }
    }
    if (trackingId == null || at == null || type == null) {
      return null;
    }
    Integer buttonIndex =
        jsonObject.has("buttonIndex") ? jsonObject.optInt("buttonIndex") : null;
    return new PopupEvent(trackingId, type, at, buttonIndex);
  }
}