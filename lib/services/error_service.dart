import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'logger_service.dart';

class ErrorService {
  const ErrorService._();

  static const String _fallbackMessage = 'Unexpected application error';

  static void report(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool fatal = false,
  }) {
    final String errorMessage = _buildMessage(message, error);
    if (kDebugMode) {
      LoggerService.error(errorMessage, error, stackTrace);
      return;
    }

    unawaited(_sendToSupabase(
      message: errorMessage,
      stackTrace: stackTrace,
      fatal: fatal,
    ));
  }

  static void reportFlutterError(FlutterErrorDetails details) {
    report(
      details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
      fatal: details.silent == false,
    );
  }

  static String _buildMessage(String message, Object? error) {
    final String trimmed = message.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return error?.toString() ?? _fallbackMessage;
  }

  static Future<void> _sendToSupabase({
    required String message,
    required StackTrace? stackTrace,
    required bool fatal,
  }) async {
    try {
      final SupabaseClient client = Supabase.instance.client;
      await client.from('error_logs').insert({
        'user_id': client.auth.currentUser?.id,
        'error_message': fatal ? '[fatal] $message' : message,
        'stack_trace': stackTrace?.toString(),
      });
    } catch (e, s) {
      LoggerService.error('Failed to submit error report', e, s);
    }
  }
}
