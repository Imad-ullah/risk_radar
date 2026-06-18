// lib/officers/screens/resolved_hazards_screen.dart

import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'hazard_report_generation_screen.dart';

class ResolvedHazardsScreen extends StatefulWidget {
  const ResolvedHazardsScreen({super.key});

  @override
  State<ResolvedHazardsScreen> createState() => _ResolvedHazardsScreenState();
}

class _ResolvedHazardsScreenState extends State<ResolvedHazardsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final HazardRepository _hazardRepository = HazardRepository();
  final ScrollController _scrollController = ScrollController();

  static const int _pageSize = 20;
  static const double _loadMoreScrollThreshold = 0.8;

  List<Map<String, dynamic>> _allHazards = [];
  List<Map<String, dynamic>> _filteredHazards = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreHazards = true;
  int _currentPage = 0;
  String? _error;
  DateTime _selectedDate = DateTime.now();
  late FixedExtentScrollController _calendarController;

  // --- Constants ---
  static const Color _headerTeal = Color(0xFF1B3D3D);
  static const Color _selectedDateColor = Color(0xFFD1F0B1);

  // Gradient Colors
  static const Color _successPrimary = Color(0xFF10B981);
  static const Color _successSecondary = Color(0xFF34D399);
  static const Color _warningPrimary = Color(0xFFF59E0B);
  static const Color _warningSecondary = Color(0xFFFBBF24);
  static const Color _errorPrimary = Color(0xFFEF4444);
  static const Color _errorSecondary = Color(0xFFF87171);

  @override
  void initState() {
    super.initState();
    _calendarController = FixedExtentScrollController(initialItem: 30);
    _scrollController.addListener(_handleScroll);
    _loadResolvedCacheFirst();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _calendarController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoadingMore ||
        !_hasMoreHazards ||
        _isLoading) {
      return;
    }

    final ScrollPosition position = _scrollController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }

    final double triggerOffset =
        position.maxScrollExtent * _loadMoreScrollThreshold;
    if (position.pixels >= triggerOffset) {
      _loadNextPage();
    }
  }

  Future<void> _loadResolvedCacheFirst() async {
    final cached = await _hazardRepository.getOfficerResolvedHazards();
    if (cached != null) {
      setState(() {
        _allHazards = cached;
        _isLoading = false;
        _error = null;
      });
      _filterHazardsByDate(_selectedDate);
    }

    await fetchResolvedHazards(
      showBlockingLoader: cached == null,
      resetPagination: true,
    );
  }

  Future<void> _loadNextPage() async {
    if (!_hasMoreHazards || _isLoadingMore) {
      return;
    }

    setState(() => _isLoadingMore = true);
    _currentPage++;
    await fetchResolvedHazards(
      showBlockingLoader: false,
      resetPagination: false,
    );
  }

  Future<void> _refreshResolvedHazards() async {
    await fetchResolvedHazards(
      showBlockingLoader: false,
      resetPagination: true,
    );
  }

  Future<void> fetchResolvedHazards({
    bool showBlockingLoader = true,
    bool resetPagination = true,
  }) async {
    if (!mounted) {
      return;
    }
    if (resetPagination) {
      _currentPage = 0;
      _hasMoreHazards = true;
    }
    if (showBlockingLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final int pageStart = _currentPage * _pageSize;
      final int pageEnd = pageStart + _pageSize - 1;
      final currentUserId = supabase.auth.currentUser?.id;
      final officerData = await supabase
          .from('officers')
          .select('officer_uid')
          .eq('id', currentUserId!)
          .maybeSingle();
      final officerUid = officerData?['officer_uid'];

      final response = await supabase
          .from('resolved_hazards')
          .select(
            '*, workers(first_name, last_name, work_type, profile_image_url), sites(name)',
          )
          .eq('officer_uid', officerUid ?? 0)
          .order('resolved_at', ascending: false)
          .range(pageStart, pageEnd);

      final List<Map<String, dynamic>> processedHazards = response.map((h) {
        final workerInfo = h['workers'] as Map<String, dynamic>?;
        String reporterName = 'Orphaned';
        String? imageUrl; // ✅ Create a variable to safely hold the image URL

        if (workerInfo != null) {
          reporterName =
              '${workerInfo['first_name']} ${workerInfo['last_name']}';
          if (workerInfo['work_type'] != null) {
            reporterName += ' (${workerInfo['work_type']})';
          }
          // ✅ Explicitly grab the image URL from the join
          imageUrl = workerInfo['profile_image_url'];
        }

        return {
          ...h,
          'reporter_name': reporterName,
          // ✅ Explicitly build the reporter object so the details screen gets exactly what it expects
          'reporter': {
            'first_name': workerInfo?['first_name'],
            'last_name': workerInfo?['last_name'],
            'work_type': workerInfo?['work_type'],
            'profile_image_url': imageUrl,
          },
        };
      }).toList();

      final List<Map<String, dynamic>> updatedHazards = resetPagination
          ? processedHazards
          : <Map<String, dynamic>>[..._allHazards, ...processedHazards];

      if (!mounted) {
        return;
      }
      await _hazardRepository.saveOfficerResolvedHazards(updatedHazards);
      setState(() {
        _allHazards = updatedHazards;
        _hasMoreHazards = processedHazards.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
      });
      _filterHazardsByDate(_selectedDate);
    } on SocketException {
      debugPrint('Officer resolved hazards offline - using cached data.');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching resolved hazards: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load hazards. Please try again.';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _filterHazardsByDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _filteredHazards = _allHazards.where((hazard) {
        final dateStr = hazard['resolved_at'] ?? hazard['created_at'];
        if (dateStr == null) {
          return false;
        }

        DateTime hazardDate;
        final str = dateStr.toString();
        if (str.endsWith('Z') || str.contains('+')) {
          hazardDate = DateTime.parse(str).toLocal();
        } else {
          hazardDate = DateTime.parse("${str}Z").toLocal();
        }

        return hazardDate.year == date.year &&
            hazardDate.month == date.month &&
            hazardDate.day == date.day;
      }).toList();
    });
  }

  List<Color> _getGradientColors(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'low':
        return [_successPrimary, _successSecondary];
      case 'moderate':
        return [_warningPrimary, _warningSecondary];
      case 'high':
        return [_errorPrimary, _errorSecondary];
      default:
        return [_successPrimary, _successSecondary];
    }
  }

  String _getHazardIconPath(String? type) {
    if (type == null) {
      return 'assets/hazards/fire_warning.svg';
    }

    final normalized = type.toLowerCase().trim();

    if (normalized.contains('slip') || normalized.contains('wet'))
      return 'assets/hazards/slip_falling.svg';
    if (normalized.contains('stair')) return 'assets/hazards/stairs_fall.svg';
    if (normalized.contains('fall') && !normalized.contains('slip'))
      return 'assets/hazards/falling_objects.svg';
    if (normalized.contains('electric') || normalized.contains('shock'))
      return 'assets/hazards/electric_shock.svg';
    if (normalized.contains('explosion')) return 'assets/hazards/explosion.svg';
    if (normalized.contains('freeze') || normalized.contains('ice'))
      return 'assets/hazards/freeze.svg';
    if (normalized.contains('high heat') || normalized.contains('heat'))
      return 'assets/hazards/high_heat.svg';
    if (normalized.contains('temperature'))
      return 'assets/hazards/high_temperature.svg';
    if (normalized.contains('lift') || normalized.contains('load'))
      return 'assets/hazards/load_lifting.svg';
    if (normalized.contains('machine') || normalized.contains('crush'))
      return 'assets/hazards/machine_crush.svg';
    if (normalized.contains('magnet'))
      return 'assets/hazards/magnetic_field.svg';
    if (normalized.contains('radio') && normalized.contains('active'))
      return 'assets/hazards/radio_active.svg';
    if (normalized.contains('radio') || normalized.contains('wave'))
      return 'assets/hazards/radio_waves.svg';
    if (normalized.contains('fire')) return 'assets/hazards/fire_warning.svg';

    return 'assets/hazards/fire_warning.svg';
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF121212)
        : const Color(0xFFF9FAFB);
    final timeTextColor = isDark ? Colors.white54 : Colors.black54;
    final dashedLineColor = isDark ? Colors.white24 : Colors.black12;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Stack(
          children: [
            _isLoading
                ? Center(child: CircularProgressIndicator(color: _headerTeal))
                : _error != null
                ? Padding(
                    padding: EdgeInsets.only(top: R.blockV * 27.5),
                    child: Center(child: Text(_error!)),
                  )
                : _filteredHazards.isEmpty
                ? Padding(
                    padding: EdgeInsets.only(top: R.blockV * 27.5),
                    child: _buildEmptyState(isDark),
                  )
                : RefreshIndicator(
                    onRefresh: _refreshResolvedHazards,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        R.blockH * 5,
                        R.blockV * 27.5,
                        R.blockH * 5,
                        R.blockV * 15,
                      ),
                      itemCount:
                          _filteredHazards.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _filteredHazards.length) {
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: R.blockV * 2,
                            ),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: _headerTeal,
                              ),
                            ),
                          );
                        }
                        return _buildTimelineItem(
                          _filteredHazards[index],
                          index,
                          timeTextColor,
                          dashedLineColor,
                        );
                      },
                    ),
                  ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: CustomPaint(
                painter: HeaderCurvePainter(color: _headerTeal),
                child: Container(
                  padding: EdgeInsets.only(bottom: R.blockV * 6.25),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.arrow_back_ios,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    DateFormat(
                                      'MMMM yyyy',
                                    ).format(_selectedDate),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: R.blockH * 5.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: R.blockH * 12.8),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Refresh',
                              icon: Icon(
                                Icons.refresh_rounded,
                                color: Colors.white,
                              ),
                              onPressed: _refreshResolvedHazards,
                            ),
                          ],
                        ),
                        SizedBox(height: R.blockV * 0.625),
                        SizedBox(
                          height: R.blockV * 11.25,
                          child: RotatedBox(
                            quarterTurns: -1,
                            child: ListWheelScrollView.useDelegate(
                              controller: _calendarController,
                              itemExtent: 65,
                              perspective: 0.002,
                              diameterRatio: 1.5,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (index) {
                                final today = DateTime.now();
                                final date = today.subtract(
                                  Duration(days: 30 - index),
                                );
                                _filterHazardsByDate(date);
                              },
                              childDelegate: ListWheelChildBuilderDelegate(
                                childCount: 31,
                                builder: (context, index) {
                                  return RotatedBox(
                                    quarterTurns: 1,
                                    child: _buildDateCapsule(index),
                                  );
                                },
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
          ],
        ),
      ),
    );
  }

  Widget _buildDateCapsule(int index) {
    final today = DateTime.now();
    final date = today.subtract(Duration(days: 30 - index));
    final isSelected =
        date.year == _selectedDate.year &&
        date.month == _selectedDate.month &&
        date.day == _selectedDate.day;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: R.blockH * 15.467,
      margin: EdgeInsets.symmetric(horizontal: R.blockH * 1),
      decoration: BoxDecoration(
        color: isSelected
            ? _selectedDateColor
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('d').format(date),
            style: TextStyle(
              color: isSelected ? _headerTeal : Colors.white,
              fontSize: R.blockH * 5,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: R.blockV * 0.5),
          Text(
            DateFormat('E').format(date),
            style: TextStyle(
              color: isSelected ? _headerTeal : Colors.white60,
              fontSize: R.blockH * 3,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    Map<String, dynamic> hazard,
    int index,
    Color timeColor,
    Color lineColor,
  ) {
    final dateStr = hazard['resolved_at'] ?? hazard['created_at'];
    String timeDisplay = '--';
    if (dateStr != null) {
      DateTime dt;
      final str = dateStr.toString();
      if (str.endsWith('Z') || str.contains('+')) {
        dt = DateTime.parse(str).toLocal();
      } else {
        dt = DateTime.parse("${str}Z").toLocal();
      }
      timeDisplay = DateFormat('h:mm a').format(dt).toLowerCase();
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: R.blockH * 14.667,
            child: Column(
              children: [
                Text(
                  timeDisplay,
                  style: TextStyle(
                    color: timeColor,
                    fontWeight: FontWeight.w600,
                    fontSize: R.blockH * 3.25,
                  ),
                ),
                SizedBox(height: R.blockV * 1),
                Expanded(
                  child: CustomPaint(
                    painter: DashedLinePainter(color: lineColor),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: R.blockV * 2.5),
              child: _buildTabbedGradientCard(hazard, index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabbedGradientCard(Map<String, dynamic> hazard, int index) {
    final String reportNumber = hazard['report_number']?.toString() ?? 'N/A';

    String siteName = 'Unknown';
    if (hazard['sites'] != null) {
      if (hazard['sites'] is Map && hazard['sites']['name'] != null) {
        siteName = hazard['sites']['name'];
      } else if (hazard['sites'] is List && hazard['sites'].isNotEmpty) {
        siteName = hazard['sites'][0]['name'] ?? 'Unknown';
      }
    }

    final hazardType = hazard['hazard_type'] ?? 'Hazard';
    final description = hazard['description'] ?? 'No description';
    final severity = hazard['severity'];

    final images =
        (hazard['image_url'] != null &&
            hazard['image_url'].toString().isNotEmpty)
        ? hazard['image_url']
              .toString()
              .split(',')
              .map((e) => e.trim())
              .toList()
        : <String>[];
    final voiceUrls =
        (hazard['voice_note_url'] != null &&
            hazard['voice_note_url'].toString().trim().isNotEmpty)
        ? hazard['voice_note_url']
              .toString()
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    final bool hasImages = images.isNotEmpty;
    final bool hasVoiceNotes = voiceUrls.isNotEmpty;

    final List<Color> gradientColors = _getGradientColors(severity);
    final String iconAsset = _getHazardIconPath(hazardType);

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 400 + (index * 100)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResolvedHazardDetailsScreen(hazard: hazard),
            ),
          );
        },
        child: CustomPaint(
          painter: TabbedCardGradientPainter(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              R.blockH * 4,
              R.blockV * 1.5,
              R.blockH * 4,
              R.blockV * 2.5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ✅ Report Number Tag
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: R.blockH * 2,
                        vertical: R.blockV * 0.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$reportNumber',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: R.blockH * 3,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // ✅ Media Icons (Profile Image entirely removed from here)
                    if (hasVoiceNotes) ...[
                      SizedBox(width: R.blockH * 2.133),
                      Icon(
                        Icons.mic_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ],
                    if (hasImages) ...[
                      SizedBox(width: R.blockH * 2.133),
                      Icon(
                        Icons.image_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: R.blockV * 2),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: R.blockH * 18.667,
                      height: R.blockV * 8.75,
                      alignment: Alignment.center,
                      child: SvgPicture.asset(
                        iconAsset,
                        fit: BoxFit.contain,
                        width: R.blockH * 15.467,
                        height: R.blockV * 7.25,
                        placeholderBuilder: (context) => Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                    ),
                    SizedBox(width: R.blockH * 4.267),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hazardType,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: R.blockH * 4.25,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: R.blockV * 0.5),
                          Text(
                            description,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: R.blockH * 3.25,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: R.blockV * 0.75),

                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                              SizedBox(width: R.blockH * 1.067),
                              Expanded(
                                child: Text(
                                  'Site: $siteName',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: R.blockH * 3,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    Container(
                      padding: EdgeInsets.all(R.blockH * 1.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(Icons.check, size: 16, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_note,
            size: 64,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          SizedBox(height: R.blockV * 2),
          Text(
            "No hazards found",
            style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
          ),
        ],
      ),
    );
  }
}

// --- PAINTERS ---

class HeaderCurvePainter extends CustomPainter {
  final Color color;
  HeaderCurvePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.lineTo(0, size.height - 40);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 40,
    );
    path.lineTo(size.width, 0);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DashedLinePainter extends CustomPainter {
  final Color color;
  DashedLinePainter({this.color = Colors.white24});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    double dashHeight = 5, dashSpace = 3, startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant DashedLinePainter oldDelegate) =>
      color != oldDelegate.color;
}

class TabbedCardGradientPainter extends CustomPainter {
  final Gradient gradient;
  TabbedCardGradientPainter({required this.gradient});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      )
      ..style = PaintingStyle.fill;

    final path = Path();
    const double radius = 20.0;
    const double tabHeight = 40.0;
    const double tabWidth = 115.0; // Wide enough for tag + icons

    path.moveTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.lineTo(tabWidth - 20, 0);
    path.cubicTo(tabWidth, 0, tabWidth, tabHeight, tabWidth + 20, tabHeight);
    path.lineTo(size.width - radius, tabHeight);
    path.quadraticBezierTo(
      size.width,
      tabHeight,
      size.width,
      tabHeight + radius,
    );
    path.lineTo(size.width, size.height - radius);
    path.quadraticBezierTo(
      size.width,
      size.height,
      size.width - radius,
      size.height,
    );
    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
