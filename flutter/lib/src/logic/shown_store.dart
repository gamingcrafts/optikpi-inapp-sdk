import 'package:shared_preferences/shared_preferences.dart';

/// Pop-up ids already drawn on this device, so a refetch never shows one again.
/// Kept across logins: the server only ever returns a pop-up to the player it was sent to.
class ShownStore {
  ShownStore({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  static const String key = 'optikpi_inapp.shown';

  /// Oldest ids drop off first. Server-side expiry (30 days at most) makes old ids irrelevant.
  static const int maxIds = 500;

  final Future<SharedPreferences> Function() _prefs;
  Set<String>? _cache;

  Future<Set<String>> load() async {
    if (_cache != null) return _cache!;
    final prefs = await _prefs();
    return _cache ??= (prefs.getStringList(key) ?? const []).toSet();
  }

  Future<void> markShown(String id) async {
    final ids = await load();
    if (!ids.add(id)) return;
    final list = ids.toList();
    if (list.length > maxIds) {
      final drop = list.sublist(0, list.length - maxIds);
      ids.removeAll(drop);
    }
    final prefs = await _prefs();
    await prefs.setStringList(key, ids.toList());
  }
}
