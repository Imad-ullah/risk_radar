// lib/workers/screens/worker_ongoing_hazards_screen.dart
// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ✅ Shared Screen & Theme Imports
import 'package:riskradar/shared/hazards/hazard_details_screen.dart';
import 'package:riskradar/shared/theme/app_colors.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';

class WorkerOngoingHazardsScreen extends StatefulWidget {
  const WorkerOngoingHazardsScreen({super.key});

  @override
  State<WorkerOngoingHazardsScreen> createState() =>
      _WorkerOngoingHazardsScreenState();
}

class _WorkerOngoingHazardsScreenState
    extends State<WorkerOngoingHazardsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final HazardRepository _hazardRepository = HazardRepository();
  final SyncRepository _syncRepository = SyncRepository();
  final ScrollController _scrollController = ScrollController();

  static const int _pageSize = 20;
  static const double _loadMoreScrollThreshold = 0.8;

  // --- State Variables ---
  List<Map<String, dynamic>> allHazards = [];
  List<Map<String, dynamic>> filteredHazards = [];

  // Filters
  String? _selectedSeverity;
  String _sortBy = 'newest';
  bool _onlyMyHazards = false;

  // isLoading = true only when there is zero cached data to show.
  // Once cache is painted it stays false even during silent bg refresh.
  bool isLoading = false;

  // True while a background Supabase refresh is running (shows subtle indicator)
  bool _isRefreshing = false;
  bool _isLoadingMore = false;
  bool _hasMoreHazards = true;
  int _currentPage = 0;

  StreamSubscription<Position>? _positionStream;

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _startLocationTracking();
    _loadHazards();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoadingMore ||
        !_hasMoreHazards ||
        isLoading) {
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

  // ══════════════════════════════════════════════════════════════════════════
  // LOCATION TRACKING — offline-safe
  // ══════════════════════════════════════════════════════════════════════════

  void _startLocationTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        _positionStream = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20,
          ),
        ).listen((Position position) async {
          if (!mounted) return;
          final user = supabase.auth.currentUser;
          if (user != null) {
            // Best-effort — silently swallowed if offline
            supabase.from('user_locations').upsert({
              'user_id': user.id,
              'latitude': position.latitude,
              'longitude': position.longitude,
              'updated_at': DateTime.now().toIso8601String(),
            }).catchError((e) {
              debugPrint('ℹ️ [Location] Offline upsert skipped: $e');
            });
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ [Location] Error starting tracking: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DATA LOADING — cache first, Supabase second
  //
  // Boot sequence:
  //   1. Read cached ongoing hazards → paint list instantly (isLoading = false)
  //   2. Silently refresh from Supabase in background
  //      → On success: save to cache + setState
  //      → On SocketException: silently skip, cached data stays
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _loadHazards() async {
    // ── Step 1: Paint from cache immediately ──────────────────────────────
    final cached = await _mergePendingOfflineReports(
      await _hazardRepository.getOngoingHazards(),
    );
    if (cached.isNotEmpty) {
      setState(() {
        allHazards = cached;
        isLoading = false;
      });
      _applyFiltersAndSort();
    } else {
      // No cache — show spinner until first Supabase response
      setState(() => isLoading = true);
    }

    // ── Step 2: Silent background refresh ────────────────────────────────
    await _refreshFromSupabase(resetPagination: true);
  }

  // ── Called by pull-to-refresh and filter Apply button ─────────────────────
  Future<void> fetchOngoingHazards() async {
    await _refreshFromSupabase(resetPagination: true);
  }

  Future<void> _loadNextPage() async {
    if (!_hasMoreHazards || _isLoadingMore) {
      return;
    }

    setState(() => _isLoadingMore = true);
    _currentPage++;
    await _refreshFromSupabase(resetPagination: false);
  }

  Future<void> _refreshFromSupabase({required bool resetPagination}) async {
    if (!mounted) return;
    if (resetPagination) {
      _currentPage = 0;
      _hasMoreHazards = true;
      setState(() => _isRefreshing = true);
    }

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            isLoading = false;
            _isRefreshing = false;
            _isLoadingMore = false;
          });
        }
        return;
      }
      final String userId = user.id;
      final int pageStart = _currentPage * _pageSize;
      final int pageEnd = pageStart + _pageSize - 1;

      // Get worker info — try workers table first, then hse_workers
      var workerData = await supabase
          .from('workers')
          .select('id, officer_uid, current_site_id')
          .eq('id', userId)
          .maybeSingle();

      workerData ??= await supabase
          .from('hse_workers')
          .select('id, officer_uid, current_site_id')
          .eq('id', userId)
          .maybeSingle();

      if (workerData == null) {
        if (mounted) {
          setState(() {
            allHazards = [];
            isLoading = false;
            _isRefreshing = false;
            _isLoadingMore = false;
          });
        }
        return;
      }

      final workerId = workerData['id'];
      final officerUid = workerData['officer_uid']?.toString();
      final currentSiteId = workerData['current_site_id']?.toString();

      List<Map<String, dynamic>> combined = [];
      bool reachedLastPage = true;

      // ── MODE A: MY HAZARDS ONLY ───────────────────────────────────────
      if (_onlyMyHazards) {
        final results = await Future.wait([
          supabase
              .from('hazards')
              .select('*, workers!hazards_worker_id_fkey (*)')
              .eq('worker_id', workerId)
              .order('created_at', ascending: false)
              .range(pageStart, pageEnd),
          supabase
              .from('worker_active_hazards_view')
              .select()
              .or('worker_id.eq.$workerId,assigned_to.eq.$workerId')
              .order('created_at', ascending: false)
              .range(pageStart, pageEnd),
        ]);

        final reportedByMe = results[0] as List<dynamic>;
        final assignedToMe = results[1] as List<dynamic>;
        reachedLastPage =
            reportedByMe.length < _pageSize && assignedToMe.length < _pageSize;
        combined = [
          ...reportedByMe.cast<Map<String, dynamic>>(),
          ...assignedToMe.cast<Map<String, dynamic>>(),
        ];
      }

      // ── MODE B: ALL SITE HAZARDS (Default) ───────────────────────────
      else {
        if (officerUid == null || currentSiteId == null) {
          debugPrint('⚠️ [OngoingHazards] Missing site context.');
          if (mounted) {
            setState(() {
              isLoading = false;
              _isRefreshing = false;
              _isLoadingMore = false;
            });
          }
          return;
        }

        final results = await Future.wait([
          supabase
              .from('hazards')
              .select('*, workers!hazards_worker_id_fkey (*)')
              .eq('officer_uid', officerUid)
              .eq('current_site_id', currentSiteId)
              .eq('status', 'reported')
              .order('created_at', ascending: false)
              .range(pageStart, pageEnd),
          supabase
              .from('worker_active_hazards_view')
              .select()
              .eq('officer_uid', officerUid)
              .eq('current_site_id', currentSiteId)
              .inFilter('status', ['assigned', 'Assigned', 'in_progress', 'In Progress'])
              .order('created_at', ascending: false)
              .range(pageStart, pageEnd),
        ]);

        final hazardsResponse = results[0] as List<dynamic>;
        final assignedResponse = results[1] as List<dynamic>;
        reachedLastPage =
            hazardsResponse.length < _pageSize && assignedResponse.length < _pageSize;
        combined = [
          ...hazardsResponse.cast<Map<String, dynamic>>(),
          ...assignedResponse.cast<Map<String, dynamic>>(),
        ];
      }

      final List<Map<String, dynamic>> updatedHazards = resetPagination
          ? combined
          : <Map<String, dynamic>>[...allHazards, ...combined];
      final List<Map<String, dynamic>> visibleHazards =
          await _mergePendingOfflineReports(updatedHazards);

      // Persist to cache
      await _hazardRepository.saveOngoingHazards(visibleHazards);

      if (!mounted) return;
      setState(() {
        allHazards = visibleHazards;
        _hasMoreHazards = !reachedLastPage;
        isLoading = false;
        _isRefreshing = false;
        _isLoadingMore = false;
      });
      _applyFiltersAndSort();

    } on SocketException {
      // Offline — cached data already visible, nothing to do
      debugPrint('ℹ️ [OngoingHazards] Offline — showing cached data.');
      if (mounted) {
        setState(() {
          isLoading = false;
          _isRefreshing = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ [OngoingHazards] Refresh error: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          _isRefreshing = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FILTERING & SORTING — unchanged logic
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> _mergePendingOfflineReports(
    List<Map<String, dynamic>> baseRows,
  ) async {
    final String? userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return baseRows;
    }

    final Map<String, Map<String, dynamic>> rowsById =
        <String, Map<String, dynamic>>{};

    void addRow(Map<String, dynamic> row) {
      final String? id = row['id']?.toString();
      if (id == null || id.isEmpty) {
        return;
      }
      rowsById[id] = Map<String, dynamic>.from(row);
    }

    for (final Map<String, dynamic> row in baseRows) {
      addRow(row);
    }

    try {
      final List<Map<String, dynamic>> pendingActions =
          await _syncRepository.getPendingActions();

      for (final Map<String, dynamic> action in pendingActions) {
        if (action['table'] != 'hazards' || action['action'] != 'insert') {
          continue;
        }

        final payload = action['payload'];
        if (payload is! Map) {
          continue;
        }

        final Map<String, dynamic> hazard =
            Map<String, dynamic>.from(payload);
        final String? workerId = hazard['worker_id']?.toString();
        if (workerId != userId || !_isActiveHazardStatus(hazard['status'])) {
          continue;
        }

        hazard['offline_pending'] = true;
        addRow(hazard);
      }
    } catch (e) {
      debugPrint('[OngoingHazards] Pending offline merge failed: $e');
    }

    return rowsById.values.toList(growable: false);
  }

  bool _isActiveHazardStatus(dynamic status) {
    final String normalized = status?.toString().toLowerCase().trim() ?? '';
    return normalized != 'resolved' && normalized != 'resolved by other';
  }

  void _applyFiltersAndSort() {
    List<Map<String, dynamic>> tempHazards = List.from(allHazards);

    if (_selectedSeverity != null) {
      tempHazards = tempHazards.where((hazard) {
        final severity = hazard['severity']?.toString().toLowerCase() ?? '';
        return severity == _selectedSeverity;
      }).toList();
    }

    tempHazards.sort((a, b) {
      final aTime = DateTime.tryParse(
          a['created_at'] ?? a['assigned_at'] ?? '') ??
          DateTime(1970);
      final bTime = DateTime.tryParse(
          b['created_at'] ?? b['assigned_at'] ?? '') ??
          DateTime(1970);
      return _sortBy == 'newest'
          ? bTime.compareTo(aTime)
          : aTime.compareTo(bTime);
    });

    setState(() => filteredHazards = tempHazards);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FILTER SHEET — unchanged
  // ══════════════════════════════════════════════════════════════════════════

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final headerColor =
            isDark ? Colors.white : AppColors.brandTeal;

            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey[700]
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text("Filter Options",
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: headerColor,
                      )),
                  const SizedBox(height: 24),
                  Text("View Scope",
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: headerColor,
                      )),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Show only my hazards",
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: const Text(
                        "Only show hazards reported by or assigned to me",
                        style: TextStyle(fontSize: 12)),
                    value: _onlyMyHazards,
                    activeThumbColor: AppColors.accentGold,
                    onChanged: (bool value) {
                      setSheetState(() => _onlyMyHazards = value);
                    },
                  ),
                  Divider(
                      height: 32,
                      color: isDark ? Colors.grey[800] : Colors.grey[200]),
                  Text("Severity",
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: headerColor,
                      )),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10.0,
                    runSpacing: 10.0,
                    children: [
                      _buildFilterChip(
                          "All", null, setSheetState, isDark),
                      _buildFilterChip(
                          "High", "high", setSheetState, isDark),
                      _buildFilterChip(
                          "Moderate", "moderate", setSheetState, isDark),
                      _buildFilterChip(
                          "Low", "low", setSheetState, isDark),
                    ],
                  ),
                  Divider(
                      height: 32,
                      color: isDark ? Colors.grey[800] : Colors.grey[200]),
                  Text("Sort by Date",
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: headerColor,
                      )),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10.0,
                    children: [
                      _buildSortChip(
                          "Newest First", "newest", setSheetState, isDark),
                      _buildSortChip(
                          "Oldest First", "oldest", setSheetState, isDark),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding:
                        const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.brandTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text("Apply Filters",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(context);
                        fetchOngoingHazards();
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String? severityValue,
      StateSetter setSheetState, bool isDark) {
    final bool isSelected = _selectedSeverity == severityValue;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setSheetState(() => _selectedSeverity = severityValue);
        }
      },
      selectedColor: AppColors.accentGold,
      backgroundColor:
      isDark ? const Color(0xFF2C2C2C) : Colors.white,
      labelStyle: TextStyle(
          color: isSelected
              ? AppColors.brandTeal
              : (isDark ? Colors.grey[300] : AppColors.brandTeal),
          fontWeight: FontWeight.bold),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: isSelected
                  ? AppColors.accentGold
                  : (isDark ? Colors.grey[800]! : Colors.grey[300]!))),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  Widget _buildSortChip(String label, String sortValue,
      StateSetter setSheetState, bool isDark) {
    final bool isSelected = _sortBy == sortValue;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setSheetState(() => _sortBy = sortValue);
        }
      },
      selectedColor: AppColors.accentGold,
      backgroundColor:
      isDark ? const Color(0xFF2C2C2C) : Colors.white,
      labelStyle: TextStyle(
          color: isSelected
              ? AppColors.brandTeal
              : (isDark ? Colors.grey[300] : AppColors.brandTeal),
          fontWeight: FontWeight.bold),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: isSelected
                  ? AppColors.accentGold
                  : (isDark ? Colors.grey[800]! : Colors.grey[300]!))),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SUB HEADER
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSubHeader() {
    final count = filteredHazards.length;
    final hazardText = count == 1 ? "Hazard" : "Hazards";
    final contextText =
    _onlyMyHazards ? "My Hazards" : "Site Hazards";
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contextText,
                      style: TextStyle(
                        color: isDark
                            ? Colors.white
                            : Theme.of(context).primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      "$count $hazardText Found",
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey[400]
                            : Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                // Subtle refresh indicator — doesn't block the UI
                if (_isRefreshing) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark
                          ? Colors.white54
                          : AppColors.brandTeal.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton.icon(
            icon: Icon(
              Icons.tune_rounded,
              size: 20,
              color: isDark
                  ? Colors.white
                  : Theme.of(context).primaryColor,
            ),
            label: Text(
              "Filter",
              style: TextStyle(
                color: isDark
                    ? Colors.white
                    : Theme.of(context).primaryColor,
              ),
            ),
            onPressed: _showFilterSheet,
            style: TextButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Theme.of(context)
                  .primaryColor
                  .withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: fetchOngoingHazards,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            _buildSubHeader(),
            Expanded(
              child: allHazards.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        _onlyMyHazards
                            ? Icons.person_off_outlined
                            : Icons.check_circle_outline,
                        size: 64,
                        color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                        _onlyMyHazards
                            ? "You have no active hazards."
                            : "No ongoing hazards on this site.",
                        style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color)),
                  ],
                ),
              )
                  : filteredHazards.isEmpty
                  ? Center(
                  child: Text(
                      "No hazards match the current filter.",
                      style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color)))
                  : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(
                    12, 12, 12, 100),
                itemCount: filteredHazards.length +
                    (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == filteredHazards.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandTeal,
                        ),
                      ),
                    );
                  }
                  return _CompactHazardCard(
                    hazard: filteredHazards[index],
                    index: index,
                    currentUserId: currentUserId,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HAZARD CARD — completely unchanged
// ══════════════════════════════════════════════════════════════════════════════

class _CompactHazardCard extends StatelessWidget {
  const _CompactHazardCard({
    required this.hazard,
    required this.index,
    required this.currentUserId,
  });

  final Map<String, dynamic> hazard;
  final int index;
  final String? currentUserId;

  Color getPrimaryColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'low':
        return const Color(0xFF10B981);
      case 'moderate':
        return const Color(0xFFF59E0B);
      case 'high':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Color getSecondaryColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'low':
        return const Color(0xFF059669);
      case 'moderate':
        return const Color(0xFFD97706);
      case 'high':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF4B5563);
    }
  }

  String getHazardSvgPath(String? type) {
    final t = type?.toLowerCase() ?? '';
    if (t.contains('fire')) return 'assets/hazards/fire_warning.svg';
    if (t.contains('electric') ||
        t.contains('shock') ||
        t.contains('electrocution'))
      return 'assets/hazards/electric_shock.svg';
    if (t.contains('slip') ||
        t.contains('trip') ||
        t.contains('wet') ||
        t.contains('fall'))
      return 'assets/hazards/slip_falling.svg';
    if (t.contains('height') || t.contains('stair'))
      return 'assets/hazards/stairs_fall.svg';
    if (t.contains('falling object') || t.contains('drop'))
      return 'assets/hazards/falling_objects.svg';
    if (t.contains('chemical') || t.contains('radio'))
      return 'assets/hazards/radio_active.svg';
    if (t.contains('heat') || t.contains('temperature'))
      return 'assets/hazards/high_temperature.svg';
    if (t.contains('machine') || t.contains('crush'))
      return 'assets/hazards/machine_crush.svg';
    if (t.contains('explosion') || t.contains('blast'))
      return 'assets/hazards/explosion.svg';
    if (t.contains('freeze') || t.contains('cold'))
      return 'assets/hazards/freeze.svg';
    if (t.contains('load') || t.contains('lifting'))
      return 'assets/hazards/load_lifting.svg';
    if (t.contains('wave')) return 'assets/hazards/radio_waves.svg';
    if (t.contains('magnetic')) return 'assets/hazards/magnetic_field.svg';
    return 'assets/hazards/fire_warning.svg';
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'N/A';
    try {
      DateTime utcDateTime;
      if (isoString.endsWith('Z') || isoString.contains('+')) {
        utcDateTime = DateTime.parse(isoString).toUtc();
      } else {
        utcDateTime = DateTime.parse("${isoString}Z").toUtc();
      }
      final localDateTime = utcDateTime.toLocal();
      return DateFormat('MMM d, h:mm a').format(localDateTime);
    } catch (e) {
      debugPrint('Error parsing date: $e');
      return 'N/A';
    }
  }

  String _capitalizeName(String name) {
    if (name.isEmpty) return name;
    return name.split(' ').map((word) {
      if (word.isEmpty) return '';
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  Widget _buildDetailRow({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reporter = hazard['workers'] ?? hazard['reporter'];
    final String reporterId =
        hazard['worker_id'] ?? (reporter != null ? reporter['id'] : '');
    final bool isReportedByMe =
        currentUserId != null && reporterId == currentUserId;

    String rawName = '';
    String? reporterImageUrl;

    if (reporter != null) {
      rawName = '${reporter['first_name']} ${reporter['last_name']}';
      reporterImageUrl = reporter['profile_image_url'];
    } else if (hazard['reporter_first_name'] != null) {
      rawName =
      '${hazard['reporter_first_name']} ${hazard['reporter_last_name']}';
      reporterImageUrl = hazard['reporter_image'];
    } else {
      rawName = hazard['reporter_name'] ?? 'Unknown User';
      reporterImageUrl = hazard['reporter_image'];
    }

    final reporterWorkType =
        reporter?['work_type'] ?? hazard['reporter_work_type'] ?? 'Worker';

    final Map<String, dynamic> passedWorkerInfo = reporter ?? {
      'id': reporterId,
      'first_name': hazard['reporter_first_name'] ??
          rawName.split(' ').first,
      'last_name': hazard['reporter_last_name'] ??
          (rawName.split(' ').length > 1 ? rawName.split(' ').last : ''),
      'work_type': reporterWorkType,
      'profile_image_url': reporterImageUrl,
    };

    final List officersList = hazard['all_assigned_officers'] ?? [];

    final images = (hazard['image_url'] != null &&
        hazard['image_url'].toString().isNotEmpty)
        ? hazard['image_url']
        .toString()
        .split(',')
        .map((e) => e.trim())
        .toList()
        : <String>[];
    final voiceUrls = (hazard['voice_note_url'] != null &&
        hazard['voice_note_url'].toString().trim().isNotEmpty)
        ? hazard['voice_note_url']
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList()
        : <String>[];

    final String title = hazard['hazard_type'] ?? 'No Type';
    final String description =
        hazard['description'] ?? 'No description provided.';
    final String severity = hazard['severity'] ?? 'Unknown';
    final String status = hazard['status'] ?? 'Unknown';
    final String timestamp = _formatTimestamp(
        hazard['created_at'] ?? hazard['assigned_at']);

    final bool hasImages = images.isNotEmpty;
    final bool hasVoiceNotes = voiceUrls.isNotEmpty;

    final primaryColor = getPrimaryColor(severity);
    final secondaryColor = getSecondaryColor(severity);

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryColor.withValues(alpha: 0.95), secondaryColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HazardDetailsScreen(
                    hazardData: {
                      ...hazard,
                      'workers': passedWorkerInfo,
                      'assign_hazards': officersList.isNotEmpty
                          ? officersList
                          : (hazard['hse_worker'] != null ? [hazard] : []),
                      'hazard_type': title,
                      'description': description,
                      'images': images,
                      'reporter_name': isReportedByMe
                          ? "Me"
                          : '${_capitalizeName(rawName)} ($reporterWorkType)',
                      'severity': severity,
                      'status': status,
                      'created_at':
                      hazard['created_at'] ?? hazard['assigned_at'],
                      'assigned_at': hazard['assigned_at'],
                      'latitude': hazard['latitude'],
                      'longitude': hazard['longitude'],
                      'voice_note_url': hazard['voice_note_url'] ?? '',
                    },
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        getHazardSvgPath(title),
                        width: 32,
                        height: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                severity.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (hasImages || hasVoiceNotes)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              children: [
                                if (hasImages)
                                  Icon(Icons.photo_library_rounded,
                                      size: 16,
                                      color: Colors.white
                                          .withValues(alpha: 0.8)),
                                if (hasImages) const SizedBox(width: 4),
                                if (hasImages)
                                  Text(images.length.toString(),
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.8),
                                          fontSize: 12)),
                                if (hasImages && hasVoiceNotes)
                                  const SizedBox(width: 12),
                                if (hasVoiceNotes)
                                  Icon(Icons.mic_rounded,
                                      size: 16,
                                      color: Colors.white
                                          .withValues(alpha: 0.8)),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.3),
                              height: 1),
                        ),
                        _buildDetailRow(
                            icon: Icons.flag_rounded, text: status),
                        const SizedBox(height: 8),
                        _buildDetailRow(
                          icon: Icons.person_rounded,
                          text: isReportedByMe
                              ? "Me"
                              : _capitalizeName(rawName),
                        ),
                        const SizedBox(height: 8),
                        _buildDetailRow(
                            icon: Icons.schedule_rounded, text: timestamp),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
