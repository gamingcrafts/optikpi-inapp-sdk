package com.optikpi.inapp;

import com.optikpi.inapp.model.InAppPopup;
import com.optikpi.inapp.model.PopupContent;
import com.optikpi.inapp.source.PopupRequestContext;

/**
 * The pop-up on screen. The handlers an action calls are the controller's, not copies kept here, so
 * they can be rebound while it is showing.
 */
public final class ActivePopup {
  public final InAppPopup popup;
  public final PopupRequestContext context;
  public final boolean isTest;

  /** Set when the first frame is reported, so a second attached activity doesn't report it again. */
  boolean drawn;

  /** The scheduled auto-dismiss, kept so it can be cancelled when this stops being current. */
  Runnable autoDismissTask;

  ActivePopup(
      InAppPopup popup,
      PopupRequestContext context,
      boolean isTest) {
    this.popup = popup;
    this.context = context;
    this.isTest = isTest;
  }

  public PopupContent getContent() {
    return popup.content;
  }

  public interface DeepLinkHandler {
    void onDeepLink(String link);
  }

  public interface CustomActionHandler {
    void onCustomAction(java.util.Map<String, String> data);
  }
}