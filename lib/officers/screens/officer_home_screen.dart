// lib/officers/screens/officer_home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/services/providers/hazard_provider.dart';
import 'package:riskradar/services/providers/notification_count_provider.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';

// Screens
import 'package:riskradar/officers/screens/resolved_hazards_screen.dart';
import 'package:riskradar/officers/screens/active_task.dart';
import 'package:riskradar/officers/screens/team_overview.dart';
import 'package:riskradar/officers/sites/officer_sites_screen.dart';
import 'package:riskradar/officers/screens/officer_analytics_screen.dart'; // NEW SCREEN IMPORT
import 'package:riskradar/officers/screens/officer_hazard_map_screen.dart';
import '../settings/app_settings_screen.dart';
import '../../shared/settings/about_app_screen.dart';
import 'package:riskradar/shared/screens/shared_emergency_sos_screen.dart';
import 'package:riskradar/shared/widgets/offline_banner.dart';
import 'package:riskradar/shared/widgets/realtime_connection_indicator.dart';

import 'package:riskradar/officers/notifications/notification_screen.dart';

// BRAND COLORS
import 'package:riskradar/shared/theme/app_colors.dart';

class OfficerDashboardCache {
  static final OfficerDashboardCache _instance = OfficerDashboardCache._internal();
  factory OfficerDashboardCache() => _instance;
  OfficerDashboardCache._internal();

  int resolvedHazardCount = 0;
  int totalSitesCount = 0;
  String officerName = "Officer";
  String? officerProfileImageUrl;
  dynamic officerUid;
  bool isLoaded = false;
}

class OfficerHomeScreen extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final void Function(ThemeMode) onThemeChanged;

  const OfficerHomeScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeChanged,
  });

  @override
  State<OfficerHomeScreen> createState() => _OfficerHomeScreenState();
}

class _OfficerHomeScreenState extends State<OfficerHomeScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late AnimationController _animationController;
  late Animation<double> _curveAnimation;

  bool isLoading = true;
  int _selectedIndex = 0;
  final cache = OfficerDashboardCache();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300)
    );
    _curveAnimation = Tween<double>(begin: 0, end: 0).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut)
    );
    _loadDashboardCacheFirst();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
    _curveAnimation = Tween<double>(begin: _curveAnimation.value, end: index.toDouble())
        .animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _animationController.forward(from: 0);
  }

  Future<void> _loadDashboardCacheFirst() async {
    final cached = OfficerRepository.instance.getOfficerDashboard();
    if (cached != null) {
      cache.officerName = cached['officer_name'] ?? "Officer";
      cache.officerProfileImageUrl = cached['profile_image_url'];
      cache.officerUid = cached['officer_uid'];
      cache.resolvedHazardCount = cached['resolved_hazard_count'] ?? 0;
      cache.totalSitesCount = cached['total_sites_count'] ?? 0;
      cache.isLoaded = true;
      if (mounted) setState(() => isLoading = false);
    }

    await _fetchData(showBlockingLoader: cached == null);
  }

  Future<void> _fetchData({bool showBlockingLoader = true}) async {
    final isInitialLoad = !cache.isLoaded;
    if (isInitialLoad && showBlockingLoader && mounted) {
      setState(() => isLoading = true);
    }

    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      if (mounted) Navigator.pushReplacementNamed(context, '/');
      return;
    }

    try {
      final officerProfile = await supabase
          .from('officers')
          .select('first_name, last_name, profile_image_url, officer_uid')
          .eq('id', currentUserId)
          .maybeSingle();

      if (officerProfile != null) {
        cache.officerName =
            "${_capitalize(officerProfile['first_name'])} ${_capitalize(officerProfile['last_name'])}"
                .trim();
        cache.officerProfileImageUrl = officerProfile['profile_image_url'];
        cache.officerUid = officerProfile['officer_uid'];

        if (cache.officerUid != null) {
          final results = await Future.wait([
            fetchResolvedHazardsCount(cache.officerUid),
            fetchTotalSitesCount(cache.officerUid),
          ]);

          cache.resolvedHazardCount = results[0];
          cache.totalSitesCount = results[1];
        }
      }
      cache.isLoaded = true;
      await OfficerRepository.instance.saveOfficerDashboard({
        'officer_name': cache.officerName,
        'profile_image_url': cache.officerProfileImageUrl,
        'officer_uid': cache.officerUid,
        'resolved_hazard_count': cache.resolvedHazardCount,
        'total_sites_count': cache.totalSitesCount,
      });
    } on SocketException {
      debugPrint('Officer dashboard offline - using cached data.');
    } catch (e) {
      debugPrint('Error in _fetchData: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _capitalize(String? s) {
    if (s == null || s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  void _onAboutTap(BuildContext context) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const AboutAppScreen()));
  }

  void _onProfileTap() {
    Navigator.of(context).pushNamed('/officer-view-profile');
  }

  Future<int> fetchResolvedHazardsCount(dynamic officerUid) async {
    try {
      final response = await supabase.from('resolved_hazards').select().eq('officer_uid', officerUid).count();
      return response.count;
    } catch (e) { return 0; }
  }

  Future<int> fetchTotalSitesCount(dynamic officerUid) async {
    try {
      final response = await supabase.from('sites').select().eq('officer_uid', officerUid).count();
      return response.count;
    } catch (e) { return 0; }
  }

  void _navigateToSOS() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SharedEmergencySOSScreen(
          currentSiteId: null,
          linkedContractorId: supabase.auth.currentUser!.id,
          isWorker: false,
        ),
      ),
    );
  }

  // --- UI BUILDERS ---

  Widget _buildOfficerDrawer() {
    return Drawer(
      backgroundColor: AppColors.brandTeal,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF142E2E)),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: cache.officerProfileImageUrl != null ? NetworkImage(cache.officerProfileImageUrl!) : null,
              child: cache.officerProfileImageUrl == null
                  ? Text(cache.officerName.isNotEmpty ? cache.officerName[0].toUpperCase() : "O",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.brandTeal))
                  : null,
            ),
            accountName: Text(cache.officerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            accountEmail: Text("UID: ${cache.officerUid ?? '-'}", style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("OFFICER CONTEXT", style: TextStyle(color: AppColors.accentGold.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                const SizedBox(height: 15),
                _drawerInfoTile(Icons.business_rounded, "Total Sites", "${cache.totalSitesCount} Sites"),
                _drawerInfoTile(Icons.security, "Role", "Contractor"),
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          _drawerTile(Icons.account_circle_outlined, "Profile Details", () {
            Navigator.pop(context);
            _onProfileTap();
          }),
          _drawerTile(Icons.settings_outlined, "Settings", () {
            Navigator.pop(context);
            _onItemTapped(4);
          }),
          const Spacer(),
          const Padding(padding: EdgeInsets.all(16.0), child: Text("RiskRadar v1.0.2", style: TextStyle(color: Colors.white24, fontSize: 11))),
        ],
      ),
    );
  }

  Widget _drawerTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
      onTap: onTap,
    );
  }

  Widget _drawerInfoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accentGold),
          const SizedBox(width: 15),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5))),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ],
      ),
    );
  }

  Widget _dashboardBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer(
      builder: (context, ref, child) {
        final hazardState = ref.watch(hazardProvider);
        final activeHazardCount = hazardState.when(
          data: (hazards) => hazards.length,
          error: (error, stackTrace) => 0,
          loading: () => 0,
        );

        return RefreshIndicator(
          onRefresh: _fetchData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Let's manage",
                  style: TextStyle(
                    fontSize: 22,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const Text(
                  "Site Safety",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentGold,
                  ),
                ),
                const SizedBox(height: 25),

                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        title: "System\nAnalytics",
                        count: "Logs",
                        icon: Icons.insights_rounded,
                        color: const Color(0xFF2563EB),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OfficerAnalyticsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        title: "Resolved\nHazards",
                        count: cache.resolvedHazardCount.toString(),
                        icon: Icons.verified_user_rounded,
                        color: const Color(0xFF10B981),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ResolvedHazardsScreen(),
                            ),
                          );
                          if (mounted) {
                            _fetchData();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        title: "View All\nHazards",
                        count: activeHazardCount.toString(),
                        icon: Icons.map_rounded,
                        color: const Color(0xFF22D3EE),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OfficerHazardMapScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required VoidCallback onTap
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 180,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.brandTeal,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 28), // Updated icon color to use passed variable slightly
                const Icon(Icons.arrow_forward, color: Colors.white24, size: 20),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    count,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)
                ),
                const SizedBox(height: 4),
                Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: Colors.white54, height: 1.2)
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  List<Widget> get _screens => [
    _dashboardBody(),
    const WorkersListScreen(),
    const OfficerSitesScreen(),
    const ViewAssignedHazardsScreen(),
    AppSettingsScreen(
      onAboutTap: _onAboutTap,
      onThemeChanged: widget.onThemeChanged,
      currentThemeMode: widget.currentThemeMode,
      onProfileTap: _onProfileTap,
    ),
  ];

  final List<String> _titles = [
    'Dashboard',
    'Team',
    'Sites',
    'Active Tasks',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (isLoading) {
      return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: const Center(child: CircularProgressIndicator(color: AppColors.brandTeal))
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, dynamic result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          _onItemTapped(0);
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildOfficerDrawer(),
        backgroundColor: backgroundColor,
        extendBody: true,
        resizeToAvoidBottomInset: false,

        appBar: AppBar(
          title: Text(_titles[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: AppColors.brandTeal,
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          iconTheme: const IconThemeData(color: Colors.white),

          leading: (_selectedIndex == 0)
              ? GestureDetector(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: CircleAvatar(
                      backgroundColor: Colors.white,
                      backgroundImage: cache.officerProfileImageUrl != null ? NetworkImage(cache.officerProfileImageUrl!) : null,
                      child: cache.officerProfileImageUrl == null
                          ? Text(cache.officerName.isNotEmpty ? cache.officerName[0].toUpperCase() : "O", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandTeal))
                          : null
                  )
              )
          )
              : null,

          actions: [
            const RealtimeConnectionIndicator(),
            Consumer(
              builder: (context, ref, child) {
                final count = ref.watch(notificationCountProvider).when(
                      data: (value) => value,
                      error: (error, stackTrace) => 0,
                      loading: () => 0,
                    );
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 28),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const NotificationScreen(),
                          ),
                        );
                      },
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
                            border: Border.all(color: AppColors.brandTeal, width: 1.5),
                          ),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            '$count',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
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
            Expanded(
              child: IndexedStack(index: _selectedIndex, children: _screens),
            ),
          ],
        ),

        floatingActionButton: _selectedIndex == 0 ? Padding(
          padding: const EdgeInsets.only(bottom: 90.0),
          child: FloatingActionButton.extended(
            backgroundColor: Colors.red.shade600,
            onPressed: _navigateToSOS,
            elevation: 4,
            icon: const Icon(Icons.sos_rounded, color: Colors.white),
            label: const Text("EMERGENCY", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ) : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

        bottomNavigationBar: _buildConcaveNavBar(),
      ),
    );
  }

  Widget _buildConcaveNavBar() {
    return SizedBox(
      height: 85,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: AnimatedBuilder(
              animation: _curveAnimation,
              builder: (context, child) {
                return CustomPaint(
                  size: Size(MediaQuery.of(context).size.width, 85),
                  painter: ConcaveNavPainter(
                      selectedIndex: _curveAnimation.value,
                      itemsCount: 5,
                      color: AppColors.brandTeal
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
                _buildNavItem(1, Icons.group_rounded, "Team"),
                _buildNavItem(2, Icons.business_rounded, "Sites"),
                _buildNavItem(3, Icons.task_alt_rounded, "Tasks"),
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
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 65, height: 85,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              top: isSelected ? 0 : 20,
              child: Container(
                width: 45, height: 45,
                decoration: BoxDecoration(color: isSelected ? AppColors.accentGold : Colors.transparent, shape: BoxShape.circle),
                child: Icon(icon, color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.5), size: 22),
              ),
            ),
            Positioned(
              bottom: 12,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: 1.0,
                child: Text(label, style: TextStyle(color: isSelected ? AppColors.accentGold : Colors.white70, fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class ConcaveNavPainter extends CustomPainter {
  final double selectedIndex;
  final int itemsCount;
  final Color color;
  ConcaveNavPainter({required this.selectedIndex, required this.itemsCount, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()..color = color..style = PaintingStyle.fill;
    Path path = Path();
    double barHeight = 65.0;
    double topOffset = size.height - barHeight;
    double sectionWidth = size.width / itemsCount;
    double currentCenter = (selectedIndex * sectionWidth) + (sectionWidth / 2);
    double notchRadius = 38.0;
    path.moveTo(0, topOffset);
    path.lineTo(currentCenter - notchRadius - 5, topOffset);
    path.cubicTo(currentCenter - notchRadius, topOffset, currentCenter - notchRadius + 5, topOffset + 40, currentCenter, topOffset + 40);
    path.cubicTo(currentCenter + notchRadius - 5, topOffset + 40, currentCenter + notchRadius, topOffset, currentCenter + notchRadius + 5, topOffset);
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

