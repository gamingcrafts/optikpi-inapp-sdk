import '../events/popup_event.dart';
import '../log.dart';
import '../model/inapp_popup.dart';
import 'mock_templates.dart';
import 'popup_source.dart';

/// The server fills merge tags; the mock stands in for it. Unknown tags show their key, like the
/// app_next preview.
Map<String, dynamic> fillMockMergeTags(
  Map<String, dynamic> content,
  Map<String, String> playerData,
) {
  String fill(String text) => text.replaceAllMapped(
    RegExp(r'\{\{\s*([\w.]+)\s*\}\}'),
    (m) => playerData[m.group(1)] ?? m.group(1)!,
  );
  return {
    ...content,
    if (content['title'] is String) 'title': fill(content['title'] as String),
    if (content['body'] is String) 'body': fill(content['body'] as String),
  };
}

/// Serves [mockPopupTemplates] as if the pull API had returned them, so the demo works before the
/// backend exists. Events are logged and dropped.
class MockPopupSource extends PopupSource {
  MockPopupSource({this.playerData = const {}, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Map<String, String> playerData;
  final DateTime Function() _clock;

  @override
  bool get needsPlayerToken => false;

  /// Template order is newest first: each one is an hour older than the one before.
  static final DateTime _newest = DateTime.utc(2026, 10, 1, 12);

  @override
  Future<PopupFetchResult> fetch(PopupRequestContext context) async {
    final now = _clock().toUtc();
    final json = {
      'popups': [
        for (final (i, template) in mockPopupTemplates.indexed)
          {
            // Per player, like the server: shown ids and sent events are shared on a device.
            'id': 'mock-${context.playerId}-${template.id}',
            'trackingId': 'mock-trk-${context.playerId}-${template.id}',
            'campaignId': 'mock-campaign',
            'createdAt': _newest.subtract(Duration(hours: i)).toIso8601String(),
            'expiresAt': now.add(const Duration(days: 3)).toIso8601String(),
            'content': fillMockMergeTags(template.content, playerData),
          },
      ],
      'nextCheckAfterSec': 300,
    };
    inAppLog('mock fetch for ${context.playerId}: ${mockPopupTemplates.length} pop-ups');
    return PopupFetchResult.fromJson(json);
  }

  @override
  Future<void> sendEvents(PopupRequestContext context, List<PopupEvent> events) async {
    for (final event in events) {
      inAppLog(
        'mock event ${event.type.name} ${event.trackingId}'
        '${event.buttonIndex != null ? ' button ${event.buttonIndex}' : ''}',
      );
    }
  }
}
