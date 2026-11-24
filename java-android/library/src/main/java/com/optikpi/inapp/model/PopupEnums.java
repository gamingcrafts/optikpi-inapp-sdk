package com.optikpi.inapp.model;

public final class PopupEnums {
  private PopupEnums() {}

  public enum PopupLayout {
    modal,
    fullscreen,
    bottomSheet,
    banner,
    toast,
    imageOnly
  }

  public enum PopupSize {
    sm,
    md,
    lg,
    iab_300x250,
    iab_320x50
  }

  public enum PopupPosition {
    top,
    bottom,
    center,
    topRight,
    bottomRight
  }

  public enum PopupActionType {
    deeplink,
    url,
    dismiss,
    custom
  }

  public enum PopupButtonStyle {
    primary,
    secondary
  }

  public enum PopupClosePosition {
    topRight,
    topLeft
  }

  public enum PopupDeliveryUnit {
    hours,
    days
  }

  public static <T extends Enum<T>> T enumByName(Class<T> type, Object name) {
    if (!(name instanceof String)) {
      return null;
    }
    try {
      return Enum.valueOf(type, (String) name);
    } catch (IllegalArgumentException e) {
      return null;
    }
  }
}