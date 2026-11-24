package com.optikpi.inapp.model;

import static com.optikpi.inapp.model.JsonHelpers.map;
import static com.optikpi.inapp.model.PopupEnums.PopupClosePosition;

import org.json.JSONObject;

public final class PopupClose {
  public final boolean show;
  public final PopupClosePosition position;
  public final boolean tapOutsideToClose;

  public PopupClose(boolean show, PopupClosePosition position, boolean tapOutsideToClose) {
    this.show = show;
    this.position = position;
    this.tapOutsideToClose = tapOutsideToClose;
  }

  public static PopupClose parse(Object json) {
    JSONObject map = map(json);
    if (map == null) {
      return new PopupClose(true, PopupClosePosition.topRight, true);
    }
    Object showValue = map.opt("show");
    boolean show = showValue instanceof Boolean ? (Boolean) showValue : true;
    PopupClosePosition position =
        PopupEnums.enumByName(PopupClosePosition.class, map.opt("position"));
    if (position == null) {
      position = PopupClosePosition.topRight;
    }
    // Only a real boolean counts: null or another type falls back to the default (true).
    Object tapOutsideValue = map.opt("tapOutsideToClose");
    boolean tapOutside = tapOutsideValue instanceof Boolean ? (Boolean) tapOutsideValue : true;
    return new PopupClose(show, position, tapOutside);
  }
}