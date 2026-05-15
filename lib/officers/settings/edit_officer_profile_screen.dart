import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/services/supabase_service.dart'; // **Ensure this path is correct**
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';

class EditOfficerProfileScreen extends StatefulWidget {
  const EditOfficerProfileScreen({super.key});

  @override
  State<EditOfficerProfileScreen> createState() =>
      _EditOfficerProfileScreenState();
}

class _EditOfficerProfileScreenState extends State<EditOfficerProfileScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  String? _birthDay, _birthMonth, _birthYear, _officerUID, _imageUrl;
  File? _imageFile;
  bool _loading = true;
  bool _saving = false;
  final SyncRepository _syncRepository = SyncRepository();

  Map<String, dynamic> _originalData = {};

  final _days = List.generate(31, (i) => '${i + 1}');
  final _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final _years = List.generate(80, (i) => '${DateTime.now().year - i}');

  @override
  void initState() {
    super.initState();
    _loadOfficerData();
    _firstName.addListener(() => setState(() {}));
    _lastName.addListener(() => setState(() {}));
    _email.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _loadOfficerData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !mounted) return;

    final cached = OfficerRepository.instance.getOfficerProfile();
    if (cached != null) {
      _applyOfficerData(cached);
      if (mounted) setState(() => _loading = false);
    }

    try {
      final res = await Supabase.instance.client
          .from('officers')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (res != null) {
        _applyOfficerData(res);
        await OfficerRepository.instance.saveOfficerProfile(res);
      }
    } on SocketException {
      debugPrint('Officer edit profile offline - using cached profile.');
    } catch (e) {
      debugPrint('Error loading officer profile for edit: $e');
    }

    if(mounted) setState(() => _loading = false);
  }

  void _applyOfficerData(Map<String, dynamic> data) {
    _firstName.text = data['first_name'] ?? '';
    _lastName.text = data['last_name'] ?? '';
    _email.text = data['email'] ?? '';
    _imageUrl = data['profile_image_url']?.toString();
    _officerUID = data['officer_uid']?.toString();

    final dob = DateTime.tryParse(data['dob']?.toString() ?? '');
    if (dob != null) {
      _birthDay = '${dob.day}';
      _birthMonth = _months[dob.month - 1];
      _birthYear = '${dob.year}';
    }

    _originalData = {
      'first_name': _firstName.text,
      'last_name': _lastName.text,
      'email': _email.text,
      'dob': dob?.toIso8601String().split('T').first,
      'profile_image_url': _imageUrl,
    };
  }

  bool get _hasChanges {
    final originalDob = _originalData['dob']?.toString() ?? '';
    final currentMonthIndex = _months.indexOf(_birthMonth ?? '');
    final currentDob = _birthYear != null && _birthDay != null && currentMonthIndex != -1
        ? '${_birthYear!}-${(currentMonthIndex + 1).toString().padLeft(2, '0')}-${_birthDay!.padLeft(2, '0')}'
        : '';

    return _firstName.text.trim() != (_originalData['first_name'] ?? '') ||
        _lastName.text.trim() != (_originalData['last_name'] ?? '') ||
        _email.text.trim() != (_originalData['email'] ?? '') ||
        currentDob != originalDob ||
        _imageFile != null;
  }

  // --- NEW: Image Source Selector ---
  void _selectImageSource() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }
  // --- END: Image Source Selector ---

  Future<void> _pickImage(ImageSource source) async {
    if (!mounted) return;

    // Determine the required permission based on the source
    Permission requiredPermission;
    if (source == ImageSource.camera) {
      requiredPermission = Permission.camera;
    } else {
      // Using Permission.photos for gallery access
      requiredPermission = Permission.photos;
    }

    final status = await requiredPermission.request();

    if (!status.isGranted && mounted) {
      _showMessage('Permission denied. Please enable access in settings.');
      // Open app settings if permission is permanently denied
      if (status.isPermanentlyDenied) {
        openAppSettings();
      }
      return;
    }

    // Proceed only if permission is granted
    if (status.isGranted) {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked != null) {
        setState(() => _imageFile = File(picked.path));
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_saving || !_hasChanges || !mounted) return;
    setState(() => _saving = true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if(mounted) setState(() => _saving = false);
      return;
    }

    if (_firstName.text.trim().isEmpty ||
        _lastName.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _birthDay == null ||
        _birthMonth == null ||
        _birthYear == null) {
      _showMessage('Please fill in all required fields');
      if(mounted) setState(() => _saving = false);
      return;
    }

    String? finalImageUrl = _imageUrl;
    if (_imageFile != null) {
      final uploaded = await SupabaseService().uploadProfileImage(
        _imageFile!,
        _firstName.text,
        _lastName.text,
      );
      if (uploaded != null) {
        finalImageUrl = uploaded;
        // Invalidate old URL cache by updating the state variable
        _imageUrl = uploaded;
      }
    }

    final dob =
        '${_birthYear!}-${(_months.indexOf(_birthMonth!) + 1).toString().padLeft(2, '0')}-${_birthDay!.padLeft(2, '0')}';

    final updateData = {
      'first_name': _firstName.text.trim(),
      'last_name': _lastName.text.trim(),
      'email': _email.text.trim(),
      'dob': dob,
      'profile_image_url': finalImageUrl,
    };

    try {
      await Supabase.instance.client
          .from('officers')
          .update(updateData)
          .eq('id', user.id);

      await OfficerRepository.instance.saveOfficerProfile({
        'id': user.id,
        'role': 'officer',
        'officer_uid': _officerUID,
        ...updateData,
      });

      _showMessage("✅ Profile updated!");
      await _loadOfficerData();
      _imageFile = null;

      // Close the edit screen upon successful save
      if(mounted) Navigator.pop(context, true);

    } on SocketException {
      final offlinePayload = {
        'id': user.id,
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'email': _email.text.trim(),
        'dob': dob,
        'profile_image_url': _imageUrl,
        if (_imageFile != null) 'image_paths': [_imageFile!.path],
      };
      await _syncRepository.enqueueAction(
        id: 'officer_profile_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        table: 'officers',
        action: 'update',
        payload: offlinePayload,
      );
      await OfficerRepository.instance.saveOfficerProfile({
        'role': 'officer',
        'officer_uid': _officerUID,
        ...offlinePayload,
      });
      _showMessage('Profile saved offline - will sync when online');
      if(mounted) Navigator.pop(context, true);

    } catch (e) {
      _showMessage("❌ Error updating profile: $e");
    }

    if(mounted) setState(() => _saving = false);
  }

  void _showMessage(String msg) {
    if(mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Officer Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              // *** UPDATED: Call the image source selection method ***
              onTap: _selectImageSource,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: _imageFile != null
                        ? FileImage(_imageFile!)
                        : (_imageUrl != null && _imageUrl!.isNotEmpty
                        ? NetworkImage(
                        '${_imageUrl!}?ts=${DateTime.now().millisecondsSinceEpoch}')
                        : const AssetImage('assets/default_user.png')
                    as ImageProvider),
                    backgroundColor: _imageUrl == null && _imageFile == null ? Colors.grey : null,
                    child: (_imageUrl == null && _imageFile == null) ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildTextField("First Name", _firstName),
            _buildTextField("Last Name", _lastName),
            _buildTextField("Email", _email, type: TextInputType.emailAddress),
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Date of Birth", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown("Day", _days, _birthDay,
                          (v) => setState(() => _birthDay = v)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDropdown("Month", _months, _birthMonth,
                          (v) => setState(() => _birthMonth = v)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDropdown("Year", _years, _birthYear,
                          (v) => setState(() => _birthYear = v)),
                ),
              ],
            ),
            const SizedBox(height: 15),
            if (_officerUID != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text("Officer UID: $_officerUID",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: (!_hasChanges || _saving) ? null : _saveProfile,
              icon: _saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.save),
              label: Text(_saving ? "Saving..." : "Save"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: _hasChanges && !_saving ? Theme.of(context).colorScheme.primary : Colors.grey,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: controller,
        keyboardType: type,
        decoration:
        InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Widget _buildDropdown(
      String label, List<String> items, String? selected, void Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      decoration:
      InputDecoration(labelText: label, border: const OutlineInputBorder()),
      initialValue: selected,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: (v) {
        onChanged(v);
        setState(() {}); // so save button reacts
      },
    );
  }
}

