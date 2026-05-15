// lib/shared/services/site_alert_listener.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class SiteAlertListener extends StatefulWidget {
  final String siteId;
  final Widget child;

  const SiteAlertListener({
    super.key,
    required this.siteId,
    required this.child
  });

  @override
  State<SiteAlertListener> createState() => _SiteAlertListenerState();
}

class _SiteAlertListenerState extends State<SiteAlertListener> {
  final SupabaseClient supabase = Supabase.instance.client;
  late RealtimeChannel _alertChannel;

  @override
  void initState() {
    super.initState();
    _subscribeToAlerts();
  }

  void _subscribeToAlerts() {
    _alertChannel = supabase.channel('public:site_alerts:site_${widget.siteId}');

    _alertChannel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'site_alerts',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'site_id',
        value: widget.siteId,
      ),
      callback: (payload) {
        _handleNewAlert(payload.newRecord);
      },
    ).subscribe();
  }

  void _handleNewAlert(Map<String, dynamic> alertData) {
    HapticFeedback.heavyImpact();

    if (!mounted) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Emergency Alert",
      barrierColor: const Color(0xFFB71C1C).withValues(alpha: 0.95),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return _buildAlertOverlay(ctx, alertData);
      },
    );
  }

  Future<void> _openMapLocation(double? lat, double? long) async {
    if (lat == null || long == null) return;

    final Uri googleMapsUrl = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$long");

    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      debugPrint("Could not launch map.");
    }
  }

  Widget _buildAlertOverlay(BuildContext context, Map<String, dynamic> data) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Pulsing Warning Icon
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.1),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, spreadRadius: 10)
                          ],
                        ),
                        child: const Icon(Icons.warning_rounded, size: 64, color: Color(0xFFD32F2F)),
                      ),
                    );
                  },
                  onEnd: () {},
                ),

                const SizedBox(height: 30),

                const Text(
                  "CRITICAL ALERT",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 32,
                    letterSpacing: 3.0,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 10),

                Text(
                  "SOS Signal Detected at your Site",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 16, fontWeight: FontWeight.w500),
                ),

                const SizedBox(height: 30),

                // 2. SMART INFO CARD (Now shows Photo)
                EmergencyInfoCard(
                    reporterUid: data['reporter_uid'],
                    initialRole: data['role'],
                    timestamp: data['created_at']
                ),

                const SizedBox(height: 40),

                // 3. Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_circle, color: Color(0xFFB71C1C)),
                    label: const Text("ACKNOWLEDGE ALERT", style: TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      elevation: 5,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                TextButton.icon(
                  onPressed: () {
                    final lat = data['latitude'] as double?;
                    final long = data['longitude'] as double?;
                    _openMapLocation(lat, long);
                  },
                  icon: const Icon(Icons.map, color: Colors.white70),
                  label: const Text("VIEW LOCATION ON MAP", style: TextStyle(color: Colors.white70)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    supabase.removeChannel(_alertChannel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// ──────────────────────────────────────────────
// EMERGENCY INFO CARD (With Profile Photo)
// ──────────────────────────────────────────────
class EmergencyInfoCard extends StatefulWidget {
  final String reporterUid;
  final String initialRole;
  final String timestamp;

  const EmergencyInfoCard({
    super.key,
    required this.reporterUid,
    required this.initialRole,
    required this.timestamp,
  });

  @override
  State<EmergencyInfoCard> createState() => _EmergencyInfoCardState();
}

class _EmergencyInfoCardState extends State<EmergencyInfoCard> {
  final SupabaseClient supabase = Supabase.instance.client;

  String _displayName = "Loading Identity...";
  String _designation = "Identifying...";
  String _finalRole = "";
  String? _profileImageUrl; // ✅ Added for Photo
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchReporterDetails();
  }

  Future<void> _fetchReporterDetails() async {
    try {
      // 1. Try finding in HSE Workers table
      final workerRes = await supabase.from('hse_workers')
          .select('first_name, last_name, designation, profile_image_url') // ✅ Fetch Image
          .eq('id', widget.reporterUid)
          .maybeSingle();

      if (workerRes != null) {
        if (mounted) {
          setState(() {
            _displayName = "${workerRes['first_name']} ${workerRes['last_name']}";
            _designation = workerRes['designation'] ?? "Safety Supervisor";
            _finalRole = "SAFETY SUPERVISOR";
            _profileImageUrl = workerRes['profile_image_url']; // ✅ Set Image
            _isLoading = false;
          });
        }
        return;
      }

      // 2. If not found, try Officers table
      final officerRes = await supabase.from('officers')
          .select('first_name, last_name, designation, profile_image_url') // ✅ Fetch Image
          .eq('id', widget.reporterUid)
          .maybeSingle();

      if (officerRes != null) {
        if (mounted) {
          setState(() {
            _displayName = "${officerRes['first_name']} ${officerRes['last_name']}";
            _designation = officerRes['designation'] ?? "Site Officer";
            _finalRole = "SITE OFFICER";
            _profileImageUrl = officerRes['profile_image_url']; // ✅ Set Image
            _isLoading = false;
          });
        }
        return;
      }

      // 3. Fallback
      if (mounted) {
        setState(() {
          _displayName = "Unknown Personnel";
          _designation = "ID: ${widget.reporterUid.substring(0, 5)}...";
          _finalRole = "UNKNOWN ROLE";
          _isLoading = false;
        });
      }

    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeString = DateTime.parse(widget.timestamp).toLocal().toString().split(' ')[1].substring(0, 5);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
        children: [
          // ✅ PROFILE PHOTO AVATAR
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
            ),
            child: CircleAvatar(
              radius: 35,
              backgroundColor: Colors.grey.shade800,
              backgroundImage: (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
                  ? NetworkImage(_profileImageUrl!)
                  : null,
              child: (_profileImageUrl == null || _profileImageUrl!.isEmpty)
                  ? const Icon(Icons.person, size: 40, color: Colors.white54)
                  : null,
            ),
          ),
          const SizedBox(height: 12),

          // Role Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _finalRole == "SITE OFFICER" ? Colors.blueAccent : Colors.orangeAccent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _finalRole,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
            ),
          ),
          const SizedBox(height: 12),

          // Name & Designation
          Text(
            _displayName.toUpperCase(),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            _designation,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),

          const Divider(color: Colors.white24, height: 30),

          // Time & Live Status Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _infoColumn(Icons.access_time_filled, "TIME", timeString),
              _liveStatusColumn(),
            ],
          )
        ],
      ),
    );
  }

  Widget _infoColumn(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _liveStatusColumn() {
    return Column(
      children: [
        // Blinking Red Dot
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 1000),
          builder: (context, value, child) {
            return Container(
              height: 12, width: 12,
              decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: value),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.6), blurRadius: 6)]
              ),
            );
          },
          onEnd: () {},
        ),
        const SizedBox(height: 8),
        const Text("STATUS", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const Text("SOS LIVE", style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}