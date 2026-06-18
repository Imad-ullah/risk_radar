import 'package:flutter/foundation.dart';

class LoggerService {
  const LoggerService._();

  static void info(String message) {
    debugPrint('[INFO] $message');
  }

  static void warning(String message, [Object? error]) {
    debugPrint('[WARN] $message${_formatError(error)}');
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[ERROR] $message${_formatError(error)}');
    if (stackTrace != null) debugPrint(stackTrace.toString());
  }

  static String _formatError(Object? error) => error == null ? '' : ' | $error';
}
