// lib/hse_workers/screens/hse_worker_dashboard.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'hse_worker_notification_screen.dart';
import 'hse_worker_hazard_notifier.dart';
import 'hse_team_members_screen.dart';
import 'HSEWorkerResolvedHazardsScreen.dart';
import 'AssignedTasksScreen.dart';
import 'hse_worker_app_settings_screen.dart';
import 'hse_worker_view_profile_screen.dart';
import '../../shared/settings/about_app_screen.dart';
import '../../shared/screens/shared_emergency_sos_screen.dart';
import '../../shared/widgets/risk_radar_loader.dart';
import '../../shared/widgets/offline_banner.dart';
import '../../shared/widgets/realtime_connection_indicator.dart';
import 'package:riskradar/services/providers/hse_task_provider.dart';
import 'package:riskradar/services/providers/notification_count_provider.dart';
import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';

class HSEWorkerHomeScreen extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final void Function(ThemeMode) onThemeChanged;

  const HSEWorkerHomeScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeChanged,
  });

  @override
  State<HSEWorkerHomeScreen> createState() => _HSEWorkerHomeScreenState();
}

class _HSEWorkerHomeScreenState extends State<HSEWorkerHomeScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AuthRepository _authRepository = AuthRepository();
  final HazardRepository _hazardRepository = HazardRepository();

  late AnimationController _animationController;
  late Animation<double> _curveAnimation;
  int _selectedIndex = 0;

  static const Color _brandTeal = Color(0xFF1B3D3D);
  static const Color _accentGold = Color(0xFFE6A050);

  bool loading = true;
  bool _hasError = false;
  bool _isRefreshing = false;

  String fullName = "";
  String firstNameInitial = "";
  String profileImageUrl = "";
  String designation = "";
  String linkedContractorName = "No contractor linked";
  String? linkedOfficerAuthId;
  String currentSiteName = "No site assigned";
  String? currentSiteId;
  int sitePersonnelCount = 0;

  int activeTasks = 0;
  int queueTasks = 0;
  int totalTasks = 0;
  double completionPercentage = 0.0;
  int teamCount = 0;

  StreamSubscription<Position>? _positionSubscription;
  List<Widget> _screens = [];
  bool _screensInitialized = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _curveAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _bootSequence();
    _startLocationTracking();
    workerHazardNotifier.startChecking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _animationController.dispose();
    workerHazardNotifier.stopChecking();
    super.dispose();
  }

  Future<void> _bootSequence() async {
    // 1. Read from cache instantly
    await _loadFromCache();
    // 2. Fetch fresh data silently
    await _refreshFromSupabase();
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
    _curveAnimation =
        Tween<double>(
          begin: _curveAnimation.value,
          end: index.toDouble(),
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );
    _animationController.forward(from: 0);
  }

  String _capitalize(String text) {
    if (text.isEmpty) return "";
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return "";
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  // ---------------------------------------------------------------------------
  // ✅ 1. CACHE READ (Instant UI Paint)
  // ---------------------------------------------------------------------------
  Future<void> _loadFromCache() async {
    try {
      final profile = _authRepository.getHseProfile();
      final tasks = await _hazardRepository.getHseAssignedTasks();
      final contextData = _authRepository.getHseContext();

      if (profile != null) {
        fullName = _capitalize(
          "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}",
        );
        firstNameInitial =
            (profile['first_name']?.toString().isNotEmpty ?? false)
            ? profile['first_name'][0].toUpperCase()
            : "H";
        profileImageUrl = profile['profile_image_url'] ?? "";
        designation = _capitalize(profile['designation'] ?? "");
        currentSiteId = profile['current_site_id']?.toString();

        if (tasks != null) {
          activeTasks = 0;
          queueTasks = 0;
          for (final task in tasks) {
            final status = (task['status'] ?? 'assigned')
                .toString()
                .toLowerCase();
            if (status != 'resolved' && status != 'resolved by other') {
              if (status == 'in_progress') {
                activeTasks++;
              } else {
                queueTasks++;
              }
            }
          }
          totalTasks = activeTasks + queueTasks;
          completionPercentage = totalTasks == 0
              ? 0.0
              : activeTasks / totalTasks;
        }

        if (contextData != null) {
          currentSiteName = _capitalize(
            contextData['site_name'] ?? "No site assigned",
          );
          sitePersonnelCount = contextData['site_personnel_count'] ?? 0;
          linkedContractorName = _capitalize(
            contextData['officer_name'] ?? "No contractor linked",
          );
          linkedOfficerAuthId = contextData['officer_auth_id'];
          teamCount = contextData['team_count'] ?? 0;
        }

        if (mounted) {
          setState(() {
            _initScreens();
            _screensInitialized = true;
            loading = false;
            _hasError = false;
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ Cache read error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // ✅ 2. SILENT BACKGROUND REFRESH
  // ---------------------------------------------------------------------------
  Future<void> _refreshFromSupabase() async {
    if (mounted) setState(() => _isRefreshing = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final Future<Map<String, dynamic>?> profileFuture = supabase
          .from('hse_workers')
          .select(
            'first_name, last_name, profile_image_url, designation, officer_uid, current_site_id',
          )
          .eq('id', userId)
          .maybeSingle();

      final Future<List<dynamic>> taskFuture = supabase
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
          .eq('assigned_to', userId);

      final results = await Future.wait([
        profileFuture,
        taskFuture,
      ]).timeout(const Duration(seconds: 15));

      final profile = results[0] as Map<String, dynamic>?;
      final taskResponse = results[1] as List<dynamic>;

      if (profile != null) {
        await _authRepository.saveHseProfile(profile);
        await _hazardRepository.saveHseAssignedTasks(taskResponse);

        final siteId = profile['current_site_id']?.toString();
        final officerUid = profile['officer_uid'];

        if (siteId != null || officerUid != null) {
          final Future<Map<String, dynamic>?> siteFuture = siteId != null
              ? supabase
                    .from('sites')
                    .select('name')
                    .eq('id', siteId)
                    .maybeSingle()
              : Future.value(null);

          final Future<dynamic> personnelFuture = siteId != null
              ? supabase
                    .from('workers')
                    .count(CountOption.exact)
                    .eq('current_site_id', siteId)
              : Future.value(0);

          final Future<Map<String, dynamic>?> officerFuture = officerUid != null
              ? supabase
                    .from('officers')
                    .select('id, first_name, last_name')
                    .eq('officer_uid', officerUid)
                    .maybeSingle()
              : Future.value(null);

          final secondBatch = await Future.wait([
            siteFuture,
            personnelFuture,
            officerFuture,
          ]).timeout(const Duration(seconds: 15));

          final site = secondBatch[0] as Map<String, dynamic>?;
          final personnelCount = (secondBatch[1] as int?) ?? 0;
          final officer = secondBatch[2] as Map<String, dynamic>?;

          int resolvedTeamCount = 0;
          if (officer != null) {
            final Future<dynamic> teamFuture = siteId != null
                ? supabase
                      .from('workers')
                      .count(CountOption.exact)
                      .eq('officer_uid', officerUid)
                      .eq('current_site_id', siteId)
                : Future.value(0);

            resolvedTeamCount = (await teamFuture) as int? ?? 0;
          }

          await _authRepository.saveHseContext({
            'site_id': siteId,
            'site_name': site?['name'],
            'site_personnel_count': personnelCount,
            'officer_uid': officerUid,
            'officer_name': officer != null
                ? "${officer['first_name']} ${officer['last_name']}"
                : null,
            'officer_auth_id': officer?['id'],
            'team_count': resolvedTeamCount,
          });
        }
      }

      // Re-read from cache strictly to update UI
      await _loadFromCache();
    } catch (e) {
      debugPrint('⚠️ Silent refresh error (Offline mode active): $e');
      if (!_screensInitialized) {
        if (mounted) setState(() => _hasError = true);
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  void _initScreens() {
    _screens = [
      _dashboardBody(),
      const AssignedTasksScreen(),
      const HSEWorkerResolvedHazardsScreen(),
      HSEWorkerAppSettingsScreen(
        onAboutTap: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(builder: (_) => const AboutAppScreen()),
        ),
        onThemeChanged: widget.onThemeChanged,
        currentThemeMode: widget.currentThemeMode,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // LOCATION TRACKING
  // ---------------------------------------------------------------------------
  Future<void> _startLocationTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 20,
            ),
          ).listen((pos) async {
            final user = supabase.auth.currentUser;
            if (user == null) return;
            try {
              await supabase.from('user_locations').upsert({
                'user_id': user.id,
                'latitude': pos.latitude,
                'longitude': pos.longitude,
                'updated_at': DateTime.now().toIso8601String(),
              }, onConflict: 'user_id');
            } catch (e) {
              debugPrint('⚠️ Location upsert error: $e'); // Graceful fail
            }
          });
    } catch (e) {
      debugPrint('⚠️ Location tracking setup error: $e');
    }
  }

  void _navigateToSOS() {
    if (currentSiteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No site assigned."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SharedEmergencySOSScreen(
          linkedContractorId: linkedOfficerAuthId,
          currentSiteId: currentSiteId,
          isWorker: false,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DRAWER
  // ---------------------------------------------------------------------------
  Widget _buildSpotifyDrawer() {
    return Drawer(
      backgroundColor: _brandTeal,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF142E2E)),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.purple.shade200,
              backgroundImage: profileImageUrl.isNotEmpty
                  ? NetworkImage(profileImageUrl)
                  : null,
              child: profileImageUrl.isEmpty
                  ? Text(
                      firstNameInitial,
                      style: TextStyle(
                        fontSize: R.blockH * 6,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    )
                  : null,
            ),
            accountName: Text(
              fullName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: R.blockH * 4.5,
                color: Colors.white,
              ),
            ),
            accountEmail: Text(
              designation,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: R.blockH * 3.5,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "CURRENT SITE CONTEXT",
                  style: TextStyle(
                    color: _accentGold.withValues(alpha: 0.8),
                    fontSize: R.blockH * 2.75,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: R.blockV * 1.875),
                _drawerInfoTile(
                  Icons.location_city,
                  "Site Name",
                  currentSiteName,
                ),
                _drawerInfoTile(
                  Icons.groups_outlined,
                  "Total Personnel",
                  "$sitePersonnelCount Active",
                ),
                _drawerInfoTile(
                  Icons.person_pin_rounded,
                  "Contractor",
                  linkedContractorName,
                ),
              ],
            ),
          ),
          Divider(color: Colors.white10),
          _drawerTile(Icons.account_circle_outlined, "Profile Details", () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const HSEWorkerEditProfileScreen(),
              ),
            );
          }),
          _drawerTile(Icons.settings_outlined, "Settings", () {
            Navigator.pop(context);
            _onItemTapped(3);
          }),
          Spacer(),
          Padding(
            padding: EdgeInsets.all(R.blockH * 4),
            child: Text(
              "RiskRadar v1.0.2",
              style: TextStyle(
                color: Colors.white24,
                fontSize: R.blockH * 2.75,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: TextStyle(
          fontSize: R.blockH * 3.75,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _drawerInfoTile(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: R.blockV * 1.875),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _accentGold),
          SizedBox(width: R.blockH * 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: R.blockH * 2.5,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: R.blockH * 3.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DASHBOARD BODY
  // ---------------------------------------------------------------------------
  Widget _dashboardBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey.shade400),
            SizedBox(height: R.blockV * 2),
            Text(
              'Failed to load dashboard',
              style: TextStyle(
                fontSize: R.blockH * 4,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(height: R.blockV * 1),
            Text(
              'Check your connection and try again',
              style: TextStyle(
                fontSize: R.blockH * 3.25,
                color: Colors.grey.shade500,
              ),
            ),
            SizedBox(height: R.blockV * 3),
            ElevatedButton.icon(
              onPressed: _bootSequence,
              icon: Icon(Icons.refresh_rounded),
              label: Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Consumer(
      builder: (context, ref, child) {
        final activeTaskCount = ref
            .watch(hseTaskProvider)
            .when(
              data: (hazards) => hazards.length,
              error: (error, stackTrace) => activeTasks,
              loading: () => activeTasks,
            );

        return RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              _refreshFromSupabase(),
              ref.read(hseTaskProvider.notifier).refresh(bypassCache: true),
            ]);
          },
          color: _accentGold,
          backgroundColor: _brandTeal,
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(R.blockH * 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Let's become",
                      style: TextStyle(
                        fontSize: R.blockH * 5.5,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      "more Productive",
                      style: TextStyle(
                        fontSize: R.blockH * 6.5,
                        fontWeight: FontWeight.bold,
                        color: _accentGold,
                      ),
                    ),
                    SizedBox(height: R.blockV * 3.125),

                    Row(
                      children: [
                        Expanded(
                          child: _buildThemedCard(
                            icon: Icons.assignment_turned_in,
                            title: "$activeTaskCount Active",
                            subtitle: "Tasks in progress",
                            buttonText: "View All",
                            onTap: () => _onItemTapped(1),
                            showProgress: true,
                          ),
                        ),
                        SizedBox(width: R.blockH * 4.267),
                        Expanded(
                          child: _buildThemedCard(
                            icon: Icons.engineering,
                            title: "$teamCount",
                            subtitle: "Total Workforce",
                            buttonText: "View Workforce",
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HSETeamMembersScreen(
                                  currentSiteId: currentSiteId,
                                ),
                              ),
                            ),
                            showProgress: false,
                          ),
                        ),
                      ],
                    ),

                    // Bottom padding for FAB + nav bar
                    SizedBox(height: R.blockV * 20),
                  ],
                ),
              ),
              if (_isRefreshing)
                Positioned(
                  top: 10,
                  right: 20,
                  child: SizedBox(
                    width: R.blockH * 4.267,
                    height: R.blockV * 2,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _brandTeal.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemedCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onTap,
    bool showProgress = false,
  }) {
    return Container(
      height: R.blockV * 22.5,
      padding: EdgeInsets.all(R.blockH * 5),
      decoration: BoxDecoration(
        color: _brandTeal,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: Colors.white70, size: 28),
              if (showProgress)
                SizedBox(
                  width: R.blockH * 10.667,
                  height: R.blockV * 5,
                  child: CircularProgressIndicator(
                    value: completionPercentage,
                    strokeWidth: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(_accentGold),
                  ),
                )
              else
                Icon(Icons.arrow_forward, color: Colors.white24, size: 20),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: R.blockH * 5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white54, fontSize: R.blockH * 3),
              ),
            ],
          ),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentGold,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: EdgeInsets.symmetric(horizontal: R.blockH * 4),
              minimumSize: const Size(double.infinity, 36),
              elevation: 0,
            ),
            child: Text(
              buttonText,
              style: TextStyle(
                color: Colors.white,
                fontSize: R.blockH * 3,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    R.init(context);
    if (loading) {
      return const RiskRadarLoadingScreen(message: 'Loading your dashboard...');
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF121212)
        : Colors.grey.shade50;

    final String title = [
      "Dashboard",
      "My Tasks",
      "Resolved",
      "Settings",
    ][_selectedIndex];

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedIndex != 0) _onItemTapped(0);
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildSpotifyDrawer(),
        backgroundColor: backgroundColor,
        extendBody: true,
        resizeToAvoidBottomInset: false,

        appBar: AppBar(
          backgroundColor: _brandTeal,
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: (_selectedIndex == 0)
              ? GestureDetector(
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  child: Padding(
                    padding: EdgeInsets.all(R.blockH * 2.5),
                    child: CircleAvatar(
                      backgroundColor: Colors.purple.shade200,
                      backgroundImage: profileImageUrl.isNotEmpty
                          ? NetworkImage(profileImageUrl)
                          : null,
                      child: profileImageUrl.isEmpty
                          ? Text(
                              firstNameInitial,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            )
                          : null,
                    ),
                  ),
                )
              : null,
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          actions: [
            const RealtimeConnectionIndicator(),
            Consumer(
              builder: (context, ref, child) {
                final count = ref
                    .watch(notificationCountProvider)
                    .when(
                      data: (value) => value,
                      error: (error, stackTrace) => 0,
                      loading: () => 0,
                    );
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.notifications_none_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              const HSEWorkerNotificationScreen(),
                        ),
                      ),
                    ),
                    if (count > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: EdgeInsets.all(R.blockH * 0.5),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: _brandTeal, width: 1.5),
                          ),
                          constraints: BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: R.blockH * 2.5,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            SizedBox(width: R.blockH * 2.133),
          ],
        ),

        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: _screensInitialized
                  ? IndexedStack(index: _selectedIndex, children: _screens)
                  : const RiskRadarLoadingScreen(
                      message: 'Preparing screens...',
                    ),
            ),
          ],
        ),

        floatingActionButton: _selectedIndex == 0
            ? Padding(
                padding: EdgeInsets.only(bottom: R.blockV * 11.25),
                child: FloatingActionButton.extended(
                  backgroundColor: Colors.red.shade600,
                  onPressed: _navigateToSOS,
                  elevation: 4,
                  icon: Icon(Icons.sos_rounded, color: Colors.white),
                  label: Text(
                    "EMERGENCY",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

        bottomNavigationBar: _buildConcaveNavBar(),
      ),
    );
  }

  Widget _buildConcaveNavBar() {
    return SizedBox(
      height: R.blockV * 10.625,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _curveAnimation,
              builder: (context, child) {
                return CustomPaint(
                  size: Size(MediaQuery.of(context).size.width, 85),
                  painter: ConcaveNavPainter(
                    selectedIndex: _curveAnimation.value,
                    itemsCount: 4,
                    color: _brandTeal,
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildNavItem(0, Icons.grid_view_rounded, "Home"),
                _buildNavItem(1, Icons.assignment_rounded, "Tasks"),
                _buildNavItem(2, Icons.check_circle_rounded, "Resolved"),
                _buildNavItem(3, Icons.settings_rounded, "Settings"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: R.blockH * 18.667,
        height: R.blockV * 10.625,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              top: isSelected ? 0 : 20,
              child: Container(
                width: R.blockH * 13.333,
                height: R.blockV * 6.25,
                decoration: BoxDecoration(
                  color: isSelected ? _accentGold : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.5),
                  size: 24,
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: 1.0,
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? _accentGold : Colors.white70,
                    fontSize: R.blockH * 2.5,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConcaveNavPainter extends CustomPainter {
  final double selectedIndex;
  final int itemsCount;
  final Color color;

  ConcaveNavPainter({
    required this.selectedIndex,
    required this.itemsCount,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    Path path = Path();
    double barHeight = 65.0;
    double topOffset = size.height - barHeight;
    double sectionWidth = size.width / itemsCount;
    double currentCenter = (selectedIndex * sectionWidth) + (sectionWidth / 2);
    double notchRadius = 38.0;

    path.moveTo(0, topOffset);
    path.lineTo(currentCenter - notchRadius - 5, topOffset);
    path.cubicTo(
      currentCenter - notchRadius,
      topOffset,
      currentCenter - notchRadius + 5,
      topOffset + 40,
      currentCenter,
      topOffset + 40,
    );
    path.cubicTo(
      currentCenter + notchRadius - 5,
      topOffset + 40,
      currentCenter + notchRadius,
      topOffset,
      currentCenter + notchRadius + 5,
      topOffset,
    );
    path.lineTo(size.width, topOffset);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.15), 4.0, true);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ConcaveNavPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex;
  }
}
