// lib/workers/details/worker_hazard_details_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:riskradar/services/logger_service.dart';
import 'package:riskradar/shared/theme/app_colors.dart';
import 'package:riskradar/shared/widgets/voice_note_player.dart' as shared_voice;

// Import your fullscreen viewer
import '../../shared/widgets/full_image_viewer.dart';

// --- Main Screen Widget ---
class WorkerHazardDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> hazardData;

  const WorkerHazardDetailsScreen({super.key, required this.hazardData});

  @override
  State<WorkerHazardDetailsScreen> createState() =>
      _WorkerHazardDetailsScreenState();
}

class _WorkerHazardDetailsScreenState extends State<WorkerHazardDetailsScreen> {
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
    } catch (Object error, StackTrace stackTrace) {
      LoggerService.error('Invalid hazard timestamp.', error, stackTrace);
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
      case 'resolved by other':
        return Colors.teal;
      case 'in_progress':
      case 'in progress':
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
    final String url =
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      LoggerService.warning('Could not launch map for $lat,$lng.');
    }
  }

  List<String> _parseStringToList(Object? data) {
    if (data == null) return [];
    if (data is Iterable<Object?>) {
      return data
          .map((Object? item) => item?.toString().trim() ?? '')
          .where((String item) => item.isNotEmpty)
          .toList();
    }
    if (data is String && data.isNotEmpty) {
      return data
          .split(',')
          .map((String item) => item.trim())
          .where((String item) => item.isNotEmpty)
          .toList();
    }
    return [];
  }

  double? _toDoubleOrNull(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : AppColors.backgroundLight;
    final textColor = isDark ? Colors.white : Colors.black87;

    final hazardData = widget.hazardData;
    final String title = hazardData['hazard_type']?.toString() ?? 'Hazard';
    final String description =
        hazardData['description']?.toString() ?? 'No description provided.';
    final List<String> images =
    _parseStringToList(hazardData['images'] ?? hazardData['image_url']);

    final String reporterName =
    _capitalizeName(hazardData['reporter_name']?.toString() ?? 'Unknown');
    final String assignedName =
    _capitalizeName(hazardData['assigned_name']?.toString() ?? 'Not Assigned');

    final String severity = hazardData['severity']?.toString() ?? 'Unknown';
    final String status = hazardData['status']?.toString() ?? 'Unknown';
    final String statusLower = status.toLowerCase();

    final String createdAt =
    _formatTimestamp(hazardData['created_at']?.toString(), convertLocal: false);
    final String assignedAt =
    _formatTimestamp(hazardData['assigned_at']?.toString(), convertLocal: true);

    final List<String> voiceUrls =
    _parseStringToList(hazardData['voice_note_url']);
    final List<String> resolutionImages =
    _parseStringToList(hazardData['resolution_image_url']);
    final List<String> resolutionVoiceUrls =
    _parseStringToList(hazardData['resolution_voice_note_url']);
    final String? resolutionNotes = hazardData['resolution_notes']?.toString();
    final bool hasResolutionDetails =
        (statusLower == 'resolved' || statusLower == 'resolved by other') &&
            ((resolutionNotes?.trim().isNotEmpty ?? false) ||
                resolutionImages.isNotEmpty ||
                resolutionVoiceUrls.isNotEmpty);
    final double? latitude = _toDoubleOrNull(hazardData['latitude']);
    final double? longitude = _toDoubleOrNull(hazardData['longitude']);

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
            // Gradient header card
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
                  isDark: isDark),
              const SizedBox(height: 24),
            ],

            _SectionHeader(title: "Status Timeline", isDark: isDark),
            const SizedBox(height: 12),
            _StatusTimeline(
              currentStatus: status,
              createdAt: createdAt,
              assignedAt: assignedAt,
              startedAt: _formatTimestamp(
                hazardData['started_at']?.toString(),
                convertLocal: true,
              ),
              resolvedAt: _formatTimestamp(
                hazardData['resolved_at']?.toString(),
                convertLocal: true,
              ),
              isDark: isDark,
            ),
            const SizedBox(height: 24),

            if (hasResolutionDetails) ...[
              _SectionHeader(title: "Resolution", isDark: isDark),
              const SizedBox(height: 12),
              _ResolutionSection(
                notes: resolutionNotes,
                imageUrls: resolutionImages,
                voiceUrls: resolutionVoiceUrls,
                isDark: isDark,
              ),
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
        // Gradient: base color to darker shade
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
  final bool isDark;

  const _VoiceNoteList(
      {required this.voiceUrls,
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
          child: shared_voice.VoiceNotePlayer(
            key: ValueKey(voiceUrls[index]),
            url: voiceUrls[index],
          ),
        );
      }),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  final String currentStatus;
  final String createdAt;
  final String assignedAt;
  final String startedAt;
  final String resolvedAt;
  final bool isDark;

  const _StatusTimeline({
    required this.currentStatus,
    required this.createdAt,
    required this.assignedAt,
    required this.startedAt,
    required this.resolvedAt,
    required this.isDark,
  });

  int get _currentStepIndex {
    switch (currentStatus.toLowerCase()) {
      case 'resolved':
      case 'resolved by other':
        return 3;
      case 'in_progress':
      case 'in progress':
        return 2;
      case 'assigned':
        return 1;
      case 'reported':
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<_TimelineStepData> steps = <_TimelineStepData>[
      _TimelineStepData(
        title: 'Reported',
        timestamp: createdAt,
        icon: Icons.report_problem_outlined,
      ),
      _TimelineStepData(
        title: 'Assigned',
        timestamp: assignedAt,
        icon: Icons.assignment_ind_outlined,
      ),
      _TimelineStepData(
        title: 'In Progress',
        timestamp: startedAt,
        icon: Icons.engineering_outlined,
      ),
      _TimelineStepData(
        title: 'Resolved',
        timestamp: resolvedAt,
        icon: Icons.verified_outlined,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: List<Widget>.generate(steps.length, (int index) {
          final bool isComplete = index <= _currentStepIndex;
          final bool isLast = index == steps.length - 1;
          return _TimelineStep(
            data: steps[index],
            isComplete: isComplete,
            isLast: isLast,
            isDark: isDark,
          );
        }),
      ),
    );
  }
}

class _TimelineStepData {
  const _TimelineStepData({
    required this.title,
    required this.timestamp,
    required this.icon,
  });

  final String title;
  final String timestamp;
  final IconData icon;
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.data,
    required this.isComplete,
    required this.isLast,
    required this.isDark,
  });

  final _TimelineStepData data;
  final bool isComplete;
  final bool isLast;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color activeColor =
        isComplete ? AppColors.brandTeal : Colors.grey.shade400;
    final String timestampText = data.timestamp == 'N/A'
        ? 'Pending'
        : data.timestamp;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Column(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    data.icon,
                    color: isComplete ? AppColors.accentGold : Colors.white,
                    size: 18,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: activeColor.withValues(alpha: 0.35),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      data.title,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      timestampText,
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolutionSection extends StatelessWidget {
  const _ResolutionSection({
    required this.notes,
    required this.imageUrls,
    required this.voiceUrls,
    required this.isDark,
  });

  final String? notes;
  final List<String> imageUrls;
  final List<String> voiceUrls;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final String? trimmedNotes = notes?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (trimmedNotes != null && trimmedNotes.isNotEmpty) ...<Widget>[
            Text(
              trimmedNotes,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            if (imageUrls.isNotEmpty || voiceUrls.isNotEmpty)
              const SizedBox(height: 16),
          ],
          if (imageUrls.isNotEmpty) ...<Widget>[
            ImageSlideshow(imageUrls: imageUrls),
            if (voiceUrls.isNotEmpty) const SizedBox(height: 16),
          ],
          if (voiceUrls.isNotEmpty)
            _VoiceNoteList(voiceUrls: voiceUrls, isDark: isDark),
        ],
      ),
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
