import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/shared/hazards/hazard_details_screen.dart';
import 'package:riskradar/shared/theme/app_colors.dart';

import 'hse_worker_hazard_notifier.dart';

enum NotificationAction { markAllRead, clearAll }

class HSEWorkerNotificationScreen extends StatefulWidget {
  const HSEWorkerNotificationScreen({super.key});

  @override
  State<HSEWorkerNotificationScreen> createState() =>
      _HSEWorkerNotificationScreenState();
}

class _HSEWorkerNotificationScreenState
    extends State<HSEWorkerNotificationScreen> {
  final AuthRepository _authRepository = AuthRepository();
  final HazardRepository _hazardRepository = HazardRepository();

  String _getHazardIconPath(String text) {
    final String normalized = text.toLowerCase();
    if (normalized.contains('slip') || normalized.contains('wet')) {
      return 'assets/hazards/slip_falling.svg';
    }
    if (normalized.contains('stair')) {
      return 'assets/hazards/stairs_fall.svg';
    }
    if (normalized.contains('fall') && !normalized.contains('slip')) {
      return 'assets/hazards/falling_objects.svg';
    }
    if (normalized.contains('electric') ||
        normalized.contains('shock') ||
        normalized.contains('electrocution')) {
      return 'assets/hazards/electric_shock.svg';
    }
    if (normalized.contains('explosion') || normalized.contains('blast')) {
      return 'assets/hazards/explosion.svg';
    }
    if (normalized.contains('freeze') ||
        normalized.contains('ice') ||
        normalized.contains('cold')) {
      return 'assets/hazards/freeze.svg';
    }
    if (normalized.contains('high heat') || normalized.contains('heat')) {
      return 'assets/hazards/high_heat.svg';
    }
    if (normalized.contains('temperature')) {
      return 'assets/hazards/high_temperature.svg';
    }
    if (normalized.contains('lift') || normalized.contains('load')) {
      return 'assets/hazards/load_lifting.svg';
    }
    if (normalized.contains('machine') || normalized.contains('crush')) {
      return 'assets/hazards/machine_crush.svg';
    }
    if (normalized.contains('magnet')) {
      return 'assets/hazards/magnetic_field.svg';
    }
    if (normalized.contains('radio') && normalized.contains('active')) {
      return 'assets/hazards/radio_active.svg';
    }
    if (normalized.contains('radio') || normalized.contains('wave')) {
      return 'assets/hazards/radio_waves.svg';
    }
    if (normalized.contains('fire')) {
      return 'assets/hazards/fire_warning.svg';
    }
    return 'assets/hazards/fire_warning.svg';
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'moderate':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    final Color unreadColorLight = AppColors.brandTeal.withValues(alpha: 0.08);
    final Color unreadColorDark = AppColors.brandTeal.withValues(alpha: 0.18);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.brandTeal,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: size.width * 0.044,
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: size.width * 0.020),
            child: ListenableBuilder(
              listenable: workerHazardNotifier,
              builder: (BuildContext context, Widget? _) {
                final int count = workerHazardNotifier.unreadCount;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.notifications, color: Colors.white),
                    if (count > 0)
                      Positioned(
                        right: 0,
                        top: 6,
                        child: Container(
                          padding: EdgeInsets.all(size.width * 0.005),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: size.width * 0.043,
                            minHeight: size.width * 0.043,
                          ),
                          child: Text(
                            count.toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: size.width * 0.025,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          PopupMenuButton<NotificationAction>(
            icon: Icon(Icons.more_vert, color: Colors.white),
            onSelected: (NotificationAction result) {
              if (result == NotificationAction.markAllRead) {
                workerHazardNotifier.markAllAsRead();
              } else if (result == NotificationAction.clearAll) {
                _showClearConfirmation();
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<NotificationAction>>[
                  PopupMenuItem<NotificationAction>(
                    value: NotificationAction.markAllRead,
                    child: Row(
                      children: [
                        Icon(
                          Icons.mark_email_read,
                          size: size.width * 0.053,
                          color: AppColors.accentGold,
                        ),
                        SizedBox(width: size.width * 0.021),
                        Text('Mark All as Read'),
                      ],
                    ),
                  ),
                  PopupMenuItem<NotificationAction>(
                    value: NotificationAction.clearAll,
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_sweep,
                          size: size.width * 0.053,
                          color: AppColors.accentGold,
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
        builder: (BuildContext context, Widget? _) {
          final List<WorkerNotification> notifications = workerHazardNotifier
              .notifications
              .reversed
              .toList();
          final bool isDark = Theme.of(context).brightness == Brightness.dark;

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
                    'You\'ll be notified when tasks are assigned nearby.',
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
              visibleHeight * 0.150,
            ),
            itemBuilder: (BuildContext context, int index) {
              final WorkerNotification notification = notifications[index];
              final String formattedTime = _formatTime(notification.timestamp);
              final Color severityColor = _severityColor(notification.severity);

              final Color cardColor = notification.isRead
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
                          color: AppColors.brandTeal.withValues(alpha: 0.22),
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
                      color: severityColor.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: severityColor.withValues(alpha: 0.85),
                        width: size.width * 0.004,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: severityColor.withValues(alpha: 0.20),
                          blurRadius: size.width * 0.021,
                          offset: Offset(
                            size.width * 0.0,
                            visibleHeight * 0.002,
                          ),
                        ),
                      ],
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
                      '${notification.body}\n${notification.distance}m away\nSeverity: ${notification.severity.toUpperCase()}',
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
                  onTap: () async {
                    workerHazardNotifier.markAsRead(notification.hazardId);

                    final hazardData = await fetchFullHazardData(
                      notification.hazardId,
                      sourceTable: notification.sourceTable,
                    );
                    if (hazardData != null && context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              HazardDetailsScreen(hazardData: hazardData),
                        ),
                      );
                      return;
                    }

                    final cached = await _findHazardInCache(
                      notification.hazardId,
                    );
                    if (cached != null && context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              HazardDetailsScreen(hazardData: cached),
                        ),
                      );
                      _refreshHazardInBackground(
                        notification.hazardId,
                        notification.sourceTable,
                      );
                      return;
                    }

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'You are offline. Task details are not cached yet.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _findHazardInCache(String hazardId) async {
    final assigned = await _hazardRepository.getHseAssignedTasks() ?? [];
    for (final task in assigned) {
      if (task['id']?.toString() == hazardId) {
        return _normaliseCachedHazard(task);
      }
    }

    final resolved = await _hazardRepository.getHseResolvedHazards() ?? [];
    for (final task in resolved) {
      if (task['id']?.toString() == hazardId) {
        return _normaliseCachedHazard(task);
      }
    }

    return null;
  }

  Map<String, dynamic> _normaliseCachedHazard(Map<String, dynamic> task) {
    final Object? worker = task['workers'];
    final Map<dynamic, dynamic>? workerMap = worker is Map ? worker : null;
    final String workerName = workerMap == null
        ? ''
        : '${workerMap['first_name'] ?? ''} ${workerMap['last_name'] ?? ''}'
              .trim();
    final String reporterName = workerName.isNotEmpty
        ? workerName
        : (task['reporter_name'] ??
                  task['worker_name'] ??
                  task['reporter_full_name'] ??
                  task['created_by_name'] ??
                  'Unknown')
              .toString()
              .trim();

    return {
      ...task,
      'workers': worker,
      'reporter_name': reporterName.isEmpty ? 'Unknown' : reporterName,
      'assignment_id': task['id'],
      'assign_hazards': [
        {
          'status': task['status'],
          'assigned_at': task['assigned_at'] ?? task['created_at'],
          'hse_worker': _authRepository.getHseProfile(),
        },
      ],
      'images':
          (task['image_url'] != null &&
              task['image_url'].toString().trim().isNotEmpty)
          ? task['image_url']
                .toString()
                .split(',')
                .map((e) => e.trim())
                .toList()
          : <String>[],
    };
  }

  Future<void> _refreshHazardInBackground(
    String hazardId,
    String sourceTable,
  ) async {
    try {
      await fetchFullHazardData(hazardId, sourceTable: sourceTable);
    } on SocketException {
      // Cached data is already being shown.
    } catch (_) {
      // Non-fatal background refresh.
    }
  }

  void _showClearConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Clear All Notifications?'),
          content: Text(
            'This will permanently remove all notification history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                workerHazardNotifier.clearNotifications();
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Clear All'),
            ),
          ],
        );
      },
    );
  }
}
