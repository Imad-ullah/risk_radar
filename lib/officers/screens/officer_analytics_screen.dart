// lib/officers/screens/officer_analytics_screen.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/shared/theme/app_colors.dart';

enum TimeFilter { today, week, month, allTime }

class OfficerAnalyticsScreen extends StatefulWidget {
  const OfficerAnalyticsScreen({super.key});

  @override
  State<OfficerAnalyticsScreen> createState() => _OfficerAnalyticsScreenState();
}

class _OfficerAnalyticsScreenState extends State<OfficerAnalyticsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _isLoading = true;
  TimeFilter _selectedFilter = TimeFilter.allTime;
  String? _selectedSiteId; // null = All Sites

  // Raw Data Caches
  List<Map<String, dynamic>> _rawReported = [];
  List<Map<String, dynamic>> _rawAssigned = [];
  List<Map<String, dynamic>> _rawResolved = [];
  List<Map<String, dynamic>> _availableSites = [];

  // Filtered & Calculated Variables
  int _totalHazards = 0;
  double _resolutionRatePercentage = 0.0;
  double _resolutionTimeAvg = 0.0;
  int _sitesMonitoredTotal = 0;
  int _sitesActiveCount = 0;

  int _reportedCount = 0;
  int _inProgressCount = 0;
  int _resolvedCount = 0;

  // Chart Data
  List<MapEntry<String, int>> _topHazardsByType = [];
  int _highSeverityCount = 0;
  int _moderateSeverityCount = 0;
  int _lowSeverityCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAnalyticsCacheFirst();
  }

  Future<void> _loadAnalyticsCacheFirst() async {
    final cached = OfficerRepository.instance.getOfficerAnalytics();
    if (cached != null) {
      _rawReported = List<Map<String, dynamic>>.from(cached['reported'] ?? []);
      _rawAssigned = List<Map<String, dynamic>>.from(cached['assigned'] ?? []);
      _rawResolved = List<Map<String, dynamic>>.from(cached['resolved'] ?? []);
      _availableSites = List<Map<String, dynamic>>.from(cached['sites'] ?? []);
      _applyFilter();
      setState(() => _isLoading = false);
    }

    await _fetchAnalyticsData(showBlockingLoader: cached == null);
  }

  Future<void> _fetchAnalyticsData({bool showBlockingLoader = true}) async {
    if (showBlockingLoader) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        return;
      }

      final officerProfile = await supabase
          .from('officers')
          .select('officer_uid')
          .eq('id', currentUserId)
          .maybeSingle();

      final officerUid = officerProfile?['officer_uid'];
      if (officerUid == null) {
        throw Exception("Officer UID not found");
      }

      // 1. Fetch available sites for the filter
      final sitesRes = await supabase
          .from('sites')
          .select('id, name')
          .eq('officer_uid', officerUid);
      _availableSites = List<Map<String, dynamic>>.from(sitesRes);

      // 2. Fetch Reported (Unassigned/Pending) hazards directly from hazards table
      _rawReported = await supabase
          .from('hazards')
          .select('id, current_site_id, created_at, hazard_type, severity')
          .eq('officer_uid', officerUid)
          .eq('status', 'Reported');

      // 3. Fetch In-Progress (Assigned)
      _rawAssigned = await supabase
          .from('worker_active_hazards_view')
          .select('id, current_site_id, created_at, hazard_type, severity')
          .eq('officer_uid', officerUid);

      // 4. Fetch Resolved
      _rawResolved = await supabase
          .from('resolved_hazards')
          .select(
            'id, current_site_id, created_at, resolved_at, hazard_type, severity',
          )
          .eq('officer_uid', officerUid);

      await OfficerRepository.instance.saveOfficerAnalytics({
        'sites': _availableSites,
        'reported': _rawReported,
        'assigned': _rawAssigned,
        'resolved': _rawResolved,
      });

      _applyFilter();
    } on SocketException {
      debugPrint("Officer analytics offline - using cached data.");
    } catch (e) {
      debugPrint("Error fetching analytics: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilter() {
    DateTime now = DateTime.now();
    DateTime? threshold;

    switch (_selectedFilter) {
      case TimeFilter.today:
        threshold = now.subtract(const Duration(days: 1));
        break;
      case TimeFilter.week:
        threshold = now.subtract(const Duration(days: 7));
        break;
      case TimeFilter.month:
        threshold = now.subtract(const Duration(days: 30));
        break;
      case TimeFilter.allTime:
        threshold = null;
        break;
    }

    bool isMatch(Map<String, dynamic> h, String dateField) {
      // 1. Check Site Filter
      if (_selectedSiteId != null &&
          h['current_site_id'].toString() != _selectedSiteId) {
        return false;
      }
      // 2. Check Time Filter
      if (threshold != null && h[dateField] != null) {
        DateTime dt = DateTime.parse(h[dateField]).toLocal();
        if (dt.isBefore(threshold)) {
          return false;
        }
      }
      return true;
    }

    // 1. Filter the lists
    final filteredReported = _rawReported
        .where((h) => isMatch(h, 'created_at'))
        .toList();
    final filteredAssigned = _rawAssigned
        .where((h) => isMatch(h, 'created_at'))
        .toList();

    final Map<String, dynamic> uniqueResolved = {};
    for (var hazard in _rawResolved) {
      if (isMatch(hazard, 'created_at')) {
        uniqueResolved[hazard['id'].toString()] = hazard;
      }
    }
    final filteredResolved = uniqueResolved.values.toList();

    // 2. Base KPIs
    _reportedCount = filteredReported.length;
    _inProgressCount = filteredAssigned.length;
    _resolvedCount = filteredResolved.length;

    _totalHazards = _reportedCount + _inProgressCount + _resolvedCount;
    if (_totalHazards > 0) {
      _resolutionRatePercentage = _resolvedCount / _totalHazards;
    } else {
      _resolutionRatePercentage = 0.0;
    }

    // 3. Average Resolution Time
    double totalHours = 0;
    int validTimeRecords = 0;

    for (var hazard in filteredResolved) {
      if (hazard['created_at'] != null && hazard['resolved_at'] != null) {
        final DateTime created = DateTime.parse(hazard['created_at']);
        final DateTime resolved = DateTime.parse(hazard['resolved_at']);
        final double hoursTaken =
            resolved.difference(created).inMinutes.abs() / 60.0;
        totalHours += hoursTaken;
        validTimeRecords++;
      }
    }
    if (validTimeRecords > 0) {
      _resolutionTimeAvg = totalHours / validTimeRecords;
    } else {
      _resolutionTimeAvg = 0.0;
    }

    // 4. Sites Monitored
    final Set<String> activeSites = {};
    final Set<String> allSites = {};

    void trackSite(Map<String, dynamic> h, bool isActive) {
      if (h['current_site_id'] != null) {
        final siteId = h['current_site_id'].toString();
        if (isActive) {
          activeSites.add(siteId);
        }
        allSites.add(siteId);
      }
    }

    for (var h in filteredReported) {
      trackSite(h, true);
    }
    for (var h in filteredAssigned) {
      trackSite(h, true);
    }
    for (var h in filteredResolved) {
      trackSite(h, false);
    }

    _sitesActiveCount = activeSites.length;
    _sitesMonitoredTotal = allSites.length;

    // 5. Chart Data: Hazards by Type & Severity
    Map<String, int> typeCounts = {};
    _highSeverityCount = 0;
    _moderateSeverityCount = 0;
    _lowSeverityCount = 0;

    void processChartData(Map<String, dynamic> hazard) {
      String type = hazard['hazard_type']?.toString().trim() ?? 'Other';
      if (type.isEmpty) {
        type = 'Other';
      }
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;

      String severity =
          hazard['severity']?.toString().toLowerCase().trim() ?? 'low';
      if (severity == 'high') {
        _highSeverityCount++;
      } else if (severity == 'moderate') {
        _moderateSeverityCount++;
      } else {
        _lowSeverityCount++;
      }
    }

    for (var h in filteredReported) {
      processChartData(h);
    }
    for (var h in filteredAssigned) {
      processChartData(h);
    }
    for (var h in filteredResolved) {
      processChartData(h);
    }

    var sortedTypes = typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _topHazardsByType = sortedTypes.take(5).toList();
  }

  String _getFilterLabel(TimeFilter filter) {
    switch (filter) {
      case TimeFilter.today:
        return "Last 24h";
      case TimeFilter.week:
        return "Last 7 Days";
      case TimeFilter.month:
        return "Last 30 Days";
      case TimeFilter.allTime:
        return "All Time";
    }
  }

  String _shortenLabel(String text) {
    if (text.length > 8) {
      return '${text.substring(0, 6)}..';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = isDark ? Colors.grey.shade900 : Colors.white;
    final filterTextColor = isDark ? Colors.white : AppColors.brandTeal;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'System Analytics',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.brandTeal,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.brandTeal))
          : RefreshIndicator(
              onRefresh: () => _fetchAnalyticsData(showBlockingLoader: false),
              color: AppColors.brandTeal,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(R.blockH * 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dashboard Header with Filter Dropdowns
                    Text(
                      'EXECUTIVE VISIBILITY',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: R.blockH * 3,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: R.blockV * 0.5),
                    Text(
                      'Dashboard & KPIs',
                      style: TextStyle(
                        fontSize: R.blockH * 5.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.brandTeal,
                      ),
                    ),
                    SizedBox(height: R.blockV * 2.5),

                    // Filter Row (Now fully restored and properly wrapped)
                    Row(
                      children: [
                        // TIME FILTER
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: R.blockH * 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.brandTeal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<TimeFilter>(
                                isExpanded: true,
                                value: _selectedFilter,
                                icon: Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: filterTextColor,
                                ),
                                style: TextStyle(
                                  color: filterTextColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: R.blockH * 3.25,
                                ),
                                dropdownColor: cardColor,
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedFilter = val;
                                      _applyFilter();
                                    });
                                  }
                                },
                                items: TimeFilter.values.map((
                                  TimeFilter filter,
                                ) {
                                  return DropdownMenuItem<TimeFilter>(
                                    value: filter,
                                    child: Text(_getFilterLabel(filter)),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: R.blockH * 3.2),

                        // SITE FILTER
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: R.blockH * 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.brandTeal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true,
                                value: _selectedSiteId,
                                icon: Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: filterTextColor,
                                ),
                                style: TextStyle(
                                  color: filterTextColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: R.blockH * 3.25,
                                ),
                                dropdownColor: cardColor,
                                onChanged: (val) {
                                  setState(() {
                                    _selectedSiteId = val;
                                    _applyFilter();
                                  });
                                },
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text("All Sites"),
                                  ),
                                  ..._availableSites.map((site) {
                                    return DropdownMenuItem<String?>(
                                      value: site['id'].toString(),
                                      child: Text(
                                        site['name'] ?? 'Unknown Site',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: R.blockV * 3),

                    // KPI Grid
                    Row(
                      children: [
                        Expanded(
                          child: _buildKPICard(
                            icon: Icons.warning_amber_rounded,
                            label: "Total Hazards",
                            value: _totalHazards.toString(),
                            indicatorLabel: _getFilterLabel(_selectedFilter),
                            indicatorColor: Colors.blue.shade600,
                            backgroundColor: cardColor,
                            isDark: isDark,
                          ),
                        ),
                        SizedBox(width: R.blockH * 4.267),
                        Expanded(
                          child: _buildKPICard(
                            icon: Icons.access_time_filled_rounded,
                            label: "Avg. Time",
                            value: "${_resolutionTimeAvg.toStringAsFixed(1)}h",
                            indicatorLabel: "per hazard",
                            indicatorColor: const Color(0xFF10B981),
                            backgroundColor: cardColor,
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: R.blockV * 2),
                    Row(
                      children: [
                        Expanded(
                          child: _buildKPICard(
                            icon: Icons.check_circle_rounded,
                            label: "Resolution",
                            value:
                                "${(_resolutionRatePercentage * 100).toInt()}%",
                            indicatorLabel: _resolutionRatePercentage > 0.8
                                ? "On target"
                                : "Needs Review",
                            indicatorColor: _resolutionRatePercentage > 0.8
                                ? const Color(0xFF10B981)
                                : Colors.orange,
                            backgroundColor: cardColor,
                            isDark: isDark,
                          ),
                        ),
                        SizedBox(width: R.blockH * 4.267),
                        Expanded(
                          child: _buildKPICard(
                            icon: Icons.location_on_rounded,
                            label: "Sites Checked",
                            value: _sitesMonitoredTotal.toString(),
                            indicatorLabel: "$_sitesActiveCount active",
                            indicatorColor: _sitesActiveCount > 0
                                ? Colors.red.shade600
                                : Colors.grey,
                            backgroundColor: cardColor,
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: R.blockV * 3),

                    // Charts
                    _buildDonutChartCard(
                      backgroundColor: cardColor,
                      isDark: isDark,
                    ),
                    SizedBox(height: R.blockV * 3),

                    _buildBarChartCard(
                      backgroundColor: cardColor,
                      isDark: isDark,
                    ),
                    SizedBox(height: R.blockV * 3),

                    _buildSeverityChartCard(
                      backgroundColor: cardColor,
                      isDark: isDark,
                    ),
                    SizedBox(height: R.blockV * 5),
                  ],
                ),
              ),
            ),
    );
  }

  // --- Helper Builders ---

  Widget _buildKPICard({
    required IconData icon,
    required String label,
    required String value,
    required String indicatorLabel,
    required Color indicatorColor,
    required Color backgroundColor,
    required bool isDark,
  }) {
    return Container(
      padding: EdgeInsets.all(R.blockH * 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.brandTeal, size: 24),
              SizedBox(width: R.blockH * 2.133),
              Flexible(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: R.blockH * 1.5,
                    vertical: R.blockV * 0.5,
                  ),
                  decoration: BoxDecoration(
                    color: indicatorColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      indicatorLabel,
                      style: TextStyle(
                        color: indicatorColor,
                        fontWeight: FontWeight.w600,
                        fontSize: R.blockH * 2.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: R.blockV * 1.5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: R.blockH * 7,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: R.blockH * 2.75,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDonutChartCard({
    required Color backgroundColor,
    required bool isDark,
  }) {
    double resolvedPercent = 0.0;
    double inProgressPercent = 0.0;
    double reportedPercent = 0.0;

    if (_totalHazards > 0) {
      resolvedPercent = _resolvedCount / _totalHazards;
      inProgressPercent = _inProgressCount / _totalHazards;
      reportedPercent = _reportedCount / _totalHazards;
    }

    return Container(
      padding: EdgeInsets.all(R.blockH * 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hazard Status Distribution',
            style: TextStyle(
              fontSize: R.blockH * 4,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: R.blockV * 2.5),
          if (_totalHazards == 0)
            SizedBox(
              height: R.blockV * 18.75,
              child: Center(child: Text("No hazards in this period.")),
            )
          else
            AspectRatio(
              aspectRatio: 1.5,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 50,
                  sections: [
                    PieChartSectionData(
                      color: const Color(0xFF10B981),
                      value: resolvedPercent,
                      title: "${(resolvedPercent * 100).toStringAsFixed(1)}%",
                      radius: 30,
                      titleStyle: TextStyle(
                        fontSize: R.blockH * 2.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      color: const Color(0xFF172554),
                      value: inProgressPercent,
                      title: "${(inProgressPercent * 100).toStringAsFixed(1)}%",
                      radius: 30,
                      titleStyle: TextStyle(
                        fontSize: R.blockH * 2.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      color: const Color(0xFFF59E0B),
                      value: reportedPercent,
                      title: "${(reportedPercent * 100).toStringAsFixed(1)}%",
                      radius: 30,
                      titleStyle: TextStyle(
                        fontSize: R.blockH * 2.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SizedBox(height: R.blockV * 2),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem(
                color: const Color(0xFF10B981),
                label: "Resolved ($_resolvedCount)",
              ),
              _buildLegendItem(
                color: const Color(0xFF172554),
                label: "In Progress ($_inProgressCount)",
              ),
              _buildLegendItem(
                color: const Color(0xFFF59E0B),
                label: "Reported ($_reportedCount)",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBarChartCard({
    required Color backgroundColor,
    required bool isDark,
  }) {
    final textColor = isDark ? Colors.white70 : Colors.black54;
    final axisLineColor = isDark ? Colors.white30 : Colors.black26;

    double maxY = 5.0;
    for (var entry in _topHazardsByType) {
      if (entry.value > maxY) {
        maxY = entry.value.toDouble() + 2;
      }
    }

    double yInterval = (maxY / 4).ceilToDouble();
    if (yInterval <= 0) {
      yInterval = 1.0;
    }

    return Container(
      padding: EdgeInsets.all(R.blockH * 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top Hazards by Type',
                style: TextStyle(
                  fontSize: R.blockH * 4,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(Icons.bar_chart_rounded, color: Colors.grey.shade400),
            ],
          ),
          SizedBox(height: R.blockV * 2.5),

          if (_topHazardsByType.isEmpty)
            SizedBox(
              height: R.blockV * 18.75,
              child: Center(child: Text("No hazards in this period.")),
            )
          else
            AspectRatio(
              aspectRatio: 1.3,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: TextStyle(
                              color: textColor,
                              fontSize: R.blockH * 2.5,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= _topHazardsByType.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: EdgeInsets.only(top: R.blockV * 1),
                            child: Text(
                              _shortenLabel(
                                _topHazardsByType[value.toInt()].key,
                              ),
                              style: TextStyle(
                                color: textColor,
                                fontSize: R.blockH * 2.5,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      left: BorderSide(color: axisLineColor, width: 1.5),
                      bottom: BorderSide(color: axisLineColor, width: 1.5),
                      top: BorderSide.none,
                      right: BorderSide.none,
                    ),
                  ),
                  barGroups: List.generate(_topHazardsByType.length, (index) {
                    final int value = _topHazardsByType[index].value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: value.toDouble(),
                          color: AppColors.brandTeal,
                          width: R.blockH * 5.333,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(4),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxY,
                            color: AppColors.brandTeal.withValues(alpha: 0.05),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSeverityChartCard({
    required Color backgroundColor,
    required bool isDark,
  }) {
    final textColor = isDark ? Colors.white70 : Colors.black54;
    final axisLineColor = isDark ? Colors.white30 : Colors.black26;

    double maxY = 5.0;
    if (_highSeverityCount > maxY) {
      maxY = _highSeverityCount.toDouble() + 2;
    }
    if (_moderateSeverityCount > maxY) {
      maxY = _moderateSeverityCount.toDouble() + 2;
    }
    if (_lowSeverityCount > maxY) {
      maxY = _lowSeverityCount.toDouble() + 2;
    }

    double yInterval = (maxY / 4).ceilToDouble();
    if (yInterval <= 0) {
      yInterval = 1.0;
    }

    return Container(
      padding: EdgeInsets.all(R.blockH * 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hazards by Severity',
                style: TextStyle(
                  fontSize: R.blockH * 4,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(Icons.assessment_outlined, color: Colors.grey.shade400),
            ],
          ),
          SizedBox(height: R.blockV * 2.5),

          if (_totalHazards == 0)
            SizedBox(
              height: R.blockV * 18.75,
              child: Center(child: Text("No hazards in this period.")),
            )
          else
            AspectRatio(
              aspectRatio: 1.3,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: TextStyle(
                              color: textColor,
                              fontSize: R.blockH * 2.5,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          String text = '';
                          if (value.toInt() == 0) {
                            text = 'High';
                          } else if (value.toInt() == 1) {
                            text = 'Moderate';
                          } else if (value.toInt() == 2) {
                            text = 'Low';
                          }

                          return Padding(
                            padding: EdgeInsets.only(top: R.blockV * 1),
                            child: Text(
                              text,
                              style: TextStyle(
                                color: textColor,
                                fontSize: R.blockH * 2.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      left: BorderSide(color: axisLineColor, width: 1.5),
                      bottom: BorderSide(color: axisLineColor, width: 1.5),
                      top: BorderSide.none,
                      right: BorderSide.none,
                    ),
                  ),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: _highSeverityCount.toDouble(),
                          color: Colors.red.shade400,
                          width: R.blockH * 7.467,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: _moderateSeverityCount.toDouble(),
                          color: Colors.orange.shade400,
                          width: R.blockH * 7.467,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 2,
                      barRods: [
                        BarChartRodData(
                          toY: _lowSeverityCount.toDouble(),
                          color: const Color(0xFF10B981),
                          width: R.blockH * 7.467,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: R.blockH * 2.667,
          height: R.blockV * 1.25,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: R.blockH * 1.6),
        Text(
          label,
          style: TextStyle(fontSize: R.blockH * 2.5, color: Colors.grey),
        ),
      ],
    );
  }
}
