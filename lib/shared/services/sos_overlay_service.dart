import 'package:flutter/material.dart';

import '../navigation/app_navigator.dart';
import '../screens/sos_acknowledge_screen.dart';

class SosOverlayService {
  const SosOverlayService._();

  static bool _isShowing = false;

  static Future<void> showFromPayload(Map<String, dynamic> payload) async {
    if (_isShowing) {
      return;
    }
    _isShowing = true;

    final context = await _waitForContext();
    if (context == null) {
      debugPrint('SOS overlay skipped: navigator context not ready.');
      _isShowing = false;
      return;
    }

    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => SosAcknowledgeScreen(payload: payload),
          fullscreenDialog: true,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('SOS acknowledge navigation error: $e');
      debugPrint(stackTrace.toString());
    } finally {
      _isShowing = false;
    }
  }

  static Future<BuildContext?> _waitForContext() async {
    for (var i = 0; i < 12; i++) {
      final context =
          navigatorKey.currentState?.overlay?.context ??
          navigatorKey.currentContext;
      if (context != null) {
        return context;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }
}
