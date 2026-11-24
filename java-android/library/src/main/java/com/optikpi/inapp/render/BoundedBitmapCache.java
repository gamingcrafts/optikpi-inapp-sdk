package com.optikpi.inapp.render;

import android.graphics.Bitmap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * A small least-recently-used cache of decoded images. Each pop-up is shown once per device, so a
 * big cache would rarely be hit again; the bound keeps a long-lived process from holding every
 * campaign image it ever drew (the Flutter package keeps eight, so does this). An image that is
 * over the byte budget by itself is the exception: it is kept as the only entry until the next
 * image arrives, so a preloaded creative is still there when the pop-up draws it.
 */
public final class BoundedBitmapCache {
  public static final int DEFAULT_MAX_ENTRIES = 8;

  /** A count alone doesn't bound memory: eight big bitmaps are a lot. */
  public static final long DEFAULT_MAX_BYTES = 32L * 1024 * 1024;

  private final int maxEntries;
  private final long maxBytes;
  private long bytes;
  private final LinkedHashMap<String, Bitmap> entries = new LinkedHashMap<>(16, 0.75f, true);

  public BoundedBitmapCache() {
    this(DEFAULT_MAX_ENTRIES, DEFAULT_MAX_BYTES);
  }

  public BoundedBitmapCache(int maxEntries) {
    this(maxEntries, DEFAULT_MAX_BYTES);
  }

  public BoundedBitmapCache(int maxEntries, long maxBytes) {
    this.maxEntries = Math.max(1, maxEntries);
    this.maxBytes = Math.max(1, maxBytes);
  }

  public synchronized Bitmap get(String url) {
    return entries.get(url);
  }

  public synchronized void put(String url, Bitmap bitmap) {
    Bitmap previous = entries.remove(url);
    if (previous != null) {
      bytes -= previous.getAllocationByteCount();
    }
    long size = bitmap.getAllocationByteCount();
    if (size > maxBytes) {
      // Over the budget on its own, but it was loaded to be drawn: refusing it would send the
      // renderer to download and decode the same image again. It is kept alone, so memory goes
      // past the budget by this one image, and only until the next image is stored.
      entries.clear();
      entries.put(url, bitmap);
      bytes = size;
      return;
    }
    entries.put(url, bitmap);
    bytes += size;
    // Drop the least recently used until both bounds hold.
    Iterator<Map.Entry<String, Bitmap>> it = entries.entrySet().iterator();
    while ((entries.size() > maxEntries || bytes > maxBytes) && it.hasNext()) {
      Map.Entry<String, Bitmap> eldest = it.next();
      if (eldest.getValue() == bitmap) {
        break;
      }
      bytes -= eldest.getValue().getAllocationByteCount();
      it.remove();
    }
  }

  public synchronized int size() {
    return entries.size();
  }
}
