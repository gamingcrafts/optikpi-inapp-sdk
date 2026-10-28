/// At most one fetch per `nextCheckAfterSec`, counted from the last successful response.
/// A failed fetch records nothing, so the next fetch moment tries again.
class FetchThrottle {
  static const Duration defaultInterval = Duration(seconds: 300);

  /// The server's value is clamped so a bad response can neither hammer it nor stop fetching.
  static const int minIntervalSec = 30;
  static const int maxIntervalSec = 24 * 60 * 60;

  DateTime? _lastResponseAt;
  Duration _interval = defaultInterval;

  Duration get interval => _interval;

  bool canFetch(DateTime now) =>
      _lastResponseAt == null || now.difference(_lastResponseAt!) >= _interval;

  void recordResponse(DateTime at, int? nextCheckAfterSec) {
    _lastResponseAt = at;
    _interval =
        nextCheckAfterSec == null
            ? defaultInterval
            : Duration(seconds: nextCheckAfterSec.clamp(minIntervalSec, maxIntervalSec));
  }
}
