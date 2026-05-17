// lib/officers/screens/active_task.dart
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/shared/theme/app_colors.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../shared/hazards/hazard_details_screen.dart';

String capitalize(String name) {
  if (name.isEmpty) return '';
  return name[0].toUpperCase() + name.substring(1).toLowerCase();
}

class ViewAssignedHazardsScreen extends StatefulWidget {
  const ViewAssignedHazardsScreen({super.key});

  @override
  State<ViewAssignedHazardsScreen> createState() =>
      _ViewAssignedHazardsScreenState();
}

class _ViewAssignedHazardsScreenState extends State<ViewAssignedHazardsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final HazardRepository _hazardRepository = HazardRepository();
  final ScrollController _scrollController = ScrollController();

  static const int _pageSize = 20;
  static const double _loadMoreScrollThreshold = 0.8;

  bool isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreHazards = true;
  int _currentPage = 0;
  List<Map<String, dynamic>> allHazards = [];
  List<Map<String, dynamic>> filteredHazards = [];

  List<Map<String, dynamic>> _availableSites = [];
  String? _selectedSiteId;
  String? _selectedSeverity;
  // ✅ CHANGED: Default sort is now 'newest'
  String _sortBy = 'newest';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadHazardsCacheFirst();
  }

  @override
  void dispose() {
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

  Future<void> _loadHazardsCacheFirst() async {
    final cachedHazards = await _hazardRepository.getOfficerActiveHazards();
    final cachedSites = OfficerRepository.instance.getOfficerSites();

    if (cachedHazards != null) {
      allHazards = cachedHazards;
      if (cachedSites != null) {
        _availableSites = cachedSites
            .map((site) => {'id': site['id'], 'name': site['name']})
            .toList();
      }
      _applyFiltersAndSort();
      if (mounted) setState(() => isLoading = false);
    } else {
      setState(() => isLoading = true);
    }

    await _fetchHazards(
      showBlockingLoader: cachedHazards == null,
      resetPagination: true,
    );
  }

  void _applyFiltersAndSort() {
    List<Map<String, dynamic>> tempHazards = List.from(allHazards);

    // Filter by Severity
    if (_selectedSeverity != null) {
      tempHazards = tempHazards.where((hazard) {
        final severity = hazard['severity']?.toString().toLowerCase() ?? '';
        return severity == _selectedSeverity;
      }).toList();
    }

    // Filter by Site
    if (_selectedSiteId != null) {
      tempHazards = tempHazards.where((hazard) {
        final siteId = hazard['sites']?['id']?.toString();
        return siteId == _selectedSiteId;
      }).toList();
    }

    // Sort by Date
    tempHazards.sort((a, b) {
      final aTime = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(1970);
      final bTime = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(1970);
      // ✅ Logic updated to handle 'newest' as default
      return _sortBy == 'oldest' ? aTime.compareTo(bTime) : bTime.compareTo(aTime);
    });

    if (mounted) {
      setState(() {
        filteredHazards = tempHazards;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedSiteId = null;
      _selectedSeverity = null;
      // ✅ CHANGED: Reset to 'newest'
      _sortBy = 'newest';
    });
    _applyFiltersAndSort();
  }

  bool get _hasActiveFilters {
    // ✅ CHANGED: Check against 'newest'
    return _selectedSiteId != null ||
        _selectedSeverity != null ||
        _sortBy != 'newest';
  }

  Future<void> _loadNextPage() async {
    if (!_hasMoreHazards || _isLoadingMore) {
      return;
    }

    setState(() => _isLoadingMore = true);
    _currentPage++;
    await _fetchHazards(
      showBlockingLoader: false,
      resetPagination: false,
    );
  }

  Future<void> _fetchHazards({
    bool showBlockingLoader = true,
    bool resetPagination = true,
  }) async {
    if (!mounted) return;
    if (resetPagination) {
      _currentPage = 0;
      _hasMoreHazards = true;
    }
    if (showBlockingLoader) setState(() => isLoading = true);
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    try {
      final int pageStart = _currentPage * _pageSize;
      final int pageEnd = pageStart + _pageSize - 1;
      final officerProfile = await supabase
          .from('officers')
          .select('officer_uid')
          .eq('id', currentUserId)
          .single();

      final officerUid = officerProfile['officer_uid']?.toString();
      if (officerUid == null) {
        if (mounted) {
          setState(() {
            allHazards = [];
            filteredHazards = [];
            _availableSites = [];
          });
        }
        return;
      }

      // Fetch available sites for filtering
      final sitesResponse = await supabase
          .from('sites')
          .select('id, name')
          .eq('officer_uid', officerUid);

      if (mounted) {
        setState(() {
          _availableSites = List<Map<String, dynamic>>.from(sitesResponse);
        });
      }
      await OfficerRepository.instance.saveOfficerSites(
        List<Map<String, dynamic>>.from(sitesResponse),
      );

      // Fetch reported hazards
      final hazardsResponse = await supabase
          .from('hazards')
          .select('''
            id, hazard_type, description, severity, status, created_at,
            image_url, voice_note_url, latitude, longitude,
            reporter:worker_id(first_name, last_name),
            sites:current_site_id(id, name)
          ''')
          .eq('officer_uid', officerUid)
          .inFilter('status', ['reported', 'Reported'])
          .order('created_at', ascending: false)
          .range(pageStart, pageEnd); // Catches both

      // Fetch assigned tasks
      final assignedTasksResponse = await supabase
          .from('assign_hazards')
          .select('''
            id, hazard_type, description, severity, status, created_at,
            image_url, voice_note_url, latitude, longitude,
            reporter:worker_id(first_name, last_name),
            assigned_at,
            hse_worker:assigned_to(id, first_name, last_name, profile_image_url),
            sites:current_site_id(id, name)
          ''')
          .eq('officer_uid', officerUid)
          .inFilter('status', ['assigned', 'Assigned', 'in_progress', 'In_progress'])
          .order('created_at', ascending: false)
          .range(pageStart, pageEnd); // Catches all variations

      final List<Map<String, dynamic>> combinedHazards = [];

      // Add unassigned hazards
      for (final hazard in hazardsResponse) {
        hazard['assign_hazards'] = [];
        combinedHazards.add(hazard);
      }

      // Group assigned tasks by created_at timestamp
      final groupedAssigned = <String, List<Map<String, dynamic>>>{};
      for (var task in assignedTasksResponse) {
        final String groupKey = task['created_at'].toString();
        if (groupedAssigned.containsKey(groupKey)) {
          groupedAssigned[groupKey]!.add(task);
        } else {
          groupedAssigned[groupKey] = [task];
        }
      }

      // Create hazard objects from grouped tasks
      groupedAssigned.forEach((key, tasksInGroup) {
        final representativeTask = tasksInGroup.first;
        final hazardMap = {
          'id': representativeTask['id'],
          'hazard_type': representativeTask['hazard_type'],
          'description': representativeTask['description'],
          'severity': representativeTask['severity'],
          'status': representativeTask['status'],
          'sites': representativeTask['sites'],
          'created_at': representativeTask['created_at'],
          'image_url': representativeTask['image_url'],
          'voice_note_url': representativeTask['voice_note_url'],
          'latitude': representativeTask['latitude'],
          'longitude': representativeTask['longitude'],
          'reporter': representativeTask['reporter'],
          'assign_hazards': tasksInGroup.map((task) {
            return {
              'id': task['id'],
              'status': task['status'],
              'assigned_at': task['assigned_at'],
              'hse_worker': task['hse_worker']
            };
          }).toList()
        };
        combinedHazards.add(hazardMap);
      });

      final List<Map<String, dynamic>> updatedHazards = resetPagination
          ? combinedHazards
          : <Map<String, dynamic>>[...allHazards, ...combinedHazards];

      if (mounted) {
        await _hazardRepository.saveOfficerActiveHazards(updatedHazards);
        setState(() {
          allHazards = updatedHazards;
          _hasMoreHazards = hazardsResponse.length == _pageSize ||
              assignedTasksResponse.length == _pageSize;
          _isLoadingMore = false;
        });
        _applyFiltersAndSort();
      }
    } on SocketException {
      debugPrint('Officer active hazards offline - using cached data.');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    } catch (e) {
      debugPrint('Error fetching hazards: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch hazards: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _showFilterSheet() {
    // Store temporary filter values
    String? tempSiteId = _selectedSiteId;
    String? tempSeverity = _selectedSeverity;
    String tempSortBy = _sortBy;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            const panelBg = Color(0xFF123636);
            final primaryText = Colors.white;
            final secondaryText = Colors.white70;
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.62,
              minChildSize: 0.45,
              maxChildSize: 0.78,
              builder: (BuildContext context, ScrollController scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: panelBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border.all(
                      color: AppColors.surfaceTeal.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Handle bar
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Header with clear button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Filters",
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: primaryText,
                              ),
                            ),
                            // ✅ CHANGED: Check against 'newest'
                            if (tempSiteId != null || tempSeverity != null || tempSortBy != 'newest')
                              TextButton.icon(
                                icon: const Icon(Icons.clear_all, size: 18),
                                label: const Text("Clear All"),
                                onPressed: () {
                                  setSheetState(() {
                                    tempSiteId = null;
                                    tempSeverity = null;
                                    // ✅ CHANGED: Reset to 'newest'
                                    tempSortBy = 'newest';
                                  });
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.accentGold,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            children: [
                              // Severity Filter Section
                              _buildFilterSection(
                                context: context,
                                title: "Severity",
                                icon: Icons.warning_amber_rounded,
                                titleColor: primaryText,
                                child: Wrap(
                                  spacing: 8.0,
                                  runSpacing: 8.0,
                                  children: [
                                    _buildFilterChip(
                                      context: context,
                                      label: "All",
                                      isSelected: tempSeverity == null,
                                      onTap: () => setSheetState(() => tempSeverity = null),
                                    ),
                                    _buildFilterChip(
                                      context: context,
                                      label: "High",
                                      isSelected: tempSeverity == "high",
                                      onTap: () => setSheetState(() => tempSeverity = "high"),
                                      color: const Color(0xFFEF4444),
                                    ),
                                    _buildFilterChip(
                                      context: context,
                                      label: "Moderate",
                                      isSelected: tempSeverity == "moderate",
                                      onTap: () => setSheetState(() => tempSeverity = "moderate"),
                                      color: const Color(0xFFF59E0B),
                                    ),
                                    _buildFilterChip(
                                      context: context,
                                      label: "Low",
                                      isSelected: tempSeverity == "low",
                                      onTap: () => setSheetState(() => tempSeverity = "low"),
                                      color: const Color(0xFF10B981),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Site Filter Section
                              _buildFilterSection(
                                context: context,
                                title: "Site",
                                icon: Icons.location_on_outlined,
                                titleColor: primaryText,
                                child: Wrap(
                                  spacing: 8.0,
                                  runSpacing: 8.0,
                                  children: [
                                    _buildFilterChip(
                                      context: context,
                                      label: "All Sites",
                                      isSelected: tempSiteId == null,
                                      onTap: () => setSheetState(() => tempSiteId = null),
                                    ),
                                    ..._availableSites.map((site) {
                                      final siteId = site['id']?.toString();
                                      return _buildFilterChip(
                                        context: context,
                                        label: site['name'] ?? 'Unknown Site',
                                        isSelected: tempSiteId == siteId,
                                        onTap: () => setSheetState(() => tempSiteId = siteId),
                                      );
                                    }),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Sort Section
                              _buildFilterSection(
                                context: context,
                                title: "Sort By",
                                icon: Icons.sort_rounded,
                                titleColor: primaryText,
                                child: Column(
                                  children: [
                                    _buildRadioTile(
                                      context: context,
                                      title: "Newest First",
                                      subtitle: "Most recent hazards",
                                      value: 'newest',
                                      groupValue: tempSortBy,
                                      onChanged: (value) => setSheetState(() => tempSortBy = value!),
                                      titleColor: primaryText,
                                      subtitleColor: secondaryText,
                                    ),
                                    _buildRadioTile(
                                      context: context,
                                      title: "Oldest First",
                                      subtitle: "Earliest hazards",
                                      value: 'oldest',
                                      groupValue: tempSortBy,
                                      onChanged: (value) => setSheetState(() => tempSortBy = value!),
                                      titleColor: primaryText,
                                      subtitleColor: secondaryText,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Apply Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: AppColors.accentGold,
                              foregroundColor: AppColors.brandTeal,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedSiteId = tempSiteId;
                                _selectedSeverity = tempSeverity;
                                _sortBy = tempSortBy;
                              });
                              _applyFiltersAndSort();
                              Navigator.pop(context);
                            },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.filter_alt_rounded, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  "Apply Filters",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
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
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFilterSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color titleColor,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.accentGold),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _buildFilterChip({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final chipColor = color ?? AppColors.brandTeal;
    const unselectedBg = Color(0x33FFFFFF);
    const unselectedBorder = Colors.white24;
    const unselectedText = Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor
              : unselectedBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? chipColor
                : unselectedBorder,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : unselectedText,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildRadioTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
    required Color titleColor,
    required Color subtitleColor,
  }) {
    final isSelected = value == groupValue;

    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandTeal.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.accentGold
                : Colors.white24,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              // ignore: deprecated_member_use
              groupValue: groupValue,
              // ignore: deprecated_member_use
              onChanged: onChanged,
              activeColor: Theme.of(context).primaryColor,
              fillColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.accentGold;
                }
                return Colors.white54;
              }),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isSelected
                          ? AppColors.accentGold
                          : titleColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = filteredHazards.length;
    final hazardText = count == 1 ? "Hazard" : "Hazards";

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      constraints: const BoxConstraints(minHeight: 56, maxHeight: 56),
      decoration: BoxDecoration(
        color: isDark
            ? Color.lerp(AppColors.brandTeal, Colors.black, 0.35)!
            : Color.lerp(AppColors.brandTeal, Colors.white, 0.78)!,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.surfaceTeal.withValues(alpha: 0.8)
              : AppColors.brandTeal.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  if (_hasActiveFilters) ...[
                    Icon(
                      Icons.filter_alt,
                      size: 16,
                      color: AppColors.accentGold,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    "$count $hazardText",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_hasActiveFilters)
            TextButton(
              onPressed: _clearFilters,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text("Clear"),
            ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.sort_rounded, size: 20),
            onPressed: _showFilterSheet,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.accentGold,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildSubHeader(),
          Expanded(
            child: allHazards.isEmpty
                ? RefreshIndicator(
              onRefresh: () => _fetchHazards(
                showBlockingLoader: false,
                resetPagination: true,
              ),
              child: Stack(
                children: [
                  ListView(),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "No active hazards",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
                : filteredHazards.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.filter_alt_off,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No hazards match filters",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text("Clear Filters"),
                  ),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: () => _fetchHazards(
                showBlockingLoader: false,
                resetPagination: true,
              ),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
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
                  final hazard = filteredHazards[index];
                  return _HazardCard(
                    hazard: hazard,
                    index: index,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HazardCard extends StatelessWidget {
  const _HazardCard({required this.hazard, required this.index});
  final Map<String, dynamic> hazard;
  final int index;

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

  String hazardEmoji(String? type) {
    switch (type?.toLowerCase()) {
      case 'fire':
        return '🔥';
      case 'electrocution':
        return '⚡';
      case 'hazardous chemicals':
        return '☣️';
      case 'slips/trips':
        return '💦';
      case 'fall from height':
        return '🪜';
      default:
        return '⚠️';
    }
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return 'N/A';
    try {
      final raw = isoString.trim();
      final parsed = (raw.endsWith('Z') || raw.contains('+'))
          ? DateTime.parse(raw).toUtc()
          : DateTime.parse('${raw}Z').toUtc();
      return DateFormat('MMM d, h:mm a').format(parsed.toLocal());
    } catch (e) {
      return 'N/A';
    }
  }

  String _hazardSvgAsset(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('fire')) return 'assets/hazards/fire_warning.svg';
    if (t.contains('electric') || t.contains('shock')) {
      return 'assets/hazards/electric_shock.svg';
    }
    if (t.contains('slip') || t.contains('trip') || t.contains('wet')) {
      return 'assets/hazards/slip_falling.svg';
    }
    if (t.contains('stair')) return 'assets/hazards/stairs_fall.svg';
    if (t.contains('fall')) return 'assets/hazards/falling_objects.svg';
    if (t.contains('radio') && t.contains('active')) {
      return 'assets/hazards/radio_active.svg';
    }
    if (t.contains('temperature')) return 'assets/hazards/high_temperature.svg';
    if (t.contains('high heat') || t.contains('heat')) {
      return 'assets/hazards/high_heat.svg';
    }
    if (t.contains('machine') || t.contains('crush')) {
      return 'assets/hazards/machine_crush.svg';
    }
    if (t.contains('explosion') || t.contains('explosive')) {
      return 'assets/hazards/explosion.svg';
    }
    if (t.contains('freeze') || t.contains('ice')) return 'assets/hazards/freeze.svg';
    if (t.contains('lift') || t.contains('load')) {
      return 'assets/hazards/load_lifting.svg';
    }
    if (t.contains('wave')) return 'assets/hazards/radio_waves.svg';
    if (t.contains('magnetic')) return 'assets/hazards/magnetic_field.svg';
    return 'assets/hazards/fire_warning.svg';
  }

  Widget _buildDetailRow({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withAlpha(230), size: 16),
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
    final reporter = hazard['reporter'];
    final reporterName = reporter != null
        ? "${capitalize(reporter['first_name'] ?? '')} ${capitalize(reporter['last_name'] ?? '')}"
        .trim()
        : 'N/A';
    final siteName = hazard['sites']?['name']?.toString() ?? 'N/A';

    final List<dynamic> assignedTasks = hazard['assign_hazards'] ?? [];
    final validTasks =
    assignedTasks.where((task) => task['hse_worker'] != null).toList();

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
    final String severity = hazard['severity'] ?? 'Unknown';
    final String timestamp = _formatTimestamp(hazard['created_at']);
    final bool hasImages = images.isNotEmpty;
    final bool hasVoiceNotes = voiceUrls.isNotEmpty;
    final primaryColor = getPrimaryColor(severity);
    final secondaryColor = getSecondaryColor(severity);
    final severityColor = getPrimaryColor(severity);

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
                  builder: (context) => HazardDetailsScreen(hazardData: hazard),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(64),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: SvgPicture.asset(
                            _hazardSvgAsset(title),
                            width: 32,
                            height: 32,
                            fit: BoxFit.contain,
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
                                    color: severityColor.withValues(alpha: 0.85),
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
                                          color: Colors.white.withAlpha(204)),
                                    if (hasImages) const SizedBox(width: 4),
                                    if (hasImages)
                                      Text(images.length.toString(),
                                          style: TextStyle(
                                              color: Colors.white.withAlpha(204),
                                              fontSize: 12)),
                                    if (hasImages && hasVoiceNotes)
                                      const SizedBox(width: 12),
                                    if (hasVoiceNotes)
                                      Icon(Icons.mic_rounded,
                                          size: 16,
                                          color: Colors.white.withAlpha(204)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      )
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(color: Colors.white.withAlpha(77), height: 1),
                  ),
                  _buildDetailRow(
                      icon: Icons.person_pin_circle_outlined,
                      text: "By: $reporterName"),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                      icon: Icons.location_on_outlined, text: "Site: $siteName"),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                      icon: Icons.schedule_rounded, text: timestamp),
                  if (validTasks.isEmpty) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      icon: Icons.person_off_outlined,
                      text: "Not yet assigned",
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: Colors.white.withAlpha(77), height: 1),
                    ),
                    Text(
                      "SITE INSPECTOR${validTasks.length > 1 ? 'S' : ''}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white.withAlpha(204),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...validTasks.map((task) {
                      final worker = task['hse_worker'];
                      final workerName = worker != null
                          ? "${capitalize(worker['first_name'] ?? 'N/A')} ${capitalize(worker['last_name'] ?? '')}"
                          .trim()
                          : 'Unassigned';
                      final profileImage = worker?['profile_image_url'];
                      final status = task['status']?.toString() ?? 'unknown';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white.withAlpha(64),
                              backgroundImage: profileImage != null
                                  ? CachedNetworkImageProvider(profileImage)
                                  : null,
                              child: profileImage == null
                                  ? Text(
                                workerName.isNotEmpty ? workerName[0] : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                              )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                workerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(64),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                status.replaceAll('_', ' ').toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

