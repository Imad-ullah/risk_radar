import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' show atan2, cos, pi, sin;
import 'hazard_details_screen.dart';

class OrphanedHazardsScreen extends StatefulWidget {
  const OrphanedHazardsScreen({super.key});

  @override
  State<OrphanedHazardsScreen> createState() => _OrphanedHazardsScreenState();
}

class _OrphanedHazardsScreenState extends State<OrphanedHazardsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  bool isLoading = true;
  bool isOfficer = false;
  List<Map<String, dynamic>> hazards = [];

  @override
  void initState() {
    super.initState();
    _checkIfOfficer();
    fetchOrphanedHazards();
  }

  Future<void> _checkIfOfficer() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final officerData = await supabase
        .from('officers')
        .select('id')
        .eq('id', userId)
        .maybeSingle();

    if (mounted) {
      setState(() {
        isOfficer = officerData != null;
      });
    }
  }

  Future<void> fetchOrphanedHazards() async {
    setState(() => isLoading = true);
    try {
      final hazardData = await supabase.from('hazards').select().order('created_at', ascending: false);
      final workerData = await supabase.from('workers').select();
      final existingWorkerIds = workerData.map((w) => w['id'].toString()).toSet();

      final List<Map<String, dynamic>> orphaned = [];
      for (var h in hazardData) {
        final String workerId = h['worker_id'] ?? '';
        if (!existingWorkerIds.contains(workerId)) {
          h['reporter_info'] = 'Worker Removed';
          h['reporter_image'] = null;
          orphaned.add(Map<String, dynamic>.from(h));
        }
      }

      setState(() {
        hazards = orphaned;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching orphaned hazards: $e');
      setState(() => isLoading = false);
    }
  }

  Color getSeverityColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'low':
        return Colors.green.shade300;
      case 'moderate':
        return Colors.orange.shade300;
      case 'high':
        return Colors.red.shade300;
      default:
        return Colors.grey.shade300;
    }
  }

  Color getStatusColor(String? status) {
    switch (status) {
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'pending':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String displayStatus(String? status) {
    switch (status) {
      case 'in_progress':
        return 'In Progress';
      case 'resolved':
        return 'Resolved';
      case 'pending':
        return 'Pending';
      default:
        return status ?? 'Unknown';
    }
  }

  String hazardEmoji(String? type) {
    switch (type?.toLowerCase()) {
      case 'fire':
        return '🔥';
      case 'electrical':
        return '⚡';
      case 'chemical':
        return '☣️';
      case 'slip':
        return '💦';
      case 'fall':
        return '🪜';
      default:
        return '⚠️';
    }
  }

  String capitalizeName(String name) {
    return name
        .split(' ')
        .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1).toLowerCase() : '')
        .join(' ');
  }

  Future<String> getDistanceAndDirection(double lat, double lng) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      double distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        lat,
        lng,
      );

      String direction = getDirection(position.latitude, position.longitude, lat, lng);

      if (distanceInMeters < 1000) {
        return "${distanceInMeters.toStringAsFixed(0)} m away, $direction";
      } else {
        double km = distanceInMeters / 1000;
        return "${km.toStringAsFixed(2)} km away, $direction";
      }
    } catch (e) {
      return "Unable to get location";
    }
  }

  String getDirection(double startLat, double startLng, double endLat, double endLng) {
    double dLon = (endLng - startLng) * pi / 180;
    double y = sin(dLon) * cos(endLat * pi / 180);
    double x = cos(startLat * pi / 180) * sin(endLat * pi / 180) -
        sin(startLat * pi / 180) * cos(endLat * pi / 180) * cos(dLon);
    double brng = atan2(y, x);
    brng = (brng * 180 / pi + 360) % 360;

    if (brng >= 337.5 || brng < 22.5) return "North";
    if (brng >= 22.5 && brng < 67.5) return "North-East";
    if (brng >= 67.5 && brng < 112.5) return "East";
    if (brng >= 112.5 && brng < 157.5) return "South-East";
    if (brng >= 157.5 && brng < 202.5) return "South";
    if (brng >= 202.5 && brng < 247.5) return "South-West";
    if (brng >= 247.5 && brng < 292.5) return "West";
    return "North-West";
  }

  Future<void> deleteHazard(dynamic hazardId) async {
    try {
      await supabase.from('hazards').delete().eq('id', hazardId);
    } catch (e) {
      debugPrint("Error deleting hazard: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text("Orphaned Hazards")),
      body: RefreshIndicator(
        onRefresh: fetchOrphanedHazards,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : hazards.isEmpty
            ? const Center(child: Text("No orphaned hazards at the moment."))
            : ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: hazards.length,
          itemBuilder: (context, index) {
            final hazard = hazards[index];
            final String title = hazard['hazard_type'] ?? 'No type';
            final String description = hazard['description'] ?? 'No description';
            final String reporterInfo = hazard['reporter_info'] ?? 'Worker Removed';
            final String status = hazard['status'] ?? 'Unknown';
            final String severity = hazard['severity'] ?? 'Unknown';
            final String? imageUrl = hazard['image_url'];
            final double? latitude = hazard['latitude'] != null
                ? double.tryParse(hazard['latitude'].toString())
                : null;
            final double? longitude = hazard['longitude'] != null
                ? double.tryParse(hazard['longitude'].toString())
                : null;
            final DateTime? createdAt = hazard['created_at'] != null
                ? DateTime.tryParse(hazard['created_at'])
                : null;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: getSeverityColor(severity), width: 2),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(hazardEmoji(title), style: const TextStyle(fontSize: 26)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 2),
                              Text(capitalizeName(reporterInfo),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isDarkTheme ? Colors.white : Colors.black87)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: getSeverityColor(severity),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(severity.toUpperCase(),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(description),
                    if (createdAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "Date: ${DateFormat.yMMMd().add_jm().format(createdAt)}",
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    if (imageUrl != null && imageUrl.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(imageUrl, height: 100, width: double.infinity, fit: BoxFit.cover),
                        ),
                      ),
                    const SizedBox(height: 6),

                    // Chips Row
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        // Status Chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: getStatusColor(status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: getStatusColor(status).withValues(alpha: 0.4)),
                          ),
                          child: Text(displayStatus(status),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: getStatusColor(status))),
                        ),

                        // Location Chip
                        if (latitude != null && longitude != null)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () async {
                              String result = await getDistanceAndDirection(latitude, longitude);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: Colors.black87,
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    content: Row(
                                      children: [
                                        const Icon(Icons.location_on, color: Colors.white),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(result, style: const TextStyle(color: Colors.white))),
                                      ],
                                    ),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.location_on, size: 16, color: Colors.green),
                                  SizedBox(width: 4),
                                  Text("Location",
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green)),
                                ],
                              ),
                            ),
                          ),

                        // Delete Chip (Officer only)
                        if (isOfficer)
                          InkWell(
                            onTap: () async {
                              await deleteHazard(hazard['id']);
                              fetchOrphanedHazards();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                  SizedBox(width: 4),
                                  Text("Delete",
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red)),
                                ],
                              ),
                            ),
                          ),
                        // Resolved Chip (Officer only)
                        if (isOfficer)
                          InkWell(
                            onTap: () async {
                              final hazardId = hazard['id'];
                              await supabase.from('hazards').update({'status': 'resolved'}).eq('id', hazardId);
                              fetchOrphanedHazards();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                                  SizedBox(width: 4),
                                  Text("Resolved",
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green)),
                                ],
                              ),
                            ),
                          ),
                        // Details Chip
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HazardDetailsScreen(
                                  hazardData: {
                                    'title': title,
                                    'description': description,
                                    'images': imageUrl != null && imageUrl.isNotEmpty ? [imageUrl] : [],
                                    'reporter_name': reporterInfo,
                                    'severity': severity,
                                    'status': status,
                                    'created_at': hazard['created_at'],
                                    'latitude': latitude,
                                    'longitude': longitude,
                                  },
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.info_outline, size: 16, color: Colors.blue),
                                SizedBox(width: 4),
                                Text("Details",
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: fetchOrphanedHazards,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
