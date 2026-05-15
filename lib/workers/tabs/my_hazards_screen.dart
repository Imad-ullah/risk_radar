// lib/workers/tabs/my_hazards_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../details/worker_hazard_details_screen.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';

class MyHazardsScreen extends StatefulWidget {
  const MyHazardsScreen({super.key});

  @override
  State<MyHazardsScreen> createState() => _MyHazardsScreenState();
}

class _MyHazardsScreenState extends State<MyHazardsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final HazardRepository _hazardRepository = HazardRepository();

  // isLoading = true only when zero cache exists
  bool isLoading = true;
  bool _isRefreshing = false;
  List<Map<String, dynamic>> hazards = [];

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _loadMyHazards();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DATA LOADING — cache first, Supabase second
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _loadMyHazards() async {
    // ── Step 1: Paint from cache immediately ──────────────────────────────
    // My hazards = worker's own hazards cached in rr_hazards
    final cached = await _hazardRepository.getHazards();
    if (cached.isNotEmpty) {
      setState(() {
        hazards = _sortByDate(cached);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = true);
    }

    // ── Step 2: Silent background refresh ────────────────────────────────
    await _refreshFromSupabase();
  }

  // Called by pull-to-refresh
  Future<void> fetchMyHazards() async {
    await _refreshFromSupabase();
  }

  Future<void> _refreshFromSupabase() async {
    if (!mounted) return;
    setState(() => _isRefreshing = true);

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() { isLoading = false; _isRefreshing = false; });
      return;
    }

    try {
      // ── Fetch reported + assigned in parallel ─────────────────────────
      final Future<Map<String, dynamic>?> workerFuture = supabase
          .from('workers')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      final Future<List<dynamic>> reportedFuture = supabase
          .from('hazards')
          .select()
          .eq('worker_id', userId);

      final Future<List<dynamic>> assignedFuture = supabase
          .from('assign_hazards')
          .select()
          .eq('worker_id', userId);

      final results = await Future.wait([
        workerFuture,
        reportedFuture,
        assignedFuture,
      ]);

      final worker = results[0] as Map<String, dynamic>?;
      if (worker == null) {
        if (mounted) setState(() { hazards = []; isLoading = false; _isRefreshing = false; });
        return;
      }

      final reported = (results[1] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final assigned = (results[2] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      // ── Batch-fetch all HSE workers in ONE query instead of N queries ──
      // Collect all unique assigned_to IDs first
      final assignedToIds = assigned
          .map((h) => h['assigned_to'])
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> hseWorkerMap = {};

      if (assignedToIds.isNotEmpty) {
        final hseWorkers = await supabase
            .from('hse_workers')
            .select('id, first_name, last_name, designation')
            .inFilter('id', assignedToIds);

        for (final hse in hseWorkers as List<dynamic>) {
          hseWorkerMap[hse['id'].toString()] =
          Map<String, dynamic>.from(hse as Map);
        }
      }

      // ── Enrich assigned hazards with HSE worker names ──────────────────
      final normalizedAssigned = assigned.map((hazard) {
        final assignedToId = hazard['assigned_to']?.toString();
        final hse = assignedToId != null ? hseWorkerMap[assignedToId] : null;
        return {
          ...hazard,
          'assigned_to_name': hse != null
              ? '${hse['first_name']} ${hse['last_name']}'
              : 'Not Assigned',
          'assigned_to_designation': hse?['designation'] ?? '',
        };
      }).toList();

      final combined = _sortByDate([...reported, ...normalizedAssigned]);

      // Persist reported hazards to cache (the canonical worker hazards key)
      await _hazardRepository.saveHazards(reported);

      if (mounted) {
        setState(() {
          hazards = combined;
          isLoading = false;
          _isRefreshing = false;
        });
      }
    } on SocketException {
      debugPrint('ℹ️ [MyHazards] Offline — showing cached data.');
      if (mounted) setState(() { isLoading = false; _isRefreshing = false; });
    } catch (e) {
      debugPrint('⚠️ [MyHazards] Refresh error: $e');
      if (mounted) setState(() { isLoading = false; _isRefreshing = false; });
    }
  }

  List<Map<String, dynamic>> _sortByDate(List<Map<String, dynamic>> list) {
    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      final aTime =
          DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(0);
      final bTime =
          DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(0);
      return bTime.compareTo(aTime);
    });
    return sorted;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COLOR HELPERS — unchanged
  // ══════════════════════════════════════════════════════════════════════════

  Color _getSeverityColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical':
      case 'extreme':
        return Colors.red.shade900;
      case 'high':
        return Colors.red;
      case 'medium':
      case 'moderate':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'resolved':
      case 'completed':
      case 'closed':
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      case 'pending':
      case 'open':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown Date';
    final date = DateTime.tryParse(dateString);
    if (date == null) return 'Invalid Date';
    return DateFormat.yMMMd().format(date);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Hazards'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          // Subtle refresh indicator in app bar
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: fetchMyHazards,
        child: hazards.isEmpty
            ? _buildEmptyState(theme)
            : ListView.builder(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          itemCount: hazards.length,
          itemBuilder: (context, index) {
            return _buildHazardCard(
                hazards[index], theme, isDark);
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UI BUILDERS — completely unchanged from original
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState(ThemeData theme) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 80, color: theme.disabledColor),
              const SizedBox(height: 16),
              Text(
                'No Hazards Found',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 8),
              Text(
                'You have no reported or assigned hazards.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.disabledColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHazardCard(
      Map<String, dynamic> hazard, ThemeData theme, bool isDark) {
    final hazardType = hazard['hazard_type'] ?? 'General Hazard';
    final description = hazard['description'] ?? 'No description provided.';
    final status = hazard['status'] ?? 'Pending';
    final statusColor = _getStatusColor(status);
    final severity = hazard['severity'] ?? 'Unknown';
    final severityColor = _getSeverityColor(severity);
    final createdAt = _formatDate(hazard['created_at']);
    final assignedTo = hazard['assigned_to_name'];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WorkerHazardDetailsScreen(
                hazardData: {
                  ...hazard,
                  'reporter_name': 'Me',
                  'images': hazard['images'] ?? [],
                },
              ),
            ),
          );
        },
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Side stripe — severity colour
              Container(width: 6, color: severityColor),

              // Main content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hazardType,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                      fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '$severity Severity',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(
                                      color: severityColor,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color
                              ?.withValues(alpha: 0.7),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (assignedTo != null) ...[
                            Icon(Icons.person_outline,
                                size: 14, color: theme.hintColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                assignedTo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.hintColor),
                              ),
                            ),
                          ] else ...[
                            const Spacer(),
                          ],
                          Icon(Icons.calendar_today_outlined,
                              size: 14, color: theme.hintColor),
                          const SizedBox(width: 4),
                          Text(
                            createdAt,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.hintColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
