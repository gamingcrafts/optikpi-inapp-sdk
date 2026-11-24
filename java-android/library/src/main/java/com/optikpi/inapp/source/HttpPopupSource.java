package com.optikpi.inapp.source;

import com.optikpi.inapp.InAppLog;
import com.optikpi.inapp.Version;
import com.optikpi.inapp.events.PopupEvent;
import com.optikpi.inapp.model.PopupFetchResult;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.json.JSONTokener;

public final class HttpPopupSource extends PopupSource {
  private static final MediaType JSON = MediaType.get("application/json; charset=utf-8");
  private final OkHttpClient client;

  /**
   * The most a whole request may take. The connect, read and write timeouts bound single steps, so
   * a server that keeps sending a trickle never trips them; and a request runs on the controller's
   * one worker thread, where a stalled one would hold up every fetch and session after it.
   */
  static final long CALL_TIMEOUT_SEC = 30;

  static OkHttpClient defaultClient() {
    return new OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .callTimeout(CALL_TIMEOUT_SEC, TimeUnit.SECONDS)
        .build();
  }

  public HttpPopupSource() {
    client = defaultClient();
  }

  public HttpPopupSource(OkHttpClient client) {
    this.client = client;
  }

  private static String base(PopupRequestContext context) {
    String base = context.baseUrl;
    if (base.endsWith("/")) {
      base = base.substring(0, base.length() - 1);
    }
    return base;
  }

  private Request.Builder headers(PopupRequestContext context) {
    return new Request.Builder()
        .header("authorization", "Bearer " + context.apiKey)
        .header("x-player-token", context.playerToken)
        .header("x-sdk-version", "optikpi_inapp-java-android/" + Version.OPTIKPI_INAPP_VERSION)
        .header("accept", "application/json");
  }

  /**
   * The body's top-level value as it is: {@code null} (or anything but an object) is an empty
   * result, not a failure, as {@code contract/fixtures/fetch-response-cases.json} requires. Only
   * unparseable text throws.
   */
  static PopupFetchResult parseBody(String body) throws JSONException {
    JSONTokener tokener = new JSONTokener(body);
    Object value = tokener.nextValue();
    // The tokener is lenient: it reads bare words such as an HTML error page as a string, and
    // stops at the first value. Only a real JSON document is a response.
    if (tokener.nextClean() != 0 || (value instanceof String && !body.trim().startsWith("\""))) {
      throw new JSONException("not a JSON document");
    }
    return PopupFetchResult.fromJson(value);
  }

  @Override
  public PopupFetchResult fetch(PopupRequestContext context) throws Exception {
    String path = "/v1/inapp/popups";
    Request request =
        headers(context).url(base(context) + path).get().build();
    try (Response response = client.newCall(request).execute()) {
      if (response.code() != 200) {
        throw new PopupHttpException(response.code(), path);
      }
      String body = response.body() != null ? response.body().string() : "{}";
      return parseBody(body);
    }
  }

  @Override
  public void sendEvents(PopupRequestContext context, List<PopupEvent> events) throws Exception {
    String path = "/ingest/popup";
    JSONObject root = new JSONObject();
    JSONArray array = new JSONArray();
    for (PopupEvent event : events) {
      array.put(event.toJson());
    }
    root.put("events", array);
    Request request =
        headers(context)
            .url(base(context) + path)
            .header("content-type", "application/json")
            .post(RequestBody.create(root.toString(), JSON))
            .build();
    try (Response response = client.newCall(request).execute()) {
      int code = response.code();
      if (code < 200 || code >= 300) {
        throw new PopupHttpException(code, path);
      }
      InAppLog.log("sent " + events.size() + " event(s)");
    }
  }
}