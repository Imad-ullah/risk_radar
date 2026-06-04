import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/sos_alarm_manager.dart';

class SosAcknowledgeScreen extends StatefulWidget {
  const SosAcknowledgeScreen({super.key, required this.payload});

  final Map<String, dynamic> payload;

  @override
  State<SosAcknowledgeScreen> createState() => _SosAcknowledgeScreenState();
}

class _SosAcknowledgeScreenState extends State<SosAcknowledgeScreen> {
  bool _acknowledging = false;

  @override
  void initState() {
    super.initState();
    SosAlarmManager.instance.startAlarm();
  }

  @override
  void dispose() {
    SosAlarmManager.instance.stopAlarm();
    super.dispose();
  }

  Future<void> _acknowledge() async {
    if (_acknowledging) {
      return;
    }

    setState(() => _acknowledging = true);
    await SosAlarmManager.instance.stopAlarm();

    final alertId = widget.payload['alert_id']?.toString();
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (alertId != null && alertId.isNotEmpty && userId != null) {
      try {
        await Supabase.instance.client
            .from('site_alerts')
            .update({
              'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
              'acknowledged_by': userId,
            })
            .eq('id', alertId);
      } catch (e) {
        debugPrint('SOS acknowledge update failed: $e');
      }
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final title = _cleanText(widget.payload['title']).isNotEmpty
        ? _cleanText(widget.payload['title'])
        : 'Emergency SOS';
    final reporterName = _cleanText(widget.payload['reporter_name']);
    final reporterRole = _cleanText(widget.payload['reporter_role']);
    final body = reporterRole.isNotEmpty
        ? '$reporterRole triggered an emergency alert.'
        : 'A site emergency alert was triggered.';
    final triggeredBy = reporterName.isEmpty
        ? null
        : '$reporterName${reporterRole.isNotEmpty ? ' ($reporterRole)' : ''}';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFB71C1C),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 30,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.warning_rounded,
                      size: 68,
                      color: Color(0xFFD32F2F),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    title.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 18,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (triggeredBy != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'TRIGGERED BY',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            triggeredBy,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _acknowledging ? null : _acknowledge,
                      icon: const Icon(
                        Icons.check_circle,
                        color: Color(0xFFB71C1C),
                      ),
                      label: Text(
                        _acknowledging
                            ? 'ACKNOWLEDGING...'
                            : 'ACKNOWLEDGE ALERT',
                        style: const TextStyle(
                          color: Color(0xFFB71C1C),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _cleanText(Object? value) => value?.toString().trim() ?? '';
}
