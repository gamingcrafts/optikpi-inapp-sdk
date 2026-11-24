package com.optikpi.inapp.source;

public final class PopupHttpException extends Exception {
  public final int statusCode;
  public final String path;

  public PopupHttpException(int statusCode, String path) {
    super("HTTP " + statusCode + " from " + path);
    this.statusCode = statusCode;
    this.path = path;
  }

  public boolean isAuthFailure() {
    return statusCode == 401 || statusCode == 403;
  }
}