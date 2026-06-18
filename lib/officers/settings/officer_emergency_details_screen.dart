// lib/officer_emergency_details_screen.dart
import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/shared/security/input_sanitizer.dart';
import 'package:riskradar/shared/theme/app_colors.dart';

class OfficerEmergencyDetailsScreen extends StatefulWidget {
  final String officerId;

  const OfficerEmergencyDetailsScreen({super.key, required this.officerId});

  @override
  State<OfficerEmergencyDetailsScreen> createState() =>
      _OfficerEmergencyDetailsScreenState();
}

class _OfficerEmergencyDetailsScreenState
    extends State<OfficerEmergencyDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final SyncRepository _syncRepository = SyncRepository();

  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();
  final TextEditingController _conditionsController = TextEditingController();
  final TextEditingController _ambulanceController = TextEditingController();
  final TextEditingController _fireBrigadeController = TextEditingController();
  final TextEditingController _supervisorController = TextEditingController();

  List<TextEditingController> _phoneControllers = [];
  String? _bloodType;
  String? _emergencyId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEmergencyDetails();
  }

  @override
  void dispose() {
    _contactNameController.dispose();
    _relationshipController.dispose();
    _allergiesController.dispose();
    _conditionsController.dispose();
    _ambulanceController.dispose();
    _fireBrigadeController.dispose();
    _supervisorController.dispose();
    for (final controller in _phoneControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEmergencyDetails() async {
    setState(() => _loading = true);
    final cached = OfficerRepository.instance.getOfficerEmergencyDetails(
      widget.officerId,
    );
    if (cached != null) {
      _applyEmergencyDetails(cached);
      if (mounted) setState(() => _loading = false);
    }

    try {
      final response = await Supabase.instance.client
          .from('officer_emergency_contacts')
          .select()
          .eq('officer_id', widget.officerId)
          .maybeSingle();

      if (response != null) {
        _applyEmergencyDetails(response);
        await OfficerRepository.instance.saveOfficerEmergencyDetails(
          widget.officerId,
          response,
        );
      }
    } on SocketException {
      debugPrint('Officer emergency details offline - using cached data.');
    } catch (e) {
      debugPrint('Error loading officer emergency details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load emergency details. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (_phoneControllers.isEmpty) {
        _phoneControllers.add(TextEditingController());
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _applyEmergencyDetails(Map<String, dynamic> data) {
    _emergencyId = data['id']?.toString();
    _contactNameController.text = data['contact_name'] ?? '';
    _relationshipController.text = data['relationship'] ?? '';
    _bloodType = data['blood_type'];
    _allergiesController.text = data['allergies'] ?? '';
    _conditionsController.text = data['chronic_conditions'] ?? '';
    _ambulanceController.text = data['ambulance'] ?? '';
    _fireBrigadeController.text = data['fire_brigade'] ?? '';
    _supervisorController.text = data['supervisor'] ?? '';

    for (final controller in _phoneControllers) {
      controller.dispose();
    }
    final phones = (data['personal'] as String?)?.split(',') ?? [];
    _phoneControllers = phones
        .where((p) => p.isNotEmpty)
        .map((p) => TextEditingController(text: p))
        .toList();
  }

  Future<void> _saveEmergencyDetails() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final phoneNumbers = _phoneControllers
        .map((c) => c.text.trim())
        .where((e) => e.isNotEmpty)
        .join(',');

    final data = {
      'officer_id': widget.officerId,
      'contact_name': InputSanitizer.cleanText(
        _contactNameController.text,
        maxLength: 80,
      ),
      'relationship': InputSanitizer.cleanText(
        _relationshipController.text,
        maxLength: 80,
      ),
      'personal': phoneNumbers,
      'blood_type': _bloodType,
      'allergies': InputSanitizer.cleanText(
        _allergiesController.text,
        maxLength: 300,
      ),
      'chronic_conditions': InputSanitizer.cleanText(
        _conditionsController.text,
        maxLength: 300,
      ),
      'ambulance': InputSanitizer.cleanText(
        _ambulanceController.text,
        maxLength: 40,
      ),
      'fire_brigade': InputSanitizer.cleanText(
        _fireBrigadeController.text,
        maxLength: 40,
      ),
      'supervisor': InputSanitizer.cleanText(
        _supervisorController.text,
        maxLength: 80,
      ),
    };

    try {
      if (_emergencyId != null) {
        await Supabase.instance.client
            .from('officer_emergency_contacts')
            .update(data)
            .eq('id', _emergencyId!);
      } else {
        await Supabase.instance.client
            .from('officer_emergency_contacts')
            .insert(data);
      }
      await OfficerRepository.instance.saveOfficerEmergencyDetails(
        widget.officerId,
        {if (_emergencyId != null) 'id': _emergencyId, ...data},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Emergency details saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } on SocketException {
      final offlineId = _emergencyId ?? const Uuid().v4();
      final offlineData = {'id': offlineId, ...data};
      await _syncRepository.enqueueAction(
        id: 'officer_emergency_${widget.officerId}_${DateTime.now().millisecondsSinceEpoch}',
        table: 'officer_emergency_contacts',
        action: _emergencyId == null ? 'insert' : 'update',
        payload: offlineData,
      );
      _emergencyId = offlineId;
      await OfficerRepository.instance.saveOfficerEmergencyDetails(
        widget.officerId,
        offlineData,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Emergency details saved offline - will sync when online',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not save emergency details. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _addPhoneNumber() =>
      setState(() => _phoneControllers.add(TextEditingController()));

  void _removePhoneNumber(int index) {
    setState(() {
      if (_phoneControllers.length > 1) {
        _phoneControllers[index].dispose();
        _phoneControllers.removeAt(index);
      } else {
        _phoneControllers[0].clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF121212)
        : AppColors.backgroundLight;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          'My Emergency Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: R.blockH * 4,
                vertical: R.blockV * 3,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildSectionCard(
                      title: 'Personal Emergency Contact',
                      icon: Icons.person_pin_rounded,
                      isDark: isDark,
                      children: [
                        _buildTextField(
                          controller: _contactNameController,
                          label: 'Contact Name',
                          isDark: isDark,
                          validator: (value) => value!.isEmpty
                              ? 'Please enter a contact name'
                              : null,
                        ),
                        SizedBox(height: R.blockV * 2),
                        _buildTextField(
                          controller: _relationshipController,
                          label: 'Relationship',
                          isDark: isDark,
                        ),
                        SizedBox(height: R.blockV * 2),
                        ..._phoneControllers.asMap().entries.map((entry) {
                          return Padding(
                            padding: EdgeInsets.only(bottom: R.blockV * 1.5),
                            child: _buildTextField(
                              controller: entry.value,
                              label: 'Phone Number ${entry.key + 1}',
                              isDark: isDark,
                              inputType: TextInputType.phone,
                              suffixIcon: _phoneControllers.length > 1
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.remove_circle,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () =>
                                          _removePhoneNumber(entry.key),
                                    )
                                  : null,
                              validator: (value) => value!.isEmpty
                                  ? 'Please enter a phone number'
                                  : null,
                            ),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _addPhoneNumber,
                            icon: Icon(
                              Icons.add_rounded,
                              color: AppColors.brandTeal,
                            ),
                            label: Text(
                              'Add Number',
                              style: TextStyle(
                                color: AppColors.brandTeal,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: R.blockV * 2.5),
                    _buildSectionCard(
                      title: 'Medical Information',
                      icon: Icons.medical_services_rounded,
                      isDark: isDark,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _bloodType,
                          items:
                              ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                                  .map(
                                    (type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(
                                        type,
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) =>
                              setState(() => _bloodType = value),
                          dropdownColor: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.white,
                          decoration: _inputDecoration('Blood Type', isDark),
                        ),
                        SizedBox(height: R.blockV * 2),
                        _buildTextField(
                          controller: _allergiesController,
                          label: 'Allergies',
                          isDark: isDark,
                        ),
                        SizedBox(height: R.blockV * 2),
                        _buildTextField(
                          controller: _conditionsController,
                          label: 'Chronic Conditions',
                          isDark: isDark,
                        ),
                      ],
                    ),
                    SizedBox(height: R.blockV * 2.5),
                    _buildSectionCard(
                      title: 'Emergency Services',
                      icon: Icons.local_hospital_rounded,
                      isDark: isDark,
                      children: [
                        _buildTextField(
                          controller: _ambulanceController,
                          label: 'Ambulance Number',
                          isDark: isDark,
                          inputType: TextInputType.phone,
                        ),
                        SizedBox(height: R.blockV * 2),
                        _buildTextField(
                          controller: _fireBrigadeController,
                          label: 'Fire Brigade Number',
                          isDark: isDark,
                          inputType: TextInputType.phone,
                        ),
                      ],
                    ),
                    SizedBox(height: R.blockV * 2.5),
                    _buildSectionCard(
                      title: 'Contact For Workers',
                      icon: Icons.work_rounded,
                      isDark: isDark,
                      children: [
                        Text(
                          'This number will be visible to your Team for emergency contact.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[700],
                              ),
                        ),
                        SizedBox(height: R.blockV * 2),
                        _buildTextField(
                          controller: _supervisorController,
                          label: 'Your Contact Number',
                          isDark: isDark,
                          inputType: TextInputType.phone,
                          validator: (value) => value!.trim().isEmpty
                              ? 'This contact number is required'
                              : null,
                        ),
                      ],
                    ),
                    SizedBox(height: R.blockV * 4),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _saveEmergencyDetails,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandTeal,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: R.blockV * 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                        ),
                        child: Text(
                          'Save My Details',
                          style: TextStyle(
                            fontSize: R.blockH * 4,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: R.blockV * 2.5),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(R.blockH * 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(R.blockH * 2),
                decoration: BoxDecoration(
                  color: AppColors.brandTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.brandTeal, size: 22),
              ),
              SizedBox(width: R.blockH * 3.2),
              Text(
                title,
                style: TextStyle(
                  fontSize: R.blockH * 4.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: R.blockV * 2.5),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required bool isDark,
    TextInputType inputType = TextInputType.text,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      inputFormatters: const [SanitizingTextInputFormatter()],
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: _inputDecoration(
        label,
        isDark,
      ).copyWith(suffixIcon: suffixIcon),
      keyboardType: inputType,
      validator: (value) =>
          validator?.call(value) ??
          InputSanitizer.validateLongText(
            value,
            required: false,
            maxLength: 300,
          ),
    );
  }

  InputDecoration _inputDecoration(String label, bool isDark) {
    final fillColor = isDark ? const Color(0xFF2C2C2C) : Colors.grey[50];
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;
    final labelColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: labelColor),
      filled: true,
      fillColor: fillColor,
      contentPadding: EdgeInsets.symmetric(
        horizontal: R.blockH * 4,
        vertical: R.blockV * 1.75,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.brandTeal, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
    );
  }
}
