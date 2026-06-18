import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:riskradar/officers/notifications/officer_hazard_notifier.dart';
import 'package:riskradar/shared/hazards/hazard_details_screen.dart';

enum NotificationAction { markAllRead, clearAll }

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  String _getHazardIconPath(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('slip') || normalized.contains('wet')) {
      return 'assets/hazards/slip_falling.svg';
    }
    if (normalized.contains('stair')) return 'assets/hazards/stairs_fall.svg';
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
    if (normalized.contains('fire')) return 'assets/hazards/fire_warning.svg';
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

  @override
  Widget build(BuildContext context) {
    R.init(context);
    const Color brandTeal = Color(0xFF1B3D3D);
    final Color unreadColorLight = Colors.blue.shade50;
    final Color unreadColorDark = brandTeal.withValues(alpha: 0.1);

    return Scaffold(
      appBar: AppBar(
        title: Text('Hazard Notifications'),
        backgroundColor: brandTeal,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: R.blockH * 2),
            child: ListenableBuilder(
              listenable: officerHazardNotifier,
              builder: (context, _) {
                final count = officerHazardNotifier.unreadCount;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.notifications, color: Colors.white),
                    if (count > 0)
                      Positioned(
                        right: 0,
                        top: 6,
                        child: Container(
                          padding: EdgeInsets.all(R.blockH * 0.5),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            count.toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: R.blockH * 2.5,
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
                officerHazardNotifier.markAllAsRead();
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
                          size: 20,
                          color: Colors.black54,
                        ),
                        SizedBox(width: R.blockH * 2.133),
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
                          size: 20,
                          color: Colors.black54,
                        ),
                        SizedBox(width: R.blockH * 2.133),
                        Text('Clear All Notifications'),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: officerHazardNotifier,
        builder: (context, child) {
          final notifications = officerHazardNotifier.notifications.reversed
              .toList();
          final isDark = Theme.of(context).brightness == Brightness.dark;

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
                  SizedBox(height: R.blockV * 2),
                  Text(
                    'No hazard notifications yet.',
                    style: TextStyle(
                      fontSize: R.blockH * 4.5,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: R.blockV * 1),
                  Text(
                    'You\'ll be notified when hazards are nearby.',
                    style: TextStyle(
                      fontSize: R.blockH * 3.5,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: notifications.length,
            // Extra bottom spacing so last card never sticks behind bottom app area.
            padding: EdgeInsets.fromLTRB(
              R.blockH * 0,
              R.blockV * 1,
              R.blockH * 0,
              R.blockV * 15,
            ),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final severityColor = _severityColor(notification.severity);
              final formattedTime =
                  '${notification.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${notification.timestamp.minute.toString().padLeft(2, '0')}';

              final cardColor = notification.isRead
                  ? (isDark ? const Color(0xFF1E1E1E) : Colors.white)
                  : (isDark ? unreadColorDark : unreadColorLight);

              return Card(
                elevation: notification.isRead ? 0.5 : 2,
                color: cardColor,
                margin: EdgeInsets.symmetric(
                  horizontal: R.blockH * 2.5,
                  vertical: R.blockV * 0.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: !notification.isRead && !isDark
                      ? BorderSide(color: Colors.blue.shade200, width: 1)
                      : BorderSide.none,
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    width: R.blockH * 12.8,
                    height: R.blockV * 6,
                    padding: EdgeInsets.all(R.blockH * 2.5),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: severityColor.withValues(alpha: 0.85),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: severityColor.withValues(alpha: 0.22),
                          blurRadius: 8,
                          offset: Offset(0, 2),
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
                    padding: EdgeInsets.only(top: R.blockV * 0.5),
                    child: Text(
                      notification.body,
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
                    style: TextStyle(
                      fontSize: R.blockH * 3,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  onTap: () async {
                    officerHazardNotifier.markAsRead(notification.hazardId);
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
                            'Could not load hazard details. It may be resolved or deleted.',
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

  void _showClearConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Clear All Notifications?'),
          content: Text(
            'This will permanently remove all notification history. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                officerHazardNotifier.clearNotifications();
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
