// lib/hse_workers/screens/hse_worker_sites_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for HapticFeedback
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/shared/theme/app_colors.dart'; // Ensure correct import

class HSEWorkerSitesScreen extends StatefulWidget {
  const HSEWorkerSitesScreen({super.key});

  @override
  State<HSEWorkerSitesScreen> createState() => _HSEWorkerSitesScreenState();
}

class _HSEWorkerSitesScreenState extends State<HSEWorkerSitesScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final AuthRepository _authRepository = AuthRepository();
  final HazardRepository _hazardRepository = HazardRepository();
  final SyncRepository _syncRepository = SyncRepository();

  bool _loading = true;
  List<Map<String, dynamic>> _sites = [];
  String _currentSite = "";
  String? _selectedSite;

  @override
  void initState() {
    super.initState();
    _loadSitesCacheFirst();
  }

  Future<void> _loadSitesCacheFirst() async {
    final cachedProfile = _authRepository.getHseProfile();
    final cachedSites = await _hazardRepository.getHseSiteHazards();

    if (cachedProfile != null) {
      _currentSite = cachedProfile['current_site_id']?.toString() ?? "";
    }
    if (cachedSites != null) {
      _sites = cachedSites;
      setState(() => _loading = false);
    } else {
      setState(() => _loading = true);
    }

    await _fetchSites(showBlockingLoader: cachedSites == null);
  }

  Future<void> _fetchSites({bool showBlockingLoader = true}) async {
    if (showBlockingLoader) setState(() => _loading = true);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final worker = await supabase
          .from('hse_workers')
          .select('officer_uid, current_site_id')
          .eq('id', userId)
          .maybeSingle();

      final officerUid = worker?['officer_uid'];
      _currentSite = worker?['current_site_id']?.toString() ?? "";

      if (officerUid != null) {
        final sitesResponse = await supabase
            .from('sites')
            .select()
            .eq('officer_uid', officerUid);

        _sites = List<Map<String, dynamic>>.from(sitesResponse as List? ?? []);
        await _hazardRepository.saveHseSiteHazards(_sites);

        final currentProfile = _authRepository.getHseProfile();
        if (currentProfile != null && worker != null) {
          await _authRepository.saveHseProfile({...currentProfile, ...worker});
        }

        if (mounted) setState(() {});
      }
    } on SocketException {
      debugPrint("HSE sites offline - using cached data.");
    } catch (e) {
      debugPrint("Error fetching sites: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load sites: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSiteTap(String siteId) {
    setState(() {
      _selectedSite = siteId;
    });
  }

  Future<void> _confirmSiteChange() async {
    if (_selectedSite == null || _selectedSite == _currentSite) return;
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;

    // ✅ Themed Confirmation Dialog (Dark Teal Gradient)
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width * 0.085,
          vertical: visibleHeight * 0.030,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size.width * 0.071),
        ),
        backgroundColor: Colors.transparent,
        elevation: size.width * 0.0,
        child: Container(
          padding: EdgeInsets.all(size.width * 0.048),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.brandTeal,
                AppColors.brandTeal.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(size.width * 0.071),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: size.width * 0.053,
                offset: Offset(size.width * 0.0, visibleHeight * 0.013),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(size.width * 0.032),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.white,
                  size: size.width * 0.080,
                ),
              ),
              SizedBox(height: visibleHeight * 0.018),
              Text(
                'Change Site?',
                style: TextStyle(
                  fontSize: size.width * 0.050,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: visibleHeight * 0.010),
              Text(
                'Are you sure you want to switch your active location to this site?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: size.width * 0.035,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              SizedBox(height: visibleHeight * 0.024),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: size.width * 0.038,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: size.width * 0.028),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.brandTeal,
                      padding: EdgeInsets.symmetric(
                        horizontal: size.width * 0.060,
                        vertical: visibleHeight * 0.010,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(size.width * 0.041),
                      ),
                      elevation: size.width * 0.011,
                    ),
                    child: Text(
                      'Confirm',
                      style: TextStyle(
                        fontSize: size.width * 0.038,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final payload = {'current_site_id': _selectedSite};

      await supabase.from('hse_workers').update(payload).eq('id', userId);

      await _applyCurrentSiteLocally(_selectedSite!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Current site updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on SocketException {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null && _selectedSite != null) {
        await _syncRepository.enqueueAction(
          id: 'hse_site_${userId}_${DateTime.now().millisecondsSinceEpoch}',
          table: 'hse_workers',
          action: 'update',
          payload: {'id': userId, 'current_site_id': _selectedSite},
        );
        await _applyCurrentSiteLocally(_selectedSite!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved offline - site change will sync when online'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } on PostgrestException catch (e) {
      // ✅ CATCH ROW LEVEL SECURITY (RLS) ERRORS
      if (mounted) {
        if (e.code == '42501') {
          // Trigger the beautiful active hazards warning popup
          _showActiveHazardsErrorDialog(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update site: ${e.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update site: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _applyCurrentSiteLocally(String siteId) async {
    final currentProfile = _authRepository.getHseProfile();
    if (currentProfile != null) {
      await _authRepository.saveHseProfile({
        ...currentProfile,
        'current_site_id': siteId,
      });
    }
    if (mounted) {
      setState(() {
        _currentSite = siteId;
        _selectedSite = null;
      });
    }
  }

  // ✅ THE NEW ACTIVE HAZARDS WARNING DIALOG
  Future<void> _showActiveHazardsErrorDialog(BuildContext context) async {
    HapticFeedback.heavyImpact();
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width * 0.085,
          vertical: visibleHeight * 0.030,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size.width * 0.071),
        ),
        backgroundColor: Colors.transparent,
        elevation: size.width * 0.0,
        child: Container(
          padding: EdgeInsets.all(size.width * 0.048),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(size.width * 0.071),
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.transparent,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: size.width * 0.053,
                offset: Offset(size.width * 0.0, visibleHeight * 0.013),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(size.width * 0.032),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Container(
                  padding: EdgeInsets.all(size.width * 0.032),
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: size.width * 0.128,
                  ),
                ),
              ),
              SizedBox(height: visibleHeight * 0.022),
              Text(
                "Active Hazards Found",
                style: TextStyle(
                  fontSize: size.width * 0.050,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.brandTeal,
                ),
              ),
              SizedBox(height: visibleHeight * 0.010),
              Text(
                "You cannot change your active site while you still have assigned or in-progress hazards. Please resolve them first.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: size.width * 0.034,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              SizedBox(height: visibleHeight * 0.024),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandTeal,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: visibleHeight * 0.013,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(size.width * 0.041),
                    ),
                    elevation: size.width * 0.005,
                  ),
                  child: Text(
                    'Understood',
                    style: TextStyle(
                      fontSize: size.width * 0.038,
                      fontWeight: FontWeight.bold,
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

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF121212)
        : AppColors.backgroundLight;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Sites', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: visibleHeight * 0.012,
                        horizontal: size.width * 0.040,
                      ),
                      child: Text(
                        "Tap a site to switch your active location",
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: size.width * 0.033,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: _sites.isEmpty
                          ? Center(
                              child: Text('No sites assigned by your officer'),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.fromLTRB(
                                size.width * 0.040,
                                visibleHeight * 0.0,
                                size.width * 0.040,
                                visibleHeight * 0.095,
                              ),
                              itemCount: _sites.length,
                              separatorBuilder: (_, _) =>
                                  SizedBox(height: visibleHeight * 0.012),
                              itemBuilder: (context, index) {
                                final site = _sites[index];
                                final siteId = site['id'] ?? "";
                                final siteName = site['name'] ?? "Unnamed Site";
                                final siteDesc = site['description'];

                                final isCurrent = siteId == _currentSite;
                                final isSelectedTemp = siteId == _selectedSite;

                                return _buildDarkSiteCard(
                                  siteName: siteName,
                                  siteDesc: siteDesc,
                                  isCurrent: isCurrent,
                                  isSelectedTemp: isSelectedTemp,
                                  onTap: () => _onSiteTap(siteId),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                if (_selectedSite != null && _selectedSite != _currentSite)
                  Positioned(
                    left: size.width * 0.043,
                    right: size.width * 0.043,
                    bottom: visibleHeight * 0.030,
                    child: ElevatedButton(
                      onPressed: _confirmSiteChange,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandTeal,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: visibleHeight * 0.014,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            size.width * 0.041,
                          ),
                        ),
                        elevation: size.width * 0.021,
                        shadowColor: AppColors.brandTeal.withValues(alpha: 0.4),
                      ),
                      child: Text(
                        'Confirm Change',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: size.width * 0.038,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildDarkSiteCard({
    required String siteName,
    String? siteDesc,
    required bool isCurrent,
    required bool isSelectedTemp,
    required VoidCallback onTap,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    String buttonText = isCurrent
        ? "Active"
        : (isSelectedTemp ? "Confirm?" : "Select");

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(size.width * 0.038),
        decoration: BoxDecoration(
          color: AppColors.brandTeal,
          borderRadius: BorderRadius.circular(size.width * 0.052),
          border: isSelectedTemp
              ? Border.all(
                  color: AppColors.accentGold,
                  width: size.width * 0.005,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: size.width * 0.040,
              offset: Offset(size.width * 0.0, visibleHeight * 0.010),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.business_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: size.width * 0.064,
                ),
                SizedBox(width: size.width * 0.028),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        siteName,
                        style: TextStyle(
                          fontSize: size.width * 0.040,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (siteDesc != null && siteDesc.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: visibleHeight * 0.004),
                          child: Text(
                            siteDesc,
                            style: TextStyle(
                              fontSize: size.width * 0.030,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: visibleHeight * 0.016),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: visibleHeight * 0.010),
              decoration: BoxDecoration(
                color: AppColors.accentGold,
                borderRadius: BorderRadius.circular(size.width * 0.041),
              ),
              alignment: Alignment.center,
              child: Text(
                buttonText,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: size.width * 0.035,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
