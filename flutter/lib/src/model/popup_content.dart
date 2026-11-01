import 'dart:ui' show Color;

/* Dart port of the content contract, app_next `app/shared/popup/popup.types.ts` on dev.
   Field for field; the parsing rules are the Flutter side's own:
   - unknown fields are ignored;
   - an unknown layout (or a `version` other than 1) makes the whole pop-up unusable, so
     `PopupContent.tryParse` returns null and the caller skips it;
   - anything else that is missing or invalid falls back to the value the web builder would
     have produced (`applyLayout` in popup.types.ts), so a slightly wrong payload still renders.
     The exception is a missing `autoDismissSec`, which means stay up (the builder's "Never"). */

enum PopupLayout { modal, fullscreen, bottomSheet, banner, toast, imageOnly }

enum PopupSize { sm, md, lg, iab_300x250, iab_320x50 }

enum PopupPosition { top, bottom, center, topRight, bottomRight }

enum PopupActionType { deeplink, url, dismiss, custom }

enum PopupButtonStyle { primary, secondary }

enum PopupClosePosition { topRight, topLeft }

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

String? _string(Object? value) => value is String ? value : null;

Map<String, dynamic>? _map(Object? value) => value is Map ? value.cast<String, dynamic>() : null;

/// The usable pairs of a `customData` array. An entry without a non-blank string key and a string
/// value is dropped. A repeated key keeps its last value, as in an FCM data payload.
Map<String, String> _customData(Object? json) {
  final data = <String, String>{};
  if (json is! List) return data;
  for (final entry in json) {
    final map = _map(entry);
    final key = _string(map?['key'])?.trim();
    final value = _string(map?['value']);
    if (key != null && key.isNotEmpty && value != null) data[key] = value;
  }
  return data;
}

/// Which sizes, positions and how many buttons each layout allows (`POPUP_LAYOUTS`).
class PopupLayoutSpec {
  const PopupLayoutSpec({
    required this.layout,
    required this.sizes,
    this.positions,
    required this.hasText,
    required this.maxButtons,
    required this.autoDismiss,
  });

  final PopupLayout layout;
  final List<PopupSize> sizes;
  final List<PopupPosition>? positions;
  final bool hasText;
  final int maxButtons;
  final bool autoDismiss;

  static const Map<PopupLayout, PopupLayoutSpec> all = {
    PopupLayout.modal: PopupLayoutSpec(
      layout: PopupLayout.modal,
      sizes: [PopupSize.sm, PopupSize.md, PopupSize.lg, PopupSize.iab_300x250],
      hasText: true,
      maxButtons: 2,
      autoDismiss: false,
    ),
    PopupLayout.fullscreen: PopupLayoutSpec(
      layout: PopupLayout.fullscreen,
      sizes: [PopupSize.lg],
      hasText: true,
      maxButtons: 2,
      autoDismiss: false,
    ),
    PopupLayout.bottomSheet: PopupLayoutSpec(
      layout: PopupLayout.bottomSheet,
      sizes: [PopupSize.sm, PopupSize.md, PopupSize.lg],
      hasText: true,
      maxButtons: 2,
      autoDismiss: false,
    ),
    PopupLayout.banner: PopupLayoutSpec(
      layout: PopupLayout.banner,
      sizes: [PopupSize.md, PopupSize.iab_320x50],
      positions: [PopupPosition.top, PopupPosition.bottom],
      hasText: true,
      maxButtons: 1,
      autoDismiss: true,
    ),
    PopupLayout.toast: PopupLayoutSpec(
      layout: PopupLayout.toast,
      sizes: [PopupSize.sm, PopupSize.md],
      positions: [PopupPosition.topRight, PopupPosition.bottomRight],
      hasText: true,
      maxButtons: 1,
      autoDismiss: true,
    ),
    PopupLayout.imageOnly: PopupLayoutSpec(
      layout: PopupLayout.imageOnly,
      sizes: [PopupSize.md, PopupSize.lg, PopupSize.iab_300x250],
      hasText: false,
      maxButtons: 0,
      autoDismiss: false,
    ),
  };
}

class PopupAction {
  const PopupAction({required this.type, this.value, this.customData});

  final PopupActionType type;
  final String? value;

  /// The key/value pairs of a `custom` action, for the app's `onCustomAction`.
  final Map<String, String>? customData;

  /// Null when the type is unknown. A deeplink or url without a value, or a custom action with no
  /// usable pairs, acts as dismiss.
  static PopupAction? tryParse(Object? json) {
    final map = _map(json);
    final type = _enumByName(PopupActionType.values, map?['type']);
    if (type == null) return null;
    if (type == PopupActionType.custom) {
      final data = _customData(map!['customData']);
      if (data.isEmpty) return const PopupAction(type: PopupActionType.dismiss);
      return PopupAction(type: type, customData: Map.unmodifiable(data));
    }
    final value = _string(map!['value'])?.trim();
    if (type != PopupActionType.dismiss && (value == null || value.isEmpty)) {
      return const PopupAction(type: PopupActionType.dismiss);
    }
    return PopupAction(type: type, value: type == PopupActionType.dismiss ? null : value);
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (value != null) 'value': value,
    if (customData != null)
      'customData': [
        for (final MapEntry(:key, :value) in customData!.entries) {'key': key, 'value': value},
      ],
  };
}

class PopupButton {
  const PopupButton({required this.label, required this.style, required this.action});

  final String label;
  final PopupButtonStyle style;
  final PopupAction action;

  /// Null when the action is missing or unknown: a button we can't act on is not drawn.
  static PopupButton? tryParse(Object? json) {
    final map = _map(json);
    if (map == null) return null;
    final action = PopupAction.tryParse(map['action']);
    if (action == null) return null;
    return PopupButton(
      label: _string(map['label']) ?? '',
      style: _enumByName(PopupButtonStyle.values, map['style']) ?? PopupButtonStyle.primary,
      action: action,
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'style': style.name, 'action': action.toJson()};
}

class PopupImage {
  const PopupImage({required this.url, this.alt, this.tapAction});

  /// An image URL, or `gradient:#a,#b` for a placeholder gradient.
  final String url;
  final String? alt;
  final PopupAction? tapAction;

  static PopupImage? tryParse(Object? json) {
    final map = _map(json);
    final url = _string(map?['url'])?.trim();
    if (url == null || url.isEmpty) return null;
    return PopupImage(
      url: url,
      alt: _string(map!['alt']),
      tapAction: PopupAction.tryParse(map['tapAction']),
    );
  }

  bool get isGradient => url.startsWith('gradient:');

  /// The two stops of a `gradient:` url. Bad colours fall back to grey.
  List<Color> get gradientColors {
    final parts = url.substring('gradient:'.length).split(',');
    const fallback = Color(0xFF98A2B3);
    final from = parsePopupColor(parts.isNotEmpty ? parts[0] : null) ?? fallback;
    final to = parsePopupColor(parts.length > 1 ? parts[1] : null) ?? from;
    return [from, to];
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    if (alt != null) 'alt': alt,
    if (tapAction != null) 'tapAction': tapAction!.toJson(),
  };
}

class PopupClose {
  const PopupClose({
    this.show = true,
    this.position = PopupClosePosition.topRight,
    this.tapOutsideToClose = true,
  });

  final bool show;
  final PopupClosePosition position;
  final bool tapOutsideToClose;

  static PopupClose parse(Object? json) {
    final map = _map(json);
    if (map == null) return const PopupClose();
    return PopupClose(
      show: map['show'] is bool ? map['show'] as bool : true,
      position:
          _enumByName(PopupClosePosition.values, map['position']) ?? PopupClosePosition.topRight,
      tapOutsideToClose: map['tapOutsideToClose'] is bool ? map['tapOutsideToClose'] as bool : true,
    );
  }

  Map<String, dynamic> toJson() => {
    'show': show,
    'position': position.name,
    'tapOutsideToClose': tapOutsideToClose,
  };
}

/// `#RGB`, `#RRGGBB` or `#RRGGBBAA` (CSS order). Anything else is null.
Color? parsePopupColor(Object? value) {
  if (value is! String) return null;
  var hex = value.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
  if (hex.length == 8) {
    return Color(int.parse('${hex.substring(6)}${hex.substring(0, 6)}', radix: 16));
  }
  return null;
}

String _colorToHex(Color color) {
  final argb = color.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final alpha = argb >>> 24;
  return alpha == 0xFF ? '#$rgb' : '#$rgb${alpha.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

class PopupTheme {
  const PopupTheme({
    this.background = const Color(0xFFFFFFFF),
    this.text = const Color(0xFF101828),
    this.primary = const Color(0xFF7F56D9),
    this.overlayOpacity = 0.5,
    this.radius = 16,
  });

  final Color background;
  final Color text;
  final Color primary;

  /// 0–1
  final double overlayOpacity;
  final double radius;

  /// Missing or bad values fall back to the builder's light theme, one field at a time.
  static PopupTheme parse(Object? json) {
    const fallback = PopupTheme();
    final map = _map(json);
    if (map == null) return fallback;
    final opacity = map['overlayOpacity'];
    final radius = map['radius'];
    return PopupTheme(
      background: parsePopupColor(map['background']) ?? fallback.background,
      text: parsePopupColor(map['text']) ?? fallback.text,
      primary: parsePopupColor(map['primary']) ?? fallback.primary,
      overlayOpacity:
          opacity is num && opacity.isFinite
              ? opacity.toDouble().clamp(0.0, 1.0)
              : fallback.overlayOpacity,
      radius: radius is num && radius.isFinite && radius >= 0 ? radius.toDouble() : fallback.radius,
    );
  }

  /// Same rule as `isDark` in PopupRenderer.tsx (perceived brightness below 140).
  bool get isDarkBackground {
    final argb = background.toARGB32();
    final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
    return r * 0.299 + g * 0.587 + b * 0.114 < 140;
  }

  Map<String, dynamic> toJson() => {
    'background': _colorToHex(background),
    'text': _colorToHex(text),
    'primary': _colorToHex(primary),
    'overlayOpacity': overlayOpacity,
    'radius': radius,
  };
}

enum PopupDeliveryUnit { hours, days }

/// Campaign-only, carried for completeness: the server applies it, the app never reads it.
class PopupDelivery {
  const PopupDelivery({required this.value, required this.unit, this.customEndsAt, this.timeZone});

  final num value;
  final PopupDeliveryUnit unit;
  final String? customEndsAt;
  final String? timeZone;

  static PopupDelivery? tryParse(Object? json) {
    final map = _map(json);
    final availableFor = _map(map?['availableFor']);
    final value = availableFor?['value'];
    final unit = _enumByName(PopupDeliveryUnit.values, availableFor?['unit']);
    if (value is! num || unit == null) return null;
    return PopupDelivery(
      value: value,
      unit: unit,
      customEndsAt: _string(map!['customEndsAt']),
      timeZone: _string(map['timeZone']),
    );
  }

  Map<String, dynamic> toJson() => {
    'availableFor': {'value': value, 'unit': unit.name},
    if (customEndsAt != null) 'customEndsAt': customEndsAt,
    if (timeZone != null) 'timeZone': timeZone,
  };
}

class PopupContent {
  const PopupContent({
    this.version = 1,
    required this.layout,
    required this.size,
    this.position,
    this.image,
    this.title,
    this.body,
    this.buttons = const [],
    this.close = const PopupClose(),
    this.theme = const PopupTheme(),
    this.autoDismissSec,
    this.mergeTags,
    this.delivery,
  });

  final int version;
  final PopupLayout layout;
  final PopupSize size;

  /// banner / toast only
  final PopupPosition? position;
  final PopupImage? image;

  /// Merge tags arrive already filled by the server; shown as is.
  final String? title;
  final String? body;

  /// 0–2, never more than the layout allows.
  final List<PopupButton> buttons;
  final PopupClose close;
  final PopupTheme theme;

  /// banner / toast only
  final int? autoDismissSec;
  final List<String>? mergeTags;
  final PopupDelivery? delivery;

  PopupLayoutSpec get spec => PopupLayoutSpec.all[layout]!;

  /// Null when the layout is unknown or the version is not 1: skip the pop-up.
  static PopupContent? tryParse(Object? json) {
    final map = _map(json);
    if (map == null) return null;
    final version = map['version'];
    if (version != null && version != 1) return null;
    final layout = _enumByName(PopupLayout.values, map['layout']);
    if (layout == null) return null;
    final spec = PopupLayoutSpec.all[layout]!;

    final size = _enumByName(PopupSize.values, map['size']);
    final position = _enumByName(PopupPosition.values, map['position']);
    final buttons = (map['buttons'] is List ? map['buttons'] as List : const [])
        .map(PopupButton.tryParse)
        .whereType<PopupButton>()
        .take(spec.maxButtons)
        .toList(growable: false);
    final autoDismiss = map['autoDismissSec'];
    final mergeTags = map['mergeTags'];

    return PopupContent(
      layout: layout,
      size: size != null && spec.sizes.contains(size) ? size : spec.sizes.first,
      position:
          spec.positions == null
              ? null
              : (position != null && spec.positions!.contains(position)
                  ? position
                  : spec.positions!.first),
      image: PopupImage.tryParse(map['image']),
      title: spec.hasText ? _string(map['title']) : null,
      body: spec.hasText ? _string(map['body']) : null,
      buttons: buttons,
      close: PopupClose.parse(map['close']),
      theme: PopupTheme.parse(map['theme']),
      // Missing, 0 or less means stay up: the builder saves its "Never" choice as a missing value.
      autoDismissSec:
          !spec.autoDismiss
              ? null
              : (autoDismiss is num && autoDismiss.isFinite && autoDismiss > 0
                  ? autoDismiss.ceil()
                  : null),
      mergeTags: mergeTags is List ? mergeTags.whereType<String>().toList(growable: false) : null,
      delivery: PopupDelivery.tryParse(map['delivery']),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'layout': layout.name,
    'size': size.name,
    if (position != null) 'position': position!.name,
    if (image != null) 'image': image!.toJson(),
    if (title != null) 'title': title,
    if (body != null) 'body': body,
    'buttons': buttons.map((b) => b.toJson()).toList(),
    'close': close.toJson(),
    'theme': theme.toJson(),
    if (autoDismissSec != null) 'autoDismissSec': autoDismissSec,
    if (mergeTags != null) 'mergeTags': mergeTags,
    if (delivery != null) 'delivery': delivery!.toJson(),
  };
}
