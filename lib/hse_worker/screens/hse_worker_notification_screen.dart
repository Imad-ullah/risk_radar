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
    final Color unreadColorLight = AppColors.brandTeal.withValues(alpha: 0.08);
    final Color unreadColorDark = AppColors.brandTeal.withValues(alpha: 0.18);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.brandTeal,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text(
          'Hazard Notifications',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ListenableBuilder(
              listenable: workerHazardNotifier,
              builder: (BuildContext context, Widget? _) {
                final int count = workerHazardNotifier.unreadCount;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.notifications, color: Colors.white),
                    if (count > 0)
                      Positioned(
                        right: 0,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            count.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
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
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (NotificationAction result) {
              if (result == NotificationAction.markAllRead) {
                workerHazardNotifier.markAllAsRead();
              } else if (result == NotificationAction.clearAll) {
                _showClearConfirmation();
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<NotificationAction>>[
                  const PopupMenuItem<NotificationAction>(
                    value: NotificationAction.markAllRead,
                    child: Row(
                      children: [
                        Icon(
                          Icons.mark_email_read,
                          size: 20,
                          color: Colors.black54,
                        ),
                        SizedBox(width: 8),
                        Text('Mark All as Read'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<NotificationAction>(
                    value: NotificationAction.clearAll,
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_sweep,
                          size: 20,
                          color: Colors.black54,
                        ),
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
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No hazard notifications yet.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You\'ll be notified when tasks are assigned nearby.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: notifications.length,
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
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
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: !notification.isRead && !isDark
                      ? BorderSide(
                          color: AppColors.brandTeal.withValues(alpha: 0.22),
                          width: 1,
                        )
                      : BorderSide.none,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: severityColor.withValues(alpha: 0.85),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: severityColor.withValues(alpha: 0.20),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
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
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${notification.body}\n${notification.distance}m away\nSeverity: ${notification.severity.toUpperCase()}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.grey.shade300 : Colors.black87,
                        fontWeight: notification.isRead
                            ? FontWeight.normal
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  trailing: Text(
                    formattedTime,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  onTap: () async {
                    workerHazardNotifier.markAsRead(notification.hazardId);

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
                    } else if (context.mounted) {
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
    final String reporterName = worker is Map<String, dynamic>
        ? '${worker['first_name'] ?? ''} ${worker['last_name'] ?? ''}'.trim()
        : task['reporter_name']?.toString() ?? 'Unknown';

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
          title: const Text('Clear All Notifications?'),
          content: const Text(
            'This will permanently remove all notification history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                workerHazardNotifier.clearNotifications();
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );
  }
}
