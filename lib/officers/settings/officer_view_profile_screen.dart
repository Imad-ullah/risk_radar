import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/shared/widgets/full_image_viewer.dart';

class OfficerViewProfileScreen extends StatefulWidget {
  const OfficerViewProfileScreen({super.key});

  @override
  State<OfficerViewProfileScreen> createState() => _OfficerViewProfileScreenState();
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
    if (!mounted) return;
    setState(() => _loading = true);

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final cached = OfficerRepository.instance.getOfficerProfile();
    if (cached != null) {
      _applyProfileData(cached, inferOnly: true);
    }

    try {
      final worker = await _supabase.from('workers').select().eq('id', userId).maybeSingle();
      if (worker != null) {
        _profileTable = 'workers';
        _applyProfileData(worker);
      } else {
        final officer = await _supabase.from('officers').select().eq('id', userId).maybeSingle();
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

    if (mounted) setState(() => _loading = false);
  }

  String _resolveDobKey(Map<String, dynamic> data) {
    if (data.containsKey('dob')) return 'dob';
    if (data.containsKey('date_of_birth')) return 'date_of_birth';
    if (data.containsKey('birth_date')) return 'birth_date';
    return 'dob';
  }

  String _readDobValue(Map<String, dynamic> data) {
    return data['dob']?.toString() ??
        data['date_of_birth']?.toString() ??
        data['birth_date']?.toString() ??
        '';
  }

  void _applyProfileData(Map<String, dynamic> data, {bool inferOnly = false}) {
    _dobKey = _resolveDobKey(data);
    _initialData = Map<String, dynamic>.from(data);

    _firstNameController.text = data['first_name']?.toString() ?? '';
    _lastNameController.text = data['last_name']?.toString() ?? '';
    _emailController.text = data['email']?.toString() ?? '';
    _dobController.text = _readDobValue(data);
    _workTypeController.text = data['work_type']?.toString() ?? data['role']?.toString() ?? '';
    _officerUidController.text = data['officer_uid']?.toString() ?? '';

    if (!inferOnly) {
      _hasChanges = false;
    }
  }

  void _checkChanges() {
    if (_initialData == null) return;
    final originalDob = _readDobValue(_initialData!);
    setState(() {
      _hasChanges =
          _firstNameController.text != (_initialData!['first_name']?.toString() ?? '') ||
          _lastNameController.text != (_initialData!['last_name']?.toString() ?? '') ||
          _dobController.text != originalDob ||
          _workTypeController.text !=
              (_initialData!['work_type']?.toString() ?? _initialData!['role']?.toString() ?? '');
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
    if (croppedFile != null) return File(croppedFile.path);
    return null;
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (image == null) return;

      final croppedImage = await _cropImage(File(image.path));
      if (croppedImage == null) return;

      setState(() => _uploadingImage = true);

      final userId = _supabase.auth.currentUser!.id;
      final fileExt = image.path.split('.').last;
      final fileName = '$userId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await _supabase.storage.from('profile-images').upload(
        fileName,
        croppedImage,
        fileOptions: const FileOptions(upsert: true),
      );

      final publicUrl = _supabase.storage.from('profile-images').getPublicUrl(fileName);

      await _supabase.from(_profileTable).update({
        'profile_image_url': publicUrl,
      }).eq('id', userId);

      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated!')),
        );
      }
    } catch (e) {
      debugPrint('Upload Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
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
    if (userId == null) return;

    setState(() => _updating = true);
    try {
      final updatePayload = {
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        _dobKey: _dobController.text.trim(),
      };

      if (_profileTable == 'workers') {
        updatePayload['work_type'] = _workTypeController.text.trim();
      }

      await _supabase.from(_profileTable).update(updatePayload).eq('id', userId);

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
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  String _capitalize(String? s) {
    if (s == null || s.isEmpty) return 'N/A';
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_initialData == null) return const Scaffold(body: Center(child: Text('Profile not found')));

    const tealColor = Color(0xFF1B3D3D);
    const goldColor = Color(0xFFE6A050);
    final imageUrl = _initialData!['profile_image_url']?.toString();
    final fullName =
        '${_capitalize(_firstNameController.text)} ${_capitalize(_lastNameController.text)}'.trim();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 280,
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
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 60, bottom: 40),
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
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: Hero(
                              tag: imageUrl ?? 'officer_profile_pic',
                              child: CircleAvatar(
                                radius: 60,
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                                    ? NetworkImage(imageUrl)
                                    : null,
                                child: _uploadingImage
                                    ? const CircularProgressIndicator(color: tealColor)
                                    : (imageUrl == null || imageUrl.isEmpty)
                                        ? const Icon(Icons.person, size: 60, color: Colors.grey)
                                        : null,
                              ),
                            ),
                          ),
                        ),
                        if (_editing)
                          GestureDetector(
                            onTap: _pickAndUploadImage,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: goldColor,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        fullName.isEmpty ? 'Officer Profile' : fullName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => setState(() => _editing = !_editing),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_editing ? Icons.close : Icons.edit, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    (_initialData!['role']?.toString() ?? 'Officer').toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'OFFICER DETAILS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: tealColor,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildStyledTextField('First Name', _firstNameController, Icons.person_outline),
                        _buildStyledTextField('Last Name', _lastNameController, Icons.person_outline),
                        _buildStyledTextField('Email ID', _emailController, Icons.email_outlined, readOnly: true),
                        _buildStyledTextField('Date of Birth', _dobController, Icons.calendar_today_outlined, onTap: _selectDate),
                        _buildStyledTextField('Role / Work Type', _workTypeController, Icons.engineering_outlined),
                        _buildStyledTextField('Officer UID', _officerUidController, Icons.admin_panel_settings_outlined, readOnly: true),
                        const SizedBox(height: 30),
                        if (_editing)
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              onPressed: _hasChanges && !_updating ? _updateProfile : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: goldColor,
                                disabledBackgroundColor: Colors.grey.shade300,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                elevation: 5,
                              ),
                              child: _updating
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text(
                                      'SAVE DETAILS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
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
          Positioned(
            top: 0,
            left: 20,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.pop(context),
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
    final isKeyboardReadOnly = onTap != null || !_editing || readOnly;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            readOnly: isKeyboardReadOnly,
            onTap: (_editing && !readOnly && onTap != null) ? onTap : null,
            onChanged: (_) => _checkChanges(),
            style: TextStyle(
              color: (!_editing || readOnly) ? Colors.grey.shade700 : Colors.black,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: const Color(0xFFE6A050)),
              filled: true,
              fillColor: (!_editing || readOnly) ? Colors.grey.shade50 : Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
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
                borderSide: const BorderSide(color: Color(0xFF1B3D3D), width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
