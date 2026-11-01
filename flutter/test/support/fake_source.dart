import 'dart:async';
import 'dart:typed_data';

import 'package:optikpi_inapp/optikpi_inapp.dart';
import 'package:optikpi_inapp/src/render/popup_image_cache.dart';

/// A PopupSource that records what it is asked and answers what the test sets.
class FakeSource extends PopupSource {
  FakeSource({this.result = const PopupFetchResult(popups: [])});

  PopupFetchResult result;
  int fetches = 0;
  int failFetches = 0;

  /// Answers every fetch and send with this HTTP status until cleared.
  int? refuseWith;

  /// Tokens seen, in order, on fetch and on send.
  final List<String> fetchTokens = [];
  final List<String> sendTokens = [];
  Future<void>? fetchGate;

  final List<List<PopupEvent>> sent = [];
  final List<String> sentFor = [];
  int failSends = 0;
  Future<void>? sendGate;

  /// Players whose batches the server refuses (an HTTP error, not offline).
  final Set<String> refuse = {};

  List<PopupEvent> get sentEvents => sent.expand((b) => b).toList();

  @override
  Future<PopupFetchResult> fetch(PopupRequestContext context) async {
    fetches++;
    fetchTokens.add(context.playerToken);
    final status = refuseWith;
    if (fetchGate != null) await fetchGate;
    if (status != null) throw PopupHttpException(status, '/v1/inapp/popups');
    if (failFetches > 0) {
      failFetches--;
      throw Exception('offline');
    }
    return result;
  }

  @override
  Future<void> sendEvents(PopupRequestContext context, List<PopupEvent> events) async {
    sendTokens.add(context.playerToken);
    if (refuseWith != null) throw PopupHttpException(refuseWith!, '/ingest/popup');
    if (sendGate != null) await sendGate;
    if (failSends > 0) {
      failSends--;
      throw Exception('offline');
    }
    if (refuse.contains(context.playerId)) throw PopupHttpException(403, '/ingest/popup');
    sent.add(List.of(events));
    sentFor.add(context.playerId);
  }
}

PopupContent content(PopupLayout layout, {String? title, int? autoDismissSec}) {
  final spec = PopupLayoutSpec.all[layout]!;
  return PopupContent(
    layout: layout,
    size: spec.sizes.first,
    position: spec.positions?.first,
    title: spec.hasText ? (title ?? 'Title ${layout.name}') : null,
    body: spec.hasText ? 'Body' : null,
    image: const PopupImage(url: 'gradient:#7F56D9,#F04438'),
    buttons: [
      if (spec.maxButtons > 0)
        const PopupButton(
          label: 'Go',
          style: PopupButtonStyle.primary,
          action: PopupAction(type: PopupActionType.deeplink, value: 'app://cashier'),
        ),
      if (spec.maxButtons > 1)
        const PopupButton(
          label: 'Later',
          style: PopupButtonStyle.secondary,
          action: PopupAction(type: PopupActionType.dismiss),
        ),
    ],
    autoDismissSec: autoDismissSec,
  );
}

InAppPopup inApp(
  String id, {
  PopupLayout layout = PopupLayout.modal,
  DateTime? createdAt,
  DateTime? expiresAt,
  int? autoDismissSec,
}) => InAppPopup(
  id: id,
  trackingId: 'trk-$id',
  createdAt: createdAt ?? DateTime.utc(2026, 10, 1),
  expiresAt: expiresAt,
  content: content(layout, title: 'Popup $id', autoDismissSec: autoDismissSec),
);

/// A pop-up whose image is a real URL, so the controller waits for it before showing.
InAppPopup inAppWithImage(
  String id, {
  PopupLayout layout = PopupLayout.modal,
  DateTime? createdAt,
}) {
  final json = inApp(id, layout: layout).content.toJson();
  return InAppPopup(
    id: id,
    trackingId: 'trk-$id',
    createdAt: createdAt ?? DateTime.utc(2026, 10, 1),
    content:
        PopupContent.tryParse({
          ...json,
          'image': {'url': 'https://img.test/$id.png'},
        })!,
  );
}

/// Image loads wait until [release]; they then fail (null), which shows the pop-up without it.
class GatedImages extends PopupImageCache {
  Completer<void> gate = Completer<void>();
  int loads = 0;

  void release() => gate.complete();

  @override
  Future<Uint8List?> load(String url) async {
    loads++;
    await gate.future;
    return null;
  }
}
