package com.optikpi.inapp.source;

import static org.junit.Assert.assertEquals;

import com.optikpi.inapp.model.PopupFetchResult;
import org.json.JSONException;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class HttpPopupSourceTest {
  @Test
  public void aNullBodyIsAnEmptyResultNotAFailure() throws Exception {
    PopupFetchResult result = HttpPopupSource.parseBody("null");
    assertEquals(0, result.popups.size());
    assertEquals(null, result.nextCheckAfterSec);
  }

  @Test
  public void aBodyThatIsNotAnObjectIsAnEmptyResult() throws Exception {
    assertEquals(0, HttpPopupSource.parseBody("[]").popups.size());
    assertEquals(0, HttpPopupSource.parseBody("\"x\"").popups.size());
  }

  @Test
  public void anObjectBodyIsParsed() throws Exception {
    PopupFetchResult result =
        HttpPopupSource.parseBody(
            "{\"popups\":[{\"id\":\"a\",\"trackingId\":\"t\",\"content\":{\"layout\":\"toast\"}}],"
                + "\"nextCheckAfterSec\":60}");
    assertEquals(1, result.popups.size());
    assertEquals(Integer.valueOf(60), result.nextCheckAfterSec);
  }

  @Test(expected = JSONException.class)
  public void textThatIsNotJsonStillFails() throws Exception {
    HttpPopupSource.parseBody("<html>");
  }

  @Test(expected = JSONException.class)
  public void anObjectFollowedByJunkStillFails() throws Exception {
    HttpPopupSource.parseBody("{} junk");
  }

  @Test
  public void everyRequestHasAnOverallDeadline() {
    assertEquals(
        HttpPopupSource.CALL_TIMEOUT_SEC * 1000,
        HttpPopupSource.defaultClient().callTimeoutMillis());
  }

  @Test(timeout = 20_000)
  public void aResponseThatKeepsTricklingIsStoppedByTheCallDeadline() throws Exception {
    java.net.ServerSocket server = new java.net.ServerSocket(0);
    Thread trickle =
        new Thread(
            () -> {
              try (java.net.Socket socket = server.accept()) {
                java.io.InputStream in = socket.getInputStream();
                // Read the request head, then answer slowly: one byte every 300 ms, far inside any
                // per-read timeout, for much longer than the call deadline below.
                byte[] buffer = new byte[4096];
                in.read(buffer);
                java.io.OutputStream out = socket.getOutputStream();
                out.write("HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n".getBytes());
                out.flush();
                for (int i = 0; i < 100; i++) {
                  out.write('x');
                  out.flush();
                  Thread.sleep(300);
                }
              } catch (Exception ignored) {
              }
            });
    trickle.setDaemon(true);
    trickle.start();

    okhttp3.OkHttpClient client =
        HttpPopupSource.defaultClient().newBuilder()
            .callTimeout(2, java.util.concurrent.TimeUnit.SECONDS)
            .build();
    HttpPopupSource source = new HttpPopupSource(client);
    long start = System.nanoTime();
    try {
      source.fetch(
          new PopupRequestContext(
              "http://127.0.0.1:" + server.getLocalPort(), "ws", "p1", "key", "token"));
      org.junit.Assert.fail("a response that never finishes must not be waited for");
    } catch (java.io.IOException expected) {
      // The call deadline fired.
    } finally {
      server.close();
    }
    long seconds = java.util.concurrent.TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - start);
    org.junit.Assert.assertTrue("stopped after " + seconds + " s", seconds < 10);
  }
}
