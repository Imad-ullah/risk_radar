import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmergencyPermissionDialog {
  const EmergencyPermissionDialog._();

  static Future<void> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyAsked =
        prefs.getBool('sos_critical_permission_asked_v2') ?? false;

    if (alreadyAsked || !context.mounted) return;

    final userAgreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        title: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1B3D3D),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Color(0x26FFFFFF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.emergency,
                      color: Color(0xFFE6A050),
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Emergency SOS Setup',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'One-time safety configuration',
                    style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              'RiskRadar needs special permissions so the SOS alarm works even when your phone is silenced or in Do Not Disturb mode.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            _PermissionItem(
              icon: Icons.volume_up_rounded,
              title: 'Override Silent Mode',
              subtitle: 'Alarm sounds even when phone is muted',
            ),
            _PermissionItem(
              icon: Icons.do_not_disturb_off_rounded,
              title: 'Bypass Do Not Disturb',
              subtitle: 'Emergency alerts break through DND',
            ),
            _PermissionItem(
              icon: Icons.fullscreen_rounded,
              title: 'Full Screen Alerts',
              subtitle: 'SOS wakes your screen immediately',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x1AE6A050),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x66E6A050)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFE6A050),
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Only used for life-safety emergencies on your worksite.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1B3D3D),
                      side: const BorderSide(color: Color(0xFF1B3D3D)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Not Now',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B3D3D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Allow',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: const [],
      ),
    );

    await prefs.setBool('sos_critical_permission_asked_v2', true);

    if (userAgreed == true) {
      await AwesomeNotifications().requestPermissionToSendNotifications(
        channelKey: 'sos_alerts_critical',
        permissions: [
          NotificationPermission.Alert,
          NotificationPermission.Sound,
          NotificationPermission.Vibration,
          NotificationPermission.FullScreenIntent,
          NotificationPermission.CriticalAlert,
          NotificationPermission.OverrideDnD,
        ],
      );
      await AwesomeNotifications().showGlobalDndOverridePage();
      await prefs.setBool('sos_permission_granted', true);
      debugPrint('SOS emergency permissions granted');
    } else {
      debugPrint('User skipped SOS permissions');
    }
  }
}

class _PermissionItem extends StatelessWidget {
  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0x141B3D3D),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF1B3D3D), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFFE6A050),
            size: 18,
          ),
        ],
      ),
    );
  }
}
