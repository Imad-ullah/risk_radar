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
          _sites = List<Map<String, dynamic>>.from(
            sitesResponse as List? ?? [],
          );
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
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);
        final size = mediaQuery.size;
        final visibleHeight =
            size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
        return Dialog(
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
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.050,
                          vertical: visibleHeight * 0.010,
                        ),
                        foregroundColor: Colors.white,
                      ),
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
                          borderRadius: BorderRadius.circular(
                            size.width * 0.041,
                          ),
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
        );
      },
    );

    if (confirm != true) return;

    try {
      setState(() => _loading = true);
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase
          .from('workers')
          .update({'current_site_id': _selectedSite})
          .eq('id', userId);

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
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    // Detect Dark Mode
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF121212)
        : AppColors.backgroundLight;
    final textColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Sites'),
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
                padding: EdgeInsets.symmetric(
                  vertical: visibleHeight * 0.012,
                  horizontal: size.width * 0.040,
                ),
                child: Text(
                  "Tap a site to switch your active location",
                  style: TextStyle(
                    color: textColor, // Updates based on theme
                    fontSize: size.width * 0.033,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // 2. List of Sites (New Dark Card Style)
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator())
                    : _sites.isEmpty
                    ? _buildEmptyState()
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

          // 3. Floating Confirm Button (Bottom Center)
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
                  padding: EdgeInsets.symmetric(vertical: visibleHeight * 0.014),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(size.width * 0.041),
                  ),
                  elevation: size.width * 0.021,
                  shadowColor: AppColors.brandTeal.withValues(alpha: 0.4),
                ),
                child: Text(
                  'Confirm Change',
                  style: TextStyle(
                    fontSize: size.width * 0.038,
                    fontWeight: FontWeight.bold,
                  ),
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
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    // Label for the button
    String buttonText = "Select";
    if (isCurrent) buttonText = "Active";
    if (isSelectedTemp) buttonText = "Confirm?";

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(size.width * 0.038),
        decoration: BoxDecoration(
          // Always Dark Brand Teal Background
          color: AppColors.brandTeal,
          borderRadius: BorderRadius.circular(size.width * 0.052),
          border: isSelectedTemp
              ? Border.all(color: AppColors.accentGold, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: 0.2,
              ), // Darker shadow for dark mode
              blurRadius: size.width * 0.040,
              offset: Offset(size.width * 0.0, visibleHeight * 0.010),
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
                Icon(
                  Icons.business_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: size.width * 0.064,
                ),
                SizedBox(width: size.width * 0.028),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        siteName,
                        style: TextStyle(
                          fontSize: size.width * 0.040,
                          fontWeight: FontWeight.bold,
                          color: Colors.white, // White text
                        ),
                      ),
                      if (siteDesc != null && siteDesc.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: visibleHeight * 0.004),
                          child: Text(
                            siteDesc,
                            style: TextStyle(
                              fontSize: size.width * 0.030,
                              color: Colors.white.withValues(
                                alpha: 0.7,
                              ), // Grey/White text
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

            // Bottom: Gold Action Button (Visual only, whole card taps)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: visibleHeight * 0.010),
              decoration: BoxDecoration(
                color: AppColors.accentGold, // Gold/Orange Button
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

  Widget _buildEmptyState() {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.domain_disabled_rounded,
            size: size.width * 0.150,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: visibleHeight * 0.014),
          Text(
            'No sites assigned.',
            style: TextStyle(
              fontSize: size.width * 0.040,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: visibleHeight * 0.006),
          Text(
            'Please contact your officer.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
