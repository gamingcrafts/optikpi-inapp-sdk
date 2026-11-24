package com.optikpi.inapp.render;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.graphics.Bitmap;
import okhttp3.ResponseBody;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class PopupImageLoaderTest {
  @Test
  public void aDownloadOverTheLimitIsRefused() throws Exception {
    byte[] small = new byte[1024];
    byte[] big = new byte[(int) PopupImageLoader.MAX_DOWNLOAD_BYTES + 1];
    assertEquals(
        1024, PopupImageLoader.readBounded(ResponseBody.create(small, null)).length);
    assertNull(PopupImageLoader.readBounded(ResponseBody.create(big, null)));
  }

  @Test
  public void aLargeImageIsDecodedSmallerThanTheScreen() throws Exception {
    Bitmap source = Bitmap.createBitmap(1600, 1200, Bitmap.Config.ARGB_8888);
    java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
    source.compress(Bitmap.CompressFormat.PNG, 100, out);

    Bitmap decoded = PopupImageLoader.decodeScaled(out.toByteArray(), 400);

    assertNotNull(decoded);
    assertTrue(decoded.getWidth() <= 400 && decoded.getHeight() <= 400);
  }
}
