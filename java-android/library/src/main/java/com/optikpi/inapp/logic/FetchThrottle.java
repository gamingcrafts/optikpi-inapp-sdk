package com.optikpi.inapp.logic;

import java.time.Duration;

/**
 * Decides when the next fetch is allowed. Times are monotonic milliseconds (on Android,
 * {@code SystemClock.elapsedRealtime()}), not wall-clock instants: if the user or the network
 * moves the device clock back, a wall-clock gap stays negative until the clock catches up and
 * would hold fetching off far beyond the 24-hour maximum.
 */
public final class FetchThrottle {
  public static final Duration DEFAULT_INTERVAL = Duration.ofSeconds(300);
  public static final int MIN_INTERVAL_SEC = 30;
  public static final int MAX_INTERVAL_SEC = 24 * 60 * 60;

  private Long lastResponseAtMs;
  private Duration interval = DEFAULT_INTERVAL;

  public Duration getInterval() {
    return interval;
  }

  public boolean canFetch(long nowMs) {
    return lastResponseAtMs == null || nowMs - lastResponseAtMs >= interval.toMillis();
  }

  public void recordResponse(long atMs, Integer nextCheckAfterSec) {
    lastResponseAtMs = atMs;
    if (nextCheckAfterSec == null) {
      interval = DEFAULT_INTERVAL;
    } else {
      int clamped = Math.max(MIN_INTERVAL_SEC, Math.min(MAX_INTERVAL_SEC, nextCheckAfterSec));
      interval = Duration.ofSeconds(clamped);
    }
  }
}
