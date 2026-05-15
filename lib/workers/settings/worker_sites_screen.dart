// lib/workers/screens/worker_sites_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/shared/theme/app_colors.dart';

class WorkerSitesScreen extends StatefulWidget {
  const WorkerSitesScreen({super.key});

  @override
  State<WorkerSitesScreen> createState() => _WorkerSitesScreenState();
}

class _WorkerSitesScreenState extends State<WorkerSitesScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _sites = [];
  String _currentSite = "";
  String? _selectedSite; // Temporary selection

  @override
  void initState() {
    super.initState();
    _fetchSites();
  }

  Future<void> _fetchSites() async {
    setState(() => _loading = true);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final worker = await supabase
          .from('workers')
          .select('officer_uid, current_site_id')
          .eq('id', userId)
          .maybeSingle();

      final officerUid = worker?['officer_uid'];
      _currentSite = worker?['current_site_id'] ?? "";

      if (officerUid != null) {
        final sitesResponse = await supabase
            .from('sites')
            .select()
            .eq('officer_uid', officerUid);

        setState(() {
          _sites =
          List<Map<String, dynamic>>.from(sitesResponse as List? ?? []);
        });
      }
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.transparent, // Transparent for gradient
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
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      setState(() => _loading = true);
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('workers').update({
        'current_site_id': _selectedSite,
      }).eq('id', userId);

      setState(() {
        _currentSite = _selectedSite!;
        _selectedSite = null;
        _loading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Current site updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
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

  @override
  Widget build(BuildContext context) {
    // Detect Dark Mode
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : AppColors.backgroundLight;
    final textColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Sites'),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Main Column Layout
          Column(
            children: [
              // 1. Subtitle Text
              Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                child: Text(
                  "Tap a site to switch your active location",
                  style: TextStyle(
                      color: textColor, // Updates based on theme
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
              ),

              // 2. List of Sites (New Dark Card Style)
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _sites.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  itemCount: _sites.length,
                  separatorBuilder: (_, _) =>
                  const SizedBox(height: 16),
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

          // 3. Floating Confirm Button (Bottom Center)
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
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  shadowColor: AppColors.brandTeal.withValues(alpha: 0.4),
                ),
                child: const Text(
                  'Confirm Change',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  // UPDATED: Dark Card Style with Gold Action Button
  Widget _buildDarkSiteCard({
    required String siteName,
    String? siteDesc,
    required bool isCurrent,
    required bool isSelectedTemp,
    required VoidCallback onTap,
  }) {
    // Label for the button
    String buttonText = "Select";
    if (isCurrent) buttonText = "Active";
    if (isSelectedTemp) buttonText = "Confirm?";

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          // Always Dark Brand Teal Background
          color: AppColors.brandTeal,
          borderRadius: BorderRadius.circular(24),
          border: isSelectedTemp
              ? Border.all(color: AppColors.accentGold, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2), // Darker shadow for dark mode
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Icon + Title info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Icon(Icons.business_rounded, color: Colors.white.withValues(alpha: 0.9), size: 28),
                const SizedBox(width: 12),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        siteName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white, // White text
                        ),
                      ),
                      if (siteDesc != null && siteDesc.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            siteDesc,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.7), // Grey/White text
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

            // Bottom: Gold Action Button (Visual only, whole card taps)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.accentGold, // Gold/Orange Button
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.domain_disabled_rounded,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No sites assigned.',
            style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please contact your officer.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
