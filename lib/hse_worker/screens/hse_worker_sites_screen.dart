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
          await _authRepository.saveHseProfile({
            ...currentProfile,
            ...worker,
          });
        }

        if (mounted) setState(() {});
      }
    } on SocketException {
      debugPrint("HSE sites offline - using cached data.");
    } catch (e) {
      debugPrint("Error fetching sites: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sites: $e'), backgroundColor: Colors.red),
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

    // ✅ Themed Confirmation Dialog (Dark Teal Gradient)
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.brandTeal,
                AppColors.brandTeal.withValues(alpha: 0.85),
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
                child: const Icon(Icons.swap_horiz_rounded,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'Change Site?',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to switch your active location to this site?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.85)),
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
                      foregroundColor: AppColors.brandTeal,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: const Text('Confirm',
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

    if (confirm != true) return;

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final payload = {'current_site_id': _selectedSite};

      await supabase.from('hse_workers').update(payload).eq('id', userId);

      await _applyCurrentSiteLocally(_selectedSite!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Current site updated successfully'), backgroundColor: Colors.green),
        );
      }
    } on SocketException {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null && _selectedSite != null) {
        await _syncRepository.enqueueAction(
          id: 'hse_site_${userId}_${DateTime.now().millisecondsSinceEpoch}',
          table: 'hse_workers',
          action: 'update',
          payload: {
            'id': userId,
            'current_site_id': _selectedSite,
          },
        );
        await _applyCurrentSiteLocally(_selectedSite!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved offline - site change will sync when online'), backgroundColor: Colors.orange),
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
            SnackBar(content: Text('Failed to update site: ${e.message}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update site: $e'), backgroundColor: Colors.red),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.transparent),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
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
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 48),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Active Hazards Found",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.brandTeal,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "You cannot change your active site while you still have assigned or in-progress hazards. Please resolve them first.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  child: const Text('Understood', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : AppColors.backgroundLight;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Sites', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                child: Text(
                  "Tap a site to switch your active location",
                  style: TextStyle(
                      color: subtitleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: _sites.isEmpty
                    ? const Center(child: Text('No sites assigned by your officer'))
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  itemCount: _sites.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
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
              left: 16,
              right: 16,
              bottom: 24,
              child: ElevatedButton(
                onPressed: _confirmSiteChange,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandTeal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  shadowColor: AppColors.brandTeal.withValues(alpha: 0.4),
                ),
                child: const Text('Confirm Change', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
    String buttonText = isCurrent ? "Active" : (isSelectedTemp ? "Confirm?" : "Select");

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.brandTeal,
          borderRadius: BorderRadius.circular(24),
          border: isSelectedTemp
              ? Border.all(color: AppColors.accentGold, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.business_rounded, color: Colors.white.withValues(alpha: 0.9), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        siteName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (siteDesc != null && siteDesc.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            siteDesc,
                            style: TextStyle(
                              fontSize: 13,
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
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.accentGold,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                buttonText,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
