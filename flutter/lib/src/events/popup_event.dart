enum PopupEventType { impression, click, dismiss }

class PopupEvent {
  const PopupEvent({
    required this.trackingId,
    required this.type,
    required this.at,
    this.buttonIndex,
  });

  final String trackingId;
  final PopupEventType type;
  final DateTime at;

  /// Set on a click from a button; absent on an image tap.
  final int? buttonIndex;

  /// Each `(trackingId, type)` is sent once.
  String get dedupeKey => '$trackingId|${type.name}';

  Map<String, dynamic> toJson() => {
    'trackingId': trackingId,
    'type': type.name,
    'at': at.toUtc().toIso8601String(),
    if (buttonIndex != null) 'buttonIndex': buttonIndex,
  };

  static PopupEvent? tryParse(Object? json) {
    if (json is! Map) return null;
    final trackingId = json['trackingId'];
    final at = json['at'] is String ? DateTime.tryParse(json['at'] as String) : null;
    final type = PopupEventType.values.where((t) => t.name == json['type']).firstOrNull;
    if (trackingId is! String || at == null || type == null) return null;
    final buttonIndex = json['buttonIndex'];
    return PopupEvent(
      trackingId: trackingId,
      type: type,
      at: at,
      buttonIndex: buttonIndex is int ? buttonIndex : null,
    );
  }
}
