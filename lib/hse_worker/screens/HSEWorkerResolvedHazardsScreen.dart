// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/shared/hazards/resolved_hazard_report_screen.dart';

class HSEWorkerResolvedHazardsScreen extends StatefulWidget {
  const HSEWorkerResolvedHazardsScreen({super.key});

  @override
  State<HSEWorkerResolvedHazardsScreen> createState() =>
      _HSEWorkerResolvedHazardsScreenState();
}

class _HSEWorkerResolvedHazardsScreenState
    extends State<HSEWorkerResolvedHazardsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final HazardRepository _hazardRepository = HazardRepository();
  final ScrollController _scrollController = ScrollController();

  static const int _pageSize = 20;
  static const double _loadMoreScrollThreshold = 0.8;

  List<Map<String, dynamic>> _allHazards = [];
  List<Map<String, dynamic>> _filteredHazards = [];

  bool loading = true;
  bool _isLoadingMore = false;
  bool _hasMoreHazards = true;
  int _currentPage = 0;
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
    _loadResolvedHazardsCacheFirst();
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
        loading) {
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

  Future<void> _loadResolvedHazardsCacheFirst() async {
    final cached = await _hazardRepository.getHseResolvedHazards();
    if (cached != null) {
      setState(() {
        _allHazards = cached;
        loading = false;
      });
      _filterHazardsByDate(_selectedDate);
    } else {
      setState(() => loading = true);
    }

    await _loadResolvedHazards(
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
    await _loadResolvedHazards(
      showBlockingLoader: false,
      resetPagination: false,
    );
  }

  Future<void> _refreshResolvedHazards() async {
    await _loadResolvedHazards(
      showBlockingLoader: false,
      resetPagination: true,
    );
  }

  Future<void> _loadResolvedHazards({
    bool showBlockingLoader = true,
    bool resetPagination = true,
  }) async {
    if (showBlockingLoader) setState(() => loading = true);
    if (resetPagination) {
      _currentPage = 0;
      _hasMoreHazards = true;
    }
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        loading = false;
        _isLoadingMore = false;
      });
      return;
    }

    try {
      final int pageStart = _currentPage * _pageSize;
      final int pageEnd = pageStart + _pageSize - 1;
      final resolvedHazardsData = await supabase
          .from('resolved_hazards')
          .select('*, workers:worker_id(profile_image_url)')
          .eq('assigned_to', userId)
          .order('resolved_at', ascending: false)
          .range(pageStart, pageEnd);

      final resolvedAssignmentsData = await supabase
          .from('assign_hazards')
          .select('''
            *,
            workers:worker_id (
              first_name,
              last_name,
              work_type,
              profile_image_url
            )
          ''')
          .eq('assigned_to', userId)
          .eq('status', 'resolved')
          .order('resolved_at', ascending: false)
          .range(pageStart, pageEnd);

      final rows = _mergeResolvedRows(
        List<Map<String, dynamic>>.from(resolvedHazardsData),
        List<Map<String, dynamic>>.from(resolvedAssignmentsData).map((row) {
          return <String, dynamic>{...row, '_source_table': 'assign_hazards'};
        }).toList(),
      );
      final List<Map<String, dynamic>> updatedRows = _mergeResolvedRows(
        _allHazards,
        rows,
      );
      await _hazardRepository.saveHseResolvedHazards(updatedRows);

      if (mounted) {
        setState(() {
          _allHazards = updatedRows;
          _hasMoreHazards =
              resolvedHazardsData.length == _pageSize ||
              resolvedAssignmentsData.length == _pageSize;
          loading = false;
          _isLoadingMore = false;
        });
        _filterHazardsByDate(_selectedDate);
      }
    } on SocketException {
      debugPrint("ℹ️ HSE resolved hazards offline - using cached data.");
      if (mounted) {
        setState(() {
          loading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error fetching resolved hazards: $e");
      if (mounted) {
        setState(() {
          loading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _mergeResolvedRows(
    List<Map<String, dynamic>> first,
    List<Map<String, dynamic>> second,
  ) {
    final Map<String, Map<String, dynamic>> byId =
        <String, Map<String, dynamic>>{};
    for (final row in <Map<String, dynamic>>[...first, ...second]) {
      final key = _resolvedRowKey(row);
      byId[key] = <String, dynamic>{...?byId[key], ...row};
    }
    final rows = byId.values.toList();
    rows.sort((a, b) {
      final aDate = _parseDate(a['resolved_at'] ?? a['created_at']);
      final bDate = _parseDate(b['resolved_at'] ?? b['created_at']);
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  String _resolvedRowKey(Map<String, dynamic> row) {
    return row['id']?.toString() ??
        row['assignment_id']?.toString() ??
        row['hazard_id']?.toString() ??
        row.hashCode.toString();
  }

  DateTime _parseDate(Object? value) {
    if (value == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    final raw = value.toString();
    try {
      if (raw.endsWith('Z') || raw.contains('+')) {
        return DateTime.parse(raw).toLocal();
      }
      return DateTime.parse("${raw}Z").toLocal();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  void _filterHazardsByDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _filteredHazards = _allHazards.where((hazard) {
        final dateStr = hazard['resolved_at'] ?? hazard['created_at'];
        if (dateStr == null) return false;

        DateTime hazardDate;
        if (dateStr.toString().endsWith('Z')) {
          hazardDate = DateTime.parse(dateStr).toLocal();
        } else {
          hazardDate = DateTime.parse(dateStr).toUtc().toLocal();
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
    if (type == null) return 'assets/hazards/fire_warning.svg';

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
        body: RefreshIndicator(
          onRefresh: _refreshResolvedHazards,
          color: _headerTeal,
          child: Stack(
            children: [
              loading
                  ? Center(child: CircularProgressIndicator(color: _headerTeal))
                  : _filteredHazards.isEmpty
                  ? Padding(
                      padding: EdgeInsets.only(top: R.blockV * 27.5),
                      child: _buildEmptyState(isDark),
                    )
                  : ListView.builder(
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
                          SizedBox(height: R.blockV * 1.25),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: R.blockH * 12.8),
                              Spacer(),
                              Text(
                                DateFormat('MMMM yyyy').format(_selectedDate),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: R.blockH * 5.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Spacer(),
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
                          SizedBox(height: R.blockV * 1.875),
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
      final dt = DateTime.parse(dateStr).toLocal();
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
    // ✅ Now perfectly targets 'report_number' everywhere
    final String reportNumber = hazard['report_number']?.toString() ?? 'N/A';

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

    String? reporterImage;
    if (hazard['workers'] != null) {
      reporterImage = hazard['workers']['profile_image_url'];
    }

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
              builder: (_) =>
                  ResolvedHazardReportScreen(hazardId: hazard['id'].toString()),
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

                    // ✅ Media Icons placed directly next to the tag
                    if (hasVoiceNotes) ...[
                      SizedBox(width: R.blockH * 2.133),
                      Icon(
                        Icons.mic_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ],
                    if (hasImages) ...[
                      SizedBox(width: R.blockH * 2.133),
                      Icon(
                        Icons.image_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ],

                    Spacer(),

                    // Profile Avatar
                    SizedBox(
                      height: R.blockV * 3.5,
                      width: R.blockH * 7.467,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 2,
                          ),
                          image: reporterImage != null
                              ? DecorationImage(
                                  image: CachedNetworkImageProvider(
                                    reporterImage,
                                  ),
                                  fit: BoxFit.cover,
                                )
                              : null,
                          color: Colors.white24,
                        ),
                        child: reporterImage == null
                            ? Icon(Icons.person, size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
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
            "No hazards found for this day",
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
