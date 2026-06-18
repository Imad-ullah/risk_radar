import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';

import 'worker_profile_screen.dart'; // <-- import your read-only profile screen

// --- Workers Cache Singleton for manage screen ---
class ManageWorkersCache {
  static final ManageWorkersCache _instance = ManageWorkersCache._internal();
  factory ManageWorkersCache() => _instance;
  ManageWorkersCache._internal();

  List<Map<String, dynamic>> workers = [];
  List<Map<String, dynamic>> hseWorkers = [];
  bool isLoaded = false;
}

class ManageWorkersScreen extends StatefulWidget {
  const ManageWorkersScreen({super.key});

  @override
  State<ManageWorkersScreen> createState() => _ManageWorkersScreenState();
}

class _ManageWorkersScreenState extends State<ManageWorkersScreen>
    with AutomaticKeepAliveClientMixin {
  final cache = ManageWorkersCache();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _workersKey = GlobalKey();
  final GlobalKey _hseWorkersKey = GlobalKey();
  final SyncRepository _syncRepository = SyncRepository();

  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkersCacheFirst();
  }

  void _loadWorkersCacheFirst() {
    final workers = OfficerRepository.instance.getOfficerWorkers();
    final hseWorkers = OfficerRepository.instance.getOfficerHseWorkers();
    if (workers != null || hseWorkers != null) {
      cache.workers = workers ?? [];
      cache.hseWorkers = hseWorkers ?? [];
      cache.isLoaded = true;
      loading = false;
    }

    _loadWorkers(showBlockingLoader: workers == null && hseWorkers == null);
  }

  Future<void> _loadWorkers({bool showBlockingLoader = true}) async {
    if (showBlockingLoader && mounted) {
      setState(() => loading = true);
    }

    try {
      // 1️⃣ Get current user's officer UID
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => loading = false);
        return;
      }

      final officer = await Supabase.instance.client
          .from('officers')
          .select('officer_uid')
          .eq('id', userId)
          .maybeSingle();

      if (officer == null) {
        setState(() => loading = false);
        return;
      }

      final officerUid = officer['officer_uid'];

      // 2️⃣ Fetch workers linked to this officer
      final responses = await Future.wait([
        Supabase.instance.client
            .from('workers')
            .select()
            .eq('officer_uid', officerUid),
        Supabase.instance.client
            .from('hse_workers')
            .select()
            .eq('officer_uid', officerUid),
      ]);

      List<Map<String, dynamic>> workersResponse =
          List<Map<String, dynamic>>.from(responses[0]);
      List<Map<String, dynamic>> hseWorkersResponse =
          List<Map<String, dynamic>>.from(responses[1]);

      // Sort alphabetically by full name
      workersResponse.sort((a, b) {
        final nameA = "${a['first_name'] ?? ''} ${a['last_name'] ?? ''}".trim();
        final nameB = "${b['first_name'] ?? ''} ${b['last_name'] ?? ''}".trim();
        return nameA.toLowerCase().compareTo(nameB.toLowerCase());
      });

      hseWorkersResponse.sort((a, b) {
        final nameA = "${a['first_name'] ?? ''} ${a['last_name'] ?? ''}".trim();
        final nameB = "${b['first_name'] ?? ''} ${b['last_name'] ?? ''}".trim();
        return nameA.toLowerCase().compareTo(nameB.toLowerCase());
      });

      cache.workers = workersResponse;
      cache.hseWorkers = hseWorkersResponse;
      cache.isLoaded = true;
      await Future.wait([
        OfficerRepository.instance.saveOfficerWorkers(workersResponse),
        OfficerRepository.instance.saveOfficerHseWorkers(hseWorkersResponse),
      ]);

      if (mounted) setState(() => loading = false);
    } on SocketException {
      final workers = OfficerRepository.instance.getOfficerWorkers();
      final hseWorkers = OfficerRepository.instance.getOfficerHseWorkers();
      cache.workers = workers ?? cache.workers;
      cache.hseWorkers = hseWorkers ?? cache.hseWorkers;
      cache.isLoaded = true;
      if (mounted) setState(() => loading = false);
    } catch (e) {
      debugPrint('Error loading workers: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  // Capitalize helper
  String capitalizeName(String name) {
    if (name.isEmpty) return '';
    return name[0].toUpperCase() + name.substring(1).toLowerCase();
  }

  // Delete worker
  Future<void> _deleteWorker(String tableName, String workerId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm Delete'),
        content: Text('Are you sure you want to delete this worker?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await Supabase.instance.client
            .from(tableName)
            .delete()
            .eq('id', workerId);

        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Worker deleted successfully')),
        );

        _loadWorkers();
      } on SocketException {
        await _syncRepository.enqueueAction(
          id: 'officer_delete_${tableName}_${workerId}_${DateTime.now().millisecondsSinceEpoch}',
          table: tableName,
          action: 'delete',
          payload: {'id': workerId},
        );
        await _removeWorkerLocally(tableName, workerId);
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Deleted offline - will sync when online.'),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to delete worker: $e')),
        );
      }
    }
  }

  Future<void> _removeWorkerLocally(String tableName, String workerId) async {
    if (tableName == 'workers') {
      cache.workers.removeWhere((worker) => worker['id'] == workerId);
      await OfficerRepository.instance.saveOfficerWorkers(cache.workers);
    } else {
      cache.hseWorkers.removeWhere((worker) => worker['id'] == workerId);
      await OfficerRepository.instance.saveOfficerHseWorkers(cache.hseWorkers);
    }
    if (mounted) setState(() {});
  }

  Widget _buildWorkerList(
    String title,
    List<Map<String, dynamic>> list,
    GlobalKey key,
    String tableName,
  ) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: R.blockH * 4.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: R.blockV * 1),
        if (list.isEmpty)
          Text("No workers registered yet.")
        else
          ...list.map((worker) {
            final firstName = worker['first_name'] ?? '';
            final lastName = worker['last_name'] ?? '';
            final name =
                "${capitalizeName(firstName)} ${capitalizeName(lastName)}"
                    .trim();

            final subtitle = tableName == 'workers'
                ? (worker['work_type'] ?? 'Unknown')
                : (worker['designation'] ?? 'Unknown');

            return Card(
              margin: EdgeInsets.symmetric(
                horizontal: R.blockH * 3,
                vertical: R.blockV * 0.75,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: worker['profile_image_url'] != null
                      ? CachedNetworkImageProvider(worker['profile_image_url'])
                      : null,
                  child: worker['profile_image_url'] == null
                      ? Icon(Icons.person)
                      : null,
                ),
                title: Text(name),
                subtitle: Text(subtitle),
                // ✅ Tappable to open profile
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WorkerProfileScreen(
                        worker: worker,
                        tableName: tableName,
                      ),
                    ),
                  );
                },
                trailing: IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteWorker(tableName, worker['id']),
                ),
              ),
            );
          }),
        SizedBox(height: R.blockV * 2.5),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Workers'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadWorkers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: loading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadWorkers,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                controller: _scrollController,
                padding: EdgeInsets.all(R.blockH * 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildWorkerList(
                      "Workers",
                      cache.workers,
                      _workersKey,
                      'workers',
                    ),
                    _buildWorkerList(
                      "HSE Workers",
                      cache.hseWorkers,
                      _hseWorkersKey,
                      'hse_workers',
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
