import 'popup_content.dart';

/// One waiting pop-up as the pull API returns it (see the repo's API.md).
class InAppPopup {
  const InAppPopup({
    required this.id,
    required this.trackingId,
    this.campaignId,
    required this.createdAt,
    this.expiresAt,
    required this.content,
  });

  final String id;
  final String trackingId;
  final String? campaignId;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final PopupContent content;

  bool isExpiredAt(DateTime now) => expiresAt != null && !now.isBefore(expiresAt!);

  /// The only message kind this version handles. An entry with no `kind` (or null) is a pop-up.
  static const String kind = 'popup';

  /// Null when the entry can't be shown or tracked: another kind of message, no id, no
  /// trackingId, unusable content.
  static InAppPopup? tryParse(Object? json) {
    if (json is! Map) return null;
    // Room for future message types: an SDK that doesn't know a kind skips it.
    final entryKind = json['kind'];
    if (entryKind != null && entryKind != kind) return null;
    final id = json['id'];
    final trackingId = json['trackingId'];
    if (id is! String || id.isEmpty || trackingId is! String || trackingId.isEmpty) return null;
    final content = PopupContent.tryParse(json['content']);
    if (content == null) return null;
    final campaignId = json['campaignId'];
    return InAppPopup(
      id: id,
      trackingId: trackingId,
      campaignId: campaignId is String ? campaignId : null,
      // A missing createdAt sorts last rather than dropping the pop-up.
      createdAt: _date(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt: _date(json['expiresAt']),
      content: content,
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}

class PopupFetchResult {
  const PopupFetchResult({required this.popups, this.nextCheckAfterSec});

  final List<InAppPopup> popups;
  final int? nextCheckAfterSec;

  /// Entries that don't parse are skipped one by one; the rest of the response still counts.
  factory PopupFetchResult.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final list = map['popups'] is List ? map['popups'] as List : const [];
    final next = map['nextCheckAfterSec'];
    return PopupFetchResult(
      popups: list.map(InAppPopup.tryParse).whereType<InAppPopup>().toList(growable: false),
      nextCheckAfterSec: next is num && next.isFinite ? next.round() : null,
    );
  }
}
