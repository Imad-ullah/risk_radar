// lib/services/firebase_messaging_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:riskradar/officers/notifications/officer_hazard_notifier.dart';

/// CRITICAL: This must be a top-level function for background execution
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message received: ${message.messageId}');

  // Initialize AwesomeNotifications if needed
  await AwesomeNotifications().initialize(
    'resource://drawable/ic_notification',
    [
      NotificationChannel(
        channelKey: 'Hazards Details',
        channelName: 'Hazard Notifications',
        channelDescription: 'Notifications for hazard alerts',
        defaultColor: Colors.orange,
        importance: NotificationImportance.High,
        playSound: true,
      ),
    ],
  );

  // Extract data from FCM message
  final data = message.data;
  final hazardId = data['hazard_id'] ?? '';
  final title = data['title'] ?? 'New Hazard Alert';
  final body = data['body'] ?? 'A new hazard requires your attention';
  final severity = data['severity'] ?? 'low';
  final imageUrl = data['image_url'];
  final sourceTable = data['source_table'] ?? 'hazards';

  if (hazardId.isEmpty) return;

  // Determine notification color based on severity
  Color color = Colors.grey;
  switch (severity.toLowerCase()) {
    case 'high':
      color = Colors.red;
      break;
    case 'moderate':
      color = Colors.orange;
      break;
    case 'low':
      color = Colors.green;
      break;
  }

  // Create notification even when app is terminated
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: hazardId.hashCode,
      channelKey: 'Hazards Details',
      title: title,
      body: body,
      payload: {'hazardId': hazardId, 'sourceTable': sourceTable},
      color: color,
      icon: 'resource://drawable/ic_notification',
      notificationLayout: (imageUrl != null && imageUrl.isNotEmpty)
          ? NotificationLayout.BigPicture
          : NotificationLayout.Default,
      bigPicture: imageUrl,
    ),
    actionButtons: [
      NotificationActionButton(
        key: 'DETAILS',
        label: 'Details',
        actionType: ActionType.Default,
      ),
      NotificationActionButton(
        key: 'NOTED',
        label: 'Noted',
        actionType: ActionType.DismissAction,
      ),
      NotificationActionButton(
        key: 'RESOLVED',
        label: 'Is Resolved',
        actionType: ActionType.Default,
      ),
    ],
  );

  debugPrint('Background notification created for hazard: $hazardId');
}

/// Foreground message handler
class FirebaseMessagingService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Initialize FCM and request permissions
  static Future<void> initialize() async {
    // Request permission for iOS
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('FCM Permission status: ${settings.authorizationStatus}');

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages (app in background but not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    // Check if app was opened from terminated state via notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleBackgroundMessage(initialMessage);
    }
  }

  /// Handle messages when app is in foreground
  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message: ${message.notification?.title}');

    final data = message.data;
    final hazardId = data['hazard_id'] ?? '';
    final title = data['title'] ?? message.notification?.title ?? 'New Hazard';
    final body = data['body'] ?? message.notification?.body ?? 'Check hazard details';
    final severity = data['severity'] ?? 'low';
    final imageUrl = data['image_url'];
    final sourceTable = data['source_table'] ?? 'hazards';

    if (hazardId.isEmpty) return;

    // Check if already notified to prevent duplicates
    if (officerHazardNotifier.isAlreadyNotified(hazardId)) {
      debugPrint('Skipping duplicate FCM notification for: $hazardId');
      return;
    }

    // Create notification object
    final notification = OfficerNotification(
      hazardId: hazardId,
      sourceTable: sourceTable,
      title: title,
      body: body,
      severity: severity,
      imageUrl: imageUrl,
      timestamp: DateTime.now(),
      isRead: false,
    );

    // Add to internal log using public method
    officerHazardNotifier.addNotificationFromFCM(notification);

    // Show local notification
    Color color = Colors.grey;
    switch (severity.toLowerCase()) {
      case 'high':
        color = Colors.red;
        break;
      case 'moderate':
        color = Colors.orange;
        break;
      case 'low':
        color = Colors.green;
        break;
    }

    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: hazardId.hashCode,
        channelKey: 'Hazards Details',
        title: title,
        body: body,
        payload: {'hazardId': hazardId, 'sourceTable': sourceTable},
        color: color,
        icon: 'resource://drawable/ic_notification',
        notificationLayout: (imageUrl != null && imageUrl.isNotEmpty)
            ? NotificationLayout.BigPicture
            : NotificationLayout.Default,
        bigPicture: imageUrl,
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'DETAILS',
          label: 'Details',
          actionType: ActionType.Default,
        ),
        NotificationActionButton(
          key: 'NOTED',
          label: 'Noted',
          actionType: ActionType.DismissAction,
        ),
        NotificationActionButton(
          key: 'RESOLVED',
          label: 'Is Resolved',
          actionType: ActionType.Default,
        ),
      ],
    );
  }

  /// Handle messages when app opens from background notification tap
  static void _handleBackgroundMessage(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.messageId}');

    final hazardId = message.data['hazard_id'];
    if (hazardId != null) {
      // Navigate to hazard details or mark as read
      officerHazardNotifier.markAsRead(hazardId);
    }
  }
}