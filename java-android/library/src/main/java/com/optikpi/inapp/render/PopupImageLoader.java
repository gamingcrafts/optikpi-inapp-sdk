package com.optikpi.inapp.render;

import android.graphics.Bitmap;
import android.content.res.Resources;
import android.graphics.BitmapFactory;
import android.util.DisplayMetrics;
import android.os.Handler;
import android.os.Looper;
import com.optikpi.inapp.InAppLog;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.ResponseBody;
import okio.BufferedSource;

/** Loads a pop-up's image over HTTP(S) into a small bounded in-memory cache. */
public final class PopupImageLoader {
  private static final long TIMEOUT_SEC = 8;

  public interface Listener {
    /** Called on the main thread. {@code bitmap} is null when the image can't be loaded. */
    void onLoaded(Bitmap bitmap);
  }

  private final OkHttpClient client;
  private final ExecutorService executor = Executors.newCachedThreadPool();
  private final Handler main = new Handler(Looper.getMainLooper());
  private final Map<String, Future<Bitmap>> inFlight = new ConcurrentHashMap<>();
  private final BoundedBitmapCache cache = new BoundedBitmapCache();

  public PopupImageLoader() {
    client = new OkHttpClient.Builder().callTimeout(TIMEOUT_SEC, TimeUnit.SECONDS).build();
  }

  /** The most bytes of image we will download, however large the server says it is. */
  public static final long MAX_DOWNLOAD_BYTES = 5L * 1024 * 1024;

  /**
   * The body's bytes, or null when it is longer than {@link #MAX_DOWNLOAD_BYTES}: a server can
   * send any length (or none, chunked), so the limit is on what is read, not only on the header.
   */
  static byte[] readBounded(ResponseBody body) throws java.io.IOException {
    long declared = body.contentLength();
    if (declared > MAX_DOWNLOAD_BYTES) {
      return null;
    }
    BufferedSource source = body.source();
    if (source.request(MAX_DOWNLOAD_BYTES + 1)) {
      return null;
    }
    return source.readByteArray();
  }

  /** No image is drawn bigger than the screen, so nothing needs more pixels than that. */
  private static int maxDimensionPx() {
    DisplayMetrics metrics = Resources.getSystem().getDisplayMetrics();
    return Math.max(1, Math.max(metrics.widthPixels, metrics.heightPixels));
  }

  /**
   * Decodes [bytes] at the largest power-of-two reduction that still has no side longer than
   * [maxDimension]. The size is read first, so a huge image is never decoded in full.
   */
  static Bitmap decodeScaled(byte[] bytes, int maxDimension) {
    BitmapFactory.Options bounds = new BitmapFactory.Options();
    bounds.inJustDecodeBounds = true;
    BitmapFactory.decodeByteArray(bytes, 0, bytes.length, bounds);
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
      return null;
    }
    int sample = 1;
    while (bounds.outWidth / sample > maxDimension || bounds.outHeight / sample > maxDimension) {
      sample *= 2;
    }
    BitmapFactory.Options options = new BitmapFactory.Options();
    options.inSampleSize = sample;
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
  }

  public Bitmap getCached(String url) {
    return cache.get(url);
  }

  /** Null for a {@code gradient:} url, which is drawn and never loaded. */
  public Future<Bitmap> load(String url) {
    if (url.startsWith("gradient:")) {
      return null;
    }
    Bitmap cached = cache.get(url);
    if (cached != null) {
      return executor.submit(() -> cached);
    }
    return inFlight.computeIfAbsent(
        url,
        key ->
            executor.submit(
                () -> {
                  try {
                    Request request = new Request.Builder().url(url).get().build();
                    try (var response = client.newCall(request).execute()) {
                      if (!response.isSuccessful() || response.body() == null) {
                        return null;
                      }
                      byte[] bytes = readBounded(response.body());
                      if (bytes == null) {
                        InAppLog.log("image too large, skipped: " + url);
                        return null;
                      }
                      Bitmap bitmap = decodeScaled(bytes, maxDimensionPx());
                      if (bitmap != null) {
                        cache.put(url, bitmap);
                      }
                      return bitmap;
                    }
                  } catch (Exception | OutOfMemoryError e) {
                    InAppLog.log("image load failed: " + url);
                    return null;
                  } finally {
                    inFlight.remove(url);
                  }
                }));
  }

  /** Loads [url] and reports on the main thread, for a view drawn before its image arrived. */
  public void loadAsync(String url, Listener listener) {
    Future<Bitmap> future = load(url);
    if (future == null) {
      return;
    }
    executor.execute(
        () -> {
          Bitmap bitmap = null;
          try {
            bitmap = future.get(TIMEOUT_SEC, TimeUnit.SECONDS);
          } catch (Exception e) {
            InAppLog.log("image still loading after " + TIMEOUT_SEC + " s: " + url);
          }
          Bitmap result = bitmap;
          main.post(() -> listener.onLoaded(result));
        });
  }

  public Bitmap awaitLoad(String url, long timeoutMs) {
    Future<Bitmap> future = load(url);
    if (future == null) {
      return null;
    }
    try {
      return future.get(timeoutMs, TimeUnit.MILLISECONDS);
    } catch (Exception e) {
      InAppLog.log("image still loading after " + (timeoutMs / 1000) + " s: " + url);
      return null;
    }
  }
}
