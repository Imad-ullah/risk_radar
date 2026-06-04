import 'package:flutter/material.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/repositories/hse_repository.dart';
import '../../officers/labours/worker_profile_screen.dart';

class HSETeamMembersScreen extends StatefulWidget {
  // ✅ Added the currentSiteId parameter
  final String? currentSiteId;

  const HSETeamMembersScreen({
    super.key,
    this.currentSiteId, // ✅ Accept the site ID from the Home Screen
  });

  @override
  State<HSETeamMembersScreen> createState() => _HSETeamMembersScreenState();
}

class _HSETeamMembersScreenState extends State<HSETeamMembersScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  bool loading = true;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  List<Map<String, dynamic>> _workers = [];
  String? _currentSiteId;
  bool _mustRegisterToSite = false;

  static const String _registerToSiteMessage =
      'Please register to a site first to view workers.';

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredWorkers = [];

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
    _currentSiteId = widget.currentSiteId;
    _loadTeamDataCacheFirst();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filterLists() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredWorkers = List.from(_workers);
      } else {
        _filteredWorkers = _workers.where((worker) {
          final fullName = "${worker['first_name']} ${worker['last_name']}".toLowerCase();
          return fullName.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadTeamDataCacheFirst() async {
    final cached = HseRepository.instance.getHseTeamMembers();
    if (cached != null &&
        _currentSiteId != null &&
        _currentSiteId!.isNotEmpty) {
      _workers = cached
          .where((worker) => worker['current_site_id']?.toString() == _currentSiteId)
          .toList();
      _filterLists();
      setState(() => loading = false);
      _fadeController.forward();
    } else {
      setState(() => loading = true);
    }

    await _loadTeamData(showBlockingLoader: cached == null);
  }

  Future<void> _loadTeamData({bool showBlockingLoader = true}) async {
    if (showBlockingLoader) setState(() => loading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
      final myProfile = await Supabase.instance.client
          .from('hse_workers')
          .select('officer_uid, current_site_id')
          .eq('id', userId)
          .maybeSingle();

      if (myProfile == null || myProfile['officer_uid'] == null) {
        setState(() => loading = false);
        return;
      }

      final officerUid = myProfile['officer_uid'];
      final siteId = myProfile['current_site_id']?.toString();

      if (siteId == null || siteId.isEmpty) {
        if (!mounted) return;
        _currentSiteId = null;
        _mustRegisterToSite = true;
        _workers = [];
        _filteredWorkers = [];
        await HseRepository.instance.saveHseTeamMembers(_workers);
        setState(() => loading = false);
        _fadeController.forward();
        return;
      }

      _currentSiteId = siteId;
      _mustRegisterToSite = false;

      // ✅ Base query: Get workers under the same contractor/officer
      var query = Supabase.instance.client
          .from('workers')
          .select('*, sites!workers_current_site_id_fkey(name)')
          .eq('officer_uid', officerUid)
          .eq('current_site_id', siteId);

      // ✅ Apply the filter if a specific site ID was passed!
      final response = await query;

      if (!mounted) return;

      _workers = List<Map<String, dynamic>>.from(response);
      await HseRepository.instance.saveHseTeamMembers(_workers);

      _filterLists();
      setState(() => loading = false);
      _fadeController.forward();
    } on SocketException {
      debugPrint('HSE team offline - using cached data.');
      if (mounted) setState(() => loading = false);
    } catch (e) {
      debugPrint('Error loading team: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  String _capitalize(String text) {
    if (text.isEmpty) return "";
    return text.split(' ').map((word) {
      if (word.isEmpty) return "";
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const tealColor = Color(0xFF1B3D3D);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: tealColor,
        title: const Text("Site Workforce", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: tealColor))
          : Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            decoration: const BoxDecoration(
              color: tealColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search workers...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
              ),
            ),
          ),

          Expanded(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _filteredWorkers.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.group_off_rounded, size: 60, color: Colors.grey.shade400),
                    const SizedBox(height: 10),
                    Text(
                      _mustRegisterToSite
                          ? _registerToSiteMessage
                          : "No workers found",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              )
                  : GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.95, // Kept this ratio
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _filteredWorkers.length,
                itemBuilder: (context, index) {
                  return _buildStylishMemberCard(_filteredWorkers[index], index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStylishMemberCard(Map<String, dynamic> user, int index) {
    final firstName = user['first_name'] ?? '';
    final lastName = user['last_name'] ?? '';
    final name = _capitalize("$firstName $lastName");
    final designation = user['work_type'] ?? 'Worker';
    final imageUrl = user['profile_image_url'];

    const tealColor = Color(0xFF1B3D3D);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WorkerProfileScreen(
              worker: user,
              tableName: 'workers',
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // 1. Background Layout
              Column(
                children: [
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            tealColor,
                            Color(0xFF2C5E5E),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Container(
                      color: Colors.white,
                      width: double.infinity,
                      padding: const EdgeInsets.only(top: 38, left: 4, right: 4, bottom: 5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 0),
                          Text(
                            designation.toUpperCase(),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: tealColor.withValues(alpha: 0.7),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // 2. Overlapping Avatar
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
                      child: imageUrl == null
                          ? const Icon(Icons.person, size: 40, color: Colors.grey)
                          : null,
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
}

