import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riskradar/services/providers/hazard_provider.dart';
import 'package:riskradar/services/providers/notification_count_provider.dart';

// --- Imports ---
import 'worker_hazard_report_screen.dart';
import 'worker_resolved_hazards_screen.dart';
import 'worker_ongoing_hazards_screen.dart';
import 'worker_app_settings_screen.dart';
import '../settings/worker_notification_screen.dart';
import '../settings/worker_view_profile_screen.dart';
import '../../shared/settings/about_app_screen.dart';
import '../../shared/screens/shared_emergency_sos_screen.dart';
import '../../shared/widgets/offline_banner.dart';
import '../../shared/widgets/realtime_connection_indicator.dart';
import '../settings/worker_hazard_notifier.dart';
import '../tabs/ai_image.dart';
import '../../shared/widgets/risk_radar_loader.dart';
import 'package:riskradar/services/repositories/auth_repository.dart';

class WorkerHomeScreen extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final void Function(ThemeMode) onThemeChanged;

  const WorkerHomeScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeChanged,
  });

  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AuthRepository _authRepository = AuthRepository();

  late AnimationController _animationController;
  late Animation<double> _curveAnimation;
  int _selectedIndex = 0;

  static const Color _brandTeal = Color(0xFF1B3D3D);
  static const Color _accentGold = Color(0xFFE6A050);

  // ── Loading state ──────────────────────────────────────────────────────────
  // loading = true only on first boot with zero cache.
  // Once cache data is painted, this stays false even during bg refresh.
  bool loading = true;

  // ── Profile display state ──────────────────────────────────────────────────
  String _firstNameInitial = "W";
  String _fullName = "Loading...";
  String _workType = "";
  String _profileImageUrl = "";

  // ── Drawer context state ───────────────────────────────────────────────────
  String _currentSiteName = "No site assigned";
  List<String> _safetyOfficersList = [];
  List<String> _contractorsList = [];

  // ── SOS / location IDs ────────────────────────────────────────────────────
  String? _currentWorkerId;
  String? _currentSiteId;
  String? _linkedOfficerUid;

  StreamSubscription<Position>? _positionSubscription;

  final List<String> _screenTitles = [
    "Dashboard",
    "Ongoing Hazards",
    "Report Hazard",
    "Resolved Hazards",
    "Settings"
  ];

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _curveAnimation = Tween<double>(begin: 0, end: 0).animate(
        CurvedAnimation(
            parent: _animationController, curve: Curves.easeInOut));

    _loadAllData();
    _startLocationTracking();
    workerHazardNotifier.startChecking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NAV HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
    _curveAnimation =
        Tween<double>(begin: _curveAnimation.value, end: index.toDouble())
            .animate(CurvedAnimation(
            parent: _animationController, curve: Curves.easeInOut));
    _animationController.forward(from: 0);
  }

  String _capitalize(String? text) {
    if (text == null || text.isEmpty) return '';
    return text
        .split(' ')
        .map((word) => word.isNotEmpty
        ? word[0].toUpperCase() + word.substring(1).toLowerCase()
        : '')
        .join(' ');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DATA LOADING — cache first, Supabase second
  //
  // Boot sequence:
  //   1. Read cached worker profile → paint UI instantly (loading = false)
  //   2. Read cached worker context → paint drawer instantly
  //   3. Attempt Supabase refresh in background
  //      → On success: update cache + setState (UI refreshes silently)
  //      → On SocketException / any error: silently skip, cached data stays
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _loadAllData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    _currentWorkerId = userId;

    // ── Step 1: Paint from cache immediately ──────────────────────────────
    final cachedProfile = _authRepository.getWorkerProfile();
    final cachedContext = _authRepository.getWorkerContext();

    if (cachedProfile != null) {
      _applyProfile(cachedProfile);
    }

    if (cachedContext != null) {
      _applyContext(cachedContext);
    }

    // If we had anything from cache, stop the loading spinner immediately.
    // The user sees real data in < 1 frame.
    if (cachedProfile != null) {
      if (mounted) setState(() => loading = false);
    }

    // ── Step 2: Background Supabase refresh ───────────────────────────────
    _refreshFromSupabase(userId);
  }

  // ── Apply cached / fresh profile row to display state ─────────────────────
  void _applyProfile(Map<String, dynamic> profile) {
    final fName = profile['first_name'] ?? '';
    final lName = profile['last_name'] ?? '';
    _firstNameInitial = fName.isNotEmpty ? fName[0].toUpperCase() : 'W';
    _fullName = _capitalize('$fName $lName');
    _workType = _capitalize(profile['work_type'] ?? 'Site Worker');
    _profileImageUrl = profile['profile_image_url'] ?? '';
    _currentSiteId = profile['current_site_id']?.toString();
    _linkedOfficerUid = profile['officer_uid']?.toString();
  }

  // ── Apply cached / fresh context map to drawer display state ──────────────
  void _applyContext(Map<String, dynamic> ctx) {
    _currentSiteName =
    (ctx['site_name'] as String?)?.isNotEmpty == true
        ? ctx['site_name'] as String
        : 'No site assigned';
    _currentSiteId = ctx['site_id'] as String?;
    _linkedOfficerUid = ctx['officer_uid'] as String?;
    _contractorsList =
        (ctx['contractors'] as List<dynamic>?)?.cast<String>() ?? [];
    _safetyOfficersList =
        (ctx['safety_officers'] as List<dynamic>?)?.cast<String>() ?? [];
  }

  // ── Silent Supabase refresh — never blocks the UI ─────────────────────────
  Future<void> _refreshFromSupabase(String userId) async {
    try {
      // Fetch worker profile
      final profile = await supabase
          .from('workers')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (profile == null) {
        // No profile row yet — just stop loading spinner if still showing
        if (mounted) setState(() => loading = false);
        return;
      }

      // Persist fresh profile to cache
      await _authRepository.saveWorkerProfile(Map<String, dynamic>.from(profile));

      // Update in-memory state
      _applyProfile(profile);

      // Fetch context data (site, contractor, HSE) in parallel
      final siteId = profile['current_site_id']?.toString();
      final officerUid = profile['officer_uid']?.toString();

      String fetchedSiteName = 'No site assigned';
      List<String> fetchedContractors = [];
      List<String> fetchedSafetyOfficers = [];

      if (siteId != null) {
        // Build futures separately so Dart can infer types correctly
        final Future<Map<String, dynamic>?> siteFuture = supabase
            .from('sites')
            .select('name')
            .eq('id', siteId)
            .maybeSingle();

        final Future<Map<String, dynamic>?> contractorFuture = officerUid != null
            ? supabase
            .from('officers')
            .select('first_name, last_name')
            .eq('officer_uid', officerUid)
            .maybeSingle()
            : Future.value(null);

        final Future<List<dynamic>> hseFuture = officerUid != null
            ? supabase
            .from('hse_workers')
            .select('first_name, last_name')
            .eq('officer_uid', officerUid)
            .eq('current_site_id', siteId)
            : Future.value(<dynamic>[]);

        final results = await Future.wait([
          siteFuture,
          contractorFuture,
          hseFuture,
        ]);

        final siteData = results[0] as Map<String, dynamic>?;
        final officerData = results[1] as Map<String, dynamic>?;
        final hseDataList = results[2] as List<dynamic>? ?? [];

        if (siteData != null) {
          fetchedSiteName = _capitalize(siteData['name'] as String? ?? '');
        }

        if (officerData != null) {
          fetchedContractors = [
            _capitalize(
                '${officerData['first_name']} ${officerData['last_name']}')
          ];
        }

        fetchedSafetyOfficers = hseDataList
            .map((hse) =>
            _capitalize('${hse['first_name']} ${hse['last_name']}'))
            .toList();
      }

      // Persist fresh context to cache
      await _authRepository.saveWorkerContext(
        siteId: siteId,
        siteName: fetchedSiteName,
        officerUid: officerUid,
        contractors: fetchedContractors,
        safetyOfficers: fetchedSafetyOfficers,
      );

      // Update drawer display state
      if (mounted) {
        setState(() {
          _currentSiteName = fetchedSiteName;
          _contractorsList = fetchedContractors;
          _safetyOfficersList = fetchedSafetyOfficers;
          loading = false; // Covers the case where there was no cache at all
        });
      }
    } on SocketException {
      // Offline — cached data already painted, nothing to do
      debugPrint('ℹ️ [WorkerHome] Offline — showing cached data.');
      if (mounted) setState(() => loading = false);
    } catch (e) {
      // Any other error — log, don't crash, cached data stays visible
      debugPrint('⚠️ [WorkerHome] Supabase refresh failed: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOCATION TRACKING — fire and forget, offline-safe
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _startLocationTracking() async {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 20),
    ).listen((pos) {
      if (_currentWorkerId != null) {
        // Best-effort upsert — silently swallowed if offline
        supabase.from('user_locations').upsert({
          'user_id': _currentWorkerId,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id').catchError((e) {
          debugPrint('ℹ️ [Location] Offline upsert skipped: $e');
        });
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SOS NAVIGATION
  // ══════════════════════════════════════════════════════════════════════════

  void _navigateToSOS() {
    if (_currentSiteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("No site assigned."),
          backgroundColor: Colors.orange));
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => SharedEmergencySOSScreen(
              linkedContractorId: _linkedOfficerUid,
              currentSiteId: _currentSiteId,
              isWorker: true,
            )));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DRAWER
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildWorkerDrawer() {
    return Drawer(
      backgroundColor: _brandTeal,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 60, 24, 20),
                  color: const Color(0xFF142E2E),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 38,
                        backgroundColor: Colors.purple.shade200,
                        backgroundImage: _profileImageUrl.isNotEmpty
                            ? CachedNetworkImageProvider(_profileImageUrl)
                            : null,
                        child: _profileImageUrl.isEmpty
                            ? Text(_firstNameInitial,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.black))
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(_fullName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(_workType,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("CURRENT SITE CONTEXT",
                          style: TextStyle(
                              color: _accentGold,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1)),
                      const SizedBox(height: 20),
                      _buildContextGroup(
                          icon: Icons.business_center,
                          label: "Contractor",
                          names: _contractorsList,
                          emptyMsg: "No contractor linked"),
                      const SizedBox(height: 16),
                      _drawerInfoTile(
                          Icons.location_city, "Site Name", _currentSiteName),
                      const SizedBox(height: 16),
                      _buildContextGroup(
                          icon: Icons.security,
                          label: "Safety Inspector",
                          names: _safetyOfficersList,
                          emptyMsg: "No inspector on site"),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10),
                _drawerTile(Icons.account_circle_outlined, "Profile Details",
                        () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const WorkerEditProfileScreen()));
                    }),
                _drawerTile(Icons.settings_outlined, "Settings", () {
                  Navigator.pop(context);
                  _onItemTapped(4);
                }),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Text("RiskRadar v1.1.0",
                style: TextStyle(color: Colors.white24, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildContextGroup(
      {required IconData icon,
        required String label,
        required List<String> names,
        required String emptyMsg}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: _accentGold),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(height: 2),
              if (names.isEmpty)
                Text(emptyMsg,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white))
              else
                ...names.map((name) => Padding(
                  padding: const EdgeInsets.only(bottom: 2.0),
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _drawerTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white)),
      onTap: onTap,
    );
  }

  Widget _drawerInfoTile(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _accentGold),
        const SizedBox(width: 15),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9, color: Colors.white.withValues(alpha: 0.5))),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ]),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DASHBOARD BODY
  // ══════════════════════════════════════════════════════════════════════════

  Widget _dashboardBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer(
      builder: (context, ref, child) {
        final activeHazardCount = ref.watch(hazardProvider).when(
              data: (hazards) => hazards.length,
              error: (error, stackTrace) => 0,
              loading: () => 0,
            );

        return RefreshIndicator(
          onRefresh: () async {
            final userId = supabase.auth.currentUser?.id;
            if (userId != null) await _refreshFromSupabase(userId);
          },
          color: _brandTeal,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Stay safe and",
                    style: TextStyle(
                        fontSize: 22,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600)),
                const Text("remain Vigilant",
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: _accentGold)),
                const SizedBox(height: 25),
                Row(
                  children: [
                    Expanded(
                      child: _buildDashboardCard(
                        title: "AI Scanner",
                        subtitle: "Detect hazards instantly",
                        icon: Icons.auto_awesome,
                        buttonText: "Scan Now",
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const HazardScreen())),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDashboardCard(
                        title: "Hazards",
                        subtitle: "$activeHazardCount active risks",
                        icon: Icons.warning_rounded,
                        buttonText: "View",
                        onTap: () => _onItemTapped(1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _brandTeal,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: Colors.white70, size: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style:
                  const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGold,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.zero,
                elevation: 0,
              ),
              child: Text(buttonText,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
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
    if (loading) return const Scaffold(body: RiskRadarLoader(size: 50));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
    isDark ? const Color(0xFF121212) : Colors.grey.shade50;

    final screens = [
      _dashboardBody(),
      const WorkerOngoingHazardsScreen(),
      Container(),
      const WorkerResolvedHazardsScreen(),
      WorkerAppSettingsScreen(
        onAboutTap: (ctx) => Navigator.push(
            ctx,
            MaterialPageRoute(
                builder: (_) => const AboutAppScreen())),
        onProfileTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const WorkerEditProfileScreen())),
        onThemeChanged: widget.onThemeChanged,
        currentThemeMode: widget.currentThemeMode,
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildWorkerDrawer(),
      backgroundColor: backgroundColor,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: _brandTeal,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(_screenTitles[_selectedIndex],
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        leading: _selectedIndex == 0
            ? GestureDetector(
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.purple.shade200,
                shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(_firstNameInitial,
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
        )
            : IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          const RealtimeConnectionIndicator(),
          Consumer(
            builder: (context, ref, _) {
              final count = ref.watch(notificationCountProvider).when(
                    data: (value) => value,
                    error: (error, stackTrace) => 0,
                    loading: () => 0,
                  );
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded,
                        color: Colors.white, size: 28),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                            const WorkerNotificationScreen())),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _brandTeal, width: 1.5)),
                        constraints: const BoxConstraints(
                            minWidth: 18, minHeight: 18),
                        child: Center(
                            child: Text('$count',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold))),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: screens[_selectedIndex]),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? Padding(
        padding: const EdgeInsets.only(bottom: 90.0),
        child: FloatingActionButton.extended(
          backgroundColor: Colors.red.shade600,
          onPressed: _navigateToSOS,
          elevation: 4,
          icon: const Icon(Icons.sos_rounded, color: Colors.white),
          label: const Text("EMERGENCY",
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildConcaveNavBar(),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BOTTOM NAV BAR
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildConcaveNavBar() {
    return SizedBox(
      height: 85,
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
                      itemsCount: 5,
                      color: _brandTeal),
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
                _buildNavItem(1, Icons.warning_rounded, "Hazards"),
                _buildNavItem(2, Icons.add_circle, "Report"),
                _buildNavItem(3, Icons.check_circle_rounded, "Resolved"),
                _buildNavItem(4, Icons.settings_rounded, "Settings"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final bool isSelected = _selectedIndex == index;
    final bool isReportButton = index == 2;

    return GestureDetector(
      onTap: () {
        if (index == 2) {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const WorkerReportHazardScreen()));
        } else {
          _onItemTapped(index);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        height: 85,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              top: isSelected ? 0 : 20,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isSelected ? _accentGold : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? Colors.white
                      : (isReportButton
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.5)),
                  size: 26,
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              child: Text(label,
                  style: TextStyle(
                      color: isSelected
                          ? _accentGold
                          : (isReportButton
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.7)),
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal)),
            )
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CONCAVE NAV PAINTER — unchanged
// ══════════════════════════════════════════════════════════════════════════════

class ConcaveNavPainter extends CustomPainter {
  final double selectedIndex;
  final int itemsCount;
  final Color color;

  ConcaveNavPainter(
      {required this.selectedIndex,
        required this.itemsCount,
        required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    Path path = Path();
    double barHeight = 65.0;
    double topOffset = size.height - barHeight;
    double sectionWidth = size.width / itemsCount;
    double currentCenter =
        (selectedIndex * sectionWidth) + (sectionWidth / 2);
    double notchRadius = 38.0;
    path.moveTo(0, topOffset);
    path.lineTo(currentCenter - notchRadius - 5, topOffset);
    path.cubicTo(
        currentCenter - notchRadius,
        topOffset,
        currentCenter - notchRadius + 5,
        topOffset + 40,
        currentCenter,
        topOffset + 40);
    path.cubicTo(
        currentCenter + notchRadius - 5,
        topOffset + 40,
        currentCenter + notchRadius,
        topOffset,
        currentCenter + notchRadius + 5,
        topOffset);
    path.lineTo(size.width, topOffset);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ConcaveNavPainter oldDelegate) =>
      oldDelegate.selectedIndex != selectedIndex;
}
