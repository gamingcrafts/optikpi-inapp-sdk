package com.optikpi.inapp.model;

import static com.optikpi.inapp.model.JsonHelpers.map;
import static com.optikpi.inapp.model.JsonHelpers.string;
import static com.optikpi.inapp.model.PopupEnums.PopupDeliveryUnit;

import org.json.JSONObject;

public final class PopupDelivery {
  public final Number value;
  public final PopupDeliveryUnit unit;
  public final String customEndsAt;
  public final String timeZone;

  public PopupDelivery(
      Number value, PopupDeliveryUnit unit, String customEndsAt, String timeZone) {
    this.value = value;
    this.unit = unit;
    this.customEndsAt = customEndsAt;
    this.timeZone = timeZone;
  }

  public static PopupDelivery tryParse(Object json) {
    JSONObject map = map(json);
    if (map == null) {
      return null;
    }
    JSONObject availableFor = map(map.opt("availableFor"));
    Object value = availableFor != null ? availableFor.opt("value") : null;
    PopupDeliveryUnit unit =
        availableFor != null
            ? PopupEnums.enumByName(PopupDeliveryUnit.class, availableFor.opt("unit"))
            : null;
    if (!(value instanceof Number) || unit == null) {
      return null;
    }
    return new PopupDelivery(
        (Number) value, unit, string(map.opt("customEndsAt")), string(map.opt("timeZone")));
  }
}