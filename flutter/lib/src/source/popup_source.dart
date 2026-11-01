import 'dart:convert';

import 'package:http/http.dart' as http;

import '../events/popup_event.dart';
import '../log.dart';
import '../model/inapp_popup.dart';
import '../version.dart';
import 'mock_popup_source.dart';

/// Who is asking: one logged-in player in one workspace.
class PopupRequestContext {
  const PopupRequestContext({
    required this.baseUrl,
    required this.workspaceId,
    required this.playerId,
    required this.apiKey,
    required this.playerToken,
  });

  final String baseUrl;

  /// `wid` of [playerToken]. Not sent; keys the on-device event queue.
  final String workspaceId;

  /// `sub` of [playerToken]. Not sent: the server takes the player from the token.
  final String playerId;
  final String apiKey;

  /// Sent as `x-player-token`. Never log it.
  final String playerToken;
}

/// Where pop-ups come from and where events go. Either call throws on failure.
abstract class PopupSource {
  const PopupSource();

  /// The pull API described in the repo's API.md.
  factory PopupSource.http({http.Client? client}) = HttpPopupSource;

  /// The bundled templates (all 6 layouts). Events are logged, never sent.
  /// [playerData] fills `{{merge_tags}}` the way the server will.
  factory PopupSource.mock({Map<String, String> playerData}) = MockPopupSource;

  /// False for a source that talks to no server, which works without a real token.
  bool get needsPlayerToken => true;

  Future<PopupFetchResult> fetch(PopupRequestContext context);

  Future<void> sendEvents(PopupRequestContext context, List<PopupEvent> events);
}

class PopupHttpException implements Exception {
  PopupHttpException(this.statusCode, this.path);

  final int statusCode;
  final String path;

  /// The server refused the player token or the key. API Gateway answers a refused token with
  /// 403; only a request with no `authorization` header gets 401.
  bool get isAuthFailure => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'HTTP $statusCode from $path';
}

class HttpPopupSource extends PopupSource {
  HttpPopupSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  Map<String, String> _headers(PopupRequestContext context) => {
    'authorization': 'Bearer ${context.apiKey}',
    'x-player-token': context.playerToken,
    'x-sdk-version': 'optikpi_inapp-flutter/$optikpiInAppVersion',
    'accept': 'application/json',
  };

  Uri _uri(PopupRequestContext context, String path) {
    final base =
        context.baseUrl.endsWith('/')
            ? context.baseUrl.substring(0, context.baseUrl.length - 1)
            : context.baseUrl;
    return Uri.parse('$base$path');
  }

  @override
  Future<PopupFetchResult> fetch(PopupRequestContext context) async {
    const path = '/v1/inapp/popups';
    final response = await _client
        .get(_uri(context, path), headers: _headers(context))
        .timeout(_timeout);
    if (response.statusCode != 200) throw PopupHttpException(response.statusCode, path);
    return PopupFetchResult.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  @override
  Future<void> sendEvents(PopupRequestContext context, List<PopupEvent> events) async {
    // The shared ingest webhook (`/apigw/ingest/{provider}`), not a pop-up endpoint of its own.
    const path = '/ingest/popup';
    final response = await _client
        .post(
          _uri(context, path),
          headers: {..._headers(context), 'content-type': 'application/json'},
          body: jsonEncode({'events': events.map((e) => e.toJson()).toList()}),
        )
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PopupHttpException(response.statusCode, path);
    }
    inAppLog('sent ${events.length} event(s)');
  }
}
