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
  static const int _proximityRadiusMeters = 25;

  String _distanceLabel(WorkerNotificationItem notification) {
    if (notification.distance <= 0) return '';
    if (notification.distance <= _proximityRadiusMeters) {
      return 'within ${_proximityRadiusMeters}m';
    }
    return '${notification.distance}m away';
  }

  String _getHazardIconPath(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('slip') || normalized.contains('wet'))
      return 'assets/hazards/slip_falling.svg';
    if (normalized.contains('stair')) return 'assets/hazards/stairs_fall.svg';
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
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    const Color brandTeal = Color(0xFF1B3D3D);
    const Color accentGold = Color(0xFFE6A050);
    final Color unreadColorLight = Colors.blue.shade50;
    final Color unreadColorDark = brandTeal.withValues(alpha: 0.1);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: size.width * 0.044,
          ),
        ),
        backgroundColor: brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.white),
            onSelected: (result) {
              if (result == 'mark_all') {
                workerHazardNotifier.markAllAsRead();
              } else if (result == 'clear_all') {
                _showClearDialog(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mark_all',
                child: Row(
                  children: [
                    Icon(
                      Icons.mark_email_read,
                      size: size.width * 0.053,
                      color: accentGold,
                    ),
                    SizedBox(width: size.width * 0.021),
                    Text('Mark All as Read'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_sweep,
                      size: size.width * 0.053,
                      color: accentGold,
                    ),
                    SizedBox(width: size.width * 0.021),
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
                  Icon(
                    Icons.notifications_off_outlined,
                    size: size.width * 0.213,
                    color: Colors.grey.shade400,
                  ),
                  SizedBox(height: visibleHeight * 0.020),
                  Text(
                    'No hazard notifications yet.',
                    style: TextStyle(
                      fontSize: size.width * 0.045,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: visibleHeight * 0.010),
                  Text(
                    'You\'ll be notified when hazards are nearby.',
                    style: TextStyle(
                      fontSize: size.width * 0.035,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: notifications.length,
            padding: EdgeInsets.fromLTRB(
              size.width * 0.0,
              visibleHeight * 0.010,
              size.width * 0.0,
              visibleHeight * 0.025,
            ),
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
                margin: EdgeInsets.symmetric(
                  horizontal: size.width * 0.025,
                  vertical: visibleHeight * 0.005,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(size.width * 0.027),
                  side: !notification.isRead && !isDark
                      ? BorderSide(
                          color: brandTeal.withValues(alpha: 0.22),
                          width: size.width * 0.003,
                        )
                      : BorderSide.none,
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: size.width * 0.040,
                    vertical: visibleHeight * 0.008,
                  ),
                  leading: Container(
                    width: size.width * 0.128,
                    height: visibleHeight * 0.060,
                    padding: EdgeInsets.all(size.width * 0.025),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: severityColor.withValues(alpha: 0.85),
                        width: size.width * 0.004,
                      ),
                    ),
                    child: SvgPicture.asset(
                      _getHazardIconPath(
                        '${notification.title} ${notification.body}',
                      ),
                      fit: BoxFit.contain,
                    ),
                  ),
                  title: Text(
                    notification.title,
                    style: TextStyle(
                      fontSize: size.width * 0.035,
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                  subtitle: Padding(
                    padding: EdgeInsets.only(top: visibleHeight * 0.005),
                    child: Text(
                      '${notification.body}\n📍 ${_distanceLabel(notification)}\nSeverity: ${notification.severity.toUpperCase()}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.grey.shade300 : Colors.black87,
                        fontSize: size.width * 0.030,
                        fontWeight: notification.isRead
                            ? FontWeight.normal
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  trailing: Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: size.width * 0.030,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  onTap: () => _onNotificationTap(context, notification),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _onNotificationTap(
    BuildContext context,
    dynamic notification,
  ) async {
    workerHazardNotifier.markAsRead(notification.hazardId);

    final freshHazard = await _fetchAndParseHazardData(
      notification.hazardId,
      notification.sourceTable,
      title: notification.title,
      body: notification.body,
      severity: notification.severity,
    );
    if (freshHazard != null) {
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HazardDetailsScreen(hazardData: freshHazard),
          ),
        );
      }
      return;
    }

    final cachedHazard = await _findInCache(notification.hazardId);
    if (cachedHazard != null) {
      final parsed = _parseHazardData(
        cachedHazard,
        notification.sourceTable,
        Supabase.instance.client.auth.currentUser?.id,
      );
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HazardDetailsScreen(hazardData: parsed),
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hazard details unavailable.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _findInCache(String hazardId) async {
    final ongoing = await _hazardRepository.getOngoingHazards();
    final match = ongoing
        .where((h) => h['id']?.toString() == hazardId)
        .toList();
    if (match.isNotEmpty) return match.first;

    final myHazards = await _hazardRepository.getHazards();
    final match2 = myHazards
        .where((h) => h['id']?.toString() == hazardId)
        .toList();
    if (match2.isNotEmpty) return match2.first;

    return null;
  }
  // PARSE — applies to both cached and fresh Supabase data
  // ══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _parseHazardData(
    Map<String, dynamic> rawHazard,
    String sourceTable,
    String? currentUserId,
  ) {
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

    final Map<String, dynamic> passedWorkerInfo =
        reporter ??
        {
          'id': reporterId,
          'first_name':
              rawHazard['reporter_first_name'] ?? rawName.split(' ').first,
          'last_name':
              rawHazard['reporter_last_name'] ??
              (rawName.split(' ').length > 1 ? rawName.split(' ').last : ''),
          'work_type': reporterWorkType,
          'profile_image_url': reporterImageUrl,
        };

    final List officersList =
        rawHazard['all_assigned_officers'] ?? rawHazard['assign_hazards'] ?? [];
    String assignedName = '';
    if (officersList.isNotEmpty) {
      final firstAssignment = officersList.first;
      final firstHse = firstAssignment is Map
          ? firstAssignment['hse_worker']
          : null;
      if (firstHse is Map) {
        assignedName =
            '${firstHse['first_name'] ?? ''} ${firstHse['last_name'] ?? ''}'
                .trim();
      }
    } else if (rawHazard['hse_worker'] != null) {
      final w = rawHazard['hse_worker'];
      assignedName = '${w['first_name']} ${w['last_name']}';
    } else if (rawHazard['hse_first_name'] != null) {
      assignedName =
          '${rawHazard['hse_first_name']} ${rawHazard['hse_last_name']}';
    } else {
      assignedName = rawHazard['assigned_to_name'] ?? 'Not Assigned';
    }
    if (assignedName.isEmpty) {
      assignedName = rawHazard['assigned_to_name'] ?? 'Not Assigned';
    }

    final bool hasFlatInspector =
        rawHazard['hse_first_name'] != null ||
        rawHazard['hse_last_name'] != null ||
        rawHazard['assigned_to_name'] != null;
    final List normalizedOfficersList = officersList.isNotEmpty
        ? officersList
        : (rawHazard['hse_worker'] != null
              ? [rawHazard]
              : (hasFlatInspector
                    ? [
                        {
                          'assigned_at': rawHazard['assigned_at'],
                          'status': rawHazard['status'],
                          'hse_worker': {
                            'id': rawHazard['assigned_to'],
                            'first_name':
                                rawHazard['hse_first_name'] ??
                                rawHazard['assigned_to_name'] ??
                                'Site Inspector',
                            'last_name': rawHazard['hse_last_name'] ?? '',
                            'profile_image_url':
                                rawHazard['hse_profile_image_url'],
                            'designation': rawHazard['hse_designation'],
                            'role': rawHazard['hse_role'] ?? 'hse_worker',
                          },
                        },
                      ]
                    : []));

    final images =
        (rawHazard['image_url'] != null &&
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
      'assign_hazards': normalizedOfficersList,
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
    String hazardId,
    String sourceTable, {
    String? title,
    String? body,
    String? severity,
  }) async {
    final supabase = Supabase.instance.client;
    final currentUserId = supabase.auth.currentUser?.id;

    try {
      Map<String, dynamic>? rawHazard;
      var resolvedSourceTable = sourceTable;

      if (sourceTable == 'assign_hazards') {
        rawHazard = await supabase
            .from('worker_active_hazards_view')
            .select()
            .eq('id', hazardId)
            .maybeSingle();

        if (rawHazard == null) {
          rawHazard = await _fetchAssignedHazardByNotificationFields(
            supabase,
            hazardType: title,
            description: body,
            severity: severity,
          );
        }
      } else {
        rawHazard = await supabase
            .from('hazards')
            .select('*, workers!hazards_worker_id_fkey (*)')
            .eq('id', hazardId)
            .maybeSingle();

        if (rawHazard == null) {
          rawHazard = await _fetchAssignedHazardByNotificationFields(
            supabase,
            hazardType: title,
            description: body,
            severity: severity,
          );
          if (rawHazard != null) {
            resolvedSourceTable = 'assign_hazards';
          }
        }

        // assign_hazards has no original hazards-table id link in this schema.
        // If the row was moved there, the field fallback above returns the
        // newest assigned copy including its hse_worker relation.
      }

      if (rawHazard == null) return null;

      return _parseHazardData(rawHazard, resolvedSourceTable, currentUserId);
    } on SocketException {
      debugPrint('ℹ️ [Notification] Offline — cannot fetch hazard details.');
      return null;
    } catch (e) {
      debugPrint('⚠️ [Notification] Fetch error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchAssignedHazardByNotificationFields(
    SupabaseClient supabase, {
    String? hazardType,
    String? description,
    String? severity,
  }) async {
    final cleanHazardType = hazardType?.trim();
    final cleanDescription = _cleanNotificationBody(description);
    final cleanSeverity = severity?.trim();

    if (cleanHazardType == null || cleanHazardType.isEmpty) return null;

    var query = supabase
        .from('assign_hazards')
        .select('''
          *,
          reporter:worker_id (
            id,
            first_name,
            last_name,
            work_type,
            profile_image_url
          ),
          hse_worker:assigned_to (
            id,
            first_name,
            last_name,
            profile_image_url,
            designation,
            role
          )
        ''')
        .eq('hazard_type', cleanHazardType);

    if (cleanDescription != null && cleanDescription.isNotEmpty) {
      query = query.eq('description', cleanDescription);
    }
    if (cleanSeverity != null && cleanSeverity.isNotEmpty) {
      query = query.eq('severity', cleanSeverity);
    }

    final rows = await query.order('created_at', ascending: false).limit(1);

    if (rows.isEmpty) return null;

    final hazard = Map<String, dynamic>.from(rows.first);
    return hazard;
  }

  static String? _cleanNotificationBody(String? body) {
    final trimmed = body?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    return trimmed
        .replaceAll(RegExp(r'\s*\(within\s+\d+\s*m\)\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*within\s+\d+\s*m\s*$', caseSensitive: false), '')
        .trim();
  }

  String _capitalizeName(String name) {
    if (name.isEmpty) return name;
    return name
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear All Notifications?'),
        content: Text(
          'This will permanently remove all notification history. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              workerHazardNotifier.clearNotifications();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
