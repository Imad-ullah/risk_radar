// lib/hse_workers/notifications/hse_worker_hazard_notifier.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/shared/navigation/app_navigator.dart';
import 'package:riskradar/services/app_config.dart';
import 'package:riskradar/shared/hazards/hazard_details_screen.dart';

// ---------------------------------------------------------------------------
// Helper: Collision-Free ID Generator for UUIDs
// ---------------------------------------------------------------------------
int generateSafeNotificationId(String uuid) {
  int hash = 5381;
  for (int i = 0; i < uuid.length; i++) {
    hash = ((hash << 5) + hash) + uuid.codeUnitAt(i);
  }
  return hash.abs() % 2147483647;
}

// ---------------------------------------------------------------------------
// WorkerNotification model
// ---------------------------------------------------------------------------
class WorkerNotification {
  final String hazardId;
  final String sourceTable;
  final String title;
  final String body;
  final String severity;
  final String notificationType;
  final String? imageUrl;
  final int distance;
  final DateTime timestamp;
  bool isRead;

  WorkerNotification({
    required this.hazardId,
    required this.sourceTable,
    required this.title,
    required this.body,
    required this.severity,
    this.notificationType = WorkerHazardNotifier.assignmentNotificationType,
    this.imageUrl,
    required this.distance,
    required this.timestamp,
    this.isRead = false,
  });
}

// Global singleton
final WorkerHazardNotifier workerHazardNotifier = WorkerHazardNotifier();

// ---------------------------------------------------------------------------
// Background action handler
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> onWorkerActionReceivedMethod(ReceivedAction receivedAction) async {
  try {
    try {
      Supabase.instance.client;
    } catch (e) {
      AppConfig.validateClientConfig();
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
    }
  } catch (e) {
    debugPrint('⚠️ Supabase init failed in background isolate: $e');
  }

  final String? hazardId = receivedAction.payload?['hazardId'];
  final String sourceTable =
      receivedAction.payload?['sourceTable'] ?? 'hazards';
  final String? notificationType = receivedAction.payload?['notificationType'];

  if (hazardId == null) return;

  if (receivedAction.buttonKeyPressed == '' ||
      receivedAction.buttonKeyPressed == 'DETAILS') {
    workerHazardNotifier.markAsRead(
      hazardId,
      notificationType: notificationType,
    );
    final hazardData = await fetchFullHazardData(
      hazardId,
      sourceTable: sourceTable,
    );
    if (hazardData != null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => HazardDetailsScreen(hazardData: hazardData),
          ),
        );
      });
    }
  } else if (receivedAction.buttonKeyPressed == 'NOTED') {
    workerHazardNotifier.markAsRead(
      hazardId,
      notificationType: notificationType,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
String _getReporterInfo(Map<String, dynamic>? r) {
  if (r == null) return 'Unknown Reporter';
  final name = '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
  final role = r['work_type'] ?? r['role'] ?? 'Worker';
  return name.isEmpty ? 'Unknown ($role)' : '$name ($role)';
}

String _getAssignedInfo(Map<String, dynamic>? w) {
  if (w == null) return 'Not Assigned';
  final name = '${w['first_name'] ?? ''} ${w['last_name'] ?? ''}'.trim();
  final desig = w['designation'] ?? w['role'] ?? 'Worker';
  return name.isEmpty ? 'Not Assigned' : '$name ($desig)';
}

Future<Map<String, dynamic>?> fetchFullHazardData(
  String hazardId, {
  required String sourceTable,
}) async {
  final supabase = Supabase.instance.client;
  final currentUserId = supabase.auth.currentUser?.id;
  if (currentUserId == null) return null;

  final fallbackTable = sourceTable == 'hazards' ? 'assign_hazards' : 'hazards';

  const selectQuery = '''
    *,
    reporter:worker_id(id,first_name,last_name,profile_image_url,work_type),
    hse_worker:assigned_to(id,first_name,last_name,profile_image_url,designation,role)
  ''';

  Map<String, dynamic>? hazard;

  try {
    hazard = await supabase
        .from(sourceTable)
        .select(selectQuery)
        .eq('id', hazardId)
        .maybeSingle();
  } catch (e) {
    debugPrint('⚠️ Primary table fetch failed: $e');
  }

  if (hazard == null) {
    try {
      hazard = await supabase
          .from(fallbackTable)
          .select(selectQuery)
          .eq('id', hazardId)
          .maybeSingle();
    } catch (e) {
      debugPrint('⚠️ Fallback table fetch failed: $e');
    }
  }

  if (hazard == null) return null;
  if (!await _canCurrentHseWorkerAccessHazard(hazard, sourceTable)) {
    debugPrint(
      '[HSEWorkerNotifier] Blocked unauthorized hazard details: $hazardId',
    );
    return null;
  }

  return {
    'id': hazard['id'],
    'hazard_type': hazard['hazard_type'],
    'description': hazard['description'],
    'status': hazard['status'],
    'severity': hazard['severity'],
    'assigned_at': hazard['assigned_at'],
    'created_at': hazard['created_at'],
    'latitude': hazard['latitude'],
    'longitude': hazard['longitude'],
    'voice_note_url': hazard['voice_note_url'],
    'reporter_name': _getReporterInfo(hazard['reporter']),
    'assigned_to': _getAssignedInfo(hazard['hse_worker']),
    'workers': hazard['reporter'],
    'assign_hazards': [
      {
        'status': hazard['status'],
        'assigned_at': hazard['assigned_at'] ?? hazard['created_at'],
        'hse_worker': hazard['hse_worker'],
      },
    ],
    'images':
        (hazard['image_url'] as String?)
            ?.split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [],
    'image_url': hazard['image_url'],
  };
}

Future<bool> _canCurrentHseWorkerAccessHazard(
  Map<String, dynamic> hazard,
  String sourceTable,
) async {
  final supabase = Supabase.instance.client;
  final currentUserId = supabase.auth.currentUser?.id;
  if (currentUserId == null) return false;

  try {
    final profile = await supabase
        .from('hse_workers')
        .select('current_site_id, officer_uid')
        .eq('id', currentUserId)
        .maybeSingle();
    final siteId = profile?['current_site_id']?.toString();
    final officerUid = profile?['officer_uid']?.toString();
    final hazardSiteId = hazard['current_site_id']?.toString();
    final hazardOfficerUid = hazard['officer_uid']?.toString();
    final isAssignedToCurrentUser =
        hazard['assigned_to']?.toString() == currentUserId;

    final hasMatchingContext =
        siteId != null &&
        siteId.isNotEmpty &&
        officerUid != null &&
        officerUid.isNotEmpty &&
        hazardSiteId == siteId &&
        hazardOfficerUid == officerUid;

    if (sourceTable == 'assign_hazards') {
      return isAssignedToCurrentUser && hasMatchingContext;
    }

    return hasMatchingContext;
  } catch (e) {
    debugPrint('[HSEWorkerNotifier] Access check failed: $e');
    return false;
  }
}

// ---------------------------------------------------------------------------
// WorkerHazardNotifier Class
// ---------------------------------------------------------------------------
class WorkerHazardNotifier extends ChangeNotifier {
  static const String _notifiedHazardsKeyPrefix = 'hse_notified_hazard_ids_v1_';
  static const int _maxPersistedHazardIds = 1000;
  static const String assignmentNotificationType = 'assignment';
  static const String proximityNotificationType = 'proximity';

  final _supabase = Supabase.instance.client;

  // Subscriptions
  StreamSubscription<Position>? _posSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  RealtimeChannel? _assignmentChannel;
  RealtimeChannel? _hazardInsertChannel;
  Timer? _pollingTimer;

  // Deduplication & State
  final Set<String> _permanentlyNotified = {};
  final Set<String> _processingQueue = {};
  String? _currentWorkerId;
  String? _currentSiteId;
  String? _currentOfficerUid;
  bool _assignmentListenerActive = false;
  bool _liveHazardListenerActive = false;
  bool _isOnline = true;
  Position? _lastKnownPosition;

  // ✅ THE SILENT CACHE: Stores all hazards in memory for offline fallback
  final Map<String, Map<String, dynamic>> _offlineHazardCache = {};

  // Retry tracking
  final Map<String, int> _retryCount = {};
  static const int _maxRetries = 3;

  // Throttling
  DateTime? _lastProximityCheck;
  static const Duration _proximityThrottle = Duration(seconds: 30);
  static const double _proximityRadiusMeters = 25.0;

  final List<WorkerNotification> _notifications = [];
  List<WorkerNotification> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadCount => _notifications
      .where((notification) => !notification.isRead)
      .map(
        (notification) => _notificationKey(
          notification.hazardId,
          notification.notificationType,
        ),
      )
      .where((key) => key.isNotEmpty)
      .toSet()
      .length;

  String _normalizeNotificationType(String? notificationType) {
    final cleanType = notificationType?.trim();
    if (cleanType == null || cleanType.isEmpty) {
      return assignmentNotificationType;
    }
    if (cleanType == 'hse_proximity' || cleanType == 'officer_proximity') {
      return proximityNotificationType;
    }
    return cleanType;
  }

  String _notificationKey(String hazardId, String? notificationType) {
    final normalizedId = hazardId.trim();
    if (normalizedId.isEmpty) return '';
    return '${_normalizeNotificationType(notificationType)}:$normalizedId';
  }

  void clearNotifications() {
    _notifications.clear();
    notifyListeners();
  }

  void markAsRead(String hazardId, {String? notificationType}) {
    var changed = false;
    final normalizedType = notificationType == null
        ? null
        : _normalizeNotificationType(notificationType);
    for (final notification in _notifications) {
      final sameHazard = notification.hazardId.trim() == hazardId.trim();
      final sameType =
          normalizedType == null ||
          _normalizeNotificationType(notification.notificationType) ==
              normalizedType;
      if (sameHazard && sameType && !notification.isRead) {
        notification.isRead = true;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void markAllAsRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  bool isAlreadyNotified(
    String hazardId, {
    String notificationType = assignmentNotificationType,
  }) {
    final key = _notificationKey(hazardId, notificationType);
    return key.isNotEmpty && _permanentlyNotified.contains(key);
  }

  void addNotificationFromFCM(WorkerNotification notification) {
    final hazardId = notification.hazardId.trim();
    final key = _notificationKey(hazardId, notification.notificationType);
    if (hazardId.isEmpty ||
        key.isEmpty ||
        _permanentlyNotified.contains(key) ||
        _notifications.any(
          (n) => _notificationKey(n.hazardId, n.notificationType) == key,
        )) {
      return;
    }

    _permanentlyNotified.add(key);
    unawaited(_persistNotifiedHazards());
    _notifications.insert(0, notification);
    notifyListeners();
  }

  String? get _notifiedHazardsStorageKey {
    final workerId = _currentWorkerId;
    if (workerId == null || workerId.isEmpty) return null;
    return '$_notifiedHazardsKeyPrefix$workerId';
  }

  Future<void> _loadPersistedNotifiedHazards() async {
    final key = _notifiedHazardsStorageKey;
    if (key == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIds = prefs.getStringList(key) ?? const <String>[];
      _permanentlyNotified
        ..clear()
        ..addAll(savedIds.map((id) => id.trim()).where((id) => id.isNotEmpty));
    } catch (e) {
      debugPrint('⚠️ Could not restore HSE notification IDs: $e');
    }
  }

  Future<void> _rememberNotifiedHazard(
    String hazardId, {
    required String notificationType,
  }) async {
    final key = _notificationKey(hazardId, notificationType);
    if (key.isEmpty) return;
    _permanentlyNotified.add(key);
    await _persistNotifiedHazards();
  }

  Future<void> _forgetNotifiedHazard(
    String hazardId, {
    required String notificationType,
  }) async {
    final key = _notificationKey(hazardId, notificationType);
    if (key.isEmpty) return;
    _permanentlyNotified.remove(key);
    await _persistNotifiedHazards();
  }

  Future<void> _persistNotifiedHazards() async {
    final key = _notifiedHazardsStorageKey;
    if (key == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = _permanentlyNotified.toList(growable: false);
      final retainedIds = ids.length <= _maxPersistedHazardIds
          ? ids
          : ids.sublist(ids.length - _maxPersistedHazardIds);
      await prefs.setStringList(key, retainedIds);
    } catch (e) {
      debugPrint('⚠️ Could not persist HSE notification IDs: $e');
    }
  }

  void removeNotification(String hazardId) {
    _notifications.removeWhere((n) => n.hazardId == hazardId);
    notifyListeners();
  }

  void removeInactiveTaskNotifications(Set<String> activeTaskIds) {
    final normalizedActiveIds = activeTaskIds
        .map((hazardId) => hazardId.trim())
        .where((hazardId) => hazardId.isNotEmpty)
        .toSet();
    final previousLength = _notifications.length;
    _notifications.removeWhere(
      (notification) =>
          notification.sourceTable == 'assign_hazards' &&
          !normalizedActiveIds.contains(notification.hazardId.trim()),
    );
    if (_notifications.length != previousLength) {
      notifyListeners();
    }
  }

  Future<void> startChecking() async {
    final workerAuthId = _supabase.auth.currentUser?.id;
    if (workerAuthId == null) return;

    if (_currentWorkerId == workerAuthId &&
        _assignmentListenerActive &&
        _liveHazardListenerActive) {
      return;
    }

    await _cleanupResources();
    _currentWorkerId = workerAuthId;
    await _loadPersistedNotifiedHazards();
    await _loadCurrentSite();

    _supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) stopChecking();
    });

    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    // Initial silent sync to build the offline cache
    _syncOfflineCache();

    _listenForAssignments();
    _listenForLiveHazards();
    _startPollingFallback();
    await _startLocationTracking();
    await _triggerImmediateProximityCheck();
  }

  void stopChecking() {
    _cleanupResources();
  }

  Future<void> _cleanupResources() async {
    _posSub?.cancel();
    _posSub = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    try {
      await _assignmentChannel?.unsubscribe();
      await _hazardInsertChannel?.unsubscribe();
    } catch (_) {}
    _assignmentChannel = null;
    _hazardInsertChannel = null;
    _currentWorkerId = null;
    _currentSiteId = null;
    _currentOfficerUid = null;
    _assignmentListenerActive = false;
    _liveHazardListenerActive = false;
    _processingQueue.clear();
    _permanentlyNotified.clear();
    _retryCount.clear();
    _offlineHazardCache.clear();
    _notifications.clear();
    _lastProximityCheck = null;
    _lastKnownPosition = null;
    notifyListeners();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final nowOnline = results.any((r) => r != ConnectivityResult.none);

    if (!_isOnline && nowOnline) {
      _isOnline = true;

      // Update our offline cache when connection returns
      _syncOfflineCache();

      if (!_assignmentListenerActive) _listenForAssignments();
      if (!_liveHazardListenerActive) _listenForLiveHazards();
      _startPollingFallback();
      _lastProximityCheck = null;
      _triggerImmediateProximityCheck();
    } else if (!nowOnline) {
      _isOnline = false;
    }
  }

  // ✅ SILENT CACHE BUILDER: Downloads all hazards to memory for offline use
  Future<void> _loadCurrentSite() async {
    final workerId = _currentWorkerId;
    if (workerId == null) return;

    try {
      final profile = await _supabase
          .from('hse_workers')
          .select('current_site_id, officer_uid')
          .eq('id', workerId)
          .maybeSingle();
      _currentSiteId = profile?['current_site_id']?.toString();
      _currentOfficerUid = profile?['officer_uid']?.toString();
    } catch (e) {
      debugPrint('[HSEWorkerNotifier] Failed to load current site: $e');
    }
  }

  Future<void> _syncOfflineCache() async {
    if (!_isOnline) return;
    final workerId = _currentWorkerId;
    final siteId = _currentSiteId;
    final officerUid = _currentOfficerUid;

    try {
      final List<dynamic> hazards =
          siteId != null &&
              siteId.isNotEmpty &&
              officerUid != null &&
              officerUid.isNotEmpty
          ? await _supabase
                .from('hazards')
                .select(
                  'id, description, severity, image_url, latitude, longitude, hazard_type, current_site_id, officer_uid',
                )
                .neq('status', 'resolved')
                .eq('current_site_id', siteId)
                .eq('officer_uid', officerUid)
          : <dynamic>[];

      final assigned =
          workerId != null &&
              siteId != null &&
              siteId.isNotEmpty &&
              officerUid != null &&
              officerUid.isNotEmpty
          ? await _supabase
                .from('assign_hazards')
                .select(
                  'id, description, severity, image_url, latitude, longitude, hazard_type, assigned_at, current_site_id, officer_uid, assigned_to',
                )
                .eq('assigned_to', workerId)
                .eq('current_site_id', siteId)
                .eq('officer_uid', officerUid)
          : <dynamic>[];

      _offlineHazardCache.clear();

      for (var h in hazards) {
        h['sourceTable'] = 'hazards';
        _offlineHazardCache[h['id'].toString()] = h;
      }
      for (var a in assigned) {
        if (!_isAssignedHazardRelevant(a)) continue;
        a['sourceTable'] = 'assign_hazards';
        _offlineHazardCache[a['id'].toString()] = a;
      }
      debugPrint(
        '✅ Offline Hazard Cache Synced: ${_offlineHazardCache.length} hazards stored.',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to sync offline cache: $e');
    }
  }

  Future<void> _triggerImmediateProximityCheck() async {
    if (_currentWorkerId == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      _lastKnownPosition = pos;
      await _checkNearbyHazards(pos);
    } catch (_) {}
  }

  Future<void> _startLocationTracking() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      _posSub?.cancel();
      _posSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              distanceFilter: 2, // ✅ REQUIRED FOR 10M TESTING
            ),
          ).listen((pos) {
            if (_currentWorkerId == null) return;
            _lastKnownPosition = pos;

            final now = DateTime.now();
            if (_lastProximityCheck != null &&
                now.difference(_lastProximityCheck!) < _proximityThrottle) {
              return;
            }
            _lastProximityCheck = now;

            _checkNearbyHazards(pos);
          });
    } catch (e) {
      debugPrint('⚠️ Worker location tracking setup error: $e');
    }
  }

  bool _isAssignedHazardRelevant(Map<dynamic, dynamic> hazard) {
    if (hazard['assigned_to']?.toString() != _currentWorkerId) {
      return false;
    }

    final hazardSiteId = hazard['current_site_id']?.toString();
    final hazardOfficerUid = hazard['officer_uid']?.toString();

    return _currentSiteId != null &&
        _currentSiteId!.isNotEmpty &&
        _currentOfficerUid != null &&
        _currentOfficerUid!.isNotEmpty &&
        hazardSiteId == _currentSiteId &&
        hazardOfficerUid == _currentOfficerUid;
  }

  bool _isGeneralHazardRelevant(Map<dynamic, dynamic> hazard) {
    final hazardSiteId = hazard['current_site_id']?.toString();
    final hazardOfficerUid = hazard['officer_uid']?.toString();

    return _currentSiteId != null &&
        _currentSiteId!.isNotEmpty &&
        _currentOfficerUid != null &&
        _currentOfficerUid!.isNotEmpty &&
        hazardSiteId == _currentSiteId &&
        hazardOfficerUid == _currentOfficerUid;
  }

  void _startPollingFallback() {
    _pollingTimer?.cancel();
    if (_currentWorkerId == null) {
      return;
    }

    _pollForNewHazards();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pollForNewHazards();
    });
  }

  Future<void> _pollForNewHazards() async {
    if (!_isOnline || _currentWorkerId == null) {
      return;
    }

    try {
      final workerId = _currentWorkerId!;
      final siteId = _currentSiteId;
      final officerUid = _currentOfficerUid;
      if (siteId == null ||
          siteId.isEmpty ||
          officerUid == null ||
          officerUid.isEmpty) {
        return;
      }

      final assignments = await _supabase
          .from('assign_hazards')
          .select(
            'id, description, severity, image_url, latitude, longitude, hazard_type, assigned_at, current_site_id, officer_uid, assigned_to, status',
          )
          .eq('assigned_to', workerId)
          .eq('current_site_id', siteId)
          .eq('officer_uid', officerUid)
          .not('status', 'in', '(resolved,"resolved by other")')
          .order('assigned_at', ascending: false)
          .limit(10);

      for (final row in assignments) {
        await _handleAssignmentRecord(Map<String, dynamic>.from(row));
      }

      if (_lastKnownPosition != null) {
        await _checkNearbyHazards(_lastKnownPosition!);
      } else {
        await _triggerImmediateProximityCheck();
      }
    } catch (e) {
      debugPrint('[HSEWorkerNotifier] Poll fallback failed: $e');
    }
  }

  Future<void> _handleAssignmentRecord(Map<String, dynamic> newAssign) async {
    final id = newAssign['id']?.toString();
    if (id == null) {
      return;
    }
    if (!_isAssignedHazardRelevant(newAssign)) {
      return;
    }

    newAssign['sourceTable'] = 'assign_hazards';
    _offlineHazardCache[id] = newAssign;

    const notificationType = assignmentNotificationType;
    final notificationKey = _notificationKey(id, notificationType);
    if (_permanentlyNotified.contains(notificationKey)) {
      return;
    }
    if (!_processingQueue.add(notificationKey)) {
      return;
    }

    try {
      await _rememberNotifiedHazard(
        id,
        notificationType: notificationType,
      );

      await _createNotification(
        hazardId: id,
        sourceTable: 'assign_hazards',
        notificationType: notificationType,
        title: 'Assigned Hazard',
        body: newAssign['description'] ?? 'A hazard has been assigned to you.',
        severity: newAssign['severity'] ?? 'moderate',
        imageUrl: newAssign['image_url'],
        distance: 0,
      );
    } catch (e) {
      await _forgetNotifiedHazard(
        id,
        notificationType: notificationType,
      );
      await _scheduleRetry(
        hazardId: id,
        sourceTable: 'assign_hazards',
        notificationType: notificationType,
        title: 'Assigned Hazard',
        body: newAssign['description'] ?? 'A hazard has been assigned to you.',
        severity: newAssign['severity'] ?? 'moderate',
        distance: 0,
        imageUrl: newAssign['image_url'],
      );
    } finally {
      _processingQueue.remove(notificationKey);
    }
  }

  void _listenForAssignments() {
    if (_assignmentListenerActive) return;
    final workerId = _currentWorkerId;
    if (workerId == null) return;

    _assignmentListenerActive = true;
    final channelName =
        'worker-assignments-$workerId-${DateTime.now().millisecondsSinceEpoch}';

    _assignmentChannel = _supabase.channel(channelName);
    _assignmentChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'assign_hazards',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'assigned_to',
        value: workerId,
      ),
      callback: (payload) async {
        final newAssign = payload.newRecord;

        final id = newAssign['id']?.toString();
        if (id == null) return;
        if (!_isAssignedHazardRelevant(newAssign)) return;

        // ✅ Keep offline cache updated with new assignments
        newAssign['sourceTable'] = 'assign_hazards';
        _offlineHazardCache[id] = newAssign;

        const notificationType = assignmentNotificationType;
        final notificationKey = _notificationKey(id, notificationType);
        if (_permanentlyNotified.contains(notificationKey)) return;
        if (!_processingQueue.add(notificationKey)) return;

        try {
          await _rememberNotifiedHazard(
            id,
            notificationType: notificationType,
          );

          await _createNotification(
            hazardId: id,
            sourceTable: 'assign_hazards',
            notificationType: notificationType,
            title: 'Assigned Hazard',
            body:
                newAssign['description'] ??
                'A hazard has been assigned to you.',
            severity: newAssign['severity'] ?? 'moderate',
            imageUrl: newAssign['image_url'],
            distance: 0,
          );
        } catch (e) {
          await _forgetNotifiedHazard(
            id,
            notificationType: notificationType,
          );
          await _scheduleRetry(
            hazardId: id,
            sourceTable: 'assign_hazards',
            notificationType: notificationType,
            title: 'Assigned Hazard',
            body:
                newAssign['description'] ??
                'A hazard has been assigned to you.',
            severity: newAssign['severity'] ?? 'moderate',
            distance: 0,
            imageUrl: newAssign['image_url'],
          );
        } finally {
          _processingQueue.remove(notificationKey);
        }
      },
    );

    _assignmentChannel!.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.channelError) {
        _assignmentListenerActive = false;
        if (_isOnline && _currentWorkerId != null) {
          Future.delayed(const Duration(seconds: 2), _listenForAssignments);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // ✅ THE HYBRID PROXIMITY ENGINE: Online RPC Database OR Offline Local Math
  // ---------------------------------------------------------------------------
  void _listenForLiveHazards() {
    if (_liveHazardListenerActive) return;
    if (_currentWorkerId == null) return;

    _liveHazardListenerActive = true;
    final channelName =
        'hse-live-hazards-${_currentWorkerId!}-${DateTime.now().millisecondsSinceEpoch}';
    final channel = _supabase.channel(channelName);

    Future<void> handlePayload(dynamic payload) async {
      await _handleLiveHazardInsert(
        Map<String, dynamic>.from(payload.newRecord),
      );
    }

    final siteId = _currentSiteId;
    final officerUid = _currentOfficerUid;
    if (siteId == null ||
        siteId.isEmpty ||
        officerUid == null ||
        officerUid.isEmpty) {
      _liveHazardListenerActive = false;
      return;
    }

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'hazards',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'current_site_id',
        value: siteId,
      ),
      callback: handlePayload,
    );

    _hazardInsertChannel = channel;
    channel.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.channelError) {
        _liveHazardListenerActive = false;
        if (_isOnline && _currentWorkerId != null) {
          Future.delayed(const Duration(seconds: 2), _listenForLiveHazards);
        }
      }
    });
  }

  Future<void> _handleLiveHazardInsert(Map<String, dynamic> hazard) async {
    final id = hazard['id']?.toString();
    if (id == null || id.isEmpty) return;

    final status = hazard['status']?.toString().toLowerCase().trim();
    if (status == 'resolved' || status == 'resolved by other') return;

    if (!_isGeneralHazardRelevant(hazard)) {
      return;
    }

    hazard['sourceTable'] = 'hazards';
    _offlineHazardCache[id] = hazard;

    await _notifyIfLiveHazardIsNearby(hazard);
  }

  Future<void> _notifyIfLiveHazardIsNearby(Map<String, dynamic> hazard) async {
    final id = hazard['id']?.toString();
    if (id == null || id.isEmpty) return;
    const notificationType = proximityNotificationType;
    final notificationKey = _notificationKey(id, notificationType);
    if (_permanentlyNotified.contains(notificationKey)) return;

    final lat = _asDouble(hazard['latitude']);
    final lng = _asDouble(hazard['longitude']);
    if (lat == null || lng == null) return;

    final position = await _positionForLiveHazardCheck();
    if (position == null) return;

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      lat,
      lng,
    );
    if (distance > _proximityRadiusMeters) return;

    if (!_processingQueue.add(notificationKey)) return;

    final rawDesc = hazard['description']?.toString().trim();
    final body = rawDesc != null && rawDesc.isNotEmpty
        ? rawDesc
        : 'A new hazard was reported near you. Stay safe!';

    try {
      await _rememberNotifiedHazard(
        id,
        notificationType: notificationType,
      );

      await _createNotification(
        hazardId: id,
        sourceTable: 'hazards',
        notificationType: notificationType,
        title: hazard['hazard_type']?.toString() ?? 'Nearby Hazard',
        body: body,
        severity: hazard['severity']?.toString() ?? 'low',
        imageUrl: hazard['image_url']?.toString(),
        distance: distance.round(),
      );
    } catch (e) {
      await _forgetNotifiedHazard(
        id,
        notificationType: notificationType,
      );
      await _scheduleRetry(
        hazardId: id,
        sourceTable: 'hazards',
        notificationType: notificationType,
        title: hazard['hazard_type']?.toString() ?? 'Nearby Hazard',
        body: body,
        severity: hazard['severity']?.toString() ?? 'low',
        distance: distance.round(),
        imageUrl: hazard['image_url']?.toString(),
      );
    } finally {
      _processingQueue.remove(notificationKey);
    }
  }

  Future<Position?> _positionForLiveHazardCheck() async {
    if (_lastKnownPosition != null) return _lastKnownPosition;

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 5));
      _lastKnownPosition = position;
      return position;
    } catch (e) {
      debugPrint('[HSEWorkerNotifier] Live hazard position check failed: $e');
      return null;
    }
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<void> _checkNearbyHazards(Position position) async {
    final userLat = position.latitude;
    final userLng = position.longitude;
    List<Map<String, dynamic>> nearbyHazards = [];

    // BRANCH 1: ONLINE MODE (Battery Saver - Let DB do the math)
    if (_isOnline) {
      try {
        final params = {
          'user_lat': userLat,
          'user_lng': userLng,
          'radius_meters': _proximityRadiusMeters,
        };

        // Run DB Math
        final results = await Future.wait([
          _supabase
              .rpc('get_nearby_hazards', params: params)
              .timeout(const Duration(seconds: 8)),
          _supabase
              .rpc('get_nearby_assigned_hazards', params: params)
              .timeout(const Duration(seconds: 8)),
        ]);

        for (final h in results[0] as List<dynamic>) {
          final hazard = {
            'sourceTable': 'hazards',
            ...Map<String, dynamic>.from(h),
          };
          if (_isGeneralHazardRelevant(hazard)) {
            nearbyHazards.add(hazard);
          }
        }
        for (final h in results[1] as List<dynamic>) {
          final hazard = {
            'sourceTable': 'assign_hazards',
            ...Map<String, dynamic>.from(h),
          };
          if (_isAssignedHazardRelevant(hazard)) {
            nearbyHazards.add(hazard);
          }
        }
      } catch (e) {
        debugPrint(
          '⚠️ Online DB Math Failed (Weak Signal). Falling back to local offline cache. Error: $e',
        );
        _isOnline = false; // Force fallback for this cycle
      }
    }

    // BRANCH 2: OFFLINE MODE / FALLBACK (Safety Net - Local Device Math)
    if (!_isOnline) {
      debugPrint(
        '📱 Using Local Offline Math. Cache size: ${_offlineHazardCache.length}',
      );
      for (final hazard in _offlineHazardCache.values) {
        final latRaw = hazard['latitude'];
        final lngRaw = hazard['longitude'];
        if (latRaw == null || lngRaw == null) continue;

        final double distance = Geolocator.distanceBetween(
          userLat,
          userLng,
          (latRaw as num).toDouble(),
          (lngRaw as num).toDouble(),
        );

        if (distance <= _proximityRadiusMeters) {
          nearbyHazards.add(hazard);
        }
      }
    }

    // Process whoever won (Online DB or Offline Cache)
    for (final hazard in nearbyHazards) {
      final id = hazard['id']?.toString();
      if (id == null) continue;

      const notificationType = proximityNotificationType;
      final notificationKey = _notificationKey(id, notificationType);
      if (_permanentlyNotified.contains(notificationKey)) continue;
      if (!_processingQueue.add(notificationKey)) continue;

      final sourceTable = hazard['sourceTable'] as String;
      final rawDesc = (hazard['description'] as String?)?.trim();
      final body = (rawDesc != null && rawDesc.isNotEmpty)
          ? rawDesc
          : 'A hazard is nearby. Stay safe!';

      try {
        await _rememberNotifiedHazard(
          id,
          notificationType: notificationType,
        );

        await _createNotification(
          hazardId: id,
          sourceTable: sourceTable,
          notificationType: notificationType,
          title: hazard['hazard_type'] ?? 'Nearby Hazard',
          body: body,
          severity: hazard['severity'] ?? 'low',
          imageUrl: hazard['image_url'],
          distance: _proximityRadiusMeters
              .round(), // Or calculate exact if preferred
        );
      } catch (e) {
        await _forgetNotifiedHazard(
          id,
          notificationType: notificationType,
        );
        await _scheduleRetry(
          hazardId: id,
          sourceTable: sourceTable,
          notificationType: notificationType,
          title: hazard['hazard_type'] ?? 'Nearby Hazard',
          body: body,
          severity: hazard['severity'] ?? 'low',
          distance: _proximityRadiusMeters.round(),
          imageUrl: hazard['image_url'],
        );
      } finally {
        _processingQueue.remove(notificationKey);
      }
    }
  }

  Future<void> _scheduleRetry({
    required String hazardId,
    required String sourceTable,
    required String notificationType,
    required String title,
    required String body,
    required String severity,
    required int distance,
    String? imageUrl,
  }) async {
    final notificationKey = _notificationKey(hazardId, notificationType);
    final attempts = _retryCount[notificationKey] ?? 0;

    if (attempts >= _maxRetries) {
      _retryCount.remove(notificationKey);
      return;
    }

    _retryCount[notificationKey] = attempts + 1;
    final delay = Duration(seconds: (2 << attempts));

    await Future.delayed(delay);

    if (_currentWorkerId == null) return;

    try {
      await _rememberNotifiedHazard(
        hazardId,
        notificationType: notificationType,
      );
      await _createNotification(
        hazardId: hazardId,
        sourceTable: sourceTable,
        notificationType: notificationType,
        title: title,
        body: body,
        severity: severity,
        imageUrl: imageUrl,
        distance: distance,
      );
      _retryCount.remove(notificationKey);
    } catch (e) {
      await _scheduleRetry(
        hazardId: hazardId,
        sourceTable: sourceTable,
        notificationType: notificationType,
        title: title,
        body: body,
        severity: severity,
        imageUrl: imageUrl,
        distance: distance,
      );
    }
  }

  Future<void> _createNotification({
    required String hazardId,
    required String sourceTable,
    required String notificationType,
    required String title,
    required String body,
    required String severity,
    required int distance,
    String? imageUrl,
  }) async {
    final notificationKey = _notificationKey(hazardId, notificationType);
    if (notificationKey.isEmpty ||
        _notifications.any(
          (n) =>
              _notificationKey(n.hazardId, n.notificationType) ==
              notificationKey,
        )) {
      return;
    }

    Color color = Colors.green;
    final sev = severity.toLowerCase();
    if (sev == 'critical' || sev == 'high') {
      color = Colors.red;
    } else if (sev == 'moderate' || sev == 'medium') {
      color = Colors.orange;
    }

    final notifBody = distance > 0 ? '$body\n📍 ${distance}m away' : body;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: generateSafeNotificationId(notificationKey),
        channelKey: 'Hazards Details',
        title: title,
        body: notifBody,
        payload: {
          'hazardId': hazardId,
          'sourceTable': sourceTable,
          'notificationType': _normalizeNotificationType(notificationType),
          'title': title,
          'body': body,
          'severity': severity,
        },
        color: color,
        icon: 'resource://drawable/ic_notification',
        notificationLayout: (imageUrl != null && imageUrl.isNotEmpty)
            ? NotificationLayout.BigPicture
            : NotificationLayout.Default,
        bigPicture: imageUrl,
      ),
      actionButtons: [
        NotificationActionButton(key: 'DETAILS', label: 'View Details'),
      ],
    );

    _notifications.insert(
      0,
      WorkerNotification(
        hazardId: hazardId,
        sourceTable: sourceTable,
        title: title,
        body: body,
        severity: severity,
        notificationType: _normalizeNotificationType(notificationType),
        distance: distance,
        timestamp: DateTime.now(),
        isRead: false,
      ),
    );

    notifyListeners();
  }
}
