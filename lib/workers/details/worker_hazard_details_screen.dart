// lib/workers/details/worker_hazard_details_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:riskradar/shared/theme/app_colors.dart';

// Import your fullscreen viewer
import '../../shared/widgets/full_image_viewer.dart';

// --- Singleton class to manage audio playback ---
class VoicePlayerManager {
  static final VoicePlayerManager _instance = VoicePlayerManager._internal();
  factory VoicePlayerManager() => _instance;

  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentUrl;

  VoicePlayerManager._internal();

  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  String? get currentUrl => _currentUrl;

  Future<void> play(String url) async {
    if (_currentUrl == url) {
      _audioPlayer.playing ? _audioPlayer.pause() : _audioPlayer.play();
    } else {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.setUrl(url);
        _currentUrl = url;
        _audioPlayer.play();
      } catch (e) {
        debugPrint("Error playing audio: $e");
        _currentUrl = null;
      }
    }
  }

  void stop() {
    _audioPlayer.stop();
    _currentUrl = null;
  }

  void dispose() {
    _audioPlayer.dispose();
    _currentUrl = null;
  }
}

// --- Main Screen Widget ---
class WorkerHazardDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> hazardData;

  const WorkerHazardDetailsScreen({super.key, required this.hazardData});

  @override
  State<WorkerHazardDetailsScreen> createState() =>
      _WorkerHazardDetailsScreenState();
}

class _WorkerHazardDetailsScreenState extends State<WorkerHazardDetailsScreen> {
  final VoicePlayerManager _voicePlayerManager = VoicePlayerManager();

  @override
  void dispose() {
    _voicePlayerManager.stop();
    super.dispose();
  }

  // Helper to capitalize names
  String _capitalizeName(String name) {
    if (name.isEmpty) return name;
    return name.split(' ').map((word) {
      if (word.isEmpty) return '';
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  String _formatTimestamp(String? isoString, {bool convertLocal = false}) {
    if (isoString == null || isoString.isEmpty) return 'N/A';
    try {
      DateTime dateTime = DateTime.parse(isoString);
      if (convertLocal) {
        dateTime = dateTime.toLocal();
      }
      return DateFormat("E, MMM d, yyyy 'at' h:mm a").format(dateTime);
    } catch (e) {
      return 'N/A';
    }
  }

  // Exact HEX colors from Ongoing Screen
  Color _getSeverityColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'low':
        return const Color(0xFF10B981); // Green
      case 'moderate':
        return const Color(0xFFF59E0B); // Orange
      case 'high':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF6B7280); // Grey
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'resolved':
        return Colors.teal;
      case 'in_progress':
        return Colors.blue.shade700;
      case 'assigned':
        return Colors.deepPurple.shade500;
      case 'reported':
        return Colors.brown.shade500;
      default:
        return Colors.grey.shade700;
    }
  }

  IconData _getHazardIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'fire':
        return Icons.local_fire_department_rounded;
      case 'electrocution':
        return Icons.bolt_rounded;
      case 'hazardous chemicals':
        return Icons.science_outlined;
      case 'slips/trips':
        return Icons.personal_injury_outlined;
      case 'fall from height':
        return Icons.personal_injury_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  Future<void> _openMap(double lat, double lng) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch map.');
    }
  }

  List<String> _parseStringToList(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      return data.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    if (data is String && data.isNotEmpty) {
      return data.split(',').map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : AppColors.backgroundLight;
    final textColor = isDark ? Colors.white : Colors.black87;

    final hazardData = widget.hazardData;
    final String title = hazardData['hazard_type'] ?? 'Hazard';
    final String description =
        hazardData['description'] ?? 'No description provided.';
    final List<String> images =
    _parseStringToList(hazardData['images'] ?? hazardData['image_url']);

    final String reporterName =
    _capitalizeName(hazardData['reporter_name'] ?? 'Unknown');
    final String assignedName =
    _capitalizeName(hazardData['assigned_name'] ?? 'Not Assigned');

    final String severity = hazardData['severity'] ?? 'Unknown';
    final String status = hazardData['status'] ?? 'Unknown';

    final String createdAt =
    _formatTimestamp(hazardData['created_at'], convertLocal: false);
    final String assignedAt =
    _formatTimestamp(hazardData['assigned_at'], convertLocal: true);

    final List<String> voiceUrls =
    _parseStringToList(hazardData['voice_note_url']);
    final double? latitude = hazardData['latitude'];
    final double? longitude = hazardData['longitude'];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Hazard Details",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        // Standard Arrow Back Button (with dash/line)
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Updated Gradient Header Card
            _HazardHeaderCard(
              title: title,
              severity: severity,
              status: status,
              icon: _getHazardIcon(title),
              severityColor: _getSeverityColor(severity),
              statusColor: _getStatusColor(status),
            ),
            const SizedBox(height: 24),

            // Images
            if (images.isNotEmpty) ...[
              _SectionHeader(title: "Photos", isDark: isDark),
              const SizedBox(height: 12),
              ImageSlideshow(imageUrls: images),
              const SizedBox(height: 24),
            ],

            // Description
            _SectionHeader(title: "Description", isDark: isDark),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
              ),
              child: Text(
                description,
                style: TextStyle(
                    fontSize: 15, height: 1.5, color: textColor),
              ),
            ),
            const SizedBox(height: 24),

            // Voice Notes
            if (voiceUrls.isNotEmpty) ...[
              _SectionHeader(title: "Voice Notes", isDark: isDark),
              const SizedBox(height: 12),
              _VoiceNoteList(
                  voiceUrls: voiceUrls,
                  playerManager: _voicePlayerManager,
                  isDark: isDark),
              const SizedBox(height: 24),
            ],

            // Details Section
            _SectionHeader(title: "Details", isDark: isDark),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    _DetailItem(
                        icon: Icons.person_pin_circle_outlined,
                        title: "Reported By",
                        value: reporterName,
                        isDark: isDark),
                    _DetailItem(
                        icon: Icons.engineering_outlined,
                        title: "Assigned To",
                        value: assignedName,
                        isDark: isDark),
                    _DetailItem(
                        icon: Icons.today_outlined,
                        title: "Reported On",
                        value: createdAt,
                        isDark: isDark),
                    if (assignedAt != 'N/A')
                      _DetailItem(
                          icon: Icons.assignment_turned_in_outlined,
                          title: "Assigned On",
                          value: assignedAt,
                          isDark: isDark),
                    if (latitude != null && longitude != null) ...[
                      Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: isDark ? Colors.grey[800] : Colors.grey[200]),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.brandTeal,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.location_on_outlined,
                              color: AppColors.accentGold, size: 20),
                        ),
                        title: Text("Location",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor)),
                        subtitle: Text("Lat: $latitude, Lng: $longitude",
                            style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[400] : Colors.grey[600])),
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandTeal,
                            foregroundColor: AppColors.accentGold,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.map_rounded, size: 18),
                          label: const Text("Open",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () => _openMap(latitude, longitude),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// --- HELPER WIDGETS ---

class _HazardHeaderCard extends StatelessWidget {
  final String title;
  final String severity;
  final String status;
  final IconData icon;
  final Color severityColor;
  final Color statusColor;

  const _HazardHeaderCard({
    required this.title,
    required this.severity,
    required this.status,
    required this.icon,
    required this.severityColor,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    // Generate a darker shade for the gradient end
    final Color darkerColor = Color.lerp(severityColor, Colors.black, 0.3)!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // ✅ Gradient: Base Color -> Darker Shade
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            severityColor,
            darkerColor,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: severityColor.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 36),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Status Chips are white/transparent to pop against gradient
                      _StatusChip(
                        label: severity,
                        backgroundColor: Colors.white,
                        textColor: severityColor, // Text matches card color
                      ),
                      _StatusChip(
                        label: status.replaceAll('_', ' ').toUpperCase(),
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        textColor: Colors.white,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _StatusChip({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 11,
            letterSpacing: 0.5),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  const _SectionHeader({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.brandTeal,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _VoiceNoteList extends StatelessWidget {
  final List<String> voiceUrls;
  final VoicePlayerManager playerManager;
  final bool isDark;

  const _VoiceNoteList(
      {required this.voiceUrls,
        required this.playerManager,
        required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(voiceUrls.length, (index) {
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
          ),
          child: VoiceNotePlayer(
            key: ValueKey(voiceUrls[index]),
            url: voiceUrls[index],
            playerManager: playerManager,
            isDark: isDark,
          ),
        );
      }),
    );
  }
}

class ImageSlideshow extends StatefulWidget {
  final List<String> imageUrls;
  const ImageSlideshow({super.key, required this.imageUrls});

  @override
  State<ImageSlideshow> createState() => _ImageSlideshowState();
}

class _ImageSlideshowState extends State<ImageSlideshow> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      if (_pageController.page?.round() != _currentPage) {
        setState(() {
          _currentPage = _pageController.page!.round();
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      height: 8.0,
      width: _currentPage == index ? 24.0 : 8.0,
      decoration: BoxDecoration(
        color: _currentPage == index
            ? AppColors.brandTeal
            : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(5.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) return const SizedBox.shrink();

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              itemBuilder: (context, index) {
                final imageUrl = widget.imageUrls[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullscreenImageViewer(
                          imageUrls: widget.imageUrls,
                          initialIndex: index,
                        ),
                      ),
                    );
                  },
                  child: Hero(
                    tag: imageUrl,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image,
                              color: Colors.grey)),
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))),
                    ),
                  ),
                );
              },
            ),
            if (widget.imageUrls.length > 1)
              Positioned(
                bottom: 10.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      widget.imageUrls.length, (index) => _buildDot(index)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool isDark;

  const _DetailItem(
      {required this.icon,
        required this.title,
        required this.value,
        required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brandTeal,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.accentGold, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerData {
  final PlayerState? playerState;
  final Duration? duration;
  final Duration? position;
  _PlayerData(this.playerState, this.duration, this.position);
}

class VoiceNotePlayer extends StatelessWidget {
  final String url;
  final VoicePlayerManager playerManager;
  final bool isDark;

  const VoiceNotePlayer(
      {super.key,
        required this.url,
        required this.playerManager,
        required this.isDark});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: playerManager.playerStateStream
          .map((_) => playerManager.currentUrl)
          .startWith(playerManager.currentUrl),
      builder: (context, activeUrlSnapshot) {
        final bool isActive = activeUrlSnapshot.data == url;

        return StreamBuilder<_PlayerData>(
          stream: Rx.combineLatest3(
              playerManager.playerStateStream,
              playerManager.durationStream,
              playerManager.positionStream,
                  (a, b, c) => _PlayerData(a, b, c)),
          builder: (context, snapshot) {
            final playerState = snapshot.data?.playerState;
            final playing = playerState?.playing ?? false;
            final duration = snapshot.data?.duration ?? Duration.zero;
            final position = isActive
                ? (snapshot.data?.position ?? Duration.zero)
                : Duration.zero;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(isActive && playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded),
                    iconSize: 40.0,
                    color: AppColors.brandTeal,
                    onPressed: () => playerManager.play(url),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Transform.translate(
                      offset: const Offset(0.0, 8.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 20,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3.0,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6.0),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12.0),
                                activeTrackColor: AppColors.brandTeal,
                                inactiveTrackColor:
                                AppColors.brandTeal.withValues(alpha: 0.2),
                                thumbColor: AppColors.brandTeal,
                              ),
                              child: Slider(
                                value: position.inMilliseconds
                                    .toDouble()
                                    .clamp(0.0,
                                    duration.inMilliseconds.toDouble()),
                                max: duration.inMilliseconds.toDouble(),
                                onChanged: (value) {
                                  if (isActive) {
                                    playerManager._audioPlayer.seek(
                                        Duration(milliseconds: value.toInt()));
                                  }
                                },
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(position),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600])),
                                Text(_formatDuration(duration),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600])),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
