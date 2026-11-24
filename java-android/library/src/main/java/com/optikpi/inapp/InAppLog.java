package com.optikpi.inapp;

import android.util.Log;

public final class InAppLog {
  private static volatile boolean debug;

  private InAppLog() {}

  public static boolean isDebug() {
    return debug;
  }

  public static void setDebug(boolean value) {
    debug = value;
  }

  public static void log(String message) {
    if (debug) {
      Log.d("OptikpiInApp", message);
    }
  }
}