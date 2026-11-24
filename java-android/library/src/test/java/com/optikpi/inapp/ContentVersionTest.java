package com.optikpi.inapp;

import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;

import com.optikpi.inapp.model.PopupContent;
import java.math.BigDecimal;
import java.math.BigInteger;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class ContentVersionTest {
  private static PopupContent parse(Object version) throws Exception {
    return PopupContent.tryParse(
        new JSONObject()
            .put("version", version)
            .put("layout", "toast")
            .put("title", "Hello"));
  }

  @Test
  public void onlyAnExactOneIsVersionOne() throws Exception {
    assertNotNull(parse(1));
    assertNotNull(parse(1L));
    assertNotNull(parse(1.0));
    assertNotNull(parse(BigInteger.ONE));
    assertNotNull(parse(new BigDecimal("1.0")));

    assertNull(parse(2));
    assertNull(parse(1.5));
    assertNull(parse(4294967297L));
    assertNull(parse(new BigDecimal("1.0000000000000001")));
    assertNull(parse(new BigDecimal("1.5")));
    assertNull(parse(BigInteger.valueOf(4294967297L)));
    assertNull(parse("1"));
  }
}
