package com.optikpi.inapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import com.optikpi.inapp.events.EventQueue;
import com.optikpi.inapp.events.PopupEvent;
import com.optikpi.inapp.events.PopupEventType;
import com.optikpi.inapp.model.PopupFetchResult;
import com.optikpi.inapp.source.PopupRequestContext;
import com.optikpi.inapp.source.PopupSource;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

@RunWith(RobolectricTestRunner.class)
public class EventQueueTest {
  private final Context context = RuntimeEnvironment.getApplication();

  private static PopupEvent impression(String trackingId) {
    return new PopupEvent(
        trackingId, PopupEventType.impression, Instant.parse("2026-10-28T09:20:01Z"), null);
  }

  private static PopupRequestContext player(String workspaceId, String playerId) {
    return new PopupRequestContext(
        "https://inapp.test", workspaceId, playerId, "key", "token");
  }

  private static final class RecordingSource extends PopupSource {
    final List<PopupEvent> sent = new ArrayList<>();

    @Override
    public PopupFetchResult fetch(PopupRequestContext context) {
      throw new UnsupportedOperationException();
    }

    @Override
    public void sendEvents(PopupRequestContext context, List<PopupEvent> events) {
      sent.addAll(events);
    }
  }

  @Test
  public void overflowDropsTheOldestEventsAndKeepsTheOrder() throws Exception {
    EventQueue queue = new EventQueue(context, 50);
    for (int i = 0; i < EventQueue.MAX_QUEUED + 5; i++) {
      assertTrue(queue.enqueue(impression("trk-" + i), "ws", "p1"));
    }
    assertEquals(EventQueue.MAX_QUEUED, queue.length());

    RecordingSource source = new RecordingSource();
    queue.flush(source, player("ws", "p1"));

    assertEquals(EventQueue.MAX_QUEUED, source.sent.size());
    // The five oldest are the ones that went, and what is left is still in the order it came in.
    for (int i = 0; i < source.sent.size(); i++) {
      assertEquals("trk-" + (i + 5), source.sent.get(i).trackingId);
    }
    assertEquals(0, queue.length());
  }

  @Test
  public void aTrackingIdAndTypeIsQueuedOnce() {
    EventQueue queue = new EventQueue(context, 50);
    assertTrue(queue.enqueue(impression("trk-1"), "ws", "p1"));
    assertFalse(queue.enqueue(impression("trk-1"), "ws", "p1"));
    assertEquals(1, queue.length());
  }

  @Test
  public void anotherPlayersEventsWaitForThatPlayer() throws Exception {
    EventQueue queue = new EventQueue(context, 50);
    queue.enqueue(impression("mine"), "ws", "p1");
    queue.enqueue(impression("theirs"), "ws", "p2");

    RecordingSource source = new RecordingSource();
    queue.flush(source, player("ws", "p1"));

    assertEquals(1, source.sent.size());
    assertEquals("mine", source.sent.get(0).trackingId);
    assertEquals(1, queue.length());
  }

  @Test
  public void sendsInBatches() throws Exception {
    EventQueue queue = new EventQueue(context, 2);
    for (int i = 0; i < 5; i++) {
      queue.enqueue(impression("trk-" + i), "ws", "p1");
    }
    final List<Integer> batchSizes = new ArrayList<>();
    PopupSource source =
        new PopupSource() {
          @Override
          public PopupFetchResult fetch(PopupRequestContext context) {
            throw new UnsupportedOperationException();
          }

          @Override
          public void sendEvents(PopupRequestContext context, List<PopupEvent> events) {
            batchSizes.add(events.size());
          }
        };
    queue.flush(source, player("ws", "p1"));
    assertEquals(List.of(2, 2, 1), batchSizes);
  }

  @Test
  public void stopsBetweenBatchesWhenNoLongerEligible() throws Exception {
    EventQueue queue = new EventQueue(context, 2);
    for (int i = 0; i < 6; i++) {
      queue.enqueue(impression("trk-" + i), "ws", "p1");
    }
    RecordingSource source = new RecordingSource();
    int[] asked = {0};
    // Eligible for the first batch only, as when the app goes to the background mid-flush.
    queue.flush(source, player("ws", "p1"), () -> asked[0]++ < 1);

    assertEquals(2, source.sent.size());
    assertEquals(4, queue.length());

    // The rest goes at the next eligible flush.
    queue.flush(source, player("ws", "p1"));
    assertEquals(6, source.sent.size());
    assertEquals(0, queue.length());
  }

  @Test
  public void anEventIsQueuedWhileAFlushIsWaitingOnTheNetwork() throws Exception {
    EventQueue queue = new EventQueue(context, 50);
    queue.enqueue(impression("first"), "ws", "p1");
    java.util.concurrent.CountDownLatch inRequest = new java.util.concurrent.CountDownLatch(1);
    java.util.concurrent.CountDownLatch release = new java.util.concurrent.CountDownLatch(1);
    PopupSource slow =
        new PopupSource() {
          @Override
          public PopupFetchResult fetch(PopupRequestContext context) {
            throw new UnsupportedOperationException();
          }

          @Override
          public void sendEvents(PopupRequestContext context, List<PopupEvent> events)
              throws Exception {
            inRequest.countDown();
            release.await(10, java.util.concurrent.TimeUnit.SECONDS);
          }
        };
    Thread flusher =
        new Thread(
            () -> {
              try {
                queue.flush(slow, player("ws", "p1"));
              } catch (Exception ignored) {
              }
            });
    flusher.start();
    assertTrue(inRequest.await(10, java.util.concurrent.TimeUnit.SECONDS));

    // The request is out: an impression recorded now must not wait for it.
    java.util.concurrent.atomic.AtomicBoolean queued =
        new java.util.concurrent.atomic.AtomicBoolean();
    Thread recorder =
        new Thread(() -> queued.set(queue.enqueue(impression("second"), "ws", "p1")));
    recorder.start();
    recorder.join(5000);
    boolean finishedWhileInFlight = !recorder.isAlive();
    release.countDown();
    flusher.join(10000);
    recorder.join(5000);

    assertTrue("enqueue waited behind the in-flight request", finishedWhileInFlight);
    assertTrue(queued.get());
    // "first" went with the request; "second" arrived meanwhile and must still be queued.
    assertEquals(1, queue.length());
  }
}
