package com.optikpi.inapp.source;

import com.optikpi.inapp.events.PopupEvent;
import com.optikpi.inapp.model.PopupFetchResult;
import java.util.List;

public abstract class PopupSource {
  public boolean needsPlayerToken() {
    return true;
  }

  public abstract PopupFetchResult fetch(PopupRequestContext context) throws Exception;

  public abstract void sendEvents(PopupRequestContext context, List<PopupEvent> events)
      throws Exception;
}