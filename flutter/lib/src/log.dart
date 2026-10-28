import 'package:flutter/foundation.dart';

/// Set through `OptikpiInApp.debug`. The package logs nothing else.
bool inAppDebugLogging = false;

void inAppLog(String message) {
  if (inAppDebugLogging) debugPrint('[OptikpiInApp] $message');
}
