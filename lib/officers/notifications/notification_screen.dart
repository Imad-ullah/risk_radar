import 'package:flutter/material.dart';
import 'package:riskradar/officers/notifications/officer_hazard_notifier.dart';
import '../../shared/hazards/hazard_details_screen.dart';

enum NotificationAction { markAllRead, clearAll }

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    // ✅ REMOVED clearNotifications() - this was causing the loop!
    // The screen should display existing notifications, not clear them
  }

  @override
  Widget build(BuildContext context) {
    final Color unreadColorLight = Colors.blue.shade50;
    final Color unreadColorDark = Theme.of(context).primaryColor.withValues(alpha: 0.1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications Log'),
        actions: [
          // Notification icon with badge
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ListenableBuilder(
              listenable: officerHazardNotifier,
              builder: (context, _) {
                final count = officerHazardNotifier.unreadCount;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.notifications),
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
          // Popup menu for global actions
          PopupMenuButton<NotificationAction>(
            onSelected: (NotificationAction result) {
              if (result == NotificationAction.markAllRead) {
                officerHazardNotifier.markAllAsRead();
              } else if (result == NotificationAction.clearAll) {
                // ✅ Show confirmation dialog before clearing
                _showClearConfirmation();
              }
            },
            itemBuilder: (BuildContext context) =>
            <PopupMenuEntry<NotificationAction>>[
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
            icon: const Icon(Icons.more_vert),
            tooltip: 'More Actions',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: officerHazardNotifier,
        builder: (context, child) {
          final notifications = officerHazardNotifier.notifications.reversed.toList();
          final isDark = Theme.of(context).brightness == Brightness.dark;

          if (notifications.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No hazard notifications.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final formattedTime =
                  '${notification.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${notification.timestamp.minute.toString().padLeft(2, '0')}';

              // Determine color based on severity
              Color severityColor = Colors.green;
              if (notification.severity.toLowerCase() == 'moderate') {
                severityColor = Colors.orange;
              } else if (notification.severity.toLowerCase() == 'high') {
                severityColor = Colors.red;
              }

              // Card background for unread notifications
              final cardBackgroundColor = notification.isRead
                  ? Theme.of(context).cardColor
                  : isDark
                  ? unreadColorDark
                  : unreadColorLight;

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
                    style: TextStyle(
                      fontWeight: notification.isRead ? FontWeight.normal : FontWeight.w500,
                    ),
                  ),
                  trailing: Text(
                    formattedTime,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  onTap: () async {
                    // ✅ Mark as read when tapped
                    officerHazardNotifier.markAsRead(notification.hazardId);

                    final hazardData = await fetchFullHazardData(
                      notification.hazardId,
                      sourceTable: notification.sourceTable,
                    );
                    if (hazardData != null && context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HazardDetailsScreen(hazardData: hazardData),
                        ),
                      );
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not load hazard details. It may be resolved or deleted.'),
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

  // Confirmation dialog before clearing all notifications
  void _showClearConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Clear All Notifications?'),
          content: const Text(
            'This will permanently remove all notification history. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                officerHazardNotifier.clearNotifications();
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


