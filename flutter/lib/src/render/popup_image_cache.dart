import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../log.dart';

/// A small in-memory cache of image bytes. The controller loads a pop-up's image before it shows
/// the pop-up, so it never appears with an empty image area. Each pop-up is shown once per device,
/// so a disk cache would rarely be hit again; that is why this is not `cached_network_image`
/// (which also brings sqflite and path_provider native plugins).
class PopupImageCache {
  PopupImageCache({http.Client? client, this.maxEntries = 8}) : _client = client ?? http.Client();

  final http.Client _client;
  final int maxEntries;
  static const Duration timeout = Duration(seconds: 8);

  final LinkedHashMap<String, Uint8List> _bytes = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _loading = {};

  Uint8List? peek(String url) => _bytes[url];

  /// Null when the image can't be loaded; the pop-up then shows without it.
  Future<Uint8List?> load(String url) {
    final cached = _bytes.remove(url);
    if (cached != null) {
      _bytes[url] = cached; // most recently used last
      return Future.value(cached);
    }
    // A block body, not `=> _loading.remove(url)`: that returns this same future, and
    // whenComplete waits for a future its callback returns, so the load would never complete.
    return _loading[url] ??= _fetch(url).whenComplete(() {
      _loading.remove(url);
    });
  }

  Future<Uint8List?> _fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) return null;
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        inAppLog('image HTTP ${response.statusCode}: $url');
        return null;
      }
      _bytes[url] = response.bodyBytes;
      while (_bytes.length > maxEntries) {
        _bytes.remove(_bytes.keys.first);
      }
      return response.bodyBytes;
    } catch (error) {
      inAppLog('image failed: $url ($error)');
      return null;
    }
  }
}
