import 'package:flutter/material.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
// Import the Edit screen to use for navigation
import 'package:riskradar/officers/settings/edit_officer_profile_screen.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';

class OfficerViewProfileScreen extends StatefulWidget {
  const OfficerViewProfileScreen({super.key});

  @override
  State<OfficerViewProfileScreen> createState() =>
      _OfficerViewProfileScreenState();
}

class _OfficerViewProfileScreenState extends State<OfficerViewProfileScreen> {
  Map<String, dynamic>? _profileData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // --- Profile Loading Logic (Kept mostly the same) ---
  Future<void> _loadProfile() async {
    if (!mounted) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final cached = OfficerRepository.instance.getOfficerProfile();
    if (cached != null) {
      setState(() {
        _profileData = cached;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = true);
    }

    try {
      // Try workers first, then officers
      Map<String, dynamic>? response = await Supabase.instance.client
          .from('workers')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      response ??= await Supabase.instance.client
          .from('officers')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      _profileData = response;
      if (response != null) {
        await OfficerRepository.instance.saveOfficerProfile(response);
      }
    } on SocketException {
      debugPrint('Officer profile offline - using cached profile.');
    } catch (e) {
      debugPrint('Error loading officer profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- Navigation and Reload ---
  void _navigateToEdit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditOfficerProfileScreen()),
    ).then((_) {
      // Reload profile data when returning from the edit screen
      _loadProfile();
    });
  }

  // Helper function to capitalize the first letter of a string
  String _capitalize(String? s) {
    if (s == null || s.isEmpty) return 'N/A';
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  // --- UI Component: Employee Card Item ---
  Widget _buildCardItem(BuildContext context, IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_profileData == null) {
      return  Scaffold(
        appBar: AppBar(
          title: const Text('Your Profile'),
        ),
        body: const Center(
          child: Text("Profile not found"),
        ),
      );
    }

    final imageUrl = _profileData!['profile_image_url']?.toString();

    // ✅ Capitalize first and last names
    final rawFirstName = _profileData!['first_name']?.toString() ?? 'N/A';
    final rawLastName = _profileData!['last_name']?.toString() ?? 'N/A';
    final firstName = _capitalize(rawFirstName);
    final lastName = _capitalize(rawLastName);
    final fullName = '$firstName $lastName';

    // ✅ Capitalize role
    final rawRole = _profileData!['role']?.toString() ?? 'Officer';
    final role = _capitalize(rawRole);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile',
            onPressed: _navigateToEdit,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
        child: Column(
          children: [
            // --- Profile Header (Badge UI) ---
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Top accent container
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                // Profile details positioned below accent
                Positioned(
                  top: 50,
                  child: Column(
                    children: [
                      // Avatar with Badge effect
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            backgroundImage: imageUrl != null && imageUrl.isNotEmpty
                                ? NetworkImage(imageUrl)
                                : null,
                            child: imageUrl == null || imageUrl.isEmpty
                                ? Text(
                              rawFirstName.isNotEmpty ? rawFirstName[0].toUpperCase() : 'U',
                              style: const TextStyle(fontSize: 40, color: Colors.white),
                            )
                                : null,
                          ),
                          // ✅ Badge Icon (shows superiority)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.surface,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.verified_user, // or Icons.stars, Icons.security
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        fullName,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        role, // ✅ Capitalized role
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 150), // Spacing for the header/avatar overlap

            // --- Details Card ---
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildCardItem(
                      context,
                      Icons.email_outlined,
                      "Email",
                      _profileData!['email']?.toString() ?? 'N/A',
                    ),
                    const Divider(height: 1),
                    _buildCardItem(
                      context,
                      Icons.calendar_today_outlined,
                      "Date of Birth",
                      _profileData!['dob']?.toString() ?? 'N/A',
                    ),
                    const Divider(height: 1),
                    if (_profileData!['officer_uid'] != null)
                      _buildCardItem(
                        context,
                        Icons.verified_user_outlined,
                        "Officer UID",
                        _profileData!['officer_uid']?.toString() ?? 'N/A',
                      ),
                    if (_profileData!['work_type'] != null)
                      _buildCardItem(
                        context,
                        Icons.work_outline,
                        "Work Type",
                        _profileData!['work_type']?.toString() ?? 'N/A',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

