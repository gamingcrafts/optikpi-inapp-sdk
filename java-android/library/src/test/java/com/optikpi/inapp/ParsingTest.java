package com.optikpi.inapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import com.optikpi.inapp.logic.PlayerTokenClaims;
import com.optikpi.inapp.model.InAppPopup;
import com.optikpi.inapp.model.PopupClose;
import com.optikpi.inapp.model.PopupContent;
import com.optikpi.inapp.model.PopupFetchResult;
import com.optikpi.inapp.model.PopupImage;
import com.optikpi.inapp.model.PopupTheme;
import com.optikpi.inapp.support.ContractFixtures;
import com.optikpi.inapp.support.PopupContentJson;
import java.time.Instant;
import java.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class ParsingTest {
  @Test
  public void contentCases() throws Exception {
    JSONObject fixture = ContractFixtures.readObject("content-cases.json");
    JSONObject base = fixture.getJSONObject("base");
    JSONArray cases = fixture.getJSONArray("cases");
    for (int i = 0; i < cases.length(); i++) {
      JSONObject c = cases.getJSONObject(i);
      String name = c.getString("name");
      Object input;
      if (c.has("content")) {
        input = c.get("content");
      } else {
        JSONObject merged = new JSONObject(base.toString());
        if (c.has("set")) {
          JSONObject set = c.getJSONObject("set");
          JSONArray keys = set.names();
          if (keys != null) {
            for (int k = 0; k < keys.length(); k++) {
              String key = keys.getString(k);
              merged.put(key, set.get(key));
            }
          }
        }
        if (c.has("remove")) {
          JSONArray remove = c.getJSONArray("remove");
          for (int r = 0; r < remove.length(); r++) {
            merged.remove(remove.getString(r));
          }
        }
        input = merged;
      }
      PopupContent content = PopupContent.tryParse(input);
      if (c.isNull("expect")) {
        assertNull("expected null for " + name, content);
      } else {
        assertNotNull("expected content for " + name, content);
        ContractFixtures.expectMatches(
            PopupContentJson.toJson(content), c.getJSONObject("expect"), name);
      }
    }
  }

  @Test
  public void fetchResponseCases() throws Exception {
    JSONObject fixture = ContractFixtures.readObject("fetch-response-cases.json");
    JSONArray cases = fixture.getJSONArray("cases");
    for (int i = 0; i < cases.length(); i++) {
      JSONObject c = cases.getJSONObject(i);
      PopupFetchResult result = PopupFetchResult.fromJson(c.get("response"));
      JSONArray expectIds = c.getJSONArray("expectIds");
      assertEquals(c.getString("name"), expectIds.length(), result.popups.size());
      for (int j = 0; j < expectIds.length(); j++) {
        assertEquals(expectIds.getString(j), result.popups.get(j).id);
      }
      if (c.isNull("expectNextCheckAfterSec")) {
        assertNull(result.nextCheckAfterSec);
      } else {
        assertEquals(c.getInt("expectNextCheckAfterSec"), result.nextCheckAfterSec.intValue());
      }
    }
  }

  @Test
  public void playerTokenCases() throws Exception {
    JSONObject fixture = ContractFixtures.readObject("player-token-cases.json");
    JSONArray cases = fixture.getJSONArray("cases");
    for (int i = 0; i < cases.length(); i++) {
      JSONObject item = cases.getJSONObject(i);
      String token;
      if (item.has("raw")) {
        token = item.getString("raw");
      } else if (!item.has("payload")) {
        token = "";
      } else if (!(item.get("payload") instanceof JSONObject)) {
        String header =
            Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString("{\"alg\":\"ES256\"}".getBytes());
        String payload =
            Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString(item.getJSONArray("payload").toString().getBytes());
        token = header + "." + payload + ".sig";
      } else {
        JSONObject payloadJson = item.getJSONObject("payload");
        String header =
            Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString("{\"alg\":\"ES256\"}".getBytes());
        String payload =
            Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString(payloadJson.toString().getBytes());
        token = header + "." + payload + ".sig";
      }
      PlayerTokenClaims claims = PlayerTokenClaims.tryRead(token);
      if (item.isNull("expect")) {
        assertNull(item.getString("name"), claims);
      } else {
        JSONObject expect = item.getJSONObject("expect");
        assertEquals(expect.getString("playerId"), claims.playerId);
        assertEquals(expect.getString("workspaceId"), claims.workspaceId);
      }
    }
  }

  @Test
  public void gradientColours() throws Exception {
    PopupImage image =
        PopupImage.tryParse(new JSONObject().put("url", "gradient:#7F56D9,#F04438"));
    assertTrue(image.isGradient());
    int[] colours = image.gradientColors();
    assertEquals(2, colours.length);
  }

  @Test
  public void darkBackgroundRule() throws Exception {
    PopupTheme dark = PopupTheme.parse(new JSONObject().put("background", "#101828"));
    PopupTheme light = PopupTheme.parse(new JSONObject().put("background", "#FFFFFF"));
    assertTrue(dark.isDarkBackground());
    assertFalse(light.isDarkBackground());
  }

  @Test
  public void inAppPopupExpiry() throws Exception {
    JSONObject json =
        new JSONObject()
            .put("id", "a")
            .put("trackingId", "t")
            .put("createdAt", "2026-10-01T12:00:00+02:00")
            .put("expiresAt", "2026-10-02T00:00:00Z")
            .put("content", new JSONObject().put("layout", "modal"));
    InAppPopup popup = InAppPopup.tryParse(json);
    assertFalse(popup.isExpiredAt(Instant.parse("2026-10-01T23:59:00Z")));
    assertTrue(popup.isExpiredAt(Instant.parse("2026-10-02T00:00:00Z")));
  }

  @Test
  public void aHugePollingIntervalClampsInsteadOfWrapping() throws Exception {
    PopupFetchResult result =
        PopupFetchResult.fromJson(
            new org.json.JSONObject("{\"popups\":[],\"nextCheckAfterSec\":5000000000}"));
    assertEquals(Integer.MAX_VALUE, (int) result.nextCheckAfterSec);
    PopupFetchResult negative =
        PopupFetchResult.fromJson(
            new org.json.JSONObject("{\"popups\":[],\"nextCheckAfterSec\":-5000000000}"));
    assertEquals(Integer.MIN_VALUE, (int) negative.nextCheckAfterSec);
  }

  @Test
  public void anInvalidCloseFlagKeepsItsDefault() throws Exception {
    for (String flag : new String[] {"null", "\"false\"", "0", "{}"}) {
      org.json.JSONObject json =
          new org.json.JSONObject("{\"tapOutsideToClose\":" + flag + ",\"show\":" + flag + "}");
      PopupClose close = PopupClose.parse(json);
      assertTrue("tapOutsideToClose " + flag, close.tapOutsideToClose);
      assertTrue("show " + flag, close.show);
    }
    PopupClose off =
        PopupClose.parse(new org.json.JSONObject("{\"tapOutsideToClose\":false,\"show\":false}"));
    assertFalse(off.tapOutsideToClose);
    assertFalse(off.show);
  }

  @Test
  public void onlyAnExactVersionOneIsRendered() throws Exception {
    for (String version : new String[] {"1.5", "4294967297", "2", "0", "\"1\"", "null"}) {
      JSONObject json =
          new JSONObject("{\"version\":" + version + ",\"layout\":\"modal\",\"title\":\"Hi\"}");
      assertNull("version " + version, PopupContent.tryParse(json));
    }
    assertNotNull(
        PopupContent.tryParse(
            new JSONObject("{\"version\":1,\"layout\":\"modal\",\"title\":\"Hi\"}")));
  }

  @Test
  public void aSurvivingButtonKeepsItsPlaceInTheDeliveredArray() throws Exception {
    PopupContent content =
        PopupContent.tryParse(
            new JSONObject(
                "{\"version\":1,\"layout\":\"modal\",\"title\":\"Hi\",\"buttons\":["
                    + "{\"label\":\"X\",\"style\":\"primary\",\"action\":{\"type\":\"teleport\"}},"
                    + "{\"label\":\"Y\",\"style\":\"primary\",\"action\":{\"type\":\"dismiss\"}}]}"));
    assertNotNull(content);
    assertEquals(1, content.buttons.size());
    assertEquals("Y", content.buttons.get(0).label);
    // Rendered first, but delivered second: the click event must say 1.
    assertEquals(1, content.buttons.get(0).sourceIndex);
  }
}
