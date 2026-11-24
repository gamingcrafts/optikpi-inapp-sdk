package com.optikpi.inapp.model;

import static com.optikpi.inapp.model.JsonHelpers.list;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

public final class PopupFetchResult {
  public final List<InAppPopup> popups;
  public final Integer nextCheckAfterSec;

  public PopupFetchResult(List<InAppPopup> popups, Integer nextCheckAfterSec) {
    this.popups = popups;
    this.nextCheckAfterSec = nextCheckAfterSec;
  }

  public static PopupFetchResult fromJson(Object json) {
    JSONArray popupList = new JSONArray();
    Object next = null;
    if (json instanceof JSONObject map) {
      Object raw = map.opt("popups");
      if (raw instanceof JSONArray arr) {
        popupList = arr;
      }
      next = map.opt("nextCheckAfterSec");
    }
    List<InAppPopup> popups = new ArrayList<>();
    for (int i = 0; i < popupList.length(); i++) {
      InAppPopup popup = InAppPopup.tryParse(popupList.opt(i));
      if (popup != null) {
        popups.add(popup);
      }
    }
    Integer nextCheck = null;
    if (next instanceof Number n && Double.isFinite(n.doubleValue())) {
      // Clamp before narrowing: a cast of a huge long wraps to a negative, which the throttle
      // would read as "poll every 30 s" instead of "wait the maximum".
      nextCheck =
          (int) Math.max(Integer.MIN_VALUE, Math.min(Integer.MAX_VALUE, Math.round(n.doubleValue())));
    }
    return new PopupFetchResult(Collections.unmodifiableList(popups), nextCheck);
  }
}