import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
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
        scrollable: true,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: EdgeInsets.fromLTRB(
          R.blockH * 6,
          R.blockV * 0,
          R.blockH * 6,
          R.blockV * 3,
        ),
        titlePadding: EdgeInsets.fromLTRB(
          R.blockH * 6,
          R.blockV * 3,
          R.blockH * 6,
          R.blockV * 2,
        ),
        title: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: R.blockV * 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFF1B3D3D),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(R.blockH * 3.5),
                    decoration: const BoxDecoration(
                      color: Color(0x26FFFFFF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.emergency,
                      color: Color(0xFFE6A050),
                      size: 36,
                    ),
                  ),
                  SizedBox(height: R.blockV * 1.5),
                  Text(
                    'Emergency SOS Setup',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: R.blockH * 4.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: R.blockV * 0.5),
                  Text(
                    'One-time safety configuration',
                    style: TextStyle(
                      color: Color(0xB3FFFFFF),
                      fontSize: R.blockH * 3,
                    ),
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
            SizedBox(height: R.blockV * 1),
            Text(
              'RiskRadar needs special permissions so the SOS alarm works even when your phone is silenced or in Do Not Disturb mode.',
              style: TextStyle(
                fontSize: R.blockH * 3.25,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
            SizedBox(height: R.blockV * 2),
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
            SizedBox(height: R.blockV * 1.5),
            Container(
              padding: EdgeInsets.all(R.blockH * 3),
              decoration: BoxDecoration(
                color: const Color(0x1AE6A050),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x66E6A050)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFE6A050),
                    size: 18,
                  ),
                  SizedBox(width: R.blockH * 2.667),
                  Expanded(
                    child: Text(
                      'Only used for life-safety emergencies on your worksite.',
                      style: TextStyle(
                        fontSize: R.blockH * 3,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: R.blockV * 2.5),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1B3D3D),
                      side: const BorderSide(color: Color(0xFF1B3D3D)),
                      padding: EdgeInsets.symmetric(
                        vertical: R.blockV * 1.75,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Not Now',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                SizedBox(width: R.blockH * 3.2),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B3D3D),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: R.blockV * 1.75,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Allow',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [],
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
    R.init(context);
    return Padding(
      padding: EdgeInsets.only(bottom: R.blockV * 1.5),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(R.blockH * 2),
            decoration: BoxDecoration(
              color: const Color(0x141B3D3D),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF1B3D3D), size: 18),
          ),
          SizedBox(width: R.blockH * 3.2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: R.blockH * 3.25,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: R.blockH * 2.75,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle_rounded, color: Color(0xFFE6A050), size: 18),
        ],
      ),
    );
  }
}
