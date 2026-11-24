package com.optikpi.inapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.os.Looper;
import android.util.Base64;
import androidx.activity.ComponentActivity;
import com.optikpi.inapp.events.PopupEvent;
import com.optikpi.inapp.events.PopupEventType;
import com.optikpi.inapp.model.InAppPopup;
import com.optikpi.inapp.model.PopupContent;
import com.optikpi.inapp.model.PopupFetchResult;
import com.optikpi.inapp.source.PopupHttpException;
import com.optikpi.inapp.source.PopupRequestContext;
import com.optikpi.inapp.source.PopupSource;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.JSONObject;
import org.junit.After;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.shadows.ShadowSystemClock;

@RunWith(RobolectricTestRunner.class)
public class ControllerConcurrencyTest {
  private static String jwt(String workspaceId, String playerId, String nonce) {
    String header =
        Base64.encodeToString(
            "{\"alg\":\"HS256\"}".getBytes(StandardCharsets.UTF_8),
            Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
    String payloadJson =
        "{\"wid\":\""
            + workspaceId
            + "\",\"sub\":\""
            + playerId
            + "\",\"jti\":\""
            + nonce
            + "\"}";
    String payload =
        Base64.encodeToString(
            payloadJson.getBytes(StandardCharsets.UTF_8),
            Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
    return header + "." + payload + ".sig";
  }

  private static InAppPopup popup(String id) throws Exception {
    PopupContent content =
        PopupContent.tryParse(
            new JSONObject()
                .put("version", 1)
                .put("layout", "modal")
                .put("size", "md")
                .put("title", "Hello " + id));
    return new InAppPopup(id, "trk-" + id, "cmp-" + id, Instant.now(), null, content);
  }

  private static ExecutorService executor(OptikpiInAppController controller, String name)
      throws Exception {
    Field f = OptikpiInAppController.class.getDeclaredField(name);
    f.setAccessible(true);
    return (ExecutorService) f.get(controller);
  }

  /** Lets every background thread the controller owns (work, flush, storage) finish what it has. */
  private static void drainAll(OptikpiInAppController controller) throws Exception {
    ExecutorService[] pools = {
      executor(controller, "workers"),
      executor(controller, "flusher"),
      executor(controller, "storage")
    };
    for (int i = 0; i < 5; i++) {
      shadowOf(Looper.getMainLooper()).idle();
      for (ExecutorService pool : pools) {
        Future<?> barrier = pool.submit(() -> {});
        barrier.get(5, TimeUnit.SECONDS);
      }
      shadowOf(Looper.getMainLooper()).idle();
    }
  }

  /**
   * Advances the Robolectric main looper until {@code latch} counts down on the worker thread,
   * without queuing a task behind a worker that is waiting on a test barrier.
   */
  private static void awaitWithMainIdle(CountDownLatch latch) throws Exception {
    long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
    shadowOf(Looper.getMainLooper()).idle();
    while (!latch.await(5, TimeUnit.MILLISECONDS)) {
      shadowOf(Looper.getMainLooper()).idle();
      if (System.nanoTime() > deadline) {
        throw new AssertionError("Timed out waiting for worker task");
      }
    }
  }

  @After
  public void cleanUp() throws Exception {
    OptikpiInAppController controller =
        OptikpiInAppController.getInstance(RuntimeEnvironment.getApplication());
    controller.logout();
    drainAll(controller);
  }

  @Test
  public void backgroundInitSerializesWithPopupPublicationAcrossPlayerSwitch() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);

    InAppPopup playerAPopup = popup("player-a-only");
    CountDownLatch playerAFetched = new CountDownLatch(1);
    PopupSource source =
        new PopupSource() {
          @Override
          public PopupFetchResult fetch(PopupRequestContext context) {
            if ("player-a".equals(context.playerId)) {
              playerAFetched.countDown();
              return new PopupFetchResult(List.of(playerAPopup), 300);
            }
            return new PopupFetchResult(Collections.emptyList(), 300);
          }

          @Override
          public void sendEvents(PopupRequestContext context, List<PopupEvent> events) {}
        };

    // Start Player A on the main thread, pause main looper so publish() sits queued on main,
    // then switch to Player B from a background login thread before draining main.
    OptikpiInApp.init(
        activity,
        "api-key",
        jwt("ws", "player-a", "1"),
        "https://inapp.test",
        null,
        null,
        Collections.emptyList(),
        source);
    awaitWithMainIdle(playerAFetched);
    // Wait for maybeShow on the worker thread to enqueue publish(sessionA, ...) onto main.
    executor(controller, "workers").submit(() -> {}).get(5, TimeUnit.SECONDS);

    // Background login callback switches to Player B while Player A's publish() is pending.
    Thread loginThread =
        new Thread(
            () ->
                OptikpiInApp.init(
                    activity,
                    "api-key",
                    jwt("ws", "player-b", "2"),
                    "https://inapp.test",
                    null,
                    null,
                    Collections.emptyList(),
                    source));
    loginThread.start();
    loginThread.join(5_000);

    drainAll(controller);

    // Player B has no pop-ups: Player A's campaign must never survive into Player B's session.
    assertNull(controller.getCurrent());
  }

  @Test
  public void authFailureRacingSamePlayerTokenRefreshNeverLeavesFreshTokenPaused()
      throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);

    for (int round = 0; round < 20; round++) {
      String staleToken = jwt("ws", "player-1", "stale-" + round);
      String freshToken = jwt("ws", "player-1", "fresh-" + round);
      InAppPopup freshPopup = popup("fresh-popup-" + round);
      CyclicBarrier raceBarrier = new CyclicBarrier(2);
      CountDownLatch staleEntered = new CountDownLatch(1);
      List<String> fetchedTokens = new CopyOnWriteArrayList<>();

      PopupSource source =
          new PopupSource() {
            @Override
            public PopupFetchResult fetch(PopupRequestContext context) throws PopupHttpException {
              fetchedTokens.add(context.playerToken);
              if (staleToken.equals(context.playerToken)) {
                staleEntered.countDown();
                try {
                  raceBarrier.await(5, TimeUnit.SECONDS);
                } catch (Exception ignored) {
                }
                throw new PopupHttpException(401, "token expired");
              }
              return new PopupFetchResult(List.of(freshPopup), 30);
            }

            @Override
            public void sendEvents(PopupRequestContext context, List<PopupEvent> events) {}
          };

      OptikpiInApp.init(
          activity,
          "api-key",
          staleToken,
          "https://inapp.test",
          null,
          null,
          Collections.emptyList(),
          source);
      awaitWithMainIdle(staleEntered);

      // Release the worker's 401 and refresh the token on the main thread at the same instant.
      raceBarrier.await(5, TimeUnit.SECONDS);
      OptikpiInApp.setPlayerToken(activity, freshToken);

      drainAll(controller);

      assertTrue(
          "fresh token fetched in round " + round, fetchedTokens.contains(freshToken));
      assertNotNull("fresh popup published in round " + round, controller.getCurrent());
      assertEquals(freshPopup.id, controller.getCurrent().popup.id);
      controller.close(controller.getCurrent(), false);
      drainAll(controller);
    }
  }

  @Test
  public void flushAuthFailureRacingTokenRefreshStillFlushesWithFreshToken() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);

    Field eventsField = OptikpiInAppController.class.getDeclaredField("events");
    eventsField.setAccessible(true);
    com.optikpi.inapp.events.EventQueue queue =
        (com.optikpi.inapp.events.EventQueue) eventsField.get(controller);

    for (int round = 0; round < 15; round++) {
      String staleToken = jwt("ws", "player-2", "stale-flush-" + round);
      String freshToken = jwt("ws", "player-2", "fresh-flush-" + round);
      queue.enqueue(
          new PopupEvent("trk-flush-" + round, PopupEventType.impression, Instant.now(), null),
          "ws",
          "player-2");

      CyclicBarrier raceBarrier = new CyclicBarrier(2);
      CountDownLatch staleFlushEntered = new CountDownLatch(1);
      List<String> flushedWithTokens = new CopyOnWriteArrayList<>();

      PopupSource source =
          new PopupSource() {
            @Override
            public PopupFetchResult fetch(PopupRequestContext context) {
              return new PopupFetchResult(Collections.emptyList(), 300);
            }

            @Override
            public void sendEvents(PopupRequestContext context, List<PopupEvent> events)
                throws PopupHttpException {
              if (staleToken.equals(context.playerToken)) {
                staleFlushEntered.countDown();
                try {
                  raceBarrier.await(5, TimeUnit.SECONDS);
                } catch (Exception ignored) {
                }
                throw new PopupHttpException(403, "refused");
              }
              flushedWithTokens.add(context.playerToken);
            }
          };

      OptikpiInApp.init(
          activity,
          "api-key",
          staleToken,
          "https://inapp.test",
          null,
          null,
          Collections.emptyList(),
          source);
      awaitWithMainIdle(staleFlushEntered);

      raceBarrier.await(5, TimeUnit.SECONDS);
      OptikpiInApp.setPlayerToken(activity, freshToken);

      drainAll(controller);

      assertTrue(
          "events flushed with fresh token in round " + round,
          flushedWithTokens.contains(freshToken));
      assertEquals(0, queue.length());
    }
  }

  @Test
  public void drawConsumptionRacingFetchPreservesNewlyFetchedPopups() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);

    for (int round = 0; round < 20; round++) {
      String token1 = jwt("ws", "player-3-" + round, "t1");
      String token2 = jwt("ws", "player-3-" + round, "t2");
      InAppPopup firstPopup = popup("first-" + round);
      InAppPopup newlyDelivered = popup("newly-delivered-" + round);
      AtomicInteger calls = new AtomicInteger();
      CountDownLatch secondFetchEntered = new CountDownLatch(1);
      CyclicBarrier raceBarrier = new CyclicBarrier(2);

      PopupSource source =
          new PopupSource() {
            @Override
            public PopupFetchResult fetch(PopupRequestContext context) {
              if (calls.incrementAndGet() == 1) {
                return new PopupFetchResult(List.of(firstPopup), 30);
              }
              secondFetchEntered.countDown();
              try {
                raceBarrier.await(5, TimeUnit.SECONDS);
              } catch (Exception ignored) {
              }
              // 24-hour throttle: if consume() overwrites this list, no third fetch can rescue it.
              return new PopupFetchResult(List.of(newlyDelivered, firstPopup), 86_400);
            }

            @Override
            public void sendEvents(PopupRequestContext context, List<PopupEvent> events) {}
          };

      OptikpiInApp.didChangeRoute(activity, "/home-" + round);
      OptikpiInApp.init(
          activity,
          "api-key",
          token1,
          "https://inapp.test",
          null,
          null,
          Collections.emptyList(),
          source);
      drainAll(controller);

      ActivePopup activeFirst = controller.getCurrent();
      assertNotNull(activeFirst);
      assertEquals(firstPopup.id, activeFirst.popup.id);

      // Allow a second fetch while firstPopup is still awaiting its first draw.
      ShadowSystemClock.advanceBy(Duration.ofSeconds(31));
      OptikpiInApp.setPlayerToken(activity, token2);
      awaitWithMainIdle(secondFetchEntered);

      // Race second fetch's waiting-list installation against firstPopup's didDraw consumption.
      raceBarrier.await(5, TimeUnit.SECONDS);
      controller.didDraw(activeFirst);

      drainAll(controller);
      controller.close(activeFirst, true);
      OptikpiInApp.didChangeRoute(activity, "/lobby-" + round);
      drainAll(controller);

      assertEquals("no third fetch allowed under 24h throttle", 2, calls.get());
      assertNotNull("newly delivered popup preserved in round " + round, controller.getCurrent());
      assertEquals(newlyDelivered.id, controller.getCurrent().popup.id);
      controller.close(controller.getCurrent(), false);
      drainAll(controller);
    }
  }

  @Test
  public void aPopupFetchedWhileTheAppIsAwayShowsWhenItComesBack() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    CountDownLatch fetchEntered = new CountDownLatch(1);
    CountDownLatch release = new CountDownLatch(1);
    InAppPopup waiting = popup("away-1");
    PopupSource source =
        new PopupSource() {
          @Override
          public PopupFetchResult fetch(PopupRequestContext context) {
            fetchEntered.countDown();
            try {
              release.await(5, TimeUnit.SECONDS);
            } catch (InterruptedException ignored) {
            }
            return new PopupFetchResult(List.of(waiting), 300);
          }

          @Override
          public void sendEvents(PopupRequestContext context, List<PopupEvent> events) {}
        };

    OptikpiInApp.init(
        activity,
        "api-key",
        jwt("ws", "player-away", "t"),
        "https://inapp.test",
        null,
        null,
        Collections.emptyList(),
        source);
    awaitWithMainIdle(fetchEntered);

    // The activity stops while the GET is in flight.
    controller.setForeground(false);
    shadowOf(Looper.getMainLooper()).idle();
    release.countDown();
    drainAll(controller);
    assertNull("nothing is shown to an app that is away", controller.getCurrent());

    controller.setForeground(true);
    drainAll(controller);
    assertNotNull("it is shown when the app returns", controller.getCurrent());
    assertEquals(waiting.id, controller.getCurrent().popup.id);
  }

  @Test
  public void aPopupThatExpiredWhileItsImageLoadedIsNotPublished() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    PopupSource empty =
        new PopupSource() {
          @Override
          public PopupFetchResult fetch(PopupRequestContext context) {
            return new PopupFetchResult(Collections.emptyList(), 300);
          }

          @Override
          public void sendEvents(PopupRequestContext context, List<PopupEvent> events) {}
        };
    OptikpiInApp.init(
        activity,
        "api-key",
        jwt("ws", "player-expiry", "t"),
        "https://inapp.test",
        null,
        null,
        Collections.emptyList(),
        empty);
    drainAll(controller);
    assertNull(controller.getCurrent());

    PopupContent content = popup("expired-1").content;
    InAppPopup expired =
        new InAppPopup(
            "expired-1",
            "trk-expired-1",
            null,
            Instant.now().minusSeconds(60),
            Instant.now().minusSeconds(1),
            content);
    Field sessionField = OptikpiInAppController.class.getDeclaredField("session");
    sessionField.setAccessible(true);
    Field visitField = OptikpiInAppController.class.getDeclaredField("visit");
    visitField.setAccessible(true);
    Object session = sessionField.get(controller);
    int visit = visitField.getInt(controller);
    java.lang.reflect.Method publish =
        OptikpiInAppController.class.getDeclaredMethod(
            "publish", session.getClass(), InAppPopup.class, int.class);
    publish.setAccessible(true);
    publish.invoke(controller, session, expired, visit);
    shadowOf(Looper.getMainLooper()).idle();

    assertNull("an expired popup must not reach the screen", controller.getCurrent());
  }

  @Test
  public void aCarriedPopupKeepsTheNewScreensVisitSpent() throws Exception {
    ComponentActivity activity =
        Robolectric.buildActivity(ComponentActivity.class).create().start().resume().get();
    OptikpiInAppController controller = OptikpiInAppController.getInstance(activity);
    InAppPopup first = popup("carried-1");
    InAppPopup second = popup("carried-2");
    PopupSource source =
        new PopupSource() {
          @Override
          public PopupFetchResult fetch(PopupRequestContext context) {
            return new PopupFetchResult(List.of(first, second), 300);
          }

          @Override
          public void sendEvents(PopupRequestContext context, List<PopupEvent> events) {}
        };
    OptikpiInApp.init(
        activity,
        "api-key",
        jwt("ws", "player-carried", "t"),
        "https://inapp.test",
        null,
        null,
        Collections.emptyList(),
        source);
    drainAll(controller);
    ActivePopup active = controller.getCurrent();
    assertNotNull(active);
    controller.didDraw(active);
    drainAll(controller);

    // The drawn pop-up is still up when the user moves to a screen that is not blocked.
    controller.didChangeRoute("/screen-b");
    drainAll(controller);
    assertEquals(active, controller.getCurrent());

    // Closing it, then leaving and returning to the app on that screen, must not bring a second.
    controller.close(active, true);
    drainAll(controller);
    controller.setForeground(false);
    drainAll(controller);
    controller.setForeground(true);
    drainAll(controller);
    assertNull("one pop-up per screen visit", controller.getCurrent());
  }
}
