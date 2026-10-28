import 'dart:convert';

import 'package:http/http.dart' as http;

import '../events/popup_event.dart';
import '../log.dart';
import '../model/inapp_popup.dart';
import '../version.dart';
import 'mock_popup_source.dart';

/// Placeholder until the pull API ships. `.invalid` never resolves, so nothing is sent anywhere.
/// The real one is per environment: `https://{dev|qa|app}.optikpi.com/apigw`.
const String defaultPopupBaseUrl = 'https://inapp.optikpi.invalid';

/// Who is asking: one logged-in player in one workspace.
class PopupRequestContext {
  const PopupRequestContext({
    required this.baseUrl,
    required this.workspaceId,
    required this.playerId,
    required this.apiKey,
    this.deviceKey,
  });

  final String baseUrl;

  /// Not sent (the API key carries the workspace); keys the on-device event queue.
  final String workspaceId;
  final String playerId;
  final String apiKey;
  final String? deviceKey;
}

/// Where pop-ups come from and where events go. Either call throws on failure.
abstract class PopupSource {
  const PopupSource();

  /// The pull API described in API.md.
  factory PopupSource.http({http.Client? client}) = HttpPopupSource;

  /// The bundled templates (all 6 layouts). Events are logged, never sent.
  /// [playerData] fills `{{merge_tags}}` the way the server will.
  factory PopupSource.mock({Map<String, String> playerData}) = MockPopupSource;

  Future<PopupFetchResult> fetch(PopupRequestContext context);

  Future<void> sendEvents(PopupRequestContext context, List<PopupEvent> events);
}

class PopupHttpException implements Exception {
  PopupHttpException(this.statusCode, this.path);

  final int statusCode;
  final String path;

  @override
  String toString() => 'HTTP $statusCode from $path';
}

class HttpPopupSource extends PopupSource {
  HttpPopupSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  Map<String, String> _headers(PopupRequestContext context) => {
    'authorization': 'Bearer ${context.apiKey}',
    if (context.deviceKey != null && context.deviceKey!.isNotEmpty)
      'x-device-key': context.deviceKey!,
    'x-sdk-version': 'optikpi_popup-flutter/$optikpiPopupVersion',
    'accept': 'application/json',
  };

  Uri _uri(PopupRequestContext context, String path, [Map<String, String>? query]) {
    final base =
        context.baseUrl.endsWith('/')
            ? context.baseUrl.substring(0, context.baseUrl.length - 1)
            : context.baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  @override
  Future<PopupFetchResult> fetch(PopupRequestContext context) async {
    const path = '/v1/inapp/popups';
    final response = await _client
        .get(_uri(context, path, {'playerId': context.playerId}), headers: _headers(context))
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
          body: jsonEncode({
            'playerId': context.playerId,
            'events': events.map((e) => e.toJson()).toList(),
          }),
        )
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PopupHttpException(response.statusCode, path);
    }
    popupLog('sent ${events.length} event(s)');
  }
}
