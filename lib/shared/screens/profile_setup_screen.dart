import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/services/supabase_service.dart';
import 'package:riskradar/officers/screens/officer_home_screen.dart';
import 'package:riskradar/workers/screens/worker_home_screen.dart';
import 'package:riskradar/shared/widgets/risk_radar_loader.dart'; // ✅ Import Added

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  // ---------------------------------------------------------------------------
  // ✅ LOGIC SECTION
  // ---------------------------------------------------------------------------
  File? _imageFile;
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _officerUIDController = TextEditingController();

  String? _role;
  String? _workType;
  String? _hseDesignation;
  String? _birthDay;
  String? _birthMonth;
  String? _birthYear;
  bool _isSaving = false;
  bool _isProfileSaved = false;
  bool _isLoadingProfile = true;

  final List<String> _roles = ['Worker', 'Officer', 'HSE Worker'];
  final List<String> _workTypes = ['Mason', 'Plumber', 'Electrician', 'Painter', 'Carpenter', 'Welder', 'Other'];
  final List<String> _hseDesignations = ['HSE Inspector', 'Safety Engineer', 'Safety Supervisor', 'Technician', 'Other'];
  final List<String> _days = List.generate(31, (i) => '${i + 1}');
  final List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final List<String> _years = List.generate(80, (i) => '${DateTime.now().year - i}');

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && user.email != null) {
      _emailController.text = user.email!;
    }
    _loadProfileIfExists();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _officerUIDController.dispose();
    super.dispose();
  }

  // --- Android Version Check ---
  Future<bool> _isAndroid13OrHigher() async {
    if (Platform.isAndroid) {
      try {
        final versionString = Platform.operatingSystemVersion;
        final RegExp regex = RegExp(r'Android\s+([0-9]+)');
        final match = regex.firstMatch(versionString);
        if (match != null && match.groupCount >= 1) {
          final version = int.parse(match.group(1)!);
          return version >= 13;
        }
      } catch (e) {
        debugPrint("Error parsing Android version: $e");
      }
    }
    return false;
  }

  // --- Image Cropper Logic ---
  Future<File?> _cropImage(File imageFile) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: imageFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Edit Photo',
          toolbarColor: const Color(0xFF1B3D3D), // Matches your Teal Theme
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true, // Force square for profile pics
          aspectRatioPresets: [CropAspectRatioPreset.square],
          hideBottomControls: true,
        ),
        IOSUiSettings(
          title: 'Edit Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
      ],
    );
    if (croppedFile != null) return File(croppedFile.path);
    return null;
  }

  // --- Pick & Crop Logic ---
  Future<void> _pickImage(ImageSource source) async {
    Permission permission;

    if (source == ImageSource.camera) {
      permission = Permission.camera;
    } else {
      if (Platform.isAndroid) {
        final isAndroid13 = await _isAndroid13OrHigher();
        permission = isAndroid13 ? Permission.photos : Permission.storage;
      } else {
        permission = Permission.photos;
      }
    }

    final status = await permission.request();

    if (status.isGranted || status.isLimited) {
      try {
        // 1. Pick Image
        final picked = await ImagePicker().pickImage(source: source);
        if (picked == null) return;

        // 2. Crop Image immediately after picking
        final File? cropped = await _cropImage(File(picked.path));

        // 3. Set State if crop was successful
        if (cropped != null) {
          setState(() => _imageFile = cropped);
        }
      } catch (e) {
        if (mounted) _showMessage('Error processing image: $e');
      }
    } else if (status.isPermanentlyDenied) {
      if (mounted) _showPermissionDialog();
    } else {
      if (mounted) _showMessage('Permission denied. Cannot upload photo.');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Permission Required"),
        content: const Text("Please enable photo access in Settings to upload your profile picture."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text("Settings"),
          ),
        ],
      ),
    );
  }

  void _showPicker() {
    if (_isProfileSaved) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF1B3D3D)),
              title: const Text('Gallery', style: TextStyle(color: Color(0xFF1B3D3D))),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Color(0xFF1B3D3D)),
              title: const Text('Camera', style: TextStyle(color: Color(0xFF1B3D3D))),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToHomeScreen() {
    void onThemeChanged(ThemeMode mode) {}
    Widget screen;
    if (_role == 'Officer') {
      screen = OfficerHomeScreen(currentThemeMode: ThemeMode.system, onThemeChanged: onThemeChanged);
    } else {
      screen = WorkerHomeScreen(currentThemeMode: ThemeMode.system, onThemeChanged: onThemeChanged);
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _loadProfileIfExists() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _isLoadingProfile = false);
      return;
    }
    try {
      final officer = await Supabase.instance.client.from('officers').select().eq('id', user.id).maybeSingle();
      if (officer != null) {
        setState(() { _role = 'Officer'; _firstNameController.text = officer['first_name'] ?? ''; _isProfileSaved = true; });
        _navigateToHomeScreen(); return;
      }
      final worker = await Supabase.instance.client.from('workers').select().eq('id', user.id).maybeSingle();
      if (worker != null) {
        setState(() { _role = 'Worker'; _firstNameController.text = worker['first_name'] ?? ''; _isProfileSaved = true; });
        _navigateToHomeScreen(); return;
      }
    } catch (e) { debugPrint("Error loading profile: $e"); }
    setState(() => _isLoadingProfile = false);
  }

  Future<void> _onSave() async {
    if (_isSaving || _isProfileSaved) return;
    if (_role == null || _firstNameController.text.trim().isEmpty || _imageFile == null) {
      _showMessage('Please complete all required fields & upload a photo.'); return;
    }
    setState(() => _isSaving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final imageUrl = await SupabaseService().uploadProfileImage(_imageFile!, user!.id, 'profile');

      String? dobFormatted;
      if (_birthDay != null && _birthMonth != null && _birthYear != null) {
        final monthIndex = _months.indexOf(_birthMonth!) + 1;
        dobFormatted = '${_birthYear!}-${monthIndex.toString().padLeft(2, '0')}-${_birthDay!.padLeft(2, '0')}';
      }

      // Safe parse
      int? officerUid = int.tryParse(_officerUIDController.text.trim());

      final data = {
        'id': user.id,
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'dob': dobFormatted,
        'profile_image_url': imageUrl,
        'created_at': DateTime.now().toIso8601String(),
      };

      if (_role == 'Worker') {
        await Supabase.instance.client.from('workers').insert({...data, 'officer_uid': officerUid, 'work_type': _workType});
      } else if (_role == 'HSE Worker') {
        await Supabase.instance.client.from('hse_workers').insert({...data, 'officer_uid': officerUid, 'designation': _hseDesignation});
      } else {
        await Supabase.instance.client.from('officers').insert(data);
      }
      _showMessage('✅ Profile saved!');
      setState(() => _isProfileSaved = true);
      _navigateToHomeScreen();
    } catch (e) { _showMessage('❌ Error: $e'); }
    setState(() => _isSaving = false);
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------------
  // ✅ UI SECTION (Updated with RiskRadarLoader)
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    const Color tealColor = Color(0xFF1B3D3D);
    const Color goldColor = Color(0xFFE6A050);
    const double headerHeight = 240;
    const double avatarSize = 130;
    const double goldRimOffset = 6.0;

    if (_isLoadingProfile) {
      // ✅ REPLACED: Full Screen Loader
      return const Scaffold(
        backgroundColor: Colors.white,
        body: RiskRadarLoader(size: 80, color: tealColor),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,

        body: ListView(
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [

            // 1. HEADER SECTION
            SizedBox(
              height: headerHeight + (avatarSize / 2) - 20,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: goldRimOffset,
                    left: 0, right: 0,
                    child: ClipPath(
                      clipper: ConcaveHeaderClipper(),
                      child: Container(height: headerHeight, color: goldColor),
                    ),
                  ),
                  ClipPath(
                    clipper: ConcaveHeaderClipper(),
                    child: Container(
                      height: headerHeight,
                      width: double.infinity,
                      color: tealColor,
                      padding: const EdgeInsets.only(top: 50),
                      child: const Column(
                        children: [
                          Text("Setup Your Profile", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          SizedBox(height: 5),
                          Text("Complete your details to continue", style: TextStyle(color: Colors.white70, fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: headerHeight - (avatarSize / 2) - 30,
                    child: Stack(
                      children: [
                        Container(
                          height: avatarSize,
                          width: avatarSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            // ✅ UPDATED: Opacity
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8))],
                          ),
                          padding: const EdgeInsets.all(4),
                          child: ClipOval(
                            child: _imageFile != null
                                ? Image.file(_imageFile!, fit: BoxFit.cover)
                                : Image.asset('assets/default_user.png', fit: BoxFit.cover,
                                errorBuilder: (c, o, s) => Container(color: Colors.grey.shade200, child: Icon(Icons.person, size: 60, color: Colors.grey.shade400))),
                          ),
                        ),
                        if (!_isProfileSaved)
                          Positioned(
                            bottom: 5, right: 5,
                            child: GestureDetector(
                              onTap: _showPicker,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: goldColor),
                                child: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // 2. FORM SECTION
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildCustomTextField(_firstNameController, "First Name", Icons.person_outline, action: TextInputAction.next)),
                      const SizedBox(width: 15),
                      Expanded(child: _buildCustomTextField(_lastNameController, "Last Name", Icons.person_outline, action: TextInputAction.next)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildCustomTextField(_emailController, "Email", Icons.email_outlined, isEnabled: false),
                  const SizedBox(height: 20),

                  _buildCustomDropdown("Select Role", _roles, _role, (value) {
                    setState(() { _role = value; _workType = null; _hseDesignation = null; _officerUIDController.clear(); });
                  }, Icons.work_outline),

                  if (_role == 'Worker' || _role == 'HSE Worker') ...[
                    const SizedBox(height: 20),
                    _buildCustomTextField(_officerUIDController, "Officer UID", Icons.badge_outlined, type: TextInputType.number),
                    const SizedBox(height: 20),
                    _buildCustomDropdown(
                        _role == 'Worker' ? "Type of Work" : "Designation",
                        _role == 'Worker' ? _workTypes : _hseDesignations,
                        _role == 'Worker' ? _workType : _hseDesignation,
                            (val) => setState(() => _role == 'Worker' ? _workType = val : _hseDesignation = val),
                        Icons.category_outlined
                    ),
                  ],

                  const SizedBox(height: 25),
                  const Align(alignment: Alignment.centerLeft, child: Text("Date of Birth", style: TextStyle(color: tealColor, fontWeight: FontWeight.w600))),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(child: _buildCustomDropdown("Day", _days, _birthDay, (val) => setState(() => _birthDay = val), null)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildCustomDropdown("Month", _months, _birthMonth, (val) => setState(() => _birthMonth = val), null)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildCustomDropdown("Year", _years, _birthYear, (val) => setState(() => _birthYear = val), null)),
                    ],
                  ),

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: (_isSaving || _isProfileSaved) ? null : _onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: goldColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 8,
                        // ✅ UPDATED: Opacity
                        shadowColor: goldColor.withValues(alpha: 0.4),
                      ),
                      child: _isSaving
                      // ✅ REPLACED: Button Loader
                          ? const RiskRadarLoader(size: 24, color: Colors.white)
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_isProfileSaved ? 'Profile Saved' : 'Complete Setup', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          if (!_isProfileSaved) const SizedBox(width: 10),
                          if (!_isProfileSaved) const Icon(Icons.check_circle_outline_rounded, color: Colors.white)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomTextField(TextEditingController controller, String label, IconData icon, {TextInputType? type, bool isEnabled = true, TextInputAction? action}) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.grey.shade200)),
      child: TextField(
        controller: controller,
        keyboardType: type,
        enabled: isEnabled && !_isProfileSaved,
        scrollPadding: const EdgeInsets.only(bottom: 100),
        style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
            prefixIcon: Padding(padding: const EdgeInsets.only(left: 15, right: 10), child: Icon(icon, color: const Color(0xFF1B3D3D), size: 22)),
            hintText: label,
            hintStyle: TextStyle(color: Colors.grey.shade500),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            filled: true,
            fillColor: Colors.transparent
        ),
      ),
    );
  }

  Widget _buildCustomDropdown(String label, List<String> items, String? selectedValue, void Function(String?) onChanged, IconData? icon) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.grey.shade200)),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedValue,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
          hint: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: const Color(0xFF1B3D3D), size: 22),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          isExpanded: true,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(20),
          items: items.map((e) => DropdownMenuItem(
              value: e,
              child: Text(e, style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)
          )).toList(),
          onChanged: _isProfileSaved ? null : onChanged,
        ),
      ),
    );
  }
}

class ConcaveHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height - 50);
    var controlPoint = Offset(size.width / 2, size.height + 60);
    var endPoint = Offset(size.width, size.height - 50);
    path.quadraticBezierTo(controlPoint.dx, controlPoint.dy, endPoint.dx, endPoint.dy);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}