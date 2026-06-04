import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase_options.dart';
import '../../officers/notifications/officer_hazard_notifier.dart'
    as officer_notifier;
import '../../shared/hazards/hazard_details_screen.dart';
import '../../shared/navigation/app_navigator.dart';
import '../../shared/services/sos_overlay_service.dart';
import '../app_config.dart';
import '../firebase_messaging_service.dart' as firebase_messaging_service;

class NotificationHandlers {
  @pragma('vm:entry-point')
  static Future<void> firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      await firebase_messaging_service.firebaseMessagingBackgroundHandler(
        message,
      );
      debugPrint('Background notification handled');
    } catch (e) {
      debugPrint('Background handler error: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> onActionReceivedMethod(
    ReceivedAction receivedAction,
  ) async {
    try {
      try {
        AppConfig.validateClientConfig();
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
        );
      } catch (e) {
        debugPrint('Supabase already initialized: $e');
      }

      if (receivedAction.payload?['type']?.toString() == 'SOS') {
        await _openSosOverlay(receivedAction.payload ?? <String, String?>{});
        return;
      }

      final hazardId = receivedAction.payload?['hazardId']?.toString();
      final buttonKey = receivedAction.buttonKeyPressed;
      final sourceTable =
          receivedAction.payload?['sourceTable']?.toString() ?? 'hazards';

      if (hazardId == null) {
        debugPrint('No hazardId in notification payload');
        return;
      }

      debugPrint('Action: $buttonKey for hazard: $hazardId');

      if (buttonKey.isEmpty || buttonKey == 'DETAILS') {
        final hazardData = await NotificationHazardDataService.fetchHazardData(
          hazardId,
          preferredSourceTable: sourceTable,
        );
        if (hazardData != null) {
          await _openHazardDetails(hazardData);
        } else {
          debugPrint('Could not fetch hazard details');
        }
      } else if (buttonKey == 'RESOLVED') {
        final success = await NotificationHazardDataService.updateHazardStatus(
          hazardId,
          'resolved',
        );
        if (success) {
          debugPrint('Hazard marked as resolved');
        } else {
          debugPrint('Failed to mark hazard as resolved');
        }
      }
    } catch (e) {
      debugPrint('Notification action error: $e');
    }
  }

  static Future<void> _openHazardDetails(Map<String, dynamic> hazardData) async {
    for (var i = 0; i < 8; i++) {
      final nav = navigatorKey.currentState;
      if (nav != null) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => HazardDetailsScreen(hazardData: hazardData),
          ),
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    debugPrint('Navigator not ready; could not open hazard details');
  }

  static Future<void> _openSosOverlay(Map<String, String?> payload) async {
    for (var i = 0; i < 8; i++) {
      if (navigatorKey.currentContext != null) {
        await SosOverlayService.showFromPayload(
          Map<String, dynamic>.from(payload),
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    debugPrint('Navigator not ready; could not open SOS overlay');
  }
}

class NotificationHazardDataService {
  static final _supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>?> fetchHazardData(
    String hazardId, {
    required String preferredSourceTable,
  }) async {
    try {
      // Reuse officer notifier mapping and honor the notification payload first.
      final orderedSources = preferredSourceTable == 'assign_hazards'
          ? const ['assign_hazards', 'hazards']
          : const ['hazards', 'assign_hazards'];

      for (final source in orderedSources) {
        final data = await officer_notifier.fetchFullHazardData(
          hazardId,
          sourceTable: source,
        );
        if (data != null) return data;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching hazard data: $e');
      return null;
    }
  }

  static Future<bool> updateHazardStatus(
    String hazardId,
    String newStatus,
  ) async {
    try {
      final hazardsResult = await _supabase
          .from('hazards')
          .update({'status': newStatus})
          .eq('id', hazardId)
          .select();

      if (hazardsResult.isNotEmpty) {
        debugPrint('Updated hazard status in hazards table');
        return true;
      }

      final assignResult = await _supabase
          .from('assign_hazards')
          .update({'status': newStatus})
          .eq('id', hazardId)
          .select();

      if (assignResult.isNotEmpty) {
        debugPrint('Updated hazard status in assign_hazards table');
        return true;
      }

      debugPrint('Hazard not found in either table');
      return false;
    } catch (e) {
      debugPrint('Failed to update hazard status: $e');
      return false;
    }
  }
}
