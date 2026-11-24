package com.optikpi.inapp.logic;

import android.util.Base64;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

public final class PlayerTokenClaims {
  public final String playerId;
  public final String workspaceId;

  public PlayerTokenClaims(String playerId, String workspaceId) {
    this.playerId = playerId;
    this.workspaceId = workspaceId;
  }

  /** `sub` and `wid` of a JWT's payload, unverified. Null when the token is null or unreadable. */
  public static PlayerTokenClaims tryRead(String token) {
    if (token == null) {
      return null;
    }
    String[] parts = token.split("\\.");
    if (parts.length != 3) {
      return null;
    }
    try {
      byte[] decoded = Base64.decode(parts[1], Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
      String payload = new String(decoded, StandardCharsets.UTF_8);
      JSONObject claims = new JSONObject(payload);
      Object subRaw = claims.opt("sub");
      Object widRaw = claims.opt("wid");
      if (!(subRaw instanceof String sub) || sub.isEmpty()) {
        return null;
      }
      if (!(widRaw instanceof String wid) || wid.isEmpty()) {
        return null;
      }
      return new PlayerTokenClaims(sub, wid);
    } catch (Exception e) {
      return null;
    }
  }
}