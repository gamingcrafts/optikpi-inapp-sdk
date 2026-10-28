import 'package:flutter/foundation.dart';

/// Set through `OptikpiPopup.debug`. The package logs nothing else.
bool popupDebugLogging = false;

void popupLog(String message) {
  if (popupDebugLogging) debugPrint('[OptikpiPopup] $message');
}
