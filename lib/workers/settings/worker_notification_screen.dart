// lib/workers/screens/worker_notification_screen.dart
// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:riskradar/workers/settings/worker_hazard_notifier.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';

import '../../shared/hazards/hazard_details_screen.dart';

class WorkerNotificationScreen extends StatelessWidget {
  const WorkerNotificationScreen({super.key});

  static final HazardRepository _hazardRepository = HazardRepository();

  String _getHazardIconPath(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('slip') || normalized.contains('wet'))
      return 'assets/hazards/slip_falling.svg';
    if (normalized.contains('stair'))
      return 'assets/hazards/stairs_fall.svg';
    if (normalized.contains('fall') && !normalized.contains('slip'))
      return 'assets/hazards/falling_objects.svg';
    if (normalized.contains('electric') ||
        normalized.contains('shock') ||
        normalized.contains('electrocution'))
      return 'assets/hazards/electric_shock.svg';
    if (normalized.contains('explosion') || normalized.contains('blast'))
      return 'assets/hazards/explosion.svg';
    if (normalized.contains('freeze') ||
        normalized.contains('ice') ||
        normalized.contains('cold'))
      return 'assets/hazards/freeze.svg';
    if (normalized.contains('high heat') || normalized.contains('heat'))
      return 'assets/hazards/high_heat.svg';
    if (normalized.contains('temperature'))
      return 'assets/hazards/high_temperature.svg';
    if (normalized.contains('lift') || normalized.contains('load'))
      return 'assets/hazards/load_lifting.svg';
    if (normalized.contains('machine') || normalized.contains('crush'))
      return 'assets/hazards/machine_crush.svg';
    if (normalized.contains('magnet'))
      return 'assets/hazards/magnetic_field.svg';
    if (normalized.contains('radio') && normalized.contains('active'))
      return 'assets/hazards/radio_active.svg';
    if (normalized.contains('radio') || normalized.contains('wave'))
      return 'assets/hazards/radio_waves.svg';
    if (normalized.contains('fire')) return 'assets/hazards/fire_warning.svg';
    return 'assets/hazards/fire_warning.svg';
  }

  @override
  Widget build(BuildContext context) {
    const Color brandTeal = Color(0xFF1B3D3D);
    final Color unreadColorLight = Colors.blue.shade50;
    final Color unreadColorDark = brandTeal.withValues(alpha: 0.1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hazard Notifications'),
        backgroundColor: brandTeal,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (result) {
              if (result == 'mark_all') {
                workerHazardNotifier.markAllAsRead();
              } else if (result == 'clear_all') {
                _showClearDialog(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'mark_all',
                child: Row(
                  children: [
                    Icon(Icons.mark_email_read,
                        size: 20, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Mark All as Read'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep,
                        size: 20, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Clear All Notifications'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: workerHazardNotifier,
        builder: (context, _) {
          final notifications = workerHazardNotifier.notifications;
          final isDark = Theme.of(context).brightness == Brightness.dark;

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined,
                      size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'No hazard notifications yet.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You\'ll be notified when hazards are nearby.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: notifications.length,
            padding: const EdgeInsets.only(top: 8, bottom: 20),
            itemBuilder: (context, index) {
              final notification = notifications[index];

              final formattedTime =
                  '${notification.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${notification.timestamp.minute.toString().padLeft(2, '0')}';

              Color severityColor = Colors.green;
              if (notification.severity.toLowerCase() == 'moderate') {
                severityColor = Colors.orange;
              } else if (notification.severity.toLowerCase() == 'high') {
                severityColor = Colors.red;
              }

              final cardColor = notification.isRead
                  ? (isDark ? const Color(0xFF1E1E1E) : Colors.white)
                  : (isDark ? unreadColorDark : unreadColorLight);

              return Card(
                elevation: notification.isRead ? 0.5 : 2,
                color: cardColor,
                margin:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: !notification.isRead && !isDark
                      ? BorderSide(color: Colors.blue.shade200, width: 1)
                      : BorderSide.none,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: SvgPicture.asset(
                      _getHazardIconPath(
                          '${notification.title} ${notification.body}'),
                      fit: BoxFit.contain,
                    ),
                  ),
                  title: Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      '${notification.body}\n📍 ${notification.distance}m away\nSeverity: ${notification.severity.toUpperCase()}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade300
                            : Colors.black87,
                        fontWeight: notification.isRead
                            ? FontWeight.normal
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  trailing: Text(
                    formattedTime,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                  onTap: () => _onNotificationTap(
                      context, notification),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NOTIFICATION TAP — cache fallback when offline
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _onNotificationTap(
      BuildContext context, dynamic notification) async {
    workerHazardNotifier.markAsRead(notification.hazardId);

    // ── Step 1: Try cache first (instant, no network needed) ─────────────
    final cachedHazard = await _findInCache(notification.hazardId);
    if (cachedHazard != null) {
      final parsed = _parseHazardData(
          cachedHazard, notification.sourceTable,
          Supabase.instance.client.auth.currentUser?.id);
      if (context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HazardDetailsScreen(hazardData: parsed)));
      }
      // Still try to refresh from Supabase in background silently
      _backgroundFetchAndUpdate(
          notification.hazardId, notification.sourceTable);
      return;
    }

    // ── Step 2: No cache — must fetch from Supabase ───────────────────────
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) =>
      const Center(child: CircularProgressIndicator()),
    );

    final hazardData = await _fetchAndParseHazardData(
        notification.hazardId, notification.sourceTable);

    if (context.mounted) {
      Navigator.pop(context); // close loading dialog

      if (hazardData != null) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                HazardDetailsScreen(hazardData: hazardData)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '📴 You\'re offline. Hazard details unavailable.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // ── Look for hazard in both cached lists ──────────────────────────────────
  Future<Map<String, dynamic>?> _findInCache(String hazardId) async {
    final ongoing = await _hazardRepository.getOngoingHazards();
    final match =
    ongoing.where((h) => h['id']?.toString() == hazardId).toList();
    if (match.isNotEmpty) return match.first;

    final myHazards = await _hazardRepository.getHazards();
    final match2 =
    myHazards.where((h) => h['id']?.toString() == hazardId).toList();
    if (match2.isNotEmpty) return match2.first;

    return null;
  }

  // ── Silent background fetch — updates cache without blocking UI ───────────
  Future<void> _backgroundFetchAndUpdate(
      String hazardId, String sourceTable) async {
    try {
      await _fetchAndParseHazardData(hazardId, sourceTable);
    } catch (_) {
      // Non-fatal — cached data already shown
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PARSE — applies to both cached and fresh Supabase data
  // ══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _parseHazardData(Map<String, dynamic> rawHazard,
      String sourceTable, String? currentUserId) {
    final reporter = rawHazard['workers'] ?? rawHazard['reporter'];
    final String reporterId =
        rawHazard['worker_id'] ?? (reporter != null ? reporter['id'] : '');
    final bool isReportedByMe =
        currentUserId != null && reporterId == currentUserId;

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

    final Map<String, dynamic> passedWorkerInfo = reporter ?? {
      'id': reporterId,
      'first_name':
      rawHazard['reporter_first_name'] ?? rawName.split(' ').first,
      'last_name': rawHazard['reporter_last_name'] ??
          (rawName.split(' ').length > 1 ? rawName.split(' ').last : ''),
      'work_type': reporterWorkType,
      'profile_image_url': reporterImageUrl,
    };

    final List officersList = rawHazard['all_assigned_officers'] ?? [];
    String assignedName = '';
    if (officersList.isNotEmpty) {
      final firstHse = officersList.first['hse_worker'];
      assignedName =
          '${firstHse['first_name'] ?? ''} ${firstHse['last_name'] ?? ''}'
              .trim();
    } else if (rawHazard['hse_worker'] != null) {
      final w = rawHazard['hse_worker'];
      assignedName = '${w['first_name']} ${w['last_name']}';
    } else if (rawHazard['hse_first_name'] != null) {
      assignedName =
      '${rawHazard['hse_first_name']} ${rawHazard['hse_last_name']}';
    } else {
      assignedName = rawHazard['assigned_to_name'] ?? 'Not Assigned';
    }

    final images = (rawHazard['image_url'] != null &&
        rawHazard['image_url'].toString().isNotEmpty)
        ? rawHazard['image_url']
        .toString()
        .split(',')
        .map((e) => e.trim())
        .toList()
        : <String>[];

    return {
      ...rawHazard,
      'workers': passedWorkerInfo,
      'assign_hazards': officersList.isNotEmpty
          ? officersList
          : (rawHazard['hse_worker'] != null ? [rawHazard] : []),
      'hazard_type': rawHazard['hazard_type'] ?? 'No Type',
      'description': rawHazard['description'] ?? 'No description provided.',
      'images': images,
      'reporter_name': isReportedByMe
          ? "Me"
          : '${_capitalizeName(rawName)} ($reporterWorkType)',
      'assigned_name': assignedName,
      'severity': rawHazard['severity'] ?? 'Unknown',
      'status': rawHazard['status'] ?? 'Unknown',
      'created_at': rawHazard['created_at'] ?? rawHazard['assigned_at'],
      'assigned_at': rawHazard['assigned_at'],
      'latitude': rawHazard['latitude'],
      'longitude': rawHazard['longitude'],
      'voice_note_url': rawHazard['voice_note_url'] ?? '',
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SUPABASE FETCH — unchanged logic, now wrapped in SocketException guard
  // ══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> _fetchAndParseHazardData(
      String hazardId, String sourceTable) async {
    final supabase = Supabase.instance.client;
    final currentUserId = supabase.auth.currentUser?.id;

    try {
      Map<String, dynamic>? rawHazard;

      if (sourceTable == 'assign_hazards') {
        rawHazard = await supabase
            .from('worker_active_hazards_view')
            .select()
            .eq('id', hazardId)
            .maybeSingle();
      } else {
        rawHazard = await supabase
            .from('hazards')
            .select('*, workers!hazards_worker_id_fkey (*)')
            .eq('id', hazardId)
            .maybeSingle();
      }

      if (rawHazard == null) return null;

      return _parseHazardData(rawHazard, sourceTable, currentUserId);
    } on SocketException {
      debugPrint('ℹ️ [Notification] Offline — cannot fetch hazard details.');
      return null;
    } catch (e) {
      debugPrint('⚠️ [Notification] Fetch error: $e');
      return null;
    }
  }

  String _capitalizeName(String name) {
    if (name.isEmpty) return name;
    return name.split(' ').map((word) {
      if (word.isEmpty) return '';
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Notifications?'),
        content: const Text(
          'This will permanently remove all notification history. '
              'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              workerHazardNotifier.clearNotifications();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
