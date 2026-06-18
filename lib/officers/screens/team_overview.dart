import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/shared/theme/app_colors.dart';
import '../labours/worker_profile_screen.dart';
import 'dart:ui';

// --- Workers Cache Singleton ---
class WorkersCache {
  static final WorkersCache _instance = WorkersCache._internal();
  factory WorkersCache() => _instance;
  WorkersCache._internal();

  List<Map<String, dynamic>> workers = [];
  List<Map<String, dynamic>> hseWorkers =
      []; // Keep internal name for consistency
  List<Map<String, dynamic>> availableSites = [];
  bool isLoaded = false;
  bool sitesLoaded = false;
}

class WorkersListScreen extends StatefulWidget {
  const WorkersListScreen({super.key});

  @override
  State<WorkersListScreen> createState() => _WorkersListScreenState();
}

class _WorkersListScreenState extends State<WorkersListScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final cache = WorkersCache();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _workersKey = GlobalKey();
  final GlobalKey _hseWorkersKey = GlobalKey(); // Keep internal name
  final SyncRepository _syncRepository = SyncRepository();
  RealtimeChannel? _workersChannel;
  RealtimeChannel? _hseWorkersChannel;
  Timer? _teamRefreshDebounce;
  dynamic _listeningOfficerUid;

  bool loading = true;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredWorkers = [];
  List<Map<String, dynamic>> _filteredHseWorkers = [];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _searchController.addListener(_filterLists);

    _loadPersistentCache();

    if (cache.isLoaded) {
      loading = false;
      _filterLists(); // Apply filter initially if cache is loaded
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fadeController.forward();
          _loadInitialData(forceRefresh: true);
        }
      });
    } else {
      _loadInitialData(forceRefresh: true);
    }
  }

  void _loadPersistentCache() {
    final workers = OfficerRepository.instance.getOfficerWorkers();
    final hseWorkers = OfficerRepository.instance.getOfficerHseWorkers();
    final sites = OfficerRepository.instance.getOfficerSites();

    if (workers != null || hseWorkers != null) {
      cache.workers = workers ?? [];
      cache.hseWorkers = hseWorkers ?? [];
      cache.isLoaded = true;
    }
    if (sites != null) {
      cache.availableSites = sites;
      cache.sitesLoaded = true;
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scrollController.dispose();
    _searchController.removeListener(_filterLists);
    _searchController.dispose();
    _teamRefreshDebounce?.cancel();
    _workersChannel?.unsubscribe();
    _hseWorkersChannel?.unsubscribe();
    super.dispose();
  }

  void _filterLists() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredWorkers = List.from(cache.workers);
        _filteredHseWorkers = List.from(cache.hseWorkers);
      } else {
        _filteredWorkers = cache.workers.where((worker) {
          final fullName =
              "${worker['first_name'] ?? ''} ${worker['last_name'] ?? ''}"
                  .toLowerCase();
          return fullName.contains(query);
        }).toList(); // .toList() is necessary here after .where()

        _filteredHseWorkers = cache.hseWorkers.where((worker) {
          final fullName =
              "${worker['first_name'] ?? ''} ${worker['last_name'] ?? ''}"
                  .toLowerCase();
          return fullName.contains(query);
        }).toList(); // .toList() is necessary here after .where()
      }
    });
  }

  Future<void> _loadInitialData({bool forceRefresh = false}) async {
    await _fetchSites(forceRefresh: forceRefresh);
    await _loadWorkers(forceRefresh: forceRefresh);
  }

  Future<void> _loadWorkers({bool forceRefresh = false}) async {
    if (!mounted) return; // Check mounted at the beginning

    if (cache.isLoaded && !forceRefresh) {
      // Data already loaded, ensure UI reflects it
      if (loading) {
        // Only update state if needed
        setState(() => loading = false);
        _fadeController.forward();
      }
      _filterLists(); // Ensure lists are filtered correctly
      return;
    }

    if (!forceRefresh) setState(() => loading = true);

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      setState(() => loading = false);
      _showSnackBar('User not logged in.', Colors.orange);
      return;
    }

    try {
      final officer = await Supabase.instance.client
          .from('officers')
          .select('officer_uid')
          .eq('id', userId)
          .maybeSingle();

      if (!mounted) return; // Check mounted after await

      if (officer == null) {
        setState(() => loading = false);
        _showSnackBar('Officer profile not found.', Colors.orange);
        return;
      }

      final officerUid = officer['officer_uid'];
      _listenForTeamChanges(officerUid);

      final responses = await Future.wait([
        Supabase.instance.client
            .from('workers')
            .select('*, sites!workers_current_site_id_fkey(id, name)')
            .eq('officer_uid', officerUid),
        Supabase.instance.client
            .from('hse_workers') // Keep internal table name
            .select('*, sites!hse_workers_current_site_id_fkey(id, name)')
            .eq('officer_uid', officerUid),
      ]);

      if (!mounted) return; // Check mounted after await

      List<Map<String, dynamic>> workersResponse =
          List<Map<String, dynamic>>.from(responses[0]);
      List<Map<String, dynamic>> hseWorkersResponse =
          List<Map<String, dynamic>>.from(responses[1]);

      workersResponse.sort((a, b) => _compareNames(a, b));
      hseWorkersResponse.sort((a, b) => _compareNames(a, b));

      cache.workers = workersResponse;
      cache.hseWorkers = hseWorkersResponse;
      cache.isLoaded = true;
      await Future.wait([
        OfficerRepository.instance.saveOfficerWorkers(workersResponse),
        OfficerRepository.instance.saveOfficerHseWorkers(hseWorkersResponse),
      ]);

      _filterLists(); // Apply filters to the newly loaded data

      setState(() => loading = false);
      _fadeController.forward();
    } on SocketException {
      debugPrint('Officer team offline - using cached data.');
      if (!mounted) return;
      _filterLists();
      setState(() => loading = false);
      _fadeController.forward();
    } catch (e) {
      debugPrint('Error loading workers: $e');
      if (!mounted) return; // Check mounted in catch block
      setState(() => loading = false);
      _showSnackBar('Error loading workers: $e', Colors.red);
    }
  }

  void _listenForTeamChanges(dynamic officerUid) {
    if (_listeningOfficerUid == officerUid &&
        _workersChannel != null &&
        _hseWorkersChannel != null) {
      return;
    }

    _listeningOfficerUid = officerUid;
    _workersChannel?.unsubscribe();
    _hseWorkersChannel?.unsubscribe();

    _workersChannel = _buildTeamChannel(
      channelName: 'contractor-workers-$officerUid',
      tableName: 'workers',
      officerUid: officerUid,
    );
    _hseWorkersChannel = _buildTeamChannel(
      channelName: 'contractor-hse-workers-$officerUid',
      tableName: 'hse_workers',
      officerUid: officerUid,
    );
  }

  RealtimeChannel _buildTeamChannel({
    required String channelName,
    required String tableName,
    required dynamic officerUid,
  }) {
    return Supabase.instance.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: tableName,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'officer_uid',
            value: officerUid,
          ),
          callback: (_) => _scheduleTeamRefresh(),
        )
        .subscribe();
  }

  void _scheduleTeamRefresh() {
    _teamRefreshDebounce?.cancel();
    _teamRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        _loadWorkers(forceRefresh: true);
      }
    });
  }

  int _compareNames(Map<String, dynamic> a, Map<String, dynamic> b) {
    final nameA = "${a['first_name'] ?? ''} ${a['last_name'] ?? ''}".trim();
    final nameB = "${b['first_name'] ?? ''} ${b['last_name'] ?? ''}".trim();
    return nameA.toLowerCase().compareTo(nameB.toLowerCase());
  }

  Future<void> _fetchSites({bool forceRefresh = false}) async {
    if (!mounted) return; // Check mounted at the beginning

    if (cache.sitesLoaded && !forceRefresh) return;
    try {
      final response = await Supabase.instance.client
          .from('sites')
          .select('id, name, description')
          .order('name', ascending: true);

      if (!mounted) return; // Check mounted after await

      cache.availableSites = List<Map<String, dynamic>>.from(response);
      cache.sitesLoaded = true;
      await OfficerRepository.instance.saveOfficerSites(cache.availableSites);
    } on SocketException {
      debugPrint('Officer sites offline - using cached data.');
    } catch (e) {
      debugPrint('Error fetching sites: $e');
      if (!mounted) return; // Check mounted in catch block
      _showSnackBar('Could not load available sites: $e', Colors.redAccent);
    }
  }

  Future<void> _deleteWorker(String tableName, String workerId) async {
    // No need to check mounted before showing dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm Deletion'),
        content: Text(
          'Are you sure you want to delete this worker? This action cannot be undone.',
        ),
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

    if (!mounted) return; // Check mounted after await for dialog

    if (confirm == true) {
      try {
        await Supabase.instance.client
            .from(tableName)
            .delete()
            .eq('id', workerId);

        if (!mounted) return; // Check mounted after await for delete

        _showSnackBar('Worker deleted successfully!', Colors.green);
        await _loadWorkers(forceRefresh: true); // Reload data
      } on SocketException {
        await _syncRepository.enqueueAction(
          id: 'officer_delete_${tableName}_${workerId}_${DateTime.now().millisecondsSinceEpoch}',
          table: tableName,
          action: 'delete',
          payload: {'id': workerId},
        );
        _removeWorkerLocally(tableName, workerId);
        _showSnackBar(
          'Deleted offline - will sync when online.',
          Colors.orange,
        );
      } catch (e) {
        if (!mounted) return; // Check mounted in catch block
        _showSnackBar('Failed to delete worker: $e', Colors.red);
      }
    }
  }

  void _showChangeSiteSheet(Map<String, dynamic> worker, String tableName) {
    final currentSiteId = worker['sites']?['id'];
    dynamic selectedSiteId = currentSiteId;

    final siteSearchController = TextEditingController();
    List<Map<String, dynamic>> filteredSites = List.from(cache.availableSites);
    // bool isDisposed = false; // Not needed

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            void filterSites(String query) {
              setModalState(() {
                if (query.isEmpty) {
                  filteredSites = List.from(cache.availableSites);
                } else {
                  filteredSites = cache.availableSites
                      .where(
                        (site) => (site['name'] as String)
                            .toLowerCase()
                            .contains(query.toLowerCase()),
                      )
                      .toList(); // .toList() is necessary here
                }
              });
            }

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        // ✅ Replaced withOpacity
                        const Color(0xFF11444D).withAlpha((255 * 0.96).round()),
                        const Color(0xFF0A2830).withAlpha((255 * 0.96).round()),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border(
                      // ✅ Replaced withOpacity
                      top: BorderSide(
                        color: Colors.white.withAlpha((255 * 0.2).round()),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(R.blockH * 5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Change Site for ${worker['first_name']}',
                          style: TextStyle(
                            fontSize: R.blockH * 5.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: R.blockV * 2),
                        // Removed unnecessary Focus widget
                        TextField(
                          controller: siteSearchController,
                          onChanged: filterSites,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search for a site...',
                            // ✅ Replaced withOpacity
                            hintStyle: TextStyle(
                              color: Colors.white.withAlpha(
                                (255 * 0.7).round(),
                              ),
                            ),
                            // ✅ Replaced withOpacity
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.white.withAlpha(
                                (255 * 0.7).round(),
                              ),
                            ),
                            filled: true,
                            // ✅ Replaced withOpacity
                            fillColor: Colors.white.withAlpha(
                              (255 * 0.1).round(),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: R.blockV * 2),
                        Flexible(
                          child: filteredSites.isEmpty
                              ? Center(
                                  child: Text(
                                    // Simplified logic
                                    'No sites found matching your search.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filteredSites.length,
                                  itemBuilder: (context, index) {
                                    final site = filteredSites[index];
                                    final description =
                                        site['description'] ??
                                        'No description available.';
                                    return RadioListTile<dynamic>(
                                      title: Text(
                                        site['name'],
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        description,
                                        // ✅ Replaced withOpacity
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(
                                            (255 * 0.8).round(),
                                          ),
                                        ),
                                      ),
                                      value: site['id'],
                                      // ignore: deprecated_member_use
                                      groupValue: selectedSiteId,
                                      activeColor: Colors.white,
                                      // ignore: deprecated_member_use
                                      onChanged: (value) {
                                        setModalState(() {
                                          selectedSiteId = value;
                                        });
                                      },
                                    );
                                  },
                                ),
                        ),
                        SizedBox(height: R.blockV * 2),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  // ✅ Replaced withOpacity
                                  side: BorderSide(
                                    color: Colors.white.withAlpha(
                                      (255 * 0.5).round(),
                                    ),
                                  ),
                                ),
                                child: Text('Cancel'),
                              ),
                            ),
                            SizedBox(width: R.blockH * 3.2),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF11444D),
                                ),
                                onPressed:
                                    (selectedSiteId != null &&
                                        selectedSiteId != currentSiteId)
                                    ? () async {
                                        // No need for FocusScope.unfocus() or delay here
                                        final navigator = Navigator.of(
                                          context,
                                        ); // Store navigator
                                        navigator.pop(); // Pop before async gap
                                        await _updateWorkerSite(
                                          tableName,
                                          worker['id'],
                                          selectedSiteId,
                                        );
                                      }
                                    : null,
                                child: Text('Save Changes'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // Safely dispose the controller after the sheet is closed
      // We don't need the isDisposed or hasListeners check
      // Dispose should happen in the main widget's dispose method
      // However, if creating temporary controllers, dispose here:
      siteSearchController.dispose();
    });
  }

  Future<void> _updateWorkerSite(
    String tableName,
    String workerId,
    dynamic newSiteId,
  ) async {
    if (!mounted) return; // Check mounted

    try {
      await Supabase.instance.client
          .from(tableName)
          .update({'current_site_id': newSiteId})
          .eq('id', workerId);

      if (!mounted) return; // Check mounted after await

      _showSnackBar('Site updated successfully!', Colors.green);
      await _loadWorkers(forceRefresh: true); // Reload data
    } on SocketException {
      await _syncRepository.enqueueAction(
        id: 'officer_site_${tableName}_${workerId}_${DateTime.now().millisecondsSinceEpoch}',
        table: tableName,
        action: 'update',
        payload: {'id': workerId, 'current_site_id': newSiteId},
      );
      await _updateWorkerSiteLocally(tableName, workerId, newSiteId);
      _showSnackBar(
        'Site change saved offline - will sync when online.',
        Colors.orange,
      );
    } catch (e) {
      debugPrint('Error updating site: $e');
      if (!mounted) return; // Check mounted in catch block
      _showSnackBar('Failed to update site: $e', Colors.red);
    }
  }

  void _removeWorkerLocally(String tableName, String workerId) {
    if (tableName == 'workers') {
      cache.workers.removeWhere((worker) => worker['id'] == workerId);
      OfficerRepository.instance.saveOfficerWorkers(cache.workers);
    } else {
      cache.hseWorkers.removeWhere((worker) => worker['id'] == workerId);
      OfficerRepository.instance.saveOfficerHseWorkers(cache.hseWorkers);
    }
    _filterLists();
  }

  Future<void> _updateWorkerSiteLocally(
    String tableName,
    String workerId,
    dynamic newSiteId,
  ) async {
    final site = cache.availableSites.firstWhere(
      (item) => item['id'] == newSiteId,
      orElse: () => {'id': newSiteId, 'name': 'Pending site'},
    );
    final list = tableName == 'workers' ? cache.workers : cache.hseWorkers;
    for (final worker in list) {
      if (worker['id'] == workerId) {
        worker['current_site_id'] = newSiteId;
        worker['sites'] = site;
      }
    }
    if (tableName == 'workers') {
      await OfficerRepository.instance.saveOfficerWorkers(cache.workers);
    } else {
      await OfficerRepository.instance.saveOfficerHseWorkers(cache.hseWorkers);
    }
    _filterLists();
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  String capitalizeName(String name) {
    if (name.isEmpty) return '';
    return name[0].toUpperCase() + name.substring(1).toLowerCase();
  }

  Widget _buildStatCard(
    String label,
    int count,
    VoidCallback onTap,
    Color color,
  ) {
    const cardBase = Color(0xFF1B3D3D);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: R.blockV * 3,
            horizontal: R.blockH * 4,
          ),
          decoration: BoxDecoration(
            color: cardBase,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.surfaceTeal.withValues(alpha: 0.8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: R.blockH * 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: R.blockV * 1),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: R.blockH * 3.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToKey(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Widget _buildWorkerCard(
    Map<String, dynamic> worker,
    String tableName,
    int index,
  ) {
    final firstName = worker['first_name'] ?? '';
    final lastName = worker['last_name'] ?? '';
    final name = "${capitalizeName(firstName)} ${capitalizeName(lastName)}"
        .trim();
    // ✅ RENAMED: Use Site Inspector title
    final subtitle = tableName == 'workers'
        ? (worker['work_type'] ?? 'Unknown')
        : (worker['designation'] ??
              'Site Inspector'); // Changed designation default
    final siteName = worker['sites']?['name'] ?? 'No site assigned';
    const cardColor = Color(0xFF1B3D3D);

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 400 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.only(
          bottom: R.blockV * 1.5,
          left: R.blockH * 1,
          right: R.blockH * 1,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B3D3D), Color(0xFF1B3D3D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              // ✅ Replaced withOpacity
              color: cardColor.withAlpha((255 * 0.3).round()),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.only(
              left: R.blockH * 4,
              top: R.blockV * 1,
              bottom: R.blockV * 1,
              right: R.blockH * 1,
            ),
            child: Row(
              children: [
                _buildWorkerAvatar(worker),
                SizedBox(width: R.blockH * 4.267),
                Expanded(child: _buildWorkerInfo(name, subtitle, siteName)),
                _buildWorkerMenu(worker, tableName),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkerAvatar(Map<String, dynamic> worker) {
    return Hero(
      tag: 'worker_${worker['id']}',
      child: Container(
        width: R.blockH * 14.933,
        height: R.blockV * 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // ✅ Replaced withOpacity
          color: Colors.white.withAlpha((255 * 0.2).round()),
          boxShadow: [
            BoxShadow(
              // ✅ Replaced withOpacity
              color: Colors.black.withAlpha((255 * 0.2).round()),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: worker['profile_image_url'] != null
            ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: worker['profile_image_url'],
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey.shade200,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) =>
                      Icon(Icons.person, color: Colors.white),
                ),
              )
            : Icon(Icons.person, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildWorkerInfo(String name, String subtitle, String siteName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: TextStyle(
            fontSize: R.blockH * 4,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: Colors.white,
          ),
        ),
        SizedBox(height: R.blockV * 0.5),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: R.blockH * 2,
            vertical: R.blockV * 0.5,
          ),
          decoration: BoxDecoration(
            // ✅ Replaced withOpacity
            color: isDark
                ? Colors.white.withAlpha((255 * 0.16).round())
                : Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: R.blockH * 3,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(height: R.blockV * 0.75),
        Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              // ✅ Replaced withOpacity
              color: Colors.white70,
              size: 14,
            ),
            SizedBox(width: R.blockH * 1.067),
            Expanded(
              child: Text(
                siteName,
                style: TextStyle(
                  // ✅ Replaced withOpacity
                  color: Colors.white70,
                  fontSize: R.blockH * 3,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWorkerMenu(Map<String, dynamic> worker, String tableName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark
        ? const Color(0xFF1B3D3D)
        : Color.lerp(AppColors.brandTeal, Colors.white, 0.82)!;
    final menuText = isDark ? Colors.white : const Color(0xFF153336);

    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: menuBg,
      elevation: 12,
      padding: EdgeInsets.all(R.blockH * 0),
      constraints: BoxConstraints(minWidth: 190),
      onSelected: (value) {
        if (value == 'view_profile') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  WorkerProfileScreen(worker: worker, tableName: tableName),
            ),
          );
        } else if (value == 'change_site') {
          _showChangeSiteSheet(worker, tableName);
        } else if (value == 'delete') {
          _deleteWorker(tableName, worker['id']);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'view_profile',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: R.blockH * 1.5),
            leading: Icon(Icons.person_outline, color: menuText),
            title: Text('View Profile', style: TextStyle(color: menuText)),
          ),
        ),
        PopupMenuItem<String>(
          value: 'change_site',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: R.blockH * 1.5),
            leading: Icon(Icons.unfold_more_outlined, color: menuText),
            title: Text('Change Site', style: TextStyle(color: menuText)),
          ),
        ),
        PopupMenuDivider(
          height: R.blockV * 1.25,
          color: isDark ? Colors.white24 : Colors.black12,
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: R.blockH * 1.5),
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('Delete Worker', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
      icon: Icon(Icons.more_vert, color: Colors.white),
    );
  }

  Widget _buildWorkerList(
    String title,
    List<Map<String, dynamic>> list,
    GlobalKey key,
    String tableName,
  ) {
    final titleColor = Theme.of(context).colorScheme.onSurface;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: R.blockH * 1,
            vertical: R.blockV * 1,
          ),
          child: Row(
            children: [
              Container(
                width: R.blockH * 1.067,
                height: R.blockV * 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      tableName == 'workers'
                          ? const Color(0xFF0F5B63)
                          : const Color(0xFF1A6F79),
                      tableName == 'workers'
                          ? const Color(0xFF0B3B43)
                          : const Color(0xFF0F4B55),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: R.blockH * 3.2),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: titleColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: R.blockV * 1.5),
        if (list.isEmpty)
          _buildEmptyState(tableName)
        else
          // ✅ Removed .toList() from spread
          ...list.asMap().entries.map((entry) {
            return _buildWorkerCard(entry.value, tableName, entry.key);
          }),
        SizedBox(height: R.blockV * 4),
      ],
    );
  }

  Widget _buildEmptyState(String tableName) {
    // ✅ RENAMED: Use Site Inspector title
    final typeName = tableName == 'workers' ? 'workers' : 'inspectors';
    return Container(
      padding: EdgeInsets.all(R.blockH * 8),
      margin: EdgeInsets.symmetric(horizontal: R.blockH * 1),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0E2B33)
            : const Color(0xFFE3F1F3),
        borderRadius: BorderRadius.circular(16),
        // ✅ Replaced withOpacity
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outline.withAlpha((255 * 0.2).round()),
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              _searchController.text.isEmpty
                  ? Icons.people_outline
                  : Icons.search_off,
              size: 48,
              // ✅ Replaced withOpacity
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withAlpha((255 * 0.5).round()),
            ),
            SizedBox(height: R.blockV * 1.5),
            Text(
              _searchController.text.isEmpty
                  ? "No $typeName registered yet"
                  : "No $typeName found for '${_searchController.text}'",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    super.build(
      context,
    ); // Ensure super.build is called for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: loading
          ? _buildLoadingState(isDark)
          : FadeTransition(
              opacity: _fadeAnimation,
              child: RefreshIndicator(
                onRefresh: () async {
                  // No need for separate await, just call the combined function
                  await _loadInitialData(forceRefresh: true);
                },
                color: const Color(0xFF0F5B63),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    R.blockH * 5,
                    R.blockV * 2.5,
                    R.blockH * 5,
                    R.blockV * 15,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSearchBar(isDark),
                      Text(
                        'Manage your workforce efficiently',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: R.blockV * 3),
                      Row(
                        children: [
                          _buildStatCard(
                            'Workers',
                            _filteredWorkers.length,
                            () => _scrollToKey(_workersKey),
                            const Color(0xFF0F5B63),
                          ),
                          SizedBox(width: R.blockH * 4.267),
                          _buildStatCard(
                            // ✅ RENAMED: HSE to Site Inspectors
                            'Site Inspectors',
                            _filteredHseWorkers.length,
                            () => _scrollToKey(_hseWorkersKey),
                            const Color(0xFF1A6F79),
                          ),
                        ],
                      ),
                      SizedBox(height: R.blockV * 4),
                      _buildWorkerList(
                        'Workers',
                        _filteredWorkers,
                        _workersKey,
                        'workers',
                      ),
                      _buildWorkerList(
                        // ✅ RENAMED: HSE to Site Inspectors
                        'Site Inspectors',
                        _filteredHseWorkers,
                        _hseWorkersKey,
                        'hse_workers', // Keep internal table name
                      ),
                      SizedBox(height: R.blockV * 2.5),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(R.blockH * 5),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  // ✅ Replaced withOpacity
                  color: Colors.black.withAlpha((255 * 0.1).round()),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F5B63)),
            ),
          ),
          SizedBox(height: R.blockV * 3),
          Text('Loading Team...', style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: R.blockV * 3),
      child: TextField(
        controller: _searchController,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search by worker name...',
          hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          prefixIcon: Icon(
            Icons.search,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    // No need to call _filterLists here, listener handles it
                  },
                )
              : null,
          filled: true,
          fillColor: isDark
              ? Color.lerp(AppColors.brandTeal, Colors.black, 0.4)!
              : Color.lerp(AppColors.brandTeal, Colors.white, 0.78)!,
          contentPadding: EdgeInsets.symmetric(vertical: R.blockV * 1.875),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.brandTeal, width: 1.4),
          ),
        ),
      ),
    );
  }

  @override
  // Keep alive to preserve state (like scroll position and search query)
  // when switching tabs if this screen is used in a TabBarView.
  bool get wantKeepAlive => true;
}
