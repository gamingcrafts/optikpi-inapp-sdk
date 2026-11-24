package com.optikpi.inapp;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import com.optikpi.inapp.model.PopupContent;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class DrawsImageTest {
  private static PopupContent content(String layout, String size) throws Exception {
    JSONObject json =
        new JSONObject()
            .put("version", 1)
            .put("layout", layout)
            .put("size", size)
            .put("title", "Hello")
            .put("image", new JSONObject().put("url", "https://cdn.example/a.png").put("alt", "a"));
    PopupContent content = PopupContent.tryParse(json);
    assertTrue(content != null && content.image != null);
    return content;
  }

  @Test
  public void aLayoutThatDoesNotDrawTheImageDoesNotWaitForIt() throws Exception {
    assertFalse(content("modal", "iab_300x250").drawsImage());
    assertFalse(content("bottomSheet", "sm").drawsImage());
    assertFalse(content("toast", "sm").drawsImage());
    assertFalse(content("toast", "lg").drawsImage());
  }

  @Test
  public void aLayoutThatDrawsTheImageWaitsForIt() throws Exception {
    assertTrue(content("modal", "sm").drawsImage());
    assertTrue(content("modal", "md").drawsImage());
    assertTrue(content("bottomSheet", "md").drawsImage());
    assertTrue(content("bottomSheet", "lg").drawsImage());
    assertTrue(content("toast", "md").drawsImage());
    assertTrue(content("banner", "md").drawsImage());
    assertTrue(content("banner", "iab_320x50").drawsImage());
    assertTrue(content("fullscreen", "md").drawsImage());
    assertTrue(content("imageOnly", "md").drawsImage());
  }
}
