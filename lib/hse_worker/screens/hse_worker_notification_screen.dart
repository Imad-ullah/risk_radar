// lib/hse_workers/screens/hse_worker_notification_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Needed for Status Bar styling
import 'dart:io';
import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/shared/hazards/hazard_details_screen.dart';
import 'hse_worker_hazard_notifier.dart'; // ✅ Contains fetchFullHazardData already!

enum NotificationAction { markAllRead, clearAll }

class HSEWorkerNotificationScreen extends StatefulWidget {
  const HSEWorkerNotificationScreen({super.key});

  @override
  State<HSEWorkerNotificationScreen> createState() => _HSEWorkerNotificationScreenState();
}

class _HSEWorkerNotificationScreenState extends State<HSEWorkerNotificationScreen> {
  final AuthRepository _authRepository = AuthRepository();
  final HazardRepository _hazardRepository = HazardRepository();

  @override
  Widget build(BuildContext context) {
    final Color unreadColorLight = Colors.blue.shade50;
    // Updated to avoid precision loss
    final Color unreadColorDark = Theme.of(context).primaryColor.withValues(alpha: 0.1);

    return Scaffold(
      appBar: AppBar(
        // ✅ 1. Professional Teal Background
        backgroundColor: const Color(0xFF1B3D3D),
        elevation: 0,
        centerTitle: true,

        // ✅ 2. White Status Bar Icons
        systemOverlayStyle: SystemUiOverlayStyle.light,

        // ✅ 3. White Back Arrow & Menu Icons
        iconTheme: const IconThemeData(color: Colors.white),

        // ✅ 4. White Title Text
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),

        actions: [
          // LOGIC: Popup Menu
          PopupMenuButton<NotificationAction>(
            onSelected: (NotificationAction result) {
              if (result == NotificationAction.markAllRead) {
                workerHazardNotifier.markAllAsRead();
              } else if (result == NotificationAction.clearAll) {
                _showClearConfirmation();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<NotificationAction>>[
              const PopupMenuItem<NotificationAction>(
                value: NotificationAction.markAllRead,
                child: Row(
                  children: [
                    Icon(Icons.mark_email_read, size: 20),
                    SizedBox(width: 8),
                    Text('Mark All as Read'),
                  ],
                ),
              ),
              const PopupMenuItem<NotificationAction>(
                value: NotificationAction.clearAll,
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 20),
                    SizedBox(width: 8),
                    Text('Clear All Notifications'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert, color: Colors.white), // Explicit white color
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: workerHazardNotifier,
        builder: (context, child) {
          final notifications = workerHazardNotifier.notifications.reversed.toList();
          final isDark = Theme.of(context).brightness == Brightness.dark;

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ 5. Changed to 'notifications_off' (Bell with Line)
                  Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No task notifications.',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final formattedTime = '${notification.timestamp.hour.toString().padLeft(2, '0')}:${notification.timestamp.minute.toString().padLeft(2, '0')}';

              Color severityColor = Colors.green;
              if (notification.severity.toLowerCase() == 'moderate') severityColor = Colors.orange;
              if (notification.severity.toLowerCase() == 'high') severityColor = Colors.red;

              final cardBackgroundColor = notification.isRead
                  ? Theme.of(context).cardColor
                  : isDark ? unreadColorDark : unreadColorLight;

              return Card(
                elevation: notification.isRead ? 0.5 : 2,
                color: cardBackgroundColor,
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: !notification.isRead && !isDark
                      ? BorderSide(color: Colors.blue.shade300, width: 1)
                      : BorderSide.none,
                ),
                child: ListTile(
                  leading: Icon(Icons.warning_amber, color: severityColor),
                  title: Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
                      color: notification.isRead ? null : Theme.of(context).textTheme.titleMedium?.color,
                    ),
                  ),
                  subtitle: Text(
                    '${notification.body}\nSeverity: ${notification.severity.toUpperCase()}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w500),
                  ),
                  trailing: Text(formattedTime, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  onTap: () async {
                    workerHazardNotifier.markAsRead(notification.hazardId);

                    final cached = await _findHazardInCache(notification.hazardId);
                    if (cached != null && context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => HazardDetailsScreen(hazardData: cached)),
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
                        MaterialPageRoute(builder: (_) => HazardDetailsScreen(hazardData: hazardData)),
                      );
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You are offline. Task details are not cached yet.')),
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
    final worker = task['workers'];
    final reporterName = worker is Map
        ? '${worker['first_name'] ?? ''} ${worker['last_name'] ?? ''}'.trim()
        : task['reporter_name'] ?? 'Unknown';

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
        }
      ],
      'images': (task['image_url'] != null &&
              task['image_url'].toString().trim().isNotEmpty)
          ? task['image_url'].toString().split(',').map((e) => e.trim()).toList()
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
          content: const Text('This will permanently remove all notification history.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
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
