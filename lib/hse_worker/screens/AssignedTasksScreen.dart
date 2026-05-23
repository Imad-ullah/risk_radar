// lib/hse_workers/screens/AssignedTasksScreen.dart
// ignore_for_file: file_names

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/services/sync_service.dart';
import 'package:riskradar/shared/hazards/hazard_details_screen.dart'
    hide VoiceNotePlayer;
import 'package:riskradar/shared/models/hazard.dart';

import 'hse_worker_resolution_form_screen.dart';

class AssignedTasksScreen extends StatefulWidget {
  const AssignedTasksScreen({super.key});

  @override
  State<AssignedTasksScreen> createState() => _AssignedTasksScreenState();
}

class _AssignedTasksScreenState extends State<AssignedTasksScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  final AuthRepository _authRepository = AuthRepository();
  final HazardRepository _hazardRepository = HazardRepository();
  final SyncRepository _syncRepository = SyncRepository();
  late TabController _tabController;
  final ScrollController _activeScrollController = ScrollController();
  final ScrollController _queueScrollController = ScrollController();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  static const int _pageSize = 20;
  static const double _loadMoreScrollThreshold = 0.8;

  bool isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreTasks = true;
  int _currentPage = 0;
  List<Map<String, dynamic>> inProgressTasks = [];
  List<Map<String, dynamic>> assignedTasks = [];
  Set<String> _locallyResolvedTaskIds = <String>{};

  String _selectedFilter = 'all';
  Timer? _elapsedTimer;

  // Severity Colors Logic
  static const Color _successColor = Color(0xFF10B981);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);

  // Original Static Teal Color
  static const Color _tealColor = Color(0xFF1B3D3D);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _activeScrollController.addListener(_handleScroll);
    _queueScrollController.addListener(_handleScroll);
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_handleConnectivityChange);
    _loadTasksCacheFirst();
    _startElapsedTimer();
  }

  @override
  void dispose() {
    _activeScrollController.dispose();
    _queueScrollController.dispose();
    _connectivitySubscription?.cancel();
    _tabController.dispose();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _handleScroll() {
    final ScrollController activeController = _tabController.index == 0
        ? _activeScrollController
        : _queueScrollController;
    if (!activeController.hasClients ||
        _isLoadingMore ||
        !_hasMoreTasks ||
        isLoading) {
      return;
    }

    final ScrollPosition position = activeController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }

    final double triggerOffset =
        position.maxScrollExtent * _loadMoreScrollThreshold;
    if (position.pixels >= triggerOffset) {
      _loadNextPage();
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final bool hasInternet = results.any(
      (ConnectivityResult result) =>
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn,
    );

    if (!hasInternet) {
      return;
    }

    unawaited(_refreshAfterConnectivityRestored());
  }

  Future<void> _refreshAfterConnectivityRestored() async {
    await SyncService.instance.run();
    if (!mounted) {
      return;
    }
    await _refreshTasksFromCache();
    await fetchTasks(showBlockingLoader: false, resetPagination: true);
  }

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && inProgressTasks.isNotEmpty) {
        setState(() {});
      }
    });
  }

  // --- Logic Helpers ---

  String _capitalize(String text) {
    if (text.isEmpty) return "";
    return text.split(' ').map((word) {
      if (word.isEmpty) return "";
      return "${word[0].toUpperCase()}${word.substring(1).toLowerCase()}";
    }).join(' ');
  }

  String _formatElapsedTime(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Duration _getElapsedDuration(String? startedAt) {
    if (startedAt == null) return Duration.zero;
    try {
      final startTime = DateTime.parse(startedAt);
      return DateTime.now().difference(startTime);
    } catch (e) {
      return Duration.zero;
    }
  }

  int _getSeverityPriority(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'high': return 0;
      case 'moderate': return 1;
      case 'low': return 2;
      default: return 3;
    }
  }

  void _sortTasksBySeverity(List<Map<String, dynamic>> tasks) {
    tasks.sort((a, b) {
      final priorityA = _getSeverityPriority(a['severity']);
      final priorityB = _getSeverityPriority(b['severity']);
      return priorityA.compareTo(priorityB);
    });
  }

  List<Map<String, dynamic>> _filterTasks(List<Map<String, dynamic>> tasks) {
    if (_selectedFilter == 'all') return tasks;
    return tasks
        .where((task) =>
    task['severity']?.toString().toLowerCase() == _selectedFilter)
        .toList();
  }

  Color getPrimaryColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'low': return _successColor;
      case 'moderate': return _warningColor;
      case 'high': return _errorColor;
      default: return const Color(0xFF6B7280);
    }
  }

  Color getSecondaryColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'low': return const Color(0xFF34D399);
      case 'moderate': return const Color(0xFFFBBF24);
      case 'high': return const Color(0xFFF87171);
      default: return const Color(0xFF9CA3AF);
    }
  }

  String hazardEmoji(String? type) {
    switch (type?.toLowerCase()) {
      case 'fire': return '🔥';
      case 'electrocution': return '⚡';
      case 'hazardous chemicals': return '☣️';
      case 'slips/trips': return '💦';
      case 'fall from height': return '🪜';
      default: return '⚠️';
    }
  }

  // --- Backend Interaction ---

  Future<void> _loadTasksCacheFirst() async {
    if (!mounted) return;

    final cachedTasks = await _hazardRepository.getHseAssignedTasks();
    _locallyResolvedTaskIds =
        await _hazardRepository.getHseLocallyResolvedTaskIds();
    final cachedProfile = _authRepository.getHseProfile();

    if (cachedTasks != null) {
      _applyTaskRows(cachedTasks, cachedProfile);
      if (mounted) {
        setState(() {
          isLoading = false;
          _isLoadingMore = false;
        });
      }
    } else {
      setState(() => isLoading = true);
    }

    await fetchTasks(
      showBlockingLoader: cachedTasks == null,
      resetPagination: true,
    );
  }

  void _applyTaskRows(List<dynamic> rows, Map<String, dynamic>? hseProfile) {
    final List<Map<String, dynamic>> loadedInProgress = [];
    final List<Map<String, dynamic>> loadedAssigned = [];

    for (final task in rows) {
      final Map<String, dynamic> taskMap =
          Map<String, dynamic>.from(task as Map);
      final String rawStatus = (taskMap['status'] ?? 'assigned').toString();
      final String statusLower = rawStatus.toLowerCase();

      if (statusLower == 'resolved' ||
          statusLower == 'resolved by other' ||
          _taskIdentifiers(taskMap).any(_locallyResolvedTaskIds.contains)) {
        continue;
      }

      taskMap['assignment_status'] = statusLower;
      taskMap['assignment_id'] = taskMap['id'];

      final workerData = taskMap['workers'];
      if (workerData is Map) {
        final String fName = workerData['first_name'] ?? '';
        final String lName = workerData['last_name'] ?? '';
        taskMap['reporter_name'] = _capitalize("$fName $lName".trim());
        taskMap['reporter_image'] = workerData['profile_image_url'];
      } else {
        taskMap['reporter_name'] = taskMap['reporter_name'] ?? 'Unknown';
      }

      taskMap['assign_hazards'] = [
        {
          'status': taskMap['status'],
          'assigned_at': taskMap['created_at'],
          'hse_worker': hseProfile,
        }
      ];

      if (statusLower == 'in_progress') {
        loadedInProgress.add(taskMap);
      } else {
        loadedAssigned.add(taskMap);
      }
    }

    _sortTasksBySeverity(loadedInProgress);
    _sortTasksBySeverity(loadedAssigned);
    inProgressTasks = loadedInProgress;
    assignedTasks = loadedAssigned;
  }

  Future<void> _loadNextPage() async {
    if (!_hasMoreTasks || _isLoadingMore) {
      return;
    }

    setState(() => _isLoadingMore = true);
    _currentPage++;
    await fetchTasks(
      showBlockingLoader: false,
      resetPagination: false,
    );
  }

  Future<void> fetchTasks({
    bool showBlockingLoader = true,
    bool resetPagination = true,
  }) async {
    if (!mounted) return;
    if (resetPagination) {
      _currentPage = 0;
      _hasMoreTasks = true;
    }
    if (showBlockingLoader) setState(() => isLoading = true);

    try {
      final int pageStart = _currentPage * _pageSize;
      final int pageEnd = pageStart + _pageSize - 1;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() {
            isLoading = false;
            _isLoadingMore = false;
          });
        }
        return;
      }

      _locallyResolvedTaskIds =
          await _hazardRepository.getHseLocallyResolvedTaskIds();

      final hseProfileRes = await supabase
          .from('hse_workers')
          .select('first_name, last_name, profile_image_url')
          .eq('id', userId)
          .maybeSingle();

      final response = await supabase
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
          .not('status', 'in', '(resolved,"resolved by other")')
          .order('created_at', ascending: false)
          .range(pageStart, pageEnd);

      final List<Map<String, dynamic>> cachedRows = resetPagination
          ? <Map<String, dynamic>>[]
          : await _hazardRepository.getHseAssignedTasks() ??
              <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> responseRows =
          List<Map<String, dynamic>>.from(response);
      final List<Map<String, dynamic>> combinedRows = _mergeTaskRows(
        cachedRows: cachedRows,
        responseRows: responseRows,
      );
      final List<Map<String, dynamic>> activeRows =
          _withoutLocallyResolvedTasks(combinedRows);

      await _hazardRepository.saveHseAssignedTasks(activeRows);
      if (hseProfileRes != null) {
        final currentProfile = _authRepository.getHseProfile();
        await _authRepository.saveHseProfile({
          ...?currentProfile,
          ...hseProfileRes,
        });
      }

      if (mounted) {
        setState(() {
          _applyTaskRows(activeRows, hseProfileRes);
          _hasMoreTasks = responseRows.length == _pageSize;
          isLoading = false;
          _isLoadingMore = false;
        });
      }
    } on SocketException {
      debugPrint("ℹ️ HSE tasks offline - using cached data.");
      if (mounted) {
        setState(() {
          isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error fetching tasks: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _mergeTaskRows({
    required List<Map<String, dynamic>> cachedRows,
    required List<Map<String, dynamic>> responseRows,
  }) {
    final Map<String, Map<String, dynamic>> rowsById =
        <String, Map<String, dynamic>>{};
    final List<String> orderedIds = <String>[];

    void addOrReplace(Map<String, dynamic> row) {
      final String? id = row['id']?.toString();
      if (id == null || id.isEmpty) {
        return;
      }
      if (!rowsById.containsKey(id)) {
        orderedIds.add(id);
      }
      rowsById[id] = row;
    }

    for (final Map<String, dynamic> row in cachedRows) {
      addOrReplace(row);
    }
    for (final Map<String, dynamic> row in responseRows) {
      addOrReplace(row);
    }

    return orderedIds
        .map((String id) => rowsById[id])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _withoutLocallyResolvedTasks(
    List<Map<String, dynamic>> rows,
  ) {
    if (_locallyResolvedTaskIds.isEmpty) {
      return rows;
    }

    return rows
        .where(
          (Map<String, dynamic> row) =>
              !_taskIdentifiers(row).any(_locallyResolvedTaskIds.contains),
        )
        .toList(growable: false);
  }

  Future<void> _updateTaskStatus(String assignmentId, String newStatus) async {
    HapticFeedback.mediumImpact();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final updateData = <String, dynamic>{'status': newStatus};
    if (newStatus == 'in_progress') {
      updateData['started_at'] = DateTime.now().toUtc().toIso8601String();
    } else if (newStatus == 'resolved') {
      updateData['resolved_at'] = DateTime.now().toUtc().toIso8601String();
    }

    try {
      await supabase
          .from('assign_hazards')
          .update(updateData)
          .eq('id', assignmentId);

      await _updateTaskInLocalCache(assignmentId, updateData);
      await fetchTasks(showBlockingLoader: false, resetPagination: true);

      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(newStatus == 'in_progress' ? "Task started!" : "Task resolved!"),
        backgroundColor: _successColor,
      ));
    } on SocketException {
      await _queueTaskStatusUpdate(assignmentId, updateData);
      scaffoldMessenger.showSnackBar(const SnackBar(
        content: Text("Saved offline - will sync when online"),
        backgroundColor: Colors.orange,
      ));
    } catch (e) {
      scaffoldMessenger.showSnackBar(const SnackBar(
        content: Text("Failed to update task status"),
        backgroundColor: _errorColor,
      ));
    }
  }

  Future<void> _queueTaskStatusUpdate(
    String assignmentId,
    Map<String, dynamic> updateData,
  ) async {
    await _updateTaskInLocalCache(assignmentId, updateData);
    await _syncRepository.enqueueAction(
      id: 'hse_status_${assignmentId}_${DateTime.now().millisecondsSinceEpoch}',
      table: 'assign_hazards',
      action: 'update',
      payload: {
        'id': assignmentId,
        ...updateData,
      },
    );
  }

  Future<void> _updateTaskInLocalCache(
    String assignmentId,
    Map<String, dynamic> updateData,
  ) async {
    final cached = await _hazardRepository.getHseAssignedTasks() ?? [];
    for (final task in cached) {
      if (task['id']?.toString() == assignmentId) {
        task.addAll(updateData);
      }
    }
    await _hazardRepository.saveHseAssignedTasks(cached);
    if (mounted) {
      setState(() {
        _applyTaskRows(cached, _authRepository.getHseProfile());
      });
    }
  }

  Future<void> _showStatusChangeDialog(Map<String, dynamic> task, String currentStatus) async {
    HapticFeedback.selectionClick();
    final assignmentId = task['assignment_id'];
    final statusLower = currentStatus.toLowerCase();

    if (statusLower == 'assigned') {
      // ✅ NEW THEMED DIALOG DESIGN
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _tealColor,
                  Color(0xDA1B3D3D), // _tealColor with values (alpha: 0.85)
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Start Task',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  'Start working on this task now?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15, color: Colors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _tealColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                      ),
                      child: const Text('Start',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (confirmed == true) {
        await _updateTaskStatus(assignmentId, 'in_progress');
      }
    } else if (statusLower == 'in_progress') {
      await _openResolutionForm(task);
    }
  }

  Future<void> _openResolutionForm(Map<String, dynamic> task) async {
    final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HseWorkerResolutionFormScreen(
            hazard: Hazard.fromMap(task),
          ),
        ),
      );

    final Map<String, dynamic>? resultMap =
        result is Map ? Map<String, dynamic>.from(result) : null;
    final bool wasResolved = result == true || resultMap?['resolved'] == true;
    final bool wasSynced = resultMap?['synced'] == true || result == true;
    if (wasResolved) {
      await _removeResolvedTaskLocally(
        task,
        additionalIdentifiers: <String>{
          ?resultMap?['assignment_id']?.toString(),
          ?resultMap?['hazard_id']?.toString(),
        },
      );
      await _refreshTasksFromCache();
      if (wasSynced) {
        await fetchTasks(showBlockingLoader: false, resetPagination: true);
      }
    }
  }

  Future<void> _removeResolvedTaskLocally(
    Map<String, dynamic> task, {
    Set<String> additionalIdentifiers = const <String>{},
  }) async {
    final Set<String> identifiers = <String>{
      ..._taskIdentifiers(task),
      ...additionalIdentifiers,
    }.where((String value) => value.trim().isNotEmpty).toSet();
    if (identifiers.isEmpty) {
      return;
    }

    _locallyResolvedTaskIds = <String>{
      ..._locallyResolvedTaskIds,
      ...identifiers,
    };

    if (mounted) {
      setState(() {
        inProgressTasks.removeWhere(
          (Map<String, dynamic> visibleTask) =>
              _taskIdentifiers(visibleTask).any(identifiers.contains),
        );
        assignedTasks.removeWhere(
          (Map<String, dynamic> visibleTask) =>
              _taskIdentifiers(visibleTask).any(identifiers.contains),
        );
        isLoading = false;
        _isLoadingMore = false;
      });
    }

    await _hazardRepository.markHseTasksResolvedLocally(identifiers);

    final List<Map<String, dynamic>> cachedTasks =
        await _hazardRepository.getHseAssignedTasks() ?? <Map<String, dynamic>>[];
    cachedTasks.removeWhere(
      (Map<String, dynamic> cachedTask) =>
          _taskIdentifiers(cachedTask).any(identifiers.contains),
    );
    await _hazardRepository.saveHseAssignedTasks(cachedTasks);
  }

  Set<String> _taskIdentifiers(Map<String, dynamic> task) {
    return <String>{
      ?task['id']?.toString(),
      ?task['assignment_id']?.toString(),
      ?task['hazard_id']?.toString(),
    }.where((String value) => value.trim().isNotEmpty).toSet();
  }

  Future<void> _refreshTasksFromCache() async {
    final List<Map<String, dynamic>> cachedTasks =
        await _hazardRepository.getHseAssignedTasks() ??
            <Map<String, dynamic>>[];
    _locallyResolvedTaskIds =
        await _hazardRepository.getHseLocallyResolvedTaskIds();
    final Map<String, dynamic>? cachedProfile = _authRepository.getHseProfile();
    if (!mounted) {
      return;
    }

    setState(() {
      _applyTaskRows(cachedTasks, cachedProfile);
      isLoading = false;
      _isLoadingMore = false;
    });
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Filter by Severity", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _tealColor)),
            const SizedBox(height: 15),
            _buildFilterOption('all', 'All Tasks', Colors.black87),
            _buildFilterOption('high', 'High Severity', _errorColor),
            _buildFilterOption('moderate', 'Moderate Severity', _warningColor),
            _buildFilterOption('low', 'Low Severity', _successColor),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(String value, String label, Color color) {
    return ListTile(
      leading: Icon(Icons.circle, color: color, size: 16),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: _selectedFilter == value ? const Icon(Icons.check, color: _tealColor) : null,
      onTap: () {
        setState(() => _selectedFilter = value);
        Navigator.pop(context);
      },
    );
  }

  // --- UI Building Blocks ---

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;

    return Scaffold(
      backgroundColor: backgroundColor,

      body: Column(
        children: [
          // 1. HEADER
          Container(
            color: backgroundColor,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              decoration: const BoxDecoration(
                color: _tealColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Row(
                children: [
                  // Tabs
                  Expanded(
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: _tealColor,
                        unselectedLabelColor: Colors.white70,
                        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        dividerColor: Colors.transparent,
                        tabs: [
                          Tab(text: "Active (${inProgressTasks.length})"),
                          Tab(text: "Queue (${assignedTasks.length})"),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Filter Button
                  Container(
                    height: 50, width: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.filter_list_rounded, color: Colors.white, size: 24),
                      onPressed: _showFilterSheet,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. TASK LIST
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: _tealColor))
                : TabBarView(
              controller: _tabController,
              children: [
                _buildTaskList(_filterTasks(inProgressTasks), true),
                _buildTaskList(_filterTasks(assignedTasks), false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(List<Map<String, dynamic>> tasks, bool isActive) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text("No tasks found", style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => fetchTasks(
        showBlockingLoader: false,
        resetPagination: true,
      ),
      child: ListView.builder(
        controller:
            isActive ? _activeScrollController : _queueScrollController,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
        itemCount: tasks.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == tasks.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: _tealColor),
              ),
            );
          }
          return _buildDesignCard(tasks[index], index, isActive);
        },
      ),
    );
  }

  Widget _buildDesignCard(Map<String, dynamic> task, int index, bool isActive) {
    final severity = task['severity'] ?? 'low';
    final primaryColor = getPrimaryColor(severity);
    final secondaryColor = getSecondaryColor(severity);
    final status = task['assignment_status'];

    final reporterName = task['reporter_name'] ?? 'Unknown';
    final reporterImage = task['reporter_image'];
    final hazardType = task['hazard_type'] ?? 'General Hazard';
    final description = task['description'] ?? 'No description provided';

    final bool hasVoice = task['voice_note_url'] != null;
    final bool hasImage = task['image_url'] != null || (task['images'] != null && (task['images'] as List).isNotEmpty);

    final createdDate = task['created_at'] != null
        ? DateFormat('MMM d').format(DateTime.parse(task['created_at']))
        : '';

    final elapsed = _getElapsedDuration(task['started_at']);
    final timerText = _formatElapsedTime(elapsed);

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
          if (isActive) {
            _openResolutionForm(task);
            return;
          }
          Navigator.push(context, MaterialPageRoute(builder: (_) => HazardDetailsScreen(hazardData: task)));
        },
        child: Container(
          height: 165,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [primaryColor, secondaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                        image: reporterImage != null
                            ? DecorationImage(image: CachedNetworkImageProvider(reporterImage), fit: BoxFit.cover)
                            : null,
                      ),
                      child: reporterImage == null
                          ? Center(child: Text(hazardEmoji(hazardType), style: const TextStyle(fontSize: 22)))
                          : null,
                    ),
                    const SizedBox(width: 14),

                    // Texts
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 1. Title Block
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hazardType,
                                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),

                              if (hasVoice || hasImage) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    if (hasVoice) ...[
                                      const Icon(Icons.mic_rounded, size: 14, color: Colors.white70),
                                      if (hasImage) const SizedBox(width: 8),
                                    ],
                                    if (hasImage)
                                      const Icon(Icons.image_rounded, size: 14, color: Colors.white70),
                                  ],
                                ),
                                const SizedBox(height: 2),
                              ] else ...[
                                const SizedBox(height: 4),
                              ],

                              // Description
                              Text(
                                description,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),

                          // 2. Stats Block (Bottom)
                          Row(
                            children: [
                              _buildMiniStat(createdDate, "Date"),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildMiniStat(reporterName, "Reporter"),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 60),
                  ],
                ),
              ),

              // Right Curve
              Positioned(
                right: 0, top: 0, bottom: 0, width: 100,
                child: CustomPaint(
                  painter: CardRightCurvePainter(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        isActive
                            ? Text(timerText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))
                            : Icon(Icons.more_horiz, color: Colors.white.withValues(alpha: 0.6)),

                        GestureDetector(
                          onTap: () => _showStatusChangeDialog(task, status),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: isActive ? Border.all(color: Colors.white, width: 1.5) : null
                            ),
                            child: Icon(
                                isActive ? Icons.check_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 28
                            ),
                          ),
                        ),

                        Text(
                            isActive ? "Resolve" : "Start",
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10)
                        ),
                      ],
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

  Widget _buildMiniStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10)),
      ],
    );
  }
}

class CardRightCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.15)..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width * 0.2, size.height);
    path.cubicTo(size.width * 0.6, size.height * 0.6, 0, size.height * 0.4, size.width * 0.4, 0);
    path.close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
