import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/shared/security/input_sanitizer.dart';
import 'package:riskradar/shared/utils/profile_photo_permission.dart';
import 'package:riskradar/shared/widgets/full_image_viewer.dart';

class OfficerViewProfileScreen extends StatefulWidget {
  const OfficerViewProfileScreen({super.key});

  @override
  State<OfficerViewProfileScreen> createState() =>
      _OfficerViewProfileScreenState();
}

class _OfficerViewProfileScreenState extends State<OfficerViewProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _editing = false;
  bool _hasChanges = false;
  bool _updating = false;
  bool _uploadingImage = false;

  String _profileTable = 'officers';
  String _dobKey = 'dob';
  Map<String, dynamic>? _initialData;

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _workTypeController = TextEditingController();
  final TextEditingController _officerUidController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _workTypeController.dispose();
    _officerUidController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (!mounted) {
      return;
    }
    setState(() => _loading = true);

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    final cached = OfficerRepository.instance.getOfficerProfile();
    if (cached != null) {
      _applyProfileData(cached, inferOnly: true);
    }

    try {
      final worker = await _supabase
          .from('workers')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (worker != null) {
        _profileTable = 'workers';
        _applyProfileData(worker);
      } else {
        final officer = await _supabase
            .from('officers')
            .select()
            .eq('id', userId)
            .maybeSingle();
        if (officer != null) {
          _profileTable = 'officers';
          _applyProfileData(officer);
        }
      }

      if (_initialData != null) {
        await OfficerRepository.instance.saveOfficerProfile(_initialData!);
      }
    } catch (e) {
      debugPrint('Error loading officer profile: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  String _resolveDobKey(Map<String, dynamic> data) {
    if (data.containsKey('dob')) {
      return 'dob';
    }
    if (data.containsKey('date_of_birth')) {
      return 'date_of_birth';
    }
    if (data.containsKey('birth_date')) {
      return 'birth_date';
    }
    return 'dob';
  }

  String _readDobValue(Map<String, dynamic> data) {
    return data['dob']?.toString() ??
        data['date_of_birth']?.toString() ??
        data['birth_date']?.toString() ??
        '';
  }

  String _readRoleValue(Map<String, dynamic> data) {
    final dynamic rawValue =
        data['work_type'] ?? data['designation'] ?? data['role'];
    if (rawValue == null) {
      return '';
    }

    final values = rawValue is Iterable
        ? rawValue.map((value) => value.toString())
        : rawValue
              .toString()
              .replaceAll(RegExp(r"[\[\]\{\}']"), '')
              .replaceAll('"', '')
              .split(',');

    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map(
          (value) => value
              .split(RegExp(r'[_\s]+'))
              .map(_capitalize)
              .join(' '),
        )
        .join(' / ');
  }

  void _applyProfileData(Map<String, dynamic> data, {bool inferOnly = false}) {
    _dobKey = _resolveDobKey(data);
    _initialData = Map<String, dynamic>.from(data);

    _firstNameController.text = data['first_name']?.toString() ?? '';
    _lastNameController.text = data['last_name']?.toString() ?? '';
    _emailController.text = data['email']?.toString() ?? '';
    _dobController.text = _readDobValue(data);
    _workTypeController.text = _readRoleValue(data);
    _officerUidController.text = data['officer_uid']?.toString() ?? '';

    if (!inferOnly) {
      _hasChanges = false;
    }
  }

  void _checkChanges() {
    if (_initialData == null) {
      return;
    }
    final originalDob = _readDobValue(_initialData!);
    setState(() {
      _hasChanges =
          _firstNameController.text !=
              (_initialData!['first_name']?.toString() ?? '') ||
          _lastNameController.text !=
              (_initialData!['last_name']?.toString() ?? '') ||
          _dobController.text != originalDob ||
          (_profileTable == 'workers' &&
              _workTypeController.text != _readRoleValue(_initialData!));
    });
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

      final croppedImage = await _cropImage(File(image.path));
      if (croppedImage == null) {
        return;
      }

      setState(() => _uploadingImage = true);

      final userId = _supabase.auth.currentUser!.id;
      final fileExt = image.path.split('.').last;
      final fileName =
          '$userId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await _supabase.storage
          .from('profile-images')
          .upload(
            fileName,
            croppedImage,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = _supabase.storage
          .from('profile-images')
          .getPublicUrl(fileName);

      await _supabase
          .from(_profileTable)
          .update({'profile_image_url': publicUrl})
          .eq('id', userId);

      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile photo updated!')));
      }
    } catch (e) {
      debugPrint('Upload Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  Future<void> _selectDate() async {
    DateTime initialDate = DateTime.now();
    if (_dobController.text.isNotEmpty) {
      try {
        initialDate = DateTime.parse(_dobController.text);
      } catch (_) {}
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1B3D3D),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dobController.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
      _checkChanges();
    }
  }

  Future<void> _updateProfile() async {
    final userId = _supabase.auth.currentUser?.id;
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
      final workTypeError = _profileTable == 'workers'
          ? InputSanitizer.validateShortText(
              _workTypeController.text,
              maxLength: 80,
            )
          : null;
      final validationError = firstNameError ?? lastNameError ?? workTypeError;
      if (validationError != null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(validationError)));
        }
        return;
      }

      final updatePayload = {
        'first_name': InputSanitizer.cleanText(
          _firstNameController.text,
          maxLength: 50,
        ),
        'last_name': InputSanitizer.cleanText(
          _lastNameController.text,
          maxLength: 50,
        ),
        _dobKey: _dobController.text.trim(),
      };

      if (_profileTable == 'workers') {
        updatePayload['work_type'] = InputSanitizer.cleanText(
          _workTypeController.text,
          maxLength: 80,
        );
      }

      await _supabase
          .from(_profileTable)
          .update(updatePayload)
          .eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }

      setState(() {
        _editing = false;
        _hasChanges = false;
      });
      await _loadProfile();
    } catch (e) {
      debugPrint('Update Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update profile. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  String _capitalize(String? s) {
    if (s == null || s.isEmpty) {
      return 'N/A';
    }
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_initialData == null) {
      return const Scaffold(body: Center(child: Text('Profile not found')));
    }

    const tealColor = Color(0xFF1B3D3D);
    const goldColor = Color(0xFFE6A050);
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    final topBarHeight = mediaQuery.padding.top + visibleHeight * 0.070;
    final imageUrl = _initialData!['profile_image_url']?.toString();
    final fullName =
        '${_capitalize(_firstNameController.text)} ${_capitalize(_lastNameController.text)}'
            .trim();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topBarHeight + visibleHeight * 0.275,
            child: Container(
              decoration: BoxDecoration(
                color: tealColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(size.width * 0.077),
                  bottomRight: Radius.circular(size.width * 0.077),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                top: topBarHeight + visibleHeight * 0.020,
                bottom: visibleHeight * 0.020,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: size.height),
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
                            padding: EdgeInsets.all(size.width * 0.010),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Hero(
                              tag: imageUrl ?? 'officer_profile_pic',
                              child: CircleAvatar(
                                radius: size.width * 0.118,
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
                                        size: size.width * 0.118,
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
                              padding: EdgeInsets.all(size.width * 0.016),
                              decoration: BoxDecoration(
                                color: goldColor,
                                shape: BoxShape.circle,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: size.width * 0.011,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: size.width * 0.044,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: visibleHeight * 0.005),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        fullName.isEmpty ? 'Officer Profile' : fullName,
                        style: TextStyle(
                          fontSize: size.width * 0.046,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(width: size.width * 0.027),
                      GestureDetector(
                        onTap: () => setState(() => _editing = !_editing),
                        child: Container(
                          padding: EdgeInsets.all(size.width * 0.013),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _editing ? Icons.close : Icons.edit,
                            color: Colors.white,
                            size: size.width * 0.039,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: visibleHeight * 0.004),
                  Text(
                    (_readRoleValue(_initialData!).isEmpty
                            ? 'Officer'
                            : _readRoleValue(_initialData!))
                        .toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: size.width * 0.028,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: visibleHeight * 0.012),
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: size.width * 0.050),
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width * 0.042,
                      vertical: visibleHeight * 0.018,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(size.width * 0.053),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: size.width * 0.053,
                          offset: Offset(
                            size.width * 0.0,
                            visibleHeight * 0.013,
                          ),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OFFICER DETAILS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: size.width * 0.038,
                            color: tealColor,
                          ),
                        ),
                        SizedBox(height: visibleHeight * 0.011),
                        _buildStyledTextField(
                          'First Name',
                          _firstNameController,
                          Icons.person_outline,
                        ),
                        _buildStyledTextField(
                          'Last Name',
                          _lastNameController,
                          Icons.person_outline,
                        ),
                        _buildStyledTextField(
                          'Email ID',
                          _emailController,
                          Icons.email_outlined,
                          readOnly: true,
                        ),
                        _buildStyledTextField(
                          'Date of Birth',
                          _dobController,
                          Icons.calendar_today_outlined,
                          onTap: _selectDate,
                        ),
                        _buildStyledTextField(
                          'Role / Work Type',
                          _workTypeController,
                          Icons.engineering_outlined,
                          readOnly: _profileTable != 'workers',
                        ),
                        _buildStyledTextField(
                          'Officer UID',
                          _officerUidController,
                          Icons.admin_panel_settings_outlined,
                          readOnly: true,
                        ),
                        SizedBox(height: visibleHeight * 0.006),
                        if (_editing)
                          SizedBox(
                            width: double.infinity,
                            height: visibleHeight * 0.060,
                            child: ElevatedButton(
                              onPressed: _hasChanges && !_updating
                                  ? _updateProfile
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: goldColor,
                                disabledBackgroundColor: Colors.grey.shade300,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    size.width * 0.077,
                                  ),
                                ),
                                elevation: size.width * 0.013,
                              ),
                              child: _updating
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : Text(
                                      'SAVE DETAILS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: size.width * 0.038,
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
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: topBarHeight,
              color: tealColor,
              padding: EdgeInsets.only(top: mediaQuery.padding.top),
              child: SizedBox(
                height: visibleHeight * 0.070,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: size.width * 0.055,
                      right: size.width * 0.055,
                      bottom: visibleHeight * 0.004,
                      child: Container(
                        height: visibleHeight * 0.0012,
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    Positioned(
                      left: size.width * 0.030,
                      child: IconButton(
                        iconSize: size.width * 0.058,
                        padding: EdgeInsets.all(size.width * 0.010),
                        constraints: BoxConstraints(
                          minWidth: size.width * 0.090,
                          minHeight: size.width * 0.090,
                        ),
                        icon: Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Text(
                      'Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: size.width * 0.044,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    final isKeyboardReadOnly = onTap != null || !_editing || readOnly;

    return Padding(
      padding: EdgeInsets.only(bottom: visibleHeight * 0.009),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: size.width * 0.029,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: visibleHeight * 0.003),
          TextField(
            controller: controller,
            inputFormatters: const [SanitizingTextInputFormatter()],
            readOnly: isKeyboardReadOnly,
            onTap: (_editing && !readOnly && onTap != null) ? onTap : null,
            onChanged: (_) => _checkChanges(),
            style: TextStyle(
              color: (!_editing || readOnly)
                  ? Colors.grey.shade700
                  : Colors.black,
              fontWeight: FontWeight.w500,
              fontSize: size.width * 0.034,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(
                icon,
                color: const Color(0xFFE6A050),
                size: size.width * 0.051,
              ),
              filled: true,
              fillColor: (!_editing || readOnly)
                  ? Colors.grey.shade50
                  : Colors.white,
              contentPadding: EdgeInsets.symmetric(
                vertical: visibleHeight * 0.008,
                horizontal: size.width * 0.044,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(size.width * 0.077),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(size.width * 0.077),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(size.width * 0.077),
                borderSide: BorderSide(
                  color: const Color(0xFF1B3D3D),
                  width: size.width * 0.004,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
