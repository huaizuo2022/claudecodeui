import 'package:flutter/foundation.dart';

/// Tiny logging seam so feature code never calls `print` directly and we can
/// silence the app in release builds.
class Logger {
  const Logger(this.tag);

  final String tag;

  void info(String message) {
    if (kDebugMode) debugPrint('[$tag] $message');
  }

  void warn(String message) {
    if (kDebugMode) debugPrint('[WARN][$tag] $message');
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[ERROR][$tag] $message');
      if (error != null) debugPrint('  $error');
      if (stackTrace != null) debugPrint('  $stackTrace');
    }
  }
}
