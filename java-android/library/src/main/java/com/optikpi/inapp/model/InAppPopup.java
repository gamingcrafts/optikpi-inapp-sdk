package com.optikpi.inapp.model;

import static com.optikpi.inapp.model.JsonHelpers.map;
import static com.optikpi.inapp.model.JsonHelpers.string;

import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

public final class InAppPopup {
  public static final String KIND = "popup";

  public final String id;
  public final String trackingId;
  public final String campaignId;
  public final Instant createdAt;
  public final Instant expiresAt;
  public final PopupContent content;

  public InAppPopup(
      String id,
      String trackingId,
      String campaignId,
      Instant createdAt,
      Instant expiresAt,
      PopupContent content) {
    this.id = id;
    this.trackingId = trackingId;
    this.campaignId = campaignId;
    this.createdAt = createdAt;
    this.expiresAt = expiresAt;
    this.content = content;
  }

  public boolean isExpiredAt(Instant now) {
    return expiresAt != null && !now.isBefore(expiresAt);
  }

  public static InAppPopup tryParse(Object json) {
    if (!(json instanceof JSONObject map)) {
      return null;
    }
    Object entryKind = map.opt("kind");
    if (entryKind != null
        && entryKind != JSONObject.NULL
        && !KIND.equals(entryKind)) {
      return null;
    }
    String id = string(map.opt("id"));
    String trackingId = string(map.opt("trackingId"));
    if (id == null || id.isEmpty() || trackingId == null || trackingId.isEmpty()) {
      return null;
    }
    PopupContent content = PopupContent.tryParse(map.opt("content"));
    if (content == null) {
      return null;
    }
    String campaignId = string(map.opt("campaignId"));
    Instant createdAt = parseDate(map.opt("createdAt"));
    if (createdAt == null) {
      createdAt = Instant.EPOCH;
    }
    return new InAppPopup(
        id, trackingId, campaignId, createdAt, parseDate(map.opt("expiresAt")), content);
  }

  private static Instant parseDate(Object value) {
    if (!(value instanceof String s)) {
      return null;
    }
    try {
      return Instant.parse(s);
    } catch (DateTimeParseException e) {
      return null;
    }
  }
}