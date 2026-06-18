import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_colors.dart';

class OfficerHazardMapScreen extends StatefulWidget {
  const OfficerHazardMapScreen({super.key});

  @override
  State<OfficerHazardMapScreen> createState() => _OfficerHazardMapScreenState();
}

class _OfficerHazardMapScreenState extends State<OfficerHazardMapScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final Set<String> _selectedSeverities = {'high', 'moderate', 'low'};

  GoogleMapController? _mapController;
  bool _isLoading = true;
  String? _error;
  List<_HazardPoint> _hazards = <_HazardPoint>[];

  static const CameraPosition _fallbackCamera = CameraPosition(
    target: LatLng(24.8607, 67.0011),
    zoom: 12,
  );
  CameraPosition _initialCamera = _fallbackCamera;
  Position? _currentPosition;
  MapType _mapType = MapType.hybrid;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  List<_HazardPoint> get _filteredHazards => _hazards
      .where((h) => _selectedSeverities.contains(h.severity.toLowerCase()))
      .toList();

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      await _loadCurrentLocation();
      await _loadHazards();
    } on SocketException {
      _error = 'No internet connection. Could not load hazard map.';
    } catch (e) {
      _error = 'Failed to load hazard map: $e';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _currentPosition = pos;
      _initialCamera = CameraPosition(
        target: LatLng(pos.latitude, pos.longitude),
        zoom: 14,
      );
    } catch (_) {
      // Keep fallback camera when location fails.
    }
  }

  Future<void> _loadHazards() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      throw StateError('No authenticated officer user found.');
    }

    final officer = await _supabase
        .from('officers')
        .select('officer_uid')
        .eq('id', currentUserId)
        .maybeSingle();
    final officerUid = officer?['officer_uid'];
    if (officerUid == null) {
      throw StateError('Officer UID not found.');
    }

    final hazardsResponse = await _supabase
        .from('hazards')
        .select('id, hazard_type, severity, status, latitude, longitude')
        .eq('officer_uid', officerUid)
        .neq('status', 'resolved');

    final assignedResponse = await _supabase
        .from('assign_hazards')
        .select('id, hazard_type, severity, status, latitude, longitude')
        .eq('officer_uid', officerUid)
        .neq('status', 'resolved');

    final combined = [
      ...List<Map<String, dynamic>>.from(hazardsResponse),
      ...List<Map<String, dynamic>>.from(assignedResponse),
    ];

    final dedup = <String, _HazardPoint>{};
    for (final row in combined) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final lat = (row['latitude'] as num?)?.toDouble();
      final lng = (row['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      dedup[id] = _HazardPoint(
        id: id,
        type: row['hazard_type']?.toString() ?? 'Hazard',
        severity: row['severity']?.toString() ?? 'unknown',
        status: row['status']?.toString() ?? 'unknown',
        point: LatLng(lat, lng),
      );
    }

    _hazards = dedup.values.toList();
  }

  double? _distanceMeters(_HazardPoint hazard) {
    final p = _currentPosition;
    if (p == null) return null;
    return Geolocator.distanceBetween(
      p.latitude,
      p.longitude,
      hazard.point.latitude,
      hazard.point.longitude,
    );
  }

  String _distanceLabel(_HazardPoint hazard) {
    final d = _distanceMeters(hazard);
    if (d == null) return 'Distance unavailable';
    if (d < 1000) return '${d.round()} m away';
    return '${(d / 1000).toStringAsFixed(1)} km away';
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'moderate':
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  void _toggleSeverity(String key) {
    setState(() {
      if (_selectedSeverities.contains(key)) {
        if (_selectedSeverities.length > 1) {
          _selectedSeverities.remove(key);
        }
      } else {
        _selectedSeverities.add(key);
      }
    });
  }

  Set<Marker> _buildMarkers() {
    return _filteredHazards.map((hazard) {
      return Marker(
        markerId: MarkerId(hazard.id),
        position: hazard.point,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          _toGoogleHue(hazard.severity),
        ),
        infoWindow: InfoWindow(
          title: hazard.type,
          snippet:
              '${hazard.severity.toUpperCase()} • ${_distanceLabel(hazard)}',
          onTap: () => _showHazardSheet(hazard),
        ),
      );
    }).toSet();
  }

  Set<Circle> _buildCircles() {
    return _filteredHazards.map((hazard) {
      final color = _severityColor(hazard.severity);
      return Circle(
        circleId: CircleId('c_${hazard.id}'),
        center: hazard.point,
        radius: 40,
        fillColor: color.withValues(alpha: 0.15),
        strokeColor: color.withValues(alpha: 0.65),
        strokeWidth: 2,
      );
    }).toSet();
  }

  double _toGoogleHue(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return BitmapDescriptor.hueRed;
      case 'moderate':
      case 'medium':
        return BitmapDescriptor.hueOrange;
      case 'low':
        return BitmapDescriptor.hueGreen;
      default:
        return BitmapDescriptor.hueAzure;
    }
  }

  void _showHazardSheet(_HazardPoint hazard) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final color = _severityColor(hazard.severity);
        return Container(
          padding: EdgeInsets.fromLTRB(
            R.blockH * 4.5,
            R.blockV * 1.75,
            R.blockH * 4.5,
            R.blockV * 3,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF102A2A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: R.blockH * 12.267,
                    height: R.blockV * 0.625,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                SizedBox(height: R.blockV * 1.75),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: color),
                    SizedBox(width: R.blockH * 2.667),
                    Expanded(
                      child: Text(
                        hazard.type,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: R.blockH * 5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: R.blockV * 1.25),
                Text(
                  'Severity: ${hazard.severity.toUpperCase()}  •  Status: ${hazard.status.toUpperCase()}',
                  style: TextStyle(color: Colors.white70),
                ),
                SizedBox(height: R.blockV * 0.75),
                Text(
                  _distanceLabel(hazard),
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _centerOnUser() async {
    if (_currentPosition == null || _mapController == null) return;
    final target = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 15.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Hazard Map'),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(R.blockH * 5),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: _initialCamera,
                  onMapCreated: (controller) => _mapController = controller,
                  mapType: _mapType,
                  myLocationEnabled: _currentPosition != null,
                  myLocationButtonEnabled: false,
                  compassEnabled: true,
                  buildingsEnabled: true,
                  trafficEnabled: false,
                  indoorViewEnabled: true,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  markers: _buildMarkers(),
                  circles: _buildCircles(),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  top: 14,
                  child: Card(
                    color: const Color(0xFF123636).withValues(alpha: 0.95),
                    elevation: 3,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active Hazards: ${_filteredHazards.length}/${_hazards.length}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: R.blockV * 1.25),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _severityChip(
                                label: 'High',
                                keyName: 'high',
                                color: Colors.red,
                              ),
                              _severityChip(
                                label: 'Moderate',
                                keyName: 'moderate',
                                color: Colors.orange,
                              ),
                              _severityChip(
                                label: 'Low',
                                keyName: 'low',
                                color: Colors.green,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'map_type_toggle',
            backgroundColor: const Color(0xFF123636),
            onPressed: () {
              setState(() {
                _mapType = _mapType == MapType.hybrid
                    ? MapType.normal
                    : MapType.hybrid;
              });
            },
            child: Icon(Icons.layers_rounded, color: Colors.white),
          ),
          SizedBox(height: R.blockV * 1.25),
          FloatingActionButton.small(
            heroTag: 'center_user',
            backgroundColor: const Color(0xFF123636),
            onPressed: _centerOnUser,
            child: Icon(Icons.my_location_rounded, color: Colors.white),
          ),
          SizedBox(height: R.blockV * 1.25),
          FloatingActionButton(
            heroTag: 'refresh_map',
            backgroundColor: AppColors.brandTeal,
            onPressed: _loadData,
            child: Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _severityChip({
    required String label,
    required String keyName,
    required Color color,
  }) {
    final selected = _selectedSeverities.contains(keyName);
    return InkWell(
      onTap: () => _toggleSeverity(keyName),
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: R.blockH * 3,
          vertical: R.blockV * 1,
        ),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? color : Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: EdgeInsets.only(right: R.blockH * 1.5),
                child: Icon(Icons.check, size: 14, color: Colors.white),
              ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: R.blockH * 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HazardPoint {
  const _HazardPoint({
    required this.id,
    required this.type,
    required this.severity,
    required this.status,
    required this.point,
  });

  final String id;
  final String type;
  final String severity;
  final String status;
  final LatLng point;
}
