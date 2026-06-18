// lib/hse_workers/screens/hse_worker_view_profile_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:riskradar/shared/security/input_sanitizer.dart';
import 'package:riskradar/shared/utils/profile_photo_permission.dart';
import 'package:riskradar/shared/widgets/full_image_viewer.dart';

class HSEWorkerEditProfileScreen extends StatefulWidget {
  const HSEWorkerEditProfileScreen({super.key});

  @override
  State<HSEWorkerEditProfileScreen> createState() =>
      _HSEWorkerEditProfileScreenState();
}

class _HSEWorkerEditProfileScreenState
    extends State<HSEWorkerEditProfileScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _editing = false;
  bool _hasChanges = false;
  bool _updating = false;
  bool _uploadingImage = false;

  Map<String, dynamic>? _initialData;

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  final TextEditingController _officerUidController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) {
      return;
    }
    setState(() => _loading = true);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    try {
      final hseWorker = await supabase
          .from('hse_workers')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (hseWorker != null) {
        _initialData = hseWorker;
        _firstNameController.text = hseWorker['first_name']?.toString() ?? '';
        _lastNameController.text = hseWorker['last_name']?.toString() ?? '';
        _emailController.text = hseWorker['email']?.toString() ?? '';
        _dobController.text = hseWorker['dob']?.toString() ?? '';
        _designationController.text =
            hseWorker['designation']?.toString() ?? '';
        _officerUidController.text = hseWorker['officer_uid']?.toString() ?? '';
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _checkChanges() {
    if (_initialData == null) {
      return;
    }
    setState(() {
      _hasChanges =
          _firstNameController.text !=
              (_initialData!['first_name']?.toString() ?? '') ||
          _lastNameController.text !=
              (_initialData!['last_name']?.toString() ?? '') ||
          _dobController.text != (_initialData!['dob']?.toString() ?? '') ||
          _designationController.text !=
              (_initialData!['designation']?.toString() ?? '');
    });
  }

  // ✅ NEW: Date Picker Logic
  Future<void> _selectDate() async {
    DateTime initialDate = DateTime.now();
    // Try to parse existing date if valid
    if (_dobController.text.isNotEmpty) {
      try {
        initialDate = DateTime.parse(_dobController.text);
      } catch (_) {}
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1B3D3D), // Teal color
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1B3D3D), // Button text color
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dobController.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
      _checkChanges();
    }
  }

  Future<File?> _cropImage(File imageFile) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: imageFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Center Your Face',
          toolbarColor: const Color(0xFF1B3D3D),
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          aspectRatioPresets: [CropAspectRatioPreset.square],
          hideBottomControls: true,
          showCropGrid: false,
        ),
        IOSUiSettings(
          title: 'Center Your Face',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
      ],
    );
    if (croppedFile != null) {
      return File(croppedFile.path);
    }
    return null;
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final bool hasPermission = await requestProfilePhotoPermission(
        context,
        ImageSource.gallery,
      );
      if (!hasPermission) {
        return;
      }

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image == null) {
        return;
      }

      File? croppedImage = await _cropImage(File(image.path));
      if (croppedImage == null) {
        return;
      }

      setState(() => _uploadingImage = true);

      final userId = supabase.auth.currentUser!.id;
      final fileExt = image.path.split('.').last;
      final fileName =
          '$userId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await supabase.storage
          .from('profile-images')
          .upload(
            fileName,
            croppedImage,
            fileOptions: const FileOptions(upsert: true),
          );

      final String publicUrl = supabase.storage
          .from('profile-images')
          .getPublicUrl(fileName);

      await supabase
          .from('hse_workers')
          .update({'profile_image_url': publicUrl})
          .eq('id', userId);

      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Profile photo updated!")));
      }
    } catch (e) {
      debugPrint("Upload Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Upload failed. Please try again.")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  Future<void> _updateProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return;
    }
    setState(() => _updating = true);
    try {
      final firstNameError = InputSanitizer.validateName(
        _firstNameController.text,
      );
      final lastNameError = InputSanitizer.validateName(
        _lastNameController.text,
      );
      final designationError = InputSanitizer.validateShortText(
        _designationController.text,
        required: false,
        maxLength: 80,
      );
      final validationError =
          firstNameError ?? lastNameError ?? designationError;
      if (validationError != null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(validationError)));
        }
        return;
      }

      await supabase
          .from('hse_workers')
          .update({
            'first_name': InputSanitizer.cleanText(
              _firstNameController.text,
              maxLength: 50,
            ),
            'last_name': InputSanitizer.cleanText(
              _lastNameController.text,
              maxLength: 50,
            ),
            'dob': _dobController.text,
            'designation': InputSanitizer.cleanText(
              _designationController.text,
              maxLength: 80,
            ),
          })
          .eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile updated successfully")),
        );
      }

      setState(() {
        _editing = false;
        _hasChanges = false;
      });
      _loadProfile();
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Update failed. Please try again.")),
        );
      }
    }
    if (mounted) {
      setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_initialData == null) {
      return const Scaffold(body: Center(child: Text("Profile not found")));
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      resizeToAvoidBottomInset: true,
      body: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    const tealColor = Color(0xFF1B3D3D);
    const goldColor = Color(0xFFE6A050);
    final imageUrl = _initialData!['profile_image_url']?.toString();
    final fullName = "${_firstNameController.text} ${_lastNameController.text}"
        .trim();

    return Stack(
      children: [
        // Header Background
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: R.blockV * 35,
          child: Container(
            decoration: const BoxDecoration(
              color: tealColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
          ),
        ),

        // Scrollable Content
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(top: R.blockV * 7.5, bottom: R.blockV * 5),
            child: Column(
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (imageUrl != null && imageUrl.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FullscreenImageViewer(
                                  imageUrls: [imageUrl],
                                  initialIndex: 0,
                                ),
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.all(R.blockH * 1),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Hero(
                            tag: 'profile_pic',
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage:
                                  (imageUrl != null && imageUrl.isNotEmpty)
                                  ? NetworkImage(imageUrl)
                                  : null,
                              child: _uploadingImage
                                  ? const CircularProgressIndicator(
                                      color: tealColor,
                                    )
                                  : (imageUrl == null || imageUrl.isEmpty)
                                  ? Icon(
                                      Icons.person,
                                      size: 60,
                                      color: Colors.grey,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),

                      if (_editing)
                        GestureDetector(
                          onTap: _pickAndUploadImage,
                          child: Container(
                            padding: EdgeInsets.all(R.blockH * 2),
                            decoration: const BoxDecoration(
                              color: goldColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                            child: Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                SizedBox(height: R.blockV * 1.875),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      fullName.isEmpty ? "User Profile" : fullName,
                      style: TextStyle(
                        fontSize: R.blockH * 5.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(width: R.blockH * 2.667),
                    GestureDetector(
                      onTap: () => setState(() => _editing = !_editing),
                      child: Container(
                        padding: EdgeInsets.all(R.blockH * 1.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _editing ? Icons.close : Icons.edit,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: R.blockV * 0.625),
                Text(
                  _designationController.text.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: R.blockH * 3,
                    letterSpacing: 1,
                  ),
                ),

                SizedBox(height: R.blockV * 3.75),

                Container(
                  margin: EdgeInsets.symmetric(horizontal: R.blockH * 5),
                  padding: EdgeInsets.all(R.blockH * 6.25),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "USER DETAILS",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: R.blockH * 4,
                          color: tealColor,
                        ),
                      ),
                      SizedBox(height: R.blockV * 2.5),
                      _buildStyledTextField(
                        "First Name",
                        _firstNameController,
                        Icons.person_outline,
                      ),
                      _buildStyledTextField(
                        "Last Name",
                        _lastNameController,
                        Icons.person_outline,
                      ),
                      _buildStyledTextField(
                        "Email ID",
                        _emailController,
                        Icons.email_outlined,
                        readOnly: true,
                      ),
                      // ✅ UPDATED: Passing _selectDate for custom tap handling
                      _buildStyledTextField(
                        "Date of Birth",
                        _dobController,
                        Icons.calendar_today_outlined,
                        onTap: _selectDate,
                      ),
                      _buildStyledTextField(
                        "Designation",
                        _designationController,
                        Icons.badge_outlined,
                      ),
                      _buildStyledTextField(
                        "Contractor UID",
                        _officerUidController,
                        Icons.admin_panel_settings_outlined,
                        readOnly: true,
                      ),
                      SizedBox(height: R.blockV * 3.75),
                      if (_editing)
                        SizedBox(
                          width: double.infinity,
                          height: R.blockV * 6.875,
                          child: ElevatedButton(
                            onPressed: _hasChanges && !_updating
                                ? _updateProfile
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: goldColor,
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 5,
                            ),
                            child: _updating
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(
                                    "SAVE DETAILS",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: R.blockH * 4,
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // BACK BUTTON
        Positioned(
          top: 0,
          left: 20,
          child: SafeArea(
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ],
    );
  }

  // ✅ UPDATED: Now supports customOnTap for date picking
  Widget _buildStyledTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    // If a custom onTap is provided (like Date), we treat the keyboard as read-only.
    // Otherwise, we respect the standard edit/readOnly flags.
    final bool isKeyboardReadOnly = onTap != null || !_editing || readOnly;

    return Padding(
      padding: EdgeInsets.only(bottom: R.blockV * 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: R.blockH * 3.25,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: R.blockV * 1),
          TextField(
            controller: controller,
            inputFormatters: const [SanitizingTextInputFormatter()],
            // Prevent keyboard if it's a date picker or not editing
            readOnly: isKeyboardReadOnly,
            // Trigger tap only if editing is active and it's not a strictly read-only field (like Email)
            onTap: (_editing && !readOnly && onTap != null) ? onTap : null,
            onChanged: (_) => _checkChanges(),
            style: TextStyle(
              color: (!_editing || readOnly)
                  ? Colors.grey.shade700
                  : Colors.black,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: const Color(0xFFE6A050)),
              filled: true,
              fillColor: (!_editing || readOnly)
                  ? Colors.grey.shade50
                  : Colors.white,
              contentPadding: EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: const BorderSide(
                  color: Color(0xFF1B3D3D),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
