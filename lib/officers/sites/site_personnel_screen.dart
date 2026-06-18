// lib/officers/sites/site_personnel_screen.dart
import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';

// Import your existing profile screen (Adjust the path if needed)
import 'package:riskradar/officers/labours/worker_profile_screen.dart';

class SitePersonnelScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const SitePersonnelScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<SitePersonnelScreen> createState() => _SitePersonnelScreenState();
}

class _SitePersonnelScreenState extends State<SitePersonnelScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _hseWorkers = [];

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
    _loadPersonnelCacheFirst();
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
        _filteredHseWorkers = List.from(_hseWorkers);
      } else {
        // Filter Workers
        _filteredWorkers = _workers.where((worker) {
          final firstName = worker['first_name'] ?? '';
          final lastName = worker['last_name'] ?? '';
          final workType = worker['work_type'] ?? 'Worker';

          final searchableString = "$firstName $lastName $workType"
              .toLowerCase();
          return searchableString.contains(query);
        }).toList();

        // Filter HSE Workers
        _filteredHseWorkers = _hseWorkers.where((worker) {
          final firstName = worker['first_name'] ?? '';
          final lastName = worker['last_name'] ?? '';
          final workType = worker['work_type'] ?? 'Safety Officer';

          final searchableString = "$firstName $lastName $workType"
              .toLowerCase();
          return searchableString.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadPersonnelCacheFirst() async {
    final cached = OfficerRepository.instance.getOfficerSitePersonnel(
      widget.siteId,
    );
    if (cached != null) {
      _workers = List<Map<String, dynamic>>.from(cached['workers'] ?? []);
      _hseWorkers = List<Map<String, dynamic>>.from(
        cached['hse_workers'] ?? [],
      );
      _filterLists();
      setState(() => _isLoading = false);
      _fadeController.forward();
    } else {
      setState(() => _isLoading = true);
    }

    await _loadPersonnelData(showBlockingLoader: cached == null);
  }

  Future<void> _loadPersonnelData({bool showBlockingLoader = true}) async {
    if (showBlockingLoader) setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // Fetch both Workers and HSE Workers for this specific site concurrently
      final responses = await Future.wait([
        supabase.from('workers').select().eq('current_site_id', widget.siteId),
        supabase
            .from('hse_workers')
            .select()
            .eq('current_site_id', widget.siteId),
      ]);

      if (!mounted) return;

      _workers = List<Map<String, dynamic>>.from(responses[0]);
      _hseWorkers = List<Map<String, dynamic>>.from(responses[1]);
      await OfficerRepository.instance.saveOfficerSitePersonnel(widget.siteId, {
        'workers': _workers,
        'hse_workers': _hseWorkers,
      });

      _filterLists();
      setState(() => _isLoading = false);
      _fadeController.forward();
    } on SocketException {
      debugPrint('Site personnel offline - using cached data.');
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading site personnel: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading personnel: $e')));
      }
    }
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

  // --- NEW: Helper method to visually highlight search terms ---
  Widget _buildHighlightedText(
    String text,
    String query,
    TextStyle defaultStyle,
  ) {
    if (query.isEmpty) {
      return Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: defaultStyle,
      );
    }

    final String lowerText = text.toLowerCase();
    final String lowerQuery = query.toLowerCase();
    final int matchIndex = lowerText.indexOf(lowerQuery);

    if (matchIndex == -1) {
      return Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: defaultStyle,
      );
    }

    // Chop the text and apply highlight styling to the matched segment
    return RichText(
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: defaultStyle,
        children: [
          TextSpan(text: text.substring(0, matchIndex)),
          TextSpan(
            text: text.substring(matchIndex, matchIndex + query.length),
            style: defaultStyle.copyWith(
              backgroundColor: Colors.yellow.withValues(alpha: 0.5),
              color: Colors.black, // Ensures contrast against yellow
            ),
          ),
          TextSpan(text: text.substring(matchIndex + query.length)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const tealColor = Color(0xFF1B3D3D);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF121212)
            : Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: tealColor,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                widget.siteName,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: R.blockH * 4.5,
                ),
              ),
              Text(
                "Site Workforce",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: R.blockH * 3,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'Workers'),
              Tab(
                icon: Icon(Icons.health_and_safety_rounded),
                text: 'Safety Officers',
              ),
            ],
          ),
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: tealColor))
            : Column(
                children: [
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      R.blockH * 5,
                      R.blockV * 1.25,
                      R.blockH * 5,
                      R.blockV * 2.5,
                    ),
                    decoration: const BoxDecoration(
                      color: tealColor,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search personnel...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        prefixIcon: Icon(Icons.search, color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          vertical: R.blockV * 0,
                          horizontal: R.blockH * 5,
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: TabBarView(
                        children: [
                          _buildPersonnelGrid(
                            _filteredWorkers,
                            'No workers assigned to this site',
                            'workers',
                          ),
                          _buildPersonnelGrid(
                            _filteredHseWorkers,
                            'No safety officers assigned to this site',
                            'hse_workers',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPersonnelGrid(
    List<Map<String, dynamic>> personnelList,
    String emptyMessage,
    String tableName,
  ) {
    if (personnelList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group_off_rounded,
              size: 60,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: R.blockV * 1.25),
            Text(
              emptyMessage,
              style: TextStyle(color: Colors.grey, fontSize: R.blockH * 4),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.all(R.blockH * 5),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.95,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: personnelList.length,
      itemBuilder: (context, index) {
        return _buildStylishMemberCard(personnelList[index], tableName);
      },
    );
  }

  Widget _buildStylishMemberCard(Map<String, dynamic> user, String tableName) {
    final firstName = user['first_name'] ?? '';
    final lastName = user['last_name'] ?? '';
    final name = _capitalize("$firstName $lastName");

    // Default designation logic
    String designation = user['work_type'] ?? '';
    if (designation.isEmpty) {
      designation = tableName == 'hse_workers' ? 'Safety Officer' : 'Worker';
    }

    final imageUrl = user['profile_image_url'];
    const tealColor = Color(0xFF1B3D3D);

    // Grab the current search query to pass into the highlighter
    final searchQuery = _searchController.text.trim();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                WorkerProfileScreen(worker: user, tableName: tableName),
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
              offset: Offset(0, 5),
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
                          colors: [tealColor, Color(0xFF2C5E5E)],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Container(
                      color: Colors.white,
                      width: double.infinity,
                      padding: EdgeInsets.only(
                        top: R.blockV * 4.75,
                        left: R.blockH * 1,
                        right: R.blockH * 1,
                        bottom: R.blockV * 0.625,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          // NEW: Using the custom highlighter for the Name
                          _buildHighlightedText(
                            name,
                            searchQuery,
                            TextStyle(
                              fontSize: R.blockH * 4,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 0),
                          // NEW: Using the custom highlighter for the Designation
                          _buildHighlightedText(
                            designation.toUpperCase(),
                            searchQuery,
                            TextStyle(
                              fontSize: R.blockH * 2.75,
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
                      border: Border.all(
                        color: Colors.white,
                        width: R.blockH * 1.067,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: imageUrl != null
                          ? CachedNetworkImageProvider(imageUrl)
                          : null,
                      child: imageUrl == null
                          ? Icon(Icons.person, size: 40, color: Colors.grey)
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
