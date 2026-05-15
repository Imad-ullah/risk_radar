// lib/officers/hazards/officer_hazard_notifier.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:riskradar/shared/hazards/hazard_details_screen.dart';
import 'package:riskradar/shared/navigation/app_navigator.dart';
import 'package:riskradar/services/app_config.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';

final HazardRepository _hazardRepository = HazardRepository();
final SyncRepository _syncRepository = SyncRepository();

// Notification Model for internal storage
class OfficerNotification {
  final String hazardId;
  final String sourceTable;
  final String title;
  final String body;
  final String severity;
  final String? imageUrl;
  final DateTime timestamp;
  bool isRead;

  OfficerNotification({
    required this.hazardId,
    required this.sourceTable,
    required this.title,
    required this.body,
    required this.severity,
    this.imageUrl,
    required this.timestamp,
    this.isRead = false,
  });
}

// Global notifier instance
final OfficerHazardNotifier officerHazardNotifier = OfficerHazardNotifier();

/// Handles notification taps (background / terminated)
@pragma('vm:entry-point')
Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {
  try {
    AppConfig.validateClientConfig();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  } catch (e) {
    debugPrint('Supabase init failed in background: $e');
  }

  final hazardId = receivedAction.payload?['hazardId'];
  final sourceTable = receivedAction.payload?['sourceTable'] ?? 'hazards';
  if (hazardId == null) return;

  officerHazardNotifier.markAsRead(hazardId);

  if (receivedAction.buttonKeyPressed == 'DETAILS') {
    final hazardData = await fetchFullHazardData(hazardId, sourceTable: sourceTable);
    if (hazardData != null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => HazardDetailsScreen(hazardData: hazardData),
          ),
        );
      });
    }
  } else if (receivedAction.buttonKeyPressed == 'RESOLVED') {
    await updateHazardStatus(hazardId, sourceTable, 'resolved');
    officerHazardNotifier.removeNotification(hazardId);
  }
}

// Helper to capitalize names
String _capitalizeName(String name) {
  if (name.isEmpty) return name;
  return name.split(' ').map((word) {
    if (word.isEmpty) return '';
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }).join(' ');
}

// ✅ FIX: Uses the SQL View & perfectly matches the robust parsing from the worker screens!
Future<Map<String, dynamic>?> fetchFullHazardData(String hazardId, {required String sourceTable}) async {
  final supabase = Supabase.instance.client;

  try {
    Map<String, dynamic>? rawHazard;

    // 1. FETCH DATA
    if (sourceTable == 'assign_hazards') {
      // Query the View to get the aggregated officers and reporter info!
      rawHazard = await supabase
          .from('worker_active_hazards_view')
          .select()
          .eq('id', hazardId)
          .maybeSingle();
    } else {
      // Unassigned hazard, query base table
      rawHazard = await supabase
          .from('hazards')
          .select('*, workers!hazards_worker_id_fkey (*)')
          .eq('id', hazardId)
          .maybeSingle();
    }

    rawHazard ??= await _findCachedOfficerHazard(hazardId);
    if (rawHazard == null) return null;

    return _normaliseOfficerHazard(rawHazard);

  } catch (e) {
    debugPrint('Error fetching hazard details: $e');
    final cachedHazard = await _findCachedOfficerHazard(hazardId);
    return cachedHazard == null ? null : _normaliseOfficerHazard(cachedHazard);
  }
}

Future<Map<String, dynamic>?> _findCachedOfficerHazard(String hazardId) async {
  final cachedLists = [
    await _hazardRepository.getOfficerActiveHazards() ?? [],
    await _hazardRepository.getOfficerResolvedHazards() ?? [],
  ];

  for (final list in cachedLists) {
    for (final hazard in list) {
      if (hazard['id']?.toString() == hazardId) {
        return Map<String, dynamic>.from(hazard);
      }
    }
  }
  return null;
}

Map<String, dynamic> _normaliseOfficerHazard(Map<String, dynamic> rawHazard) {
  final reporter = rawHazard['workers'] ?? rawHazard['reporter'];
  final String reporterId =
      rawHazard['worker_id'] ?? (reporter != null ? reporter['id'] : '');

  String rawName = '';
  String? reporterImageUrl;

  if (reporter != null) {
    rawName = '${reporter['first_name']} ${reporter['last_name']}';
    reporterImageUrl = reporter['profile_image_url'];
  } else if (rawHazard['reporter_first_name'] != null) {
    rawName =
        '${rawHazard['reporter_first_name']} ${rawHazard['reporter_last_name']}';
    reporterImageUrl = rawHazard['reporter_image'];
  } else {
    rawName = rawHazard['reporter_name'] ?? 'Unknown User';
    reporterImageUrl = rawHazard['reporter_image'];
  }

  final reporterWorkType =
      reporter?['work_type'] ?? rawHazard['reporter_work_type'] ?? 'Worker';

  final nameParts = rawName.split(' ');
  final Map<String, dynamic> passedWorkerInfo = reporter ??
      {
        'id': reporterId,
        'first_name': rawHazard['reporter_first_name'] ?? nameParts.first,
        'last_name': rawHazard['reporter_last_name'] ??
            (nameParts.length > 1 ? nameParts.last : ''),
        'work_type': reporterWorkType,
        'profile_image_url': reporterImageUrl,
      };

  final List officersList = rawHazard['all_assigned_officers'] ??
      rawHazard['assign_hazards'] ??
      [];
  String assignedName = '';

  if (officersList.isNotEmpty) {
    final firstAssignment = officersList.first;
    final firstHse = firstAssignment is Map ? firstAssignment['hse_worker'] : null;
    if (firstHse is Map) {
      assignedName =
          '${firstHse['first_name'] ?? ''} ${firstHse['last_name'] ?? ''}'
              .trim();
    }
  } else if (rawHazard['hse_worker'] != null) {
    final assignedWorker = rawHazard['hse_worker'];
    assignedName =
        '${assignedWorker['first_name']} ${assignedWorker['last_name']}';
  } else if (rawHazard['hse_first_name'] != null) {
    assignedName = '${rawHazard['hse_first_name']} ${rawHazard['hse_last_name']}';
  }
  if (assignedName.isEmpty) {
    assignedName = rawHazard['assigned_to_name'] ?? 'Not Assigned';
  }

  final images =
      (rawHazard['image_url'] != null && rawHazard['image_url'].toString().isNotEmpty)
          ? rawHazard['image_url'].toString().split(',').map((e) => e.trim()).toList()
          : <String>[];

  final title = rawHazard['hazard_type'] ?? 'No Type';
  final description = rawHazard['description'] ?? 'No description provided.';
  final severity = rawHazard['severity'] ?? 'Unknown';
  final status = rawHazard['status'] ?? 'Unknown';

  return {
    ...rawHazard,
    'workers': passedWorkerInfo,
    'assign_hazards': officersList.isNotEmpty
        ? officersList
        : (rawHazard['hse_worker'] != null ? [rawHazard] : []),
    'hazard_type': title,
    'description': description,
    'images': images,
    'reporter_name': '${_capitalizeName(rawName)} ($reporterWorkType)',
    'assigned_name': assignedName,
    'severity': severity,
    'status': status,
    'created_at': rawHazard['created_at'] ?? rawHazard['assigned_at'],
    'assigned_at': rawHazard['assigned_at'],
    'latitude': rawHazard['latitude'],
    'longitude': rawHazard['longitude'],
    'voice_note_url': rawHazard['voice_note_url'] ?? '',
  };
}

// Update hazard status
Future<void> updateHazardStatus(String hazardId, String table, String status) async {
  final supabase = Supabase.instance.client;
  try {
    if (status == 'resolved') {
      final hazard = await supabase.from(table).select().eq('id', hazardId).single();
      await supabase.from('resolved_hazards').insert({
        ...hazard,
        'status': 'resolved',
        'resolved_at': DateTime.now().toIso8601String(),
      });
      await supabase.from(table).delete().eq('id', hazardId);
    } else {
      await supabase.from(table).update({'status': status}).eq('id', hazardId);
    }
  } on SocketException {
    await _queueHazardStatusOffline(hazardId, table, status);
  } catch (e) {
    debugPrint('Error updating status: $e');
  }
}

Future<void> _queueHazardStatusOffline(
  String hazardId,
  String table,
  String status,
) async {
  final now = DateTime.now().toIso8601String();
  if (status == 'resolved') {
    final hazard = await _findCachedOfficerHazard(hazardId);
    if (hazard == null) return;

    await _syncRepository.enqueueAction(
      id: 'officer_notification_resolve_insert_${hazardId}_${DateTime.now().millisecondsSinceEpoch}',
      table: 'resolved_hazards',
      action: 'insert',
      payload: _resolvedHazardPayload(hazard, now),
    );
    await _syncRepository.enqueueAction(
      id: 'officer_notification_resolve_delete_${hazardId}_${DateTime.now().millisecondsSinceEpoch}',
      table: table,
      action: 'delete',
      payload: {'id': hazardId},
    );
    await _moveCachedHazardToResolved(hazardId, now);
    return;
  }

  await _syncRepository.enqueueAction(
    id: 'officer_notification_status_${hazardId}_${DateTime.now().millisecondsSinceEpoch}',
    table: table,
    action: 'update',
    payload: {
      'id': hazardId,
      'status': status,
    },
  );
}

Map<String, dynamic> _resolvedHazardPayload(
  Map<String, dynamic> hazard,
  String resolvedAt,
) {
  return {
    'id': hazard['id'],
    'worker_id': hazard['worker_id'],
    'hazard_type': hazard['hazard_type'],
    'description': hazard['description'],
    'severity': hazard['severity'],
    'latitude': hazard['latitude'],
    'longitude': hazard['longitude'],
    'status': 'resolved',
    'created_at': hazard['created_at'],
    'image_url': hazard['image_url'],
    'officer_uid': hazard['officer_uid'],
    'voice_note_url': hazard['voice_note_url'],
    'current_site_id': hazard['current_site_id'],
    'assigned_to': hazard['assigned_to'],
    'assigned_at': hazard['assigned_at'],
    'started_at': hazard['started_at'],
    'resolved_at': resolvedAt,
    'resolution_notes': hazard['resolution_notes'],
    'resolution_image_url': hazard['resolution_image_url'],
    'resolution_voice_note_url': hazard['resolution_voice_note_url'],
    'report_number': hazard['report_number'],
  };
}

Future<void> _moveCachedHazardToResolved(
  String hazardId,
  String resolvedAt,
) async {
  final active = await _hazardRepository.getOfficerActiveHazards() ?? [];
  final resolved = await _hazardRepository.getOfficerResolvedHazards() ?? [];
  final index = active.indexWhere((hazard) => hazard['id']?.toString() == hazardId);
  if (index == -1) return;

  final hazard = Map<String, dynamic>.from(active.removeAt(index));
  hazard['status'] = 'resolved';
  hazard['resolved_at'] = resolvedAt;
  resolved.removeWhere((item) => item['id']?.toString() == hazardId);
  resolved.insert(0, hazard);

  await Future.wait([
    _hazardRepository.saveOfficerActiveHazards(active),
    _hazardRepository.saveOfficerResolvedHazards(resolved),
  ]);
}

// Main Notifier Class
class OfficerHazardNotifier extends ChangeNotifier {
  final supabase = Supabase.instance.client;

  StreamSubscription<Position>? _posSub;
  RealtimeChannel? _insertChannel;

  // CRITICAL FIX: Separate tracking for shown notifications vs internal log
  final Set<String> _permanentlyNotified = {}; // Never cleared, persists across sessions
  final Set<String> _processingQueue = {}; // Prevent duplicate processing

  String? _customOfficerUid;
  bool _hazardListenerActive = false;

  // Persistent Notification Log
  final List<OfficerNotification> _notifications = [];
  List<OfficerNotification> get notifications => _notifications;

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void clearNotifications() {
    _notifications.clear();
    // DO NOT clear _permanentlyNotified - this prevents re-notification loop
    notifyListeners();
    debugPrint('✅ Cleared notification log (${_permanentlyNotified.length} hazards still tracked)');
  }

  void markAllAsRead() {
    for (var n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void markAsRead(String hazardId) {
    final index = _notifications.indexWhere((n) => n.hazardId == hazardId && !n.isRead);
    if (index != -1) {
      _notifications[index].isRead = true;
      notifyListeners();
    }
  }

  // Remove from both tracking and notifications
  void removeNotification(String hazardId) {
    _notifications.removeWhere((n) => n.hazardId == hazardId);
    // Keep in _permanentlyNotified to prevent re-notification
    notifyListeners();
  }

  // Public method for FCM to add notifications
  void addNotificationFromFCM(OfficerNotification notification) {
    if (_notifications.any((n) => n.hazardId == notification.hazardId)) {
      debugPrint('⏭️ Skipping duplicate FCM notification: ${notification.hazardId}');
      return;
    }

    _permanentlyNotified.add(notification.hazardId);
    _notifications.add(notification);
    notifyListeners();
  }

  // Public method to check if hazard already notified
  bool isAlreadyNotified(String hazardId) {
    return _permanentlyNotified.contains(hazardId);
  }

  /// Start realtime & location-based monitoring
  Future<void> startChecking() async {
    final officerAuthId = supabase.auth.currentUser?.id;
    if (officerAuthId == null) {
      debugPrint('❌ No logged-in officer.');
      return;
    }

    try {
      final officerData = await supabase
          .from('officers')
          .select('officer_uid')
          .eq('id', officerAuthId)
          .single();

      _customOfficerUid = officerData['officer_uid']?.toString();
    } catch (e) {
      debugPrint('❌ Failed to fetch custom officer_uid for $officerAuthId: $e');
      _customOfficerUid = null;
    }

    if (_customOfficerUid == null) {
      debugPrint('❌ Custom officer ID (officer_uid) not found in officers table.');
      return;
    }

    debugPrint('✅ Using custom officer_uid: $_customOfficerUid');

    _listenForNewHazards();

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        debugPrint('⚠️ Location permission denied.');
        return;
      }
    }

    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((pos) => _checkNearbyHazards(pos, _customOfficerUid!));

    debugPrint('✅ Officer monitoring started.');
  }

  void stopChecking() {
    _posSub?.cancel();
    _insertChannel?.unsubscribe();
    _customOfficerUid = null;
    _hazardListenerActive = false;
    _processingQueue.clear();
    debugPrint('🛑 Officer monitoring stopped.');
  }

  // Listen for ONLY new hazards assigned to this officer
  void _listenForNewHazards() {
    if (_hazardListenerActive) return;
    _hazardListenerActive = true;

    final officerId = _customOfficerUid;
    if (officerId == null) {
      debugPrint('⚠️ Cannot start hazard listener: Officer ID is null.');
      return;
    }

    _insertChannel?.unsubscribe();
    _insertChannel = supabase.channel('hazard-inserts-$officerId');

    _insertChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'hazards',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'officer_uid',
        value: officerId,
      ),
      callback: (payload) async {
        final newHaz = payload.newRecord;

        final id = newHaz['id'].toString();

        if (_permanentlyNotified.contains(id)) {
          debugPrint('⏭️ Skipping already notified hazard: $id');
          return;
        }

        if (_processingQueue.contains(id)) {
          debugPrint('⏳ Already processing hazard: $id');
          return;
        }

        _processingQueue.add(id);

        try {
          await Future.delayed(const Duration(milliseconds: 500));

          final hazardData = await fetchFullHazardData(id, sourceTable: 'hazards');
          if (hazardData == null) {
            debugPrint('⚠️ Skipping notification for hazard $id - not found in database');
            _processingQueue.remove(id);
            return;
          }

          _permanentlyNotified.add(id);

          await _createNotification(
            hazardId: id,
            sourceTable: 'hazards',
            title: 'New Hazard Reported!',
            body: newHaz['description'] ?? 'A new hazard has been reported and assigned to you.',
            severity: newHaz['severity'] ?? 'low',
            imageUrl: newHaz['image_url'],
          );
        } finally {
          _processingQueue.remove(id);
        }
      },
    );

    _insertChannel!.subscribe();
    debugPrint('✅ Listening for new hazards assigned to $officerId.');
  }

  // Proximity-based hazard check
  Future<void> _checkNearbyHazards(Position pos, String customOfficerUid) async {
    try {
      final lat = pos.latitude;
      final lng = pos.longitude;

      final hazards = await supabase
          .from('hazards')
          .select()
          .neq('status', 'resolved')
          .eq('officer_uid', customOfficerUid);

      // ✅ THE FIX: Query the SQL view to perfectly collapse duplicates!
      final assigned = await supabase
          .from('worker_active_hazards_view')
          .select()
          .eq('officer_uid', customOfficerUid);

      final allHazards = [...hazards, ...assigned];

      for (final h in allHazards) {
        final id = h['id'].toString();

        if (_permanentlyNotified.contains(id)) continue;
        if (_processingQueue.contains(id)) continue;

        final dist = Geolocator.distanceBetween(
          lat,
          lng,
          (h['latitude'] as num).toDouble(),
          (h['longitude'] as num).toDouble(),
        );

        if (dist <= 10) {
          _processingQueue.add(id);
          _permanentlyNotified.add(id);

          // Track the correct table origin so the click-through goes to the right place
          final src = h.containsKey('assigned_at') ? 'assign_hazards' : 'hazards';

          await _createNotification(
            hazardId: id,
            sourceTable: src,
            title: 'Nearby Hazard!',
            body: h['description'] ?? 'A hazard is nearby!',
            severity: h['severity'] ?? 'low',
            imageUrl: h['image_url'],
          );

          _processingQueue.remove(id);
        }
      }
    } catch (e) {
      debugPrint('❌ Error in proximity check: $e');
    }
  }

  // Create a local notification
  Future<void> _createNotification({
    required String hazardId,
    required String sourceTable,
    required String title,
    required String body,
    required String severity,
    String? imageUrl,
  }) async {
    if (_notifications.any((n) => n.hazardId == hazardId)) {
      debugPrint('⏭️ Skipping duplicate notification for hazard $hazardId');
      return;
    }

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

    try {
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

      await Future.delayed(const Duration(milliseconds: 100));

      _notifications.add(OfficerNotification(
        hazardId: hazardId,
        sourceTable: sourceTable,
        title: title,
        body: body,
        severity: severity,
        imageUrl: imageUrl,
        timestamp: DateTime.now(),
        isRead: false,
      ));

      notifyListeners();
      debugPrint('✅ Notification created for hazard: $hazardId');

    } catch (e) {
      debugPrint('❌ Error creating notification: $e');
    }
  }
}
