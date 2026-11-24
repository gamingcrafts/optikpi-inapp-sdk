package com.optikpi.inapp.source;

import android.content.Context;
import com.optikpi.inapp.InAppLog;
import com.optikpi.inapp.events.PopupEvent;
import com.optikpi.inapp.model.InAppPopup;
import com.optikpi.inapp.model.PopupContent;
import com.optikpi.inapp.model.PopupFetchResult;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.json.JSONObject;

public final class MockPopupSource extends PopupSource {
  private static final Pattern MERGE_TAG = Pattern.compile("\\{\\{\\s*([\\w.]+)\\s*\\}\\}");

  private final Context context;
  private final Map<String, String> playerData;
  private final Instant newest = Instant.parse("2026-10-01T12:00:00Z");

  public MockPopupSource(Context context) {
    this(context, Collections.emptyMap());
  }

  public MockPopupSource(Context context, Map<String, String> playerData) {
    this.context = context.getApplicationContext();
    this.playerData = playerData;
  }

  @Override
  public boolean needsPlayerToken() {
    return false;
  }

  @Override
  public PopupFetchResult fetch(PopupRequestContext context) throws Exception {
    List<InAppPopup> popups = new ArrayList<>();
    Instant now = Instant.now();
    String[] layouts =
        new String[] {
          "modal", "fullscreen", "bottomSheet", "banner", "toast", "imageOnly"
        };
    for (int i = 0; i < layouts.length; i++) {
      String layout = layouts[i];
      String json = readAsset("optikpi_mock/layouts/" + layout + ".json");
      JSONObject contentJson = new JSONObject(fillMergeTags(new JSONObject(json)));
      PopupContent content = PopupContent.tryParse(contentJson);
      if (content == null) {
        continue;
      }
      Instant created = newest.minus(i, ChronoUnit.HOURS);
      popups.add(
          new InAppPopup(
              "mock-" + context.playerId + "-" + layout,
              "mock-trk-" + context.playerId + "-" + layout,
              "mock-campaign",
              created,
              now.plus(3, ChronoUnit.DAYS),
              content));
    }
    InAppLog.log("mock fetch for " + context.playerId + ": " + popups.size() + " pop-up(s)");
    return new PopupFetchResult(popups, 300);
  }

  @Override
  public void sendEvents(PopupRequestContext context, List<PopupEvent> events) {
    for (PopupEvent event : events) {
      String suffix = event.buttonIndex != null ? " button " + event.buttonIndex : "";
      InAppLog.log("mock event " + event.type.name() + " " + event.trackingId + suffix);
    }
  }

  private String readAsset(String path) throws Exception {
    try (var stream = this.context.getAssets().open(path);
        var reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
      StringBuilder sb = new StringBuilder();
      String line;
      while ((line = reader.readLine()) != null) {
        sb.append(line).append('\n');
      }
      return sb.toString();
    }
  }

  private String fillMergeTags(JSONObject content) throws Exception {
    JSONObject copy = new JSONObject(content.toString());
    if (copy.has("title")) {
      copy.put("title", fill(copy.optString("title")));
    }
    if (copy.has("body")) {
      copy.put("body", fill(copy.optString("body")));
    }
    return copy.toString();
  }

  private String fill(String text) {
    Matcher matcher = MERGE_TAG.matcher(text);
    StringBuffer sb = new StringBuffer();
    while (matcher.find()) {
      String key = matcher.group(1);
      String replacement = playerData.getOrDefault(key, key);
      matcher.appendReplacement(sb, Matcher.quoteReplacement(replacement));
    }
    matcher.appendTail(sb);
    return sb.toString();
  }
}