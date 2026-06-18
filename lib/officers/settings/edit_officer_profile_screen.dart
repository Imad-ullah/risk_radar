import 'dart:io';
import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/services/logger_service.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/services/sync_service.dart';
import 'package:riskradar/shared/security/input_sanitizer.dart';
import 'package:riskradar/shared/utils/profile_photo_permission.dart';

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
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
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
    if (user == null || !mounted) {
      return;
    }

    final cached = OfficerRepository.instance.getOfficerProfile();
    if (cached != null) {
      _applyOfficerData(cached);
      if (mounted) {
        setState(() => _loading = false);
      }
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
    } on SocketException catch (e) {
      LoggerService.warning(
        'Officer edit profile offline - using cached profile.',
        e,
      );
    } catch (e, s) {
      LoggerService.error('Error loading officer profile for edit', e, s);
    }

    if (mounted) {
      setState(() => _loading = false);
    }
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
    final currentDob =
        _birthYear != null && _birthDay != null && currentMonthIndex != -1
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
                leading: Icon(Icons.photo_library),
                title: Text('Photo Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
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
    if (!mounted) {
      return;
    }

    final bool hasPermission = await requestProfilePhotoPermission(
      context,
      source,
    );
    if (!hasPermission) {
      return;
    }

    final picked = await ImagePicker().pickImage(source: source);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _saveProfile() async {
    if (_saving || !_hasChanges || !mounted) {
      return;
    }
    setState(() => _saving = true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _saving = false);
      }
      return;
    }

    if (_firstName.text.trim().isEmpty ||
        _lastName.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _birthDay == null ||
        _birthMonth == null ||
        _birthYear == null) {
      _showMessage('Please fill in all required fields', isError: true);
      if (mounted) {
        setState(() => _saving = false);
      }
      return;
    }

    final firstNameError = InputSanitizer.validateName(_firstName.text);
    final lastNameError = InputSanitizer.validateName(_lastName.text);
    if (firstNameError != null || lastNameError != null) {
      _showMessage(
        firstNameError ?? lastNameError ?? InputSanitizer.invalidInputMessage,
        isError: true,
      );
      if (mounted) {
        setState(() => _saving = false);
      }
      return;
    }

    final firstName = InputSanitizer.cleanText(_firstName.text, maxLength: 50);
    final lastName = InputSanitizer.cleanText(_lastName.text, maxLength: 50);
    final dob =
        '${_birthYear!}-${(_months.indexOf(_birthMonth!) + 1).toString().padLeft(2, '0')}-${_birthDay!.padLeft(2, '0')}';

    final updateData = {
      'id': user.id,
      'first_name': firstName,
      'last_name': lastName,
      'email': _email.text.trim(),
      'dob': dob,
      'profile_image_url': _imageUrl,
      if (_imageFile != null) 'image_paths': [_imageFile!.path],
    };

    try {
      await _syncRepository.enqueueAction(
        id: 'officer_profile_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        table: 'officers',
        action: 'update',
        payload: updateData,
      );

      await OfficerRepository.instance.saveOfficerProfile({
        'role': 'officer',
        'officer_uid': _officerUID,
        ...updateData,
      });

      final syncResult = await SyncService.instance.run();
      final savedOffline =
          syncResult.reason != null ||
          syncResult.hasFailures ||
          syncResult.pending > 0;

      _showMessage(
        savedOffline
            ? 'Profile saved offline - will sync when online'
            : 'Profile updated!',
      );
      if (!savedOffline) {
        await _loadOfficerData();
      }
      _imageFile = null;

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e, s) {
      LoggerService.error('Error updating officer profile', e, s);
      _showMessage(
        'Could not update profile. Please try again.',
        isError: true,
      );
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError ? Colors.red.shade700 : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Edit Officer Profile')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(R.blockH * 5),
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
                                  '${_imageUrl!}?ts=${DateTime.now().millisecondsSinceEpoch}',
                                )
                              : const AssetImage('assets/default_user.png')
                                    as ImageProvider),
                    backgroundColor: _imageUrl == null && _imageFile == null
                        ? Colors.grey
                        : null,
                    child: (_imageUrl == null && _imageFile == null)
                        ? Icon(Icons.person, size: 50, color: Colors.white)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.all(R.blockH * 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: R.blockV * 2.5),
            _buildTextField("First Name", _firstName),
            _buildTextField("Last Name", _lastName),
            _buildTextField("Email", _email, type: TextInputType.emailAddress),
            SizedBox(height: R.blockV * 1.25),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Date of Birth",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: R.blockV * 1),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    "Day",
                    _days,
                    _birthDay,
                    (v) => setState(() => _birthDay = v),
                  ),
                ),
                SizedBox(width: R.blockH * 2.133),
                Expanded(
                  child: _buildDropdown(
                    "Month",
                    _months,
                    _birthMonth,
                    (v) => setState(() => _birthMonth = v),
                  ),
                ),
                SizedBox(width: R.blockH * 2.133),
                Expanded(
                  child: _buildDropdown(
                    "Year",
                    _years,
                    _birthYear,
                    (v) => setState(() => _birthYear = v),
                  ),
                ),
              ],
            ),
            SizedBox(height: R.blockV * 1.875),
            if (_officerUID != null)
              Padding(
                padding: EdgeInsets.only(bottom: R.blockV * 2.5),
                child: Text(
                  "Officer UID: $_officerUID",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            SizedBox(height: R.blockV * 1.25),
            ElevatedButton.icon(
              onPressed: (!_hasChanges || _saving) ? null : _saveProfile,
              icon: _saving
                  ? SizedBox(
                      width: R.blockH * 4.8,
                      height: R.blockV * 2.25,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.save),
              label: Text(_saving ? "Saving..." : "Save"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: _hasChanges && !_saving
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    TextInputType? type,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: R.blockV * 1.875),
      child: TextField(
        controller: controller,
        keyboardType: type,
        inputFormatters: const [SanitizingTextInputFormatter()],
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String? selected,
    void Function(String?) onChanged,
  ) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(),
      ),
      initialValue: selected,
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: (v) {
        onChanged(v);
        setState(() {}); // so save button reacts
      },
    );
  }
}
