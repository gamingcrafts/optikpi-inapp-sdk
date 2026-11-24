package com.optikpi.inapp.model;

import static com.optikpi.inapp.model.JsonHelpers.map;
import static com.optikpi.inapp.model.JsonHelpers.string;
import static com.optikpi.inapp.model.PopupEnums.PopupButtonStyle;

import org.json.JSONObject;

public final class PopupButton {
  public final String label;
  public final PopupButtonStyle style;
  public final PopupAction action;

  /**
   * Where this button sat in the delivered {@code content.buttons}. Buttons with an unsupported
   * action are dropped before rendering, so the position in the rendered list can differ; click
   * events report this one (API.md: {@code buttonIndex} indexes the delivered array).
   */
  public final int sourceIndex;

  public PopupButton(String label, PopupButtonStyle style, PopupAction action, int sourceIndex) {
    this.sourceIndex = sourceIndex;
    this.label = label;
    this.style = style;
    this.action = action;
  }

  public static PopupButton tryParse(Object json, int sourceIndex) {
    JSONObject map = map(json);
    if (map == null) {
      return null;
    }
    PopupAction action = PopupAction.tryParse(map.opt("action"));
    if (action == null) {
      return null;
    }
    String label = string(map.opt("label"));
    if (label == null) {
      label = "";
    }
    PopupButtonStyle style =
        PopupEnums.enumByName(PopupButtonStyle.class, map.opt("style"));
    if (style == null) {
      style = PopupButtonStyle.primary;
    }
    return new PopupButton(label, style, action, sourceIndex);
  }
}