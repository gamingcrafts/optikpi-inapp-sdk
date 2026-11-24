package com.optikpi.inapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import com.optikpi.inapp.logic.FetchThrottle;
import org.junit.Test;

public class FetchThrottleTest {
  @Test
  public void allowsTheFirstFetchThenWaitsTheInterval() {
    FetchThrottle throttle = new FetchThrottle();
    assertTrue(throttle.canFetch(1_000));
    throttle.recordResponse(1_000, 60);
    assertFalse(throttle.canFetch(1_000 + 59_999));
    assertTrue(throttle.canFetch(1_000 + 60_000));
  }

  @Test
  public void clampsTheIntervalToTheContractBounds() {
    FetchThrottle throttle = new FetchThrottle();
    throttle.recordResponse(0, 1);
    assertEquals(FetchThrottle.MIN_INTERVAL_SEC, throttle.getInterval().getSeconds());
    throttle.recordResponse(0, Integer.MAX_VALUE);
    assertEquals(FetchThrottle.MAX_INTERVAL_SEC, throttle.getInterval().getSeconds());
    throttle.recordResponse(0, null);
    assertEquals(300, throttle.getInterval().getSeconds());
  }

  @Test
  public void aMonotonicClockCannotRunBackwardsIntoALongWait() {
    // The wall clock being set back a day must not cost a day: the throttle only sees elapsed time,
    // which keeps counting from the response.
    FetchThrottle throttle = new FetchThrottle();
    throttle.recordResponse(10_000, 300);
    assertTrue(throttle.canFetch(10_000 + 300_000));
  }
}
