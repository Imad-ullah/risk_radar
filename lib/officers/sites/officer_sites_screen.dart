// lib/officers/sites/officer_sites_screen.dart
import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/officers/sites/site_personnel_screen.dart';
import 'package:riskradar/services/connectivity_service.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/shared/security/input_sanitizer.dart';
import 'package:riskradar/shared/theme/app_colors.dart';
import 'package:uuid/uuid.dart';

class OfficerSitesScreen extends StatefulWidget {
  const OfficerSitesScreen({super.key});

  @override
  State<OfficerSitesScreen> createState() => _OfficerSitesScreenState();
}

class _OfficerSitesScreenState extends State<OfficerSitesScreen> {
  final supabase = Supabase.instance.client;
  final SyncRepository _syncRepository = SyncRepository();
  late Future<List<Map<String, dynamic>>> _sitesFuture;
  int? _numericOfficerUid;

  @override
  void initState() {
    super.initState();
    _sitesFuture = Future.value(
      OfficerRepository.instance.getOfficerSites() ?? [],
    );
    _initializeAndFetchData();
  }

  Future<void> _initializeAndFetchData() async {
    await _fetchNumericOfficerUid();
    await _fetchSites();
  }

  Future<void> _fetchNumericOfficerUid() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('officers')
          .select('officer_uid')
          .eq('id', userId)
          .single();

      if (mounted) {
        _numericOfficerUid = response['officer_uid'];
      }
    } catch (e) {
      debugPrint("Error fetching numeric officer UID: $e");
    }
  }

  Future<void> _fetchSites({bool bypassCache = false}) async {
    if (bypassCache) {
      await ConnectivityService.instance.refresh();
    }
    final bool liveOnly = bypassCache && ConnectivityService.instance.isOnline;

    if (_numericOfficerUid == null) {
      final cached = liveOnly
          ? <Map<String, dynamic>>[]
          : OfficerRepository.instance.getOfficerSites() ?? [];
      if (mounted) setState(() => _sitesFuture = Future.value(cached));
      return;
    }

    final future = supabase
        .from('sites')
        .select(
          '*, workers!current_site_id(count), hse_workers!current_site_id(count)',
        )
        .eq('officer_uid', _numericOfficerUid!)
        .order('name', ascending: true)
        .then((data) async {
          final rows = List<Map<String, dynamic>>.from(data);
          await OfficerRepository.instance.saveOfficerSites(rows);
          return rows;
        })
        .catchError((error) {
          if (liveOnly) {
            throw error;
          }
          debugPrint('Officer sites offline/error - using cached data: $error');
          return OfficerRepository.instance.getOfficerSites() ??
              <Map<String, dynamic>>[];
        });

    if (mounted) {
      setState(() => _sitesFuture = future);
    } else {
      _sitesFuture = future;
    }
    await future.catchError((_) => <Map<String, dynamic>>[]);
  }

  Future<void> _addOrEditSite({Map<String, dynamic>? site}) async {
    final nameController = TextEditingController(text: site?['name'] ?? '');
    final descController = TextEditingController(
      text: site?['description'] ?? '',
    );
    final isEditing = site != null;
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        const dialogBg = Color(0xFF123636);
        const fieldBg = Color(0x33FFFFFF);
        const textColor = Colors.white;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: dialogBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.surfaceTeal.withValues(alpha: 0.8),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
              R.blockH * 5,
              R.blockV * 2,
              R.blockH * 5,
              R.blockV * 1.5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(R.blockH * 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandTeal.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isEditing
                            ? Icons.edit_location_alt_rounded
                            : Icons.add_location_alt_rounded,
                        color: AppColors.accentGold,
                      ),
                    ),
                    SizedBox(width: R.blockH * 3.2),
                    Text(
                      isEditing ? 'Edit Site' : 'Add New Site',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        fontSize: R.blockH * 5,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: R.blockV * 1.75),
                Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        inputFormatters: const [SanitizingTextInputFormatter()],
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          labelText: 'Site Name',
                          labelStyle: TextStyle(
                            color: textColor.withValues(alpha: 0.8),
                          ),
                          prefixIcon: Icon(
                            Icons.domain_rounded,
                            color: AppColors.accentGold,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(
                              color: textColor.withValues(alpha: 0.25),
                            ),
                          ),
                          filled: true,
                          fillColor: fieldBg,
                        ),
                        validator: (value) => value!.trim().isEmpty
                            ? 'Site name is required'
                            : InputSanitizer.validateShortText(
                                value,
                                maxLength: 80,
                              ),
                      ),
                      SizedBox(height: R.blockV * 2),
                      TextFormField(
                        controller: descController,
                        maxLines: 3,
                        inputFormatters: const [SanitizingTextInputFormatter()],
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          labelText: 'Description (Optional)',
                          labelStyle: TextStyle(
                            color: textColor.withValues(alpha: 0.8),
                          ),
                          prefixIcon: Icon(
                            Icons.description_outlined,
                            color: AppColors.accentGold,
                          ),
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(
                              color: textColor.withValues(alpha: 0.25),
                            ),
                          ),
                          filled: true,
                          fillColor: fieldBg,
                        ),
                        validator: (value) => InputSanitizer.validateLongText(
                          value,
                          required: false,
                          maxLength: 300,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: R.blockV * 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    SizedBox(width: R.blockH * 2.133),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandTeal,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(this.context);
                        final siteName = InputSanitizer.cleanText(
                          nameController.text,
                          maxLength: 80,
                        );
                        final siteDescription = InputSanitizer.cleanText(
                          descController.text,
                          maxLength: 300,
                        );
                        try {
                          if (isEditing) {
                            await supabase
                                .from('sites')
                                .update({
                                  'name': siteName,
                                  'description': siteDescription,
                                })
                                .eq('id', site['id']);
                            await _upsertSiteLocally({
                              ...site,
                              'name': siteName,
                              'description': siteDescription,
                            });
                          } else {
                            if (_numericOfficerUid == null) {
                              throw Exception(
                                "Cannot create site: Officer identifier is missing.",
                              );
                            }
                            final payload = {
                              'name': siteName,
                              'description': siteDescription,
                              'officer_uid': _numericOfficerUid!,
                            };
                            final inserted = await supabase
                                .from('sites')
                                .insert(payload)
                                .select()
                                .single();
                            await _upsertSiteLocally(
                              Map<String, dynamic>.from(inserted),
                            );
                          }
                          if (mounted) {
                            navigator.pop();
                            await _fetchSites(bypassCache: true);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  isEditing
                                      ? 'Site updated successfully'
                                      : 'Site added successfully',
                                ),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } on SocketException {
                          final localId =
                              site?['id']?.toString() ?? const Uuid().v4();
                          final payload = {
                            'id': localId,
                            'name': siteName,
                            'description': siteDescription,
                            ...?(_numericOfficerUid == null
                                ? null
                                : {'officer_uid': _numericOfficerUid}),
                          };
                          await _syncRepository.enqueueAction(
                            id: 'officer_site_${isEditing ? 'update' : 'insert'}_${localId}_${DateTime.now().millisecondsSinceEpoch}',
                            table: 'sites',
                            action: isEditing ? 'update' : 'insert',
                            payload: payload,
                          );
                          await _upsertSiteLocally(payload);
                          if (mounted) {
                            navigator.pop();
                            await _fetchSites();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Saved offline - site change will sync when online',
                                ),
                                backgroundColor: Colors.orange,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not save site. Please try again.',
                                ),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                      child: Text(isEditing ? 'Update' : 'Add'),
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

  Future<void> _deleteSite(Map<String, dynamic> site) async {
    final String id = site['id'];
    final String name = site['name'];
    final workersData = site['workers'] as List? ?? [];
    final workerCount = workersData.isNotEmpty ? workersData[0]['count'] : 0;
    final hseWorkersData = site['hse_workers'] as List? ?? [];
    final hseWorkerCount = hseWorkersData.isNotEmpty
        ? hseWorkersData[0]['count']
        : 0;
    final totalWorkers = workerCount + hseWorkerCount;
    final bool hasWorkers = totalWorkers > 0;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        const dialogBg = Color(0xFF123636);
        const textColor = Colors.white;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: dialogBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.surfaceTeal.withValues(alpha: 0.8),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              R.blockH * 5,
              R.blockV * 2,
              R.blockH * 5,
              R.blockV * 1.5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hasWorkers
                          ? Icons.warning_amber_rounded
                          : Icons.delete_forever_rounded,
                      color: Colors.redAccent,
                    ),
                    SizedBox(width: R.blockH * 3.2),
                    Expanded(
                      child: Text(
                        hasWorkers ? 'Warning: Site in Use' : 'Delete Site',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          fontSize: R.blockH * 5,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: R.blockV * 1.5),
                Text(
                  hasWorkers
                      ? '"$name" is currently assigned to $totalWorkers worker(s) and may be linked to other records like resolved hazards.\n\nDeleting the site will automatically un-link it from all associated records. Are you sure you want to proceed?'
                      : 'Are you sure you want to delete "$name"? This action cannot be undone.',
                  style: TextStyle(color: textColor.withValues(alpha: 0.9)),
                ),
                SizedBox(height: R.blockV * 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    SizedBox(width: R.blockH * 2.133),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirm == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await supabase.from('sites').delete().eq('id', id);
        await _removeSiteLocally(id);

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('"$name" deleted successfully.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _fetchSites(bypassCache: true);
      } on SocketException {
        await _syncRepository.enqueueAction(
          id: 'officer_site_delete_${id}_${DateTime.now().millisecondsSinceEpoch}',
          table: 'sites',
          action: 'delete',
          payload: {'id': id},
        );
        await _removeSiteLocally(id);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Deleted "$name" offline - will sync when online.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _fetchSites();
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error deleting site: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _upsertSiteLocally(Map<String, dynamic> site) async {
    final sites = OfficerRepository.instance.getOfficerSites() ?? [];
    final index = sites.indexWhere((item) => item['id'] == site['id']);
    final normalised = {
      'workers': const [
        {'count': 0},
      ],
      'hse_workers': const [
        {'count': 0},
      ],
      ...site,
    };
    if (index == -1) {
      sites.insert(0, normalised);
    } else {
      sites[index] = {...sites[index], ...normalised};
    }
    await OfficerRepository.instance.saveOfficerSites(sites);
  }

  Future<void> _removeSiteLocally(String id) async {
    final sites = OfficerRepository.instance.getOfficerSites() ?? [];
    sites.removeWhere((site) => site['id'] == id);
    await OfficerRepository.instance.saveOfficerSites(sites);
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: () => _fetchSites(bypassCache: true),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _sitesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(R.blockH * 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red.shade400,
                      ),
                      SizedBox(height: R.blockV * 2),
                      Text(
                        'Error: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: R.blockH * 4),
                      ),
                    ],
                  ),
                ),
              );
            }

            final sites = snapshot.data ?? [];

            if (sites.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(R.blockH * 8),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.maps_home_work_rounded,
                        size: 80,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    SizedBox(height: R.blockV * 3),
                    Text(
                      'No sites found',
                      style: TextStyle(
                        fontSize: R.blockH * 5.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: R.blockV * 1),
                    Text(
                      'Create your first site to get started',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: R.blockH * 4,
                      ),
                    ),
                    SizedBox(height: R.blockV * 4),
                    ElevatedButton.icon(
                      onPressed: () => _addOrEditSite(),
                      icon: Icon(Icons.add),
                      label: Text('Add Site'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                // Header Section
                Container(
                  margin: EdgeInsets.fromLTRB(
                    R.blockH * 5,
                    R.blockV * 1.5,
                    R.blockH * 5,
                    R.blockV * 1,
                  ),
                  padding: EdgeInsets.fromLTRB(
                    R.blockH * 3.5,
                    R.blockV * 1,
                    R.blockH * 2,
                    R.blockV * 1,
                  ),
                  constraints: BoxConstraints(minHeight: 56, maxHeight: 56),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Color.lerp(AppColors.brandTeal, Colors.black, 0.35)!
                        : Color.lerp(AppColors.brandTeal, Colors.white, 0.78)!,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.surfaceTeal.withValues(alpha: 0.8)
                          : AppColors.brandTeal.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "${sites.length} ${sites.length == 1 ? 'Site' : 'Sites'}",
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                          ),
                        ),
                      ),
                      IconButton.filled(
                        icon: Icon(Icons.add, size: 20),
                        onPressed: () => _addOrEditSite(),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.accentGold,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                // Sites List
                Expanded(
                  child: ListView.builder(
                    // ADDED BOTTOM PADDING HERE TO CLEAR THE NAV BAR
                    padding: EdgeInsets.only(
                      left: R.blockH * 3,
                      right: R.blockH * 3,
                      top: R.blockV * 1.5,
                      bottom: R.blockV * 12.5,
                    ),
                    itemCount: sites.length,
                    itemBuilder: (context, index) {
                      final site = sites[index];
                      return _SiteCard(
                        site: site,
                        index: index,
                        onEdit: () => _addOrEditSite(site: site),
                        onDelete: () => _deleteSite(site),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({
    required this.site,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> site;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final description = site['description'];
    final workersData = site['workers'] as List? ?? [];
    final workerCount = workersData.isNotEmpty ? workersData[0]['count'] : 0;
    final hseWorkersData = site['hse_workers'] as List? ?? [];
    final hseWorkerCount = hseWorkersData.isNotEmpty
        ? hseWorkersData[0]['count']
        : 0;
    final totalWorkers = workerCount + hseWorkerCount;

    // Color gradient based on index
    final colors = [
      [const Color(0xFF6366F1), const Color(0xFF8B5CF6)], // Indigo to Purple
      [const Color(0xFF0EA5E9), const Color(0xFF06B6D4)], // Sky to Cyan
      [const Color(0xFFF59E0B), const Color(0xFFF97316)], // Amber to Orange
      [const Color(0xFF10B981), const Color(0xFF059669)], // Emerald to Green
      [const Color(0xFFEC4899), const Color(0xFFDB2777)], // Pink to Rose
    ];
    final colorPair = colors[index % colors.length];

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: R.blockV * 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorPair[0].withValues(alpha: 0.95),
              colorPair[1].withValues(alpha: 0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colorPair[0].withValues(alpha: 0.4),
              blurRadius: 15,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              // Navigates to the new personnel screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SitePersonnelScreen(
                    siteId: site['id'],
                    siteName: site['name'] ?? 'Unnamed Site',
                  ),
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.all(R.blockH * 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: R.blockH * 14.933,
                        height: R.blockV * 7,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.domain_rounded,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: R.blockH * 4.267),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              site['name'] ?? 'Unnamed Site',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: R.blockH * 5,
                                color: Colors.white,
                              ),
                            ),
                            if (description != null && description.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: R.blockV * 0.75),
                                child: Text(
                                  description,
                                  style: TextStyle(
                                    fontSize: R.blockH * 3.5,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    height: 1.4,
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

                  SizedBox(height: R.blockV * 2),

                  // Divider
                  Divider(
                    color: Colors.white.withValues(alpha: 0.3),
                    height: 1,
                  ),

                  SizedBox(height: R.blockV * 2),

                  // Worker Stats
                  Row(
                    children: [
                      Expanded(
                        child: _StatBox(
                          icon: Icons.people_alt_rounded,
                          label: 'Workers',
                          count: workerCount.toString(),
                        ),
                      ),
                      SizedBox(width: R.blockH * 3.2),
                      Expanded(
                        child: _StatBox(
                          icon: Icons.health_and_safety_rounded,
                          label: 'Site Inspector',
                          count: hseWorkerCount.toString(),
                        ),
                      ),
                      SizedBox(width: R.blockH * 3.2),
                      Expanded(
                        child: _StatBox(
                          icon: Icons.groups_rounded,
                          label: 'Total',
                          count: totalWorkers.toString(),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: R.blockV * 2),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onEdit,
                          icon: Icon(Icons.edit_rounded, size: 18),
                          label: Text('Edit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.25,
                            ),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.symmetric(
                              vertical: R.blockV * 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: R.blockH * 3.2),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onDelete,
                          icon: Icon(Icons.delete_forever_rounded, size: 18),
                          label: Text('Delete'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.25,
                            ),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.symmetric(
                              vertical: R.blockV * 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final String count;

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: R.blockV * 1.5,
        horizontal: R.blockH * 2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          SizedBox(height: R.blockV * 0.5),
          Text(
            count,
            style: TextStyle(
              color: Colors.white,
              fontSize: R.blockH * 4.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: R.blockH * 2.75,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
