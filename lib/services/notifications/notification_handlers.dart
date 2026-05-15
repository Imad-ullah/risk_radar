import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase_options.dart';
import '../../shared/hazards/hazard_details_screen.dart';
import '../../shared/navigation/app_navigator.dart';
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

      if (message.data['type'] == 'SOS') {
        AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: 911,
            channelKey: 'sos_alerts_critical',
            title: 'Emergency SOS',
            body: message.data['message'] ?? 'Site Emergency Triggered!',
            notificationLayout: NotificationLayout.BigText,
            category: NotificationCategory.Alarm,
            backgroundColor: Colors.red,
            color: Colors.white,
            wakeUpScreen: true,
            fullScreenIntent: true,
            criticalAlert: true,
          ),
        );
      }

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

      final hazardId = receivedAction.payload?['hazardId'];
      final buttonKey = receivedAction.buttonKeyPressed;

      if (hazardId == null) {
        debugPrint('No hazardId in notification payload');
        return;
      }

      debugPrint('Action: $buttonKey for hazard: $hazardId');

      if (buttonKey == 'DETAILS') {
        final hazardData =
            await NotificationHazardDataService.fetchHazardData(hazardId);
        if (hazardData != null) {
          Future.delayed(const Duration(milliseconds: 300), () {
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => HazardDetailsScreen(hazardData: hazardData),
              ),
            );
          });
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
}

class NotificationHazardDataService {
  static final _supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>?> fetchHazardData(String hazardId) async {
    try {
      final hazard = await _supabase
          .from('hazards')
          .select()
          .eq('id', hazardId)
          .maybeSingle();

      if (hazard != null) {
        debugPrint('Hazard found in hazards table');
        return hazard;
      }

      debugPrint('Trying assign_hazards table...');
      final assignedHazard = await _supabase
          .from('assign_hazards')
          .select()
          .eq('id', hazardId)
          .maybeSingle();

      if (assignedHazard != null) {
        debugPrint('Hazard found in assign_hazards table');
      }

      return assignedHazard;
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
