package com.optikpi.inapp.source;

public final class PopupRequestContext {
  public final String baseUrl;
  public final String workspaceId;
  public final String playerId;
  public final String apiKey;
  public final String playerToken;

  public PopupRequestContext(
      String baseUrl,
      String workspaceId,
      String playerId,
      String apiKey,
      String playerToken) {
    this.baseUrl = baseUrl;
    this.workspaceId = workspaceId;
    this.playerId = playerId;
    this.apiKey = apiKey;
    this.playerToken = playerToken;
  }
}