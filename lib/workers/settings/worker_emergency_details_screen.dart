// lib/workers/screens/worker_emergency_details_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/shared/security/input_sanitizer.dart';
import 'package:riskradar/shared/theme/app_colors.dart';

class WorkerEmergencyDetailsScreen extends StatefulWidget {
  final String workerId;

  const WorkerEmergencyDetailsScreen({super.key, required this.workerId});

  @override
  State<WorkerEmergencyDetailsScreen> createState() =>
      _WorkerEmergencyDetailsScreenState();
}

class _WorkerEmergencyDetailsScreenState
    extends State<WorkerEmergencyDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();
  final TextEditingController _conditionsController = TextEditingController();
  final TextEditingController _ambulanceController = TextEditingController();
  final TextEditingController _fireBrigadeController = TextEditingController();

  List<TextEditingController> _phoneControllers = [];
  String? _bloodType;
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
    for (final controller in _phoneControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEmergencyDetails() async {
    setState(() => _loading = true);
    try {
      final response = await Supabase.instance.client
          .from('worker_emergency_contacts')
          .select()
          .eq('worker_id', widget.workerId)
          .maybeSingle();

      if (response != null) {
        final data = response;
        _contactNameController.text = data['contact_name'] ?? '';
        _relationshipController.text = data['relationship'] ?? '';
        _bloodType = data['blood_type'];
        _allergiesController.text = data['allergies'] ?? '';
        _conditionsController.text = data['chronic_conditions'] ?? '';
        _ambulanceController.text = data['ambulance'] ?? '';
        _fireBrigadeController.text = data['fire_brigade'] ?? '';

        final phones = (data['phone'] as String?)?.split(',') ?? [];
        _phoneControllers = phones
            .where((p) => p.isNotEmpty)
            .map((p) => TextEditingController(text: p))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading worker emergency details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load emergency details. Please try again.',
            ),
            backgroundColor: Colors.red,
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

  Future<void> _saveEmergencyDetails() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final phoneNumbers = _phoneControllers
        .map((c) => c.text.trim())
        .where((e) => e.isNotEmpty)
        .join(',');

    final data = {
      'worker_id': widget.workerId,
      'contact_name': InputSanitizer.cleanText(
        _contactNameController.text,
        maxLength: 80,
      ),
      'relationship': InputSanitizer.cleanText(
        _relationshipController.text,
        maxLength: 80,
      ),
      'phone': phoneNumbers,
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
    };

    try {
      await Supabase.instance.client
          .from('worker_emergency_contacts')
          .upsert(data, onConflict: 'worker_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Emergency details saved successfully!'),
            backgroundColor: Colors.green,
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
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    // Detect Theme
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Define colors based on theme
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
        // Standardized Back Button
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: size.width * 0.040,
                vertical: visibleHeight * 0.004,
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
                        SizedBox(height: visibleHeight * 0.005),
                        _buildTextField(
                          controller: _relationshipController,
                          label: 'Relationship',
                          isDark: isDark,
                        ),
                        SizedBox(height: visibleHeight * 0.005),
                        ..._phoneControllers.asMap().entries.map((entry) {
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: visibleHeight * 0.005,
                            ),
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
                              color: AppColors.accentGold,
                            ),
                            label: Text(
                              'Add Number',
                              style: TextStyle(
                                color: AppColors.accentGold,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: visibleHeight * 0.006),
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
                        SizedBox(height: visibleHeight * 0.005),
                        _buildTextField(
                          controller: _allergiesController,
                          label: 'Allergies',
                          isDark: isDark,
                        ),
                        SizedBox(height: visibleHeight * 0.005),
                        _buildTextField(
                          controller: _conditionsController,
                          label: 'Chronic Conditions',
                          isDark: isDark,
                        ),
                      ],
                    ),
                    SizedBox(height: visibleHeight * 0.006),
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
                        SizedBox(height: visibleHeight * 0.005),
                        _buildTextField(
                          controller: _fireBrigadeController,
                          label: 'Fire Brigade Number',
                          isDark: isDark,
                          inputType: TextInputType.phone,
                        ),
                      ],
                    ),
                    SizedBox(height: visibleHeight * 0.008),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _saveEmergencyDetails,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentGold,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: visibleHeight * 0.011,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              size.width * 0.041,
                            ),
                          ),
                          elevation: size.width * 0.011,
                        ),
                        child: Text(
                          'Save My Details',
                          style: TextStyle(
                            fontSize: size.width * 0.035,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: visibleHeight * 0.006),
                  ],
                ),
              ),
            ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(size.width * 0.038),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: size.width * 0.027,
            offset: Offset(size.width * 0.0, visibleHeight * 0.005),
          ),
        ],
      ),
      padding: EdgeInsets.all(size.width * 0.024),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(size.width * 0.010),
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(size.width * 0.018),
                ),
                child: Icon(
                  icon,
                  color: AppColors.accentGold,
                  size: size.width * 0.046,
                ),
              ),
              SizedBox(width: size.width * 0.020),
              Text(
                title,
                style: TextStyle(
                  fontSize: size.width * 0.036,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: visibleHeight * 0.006),
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
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
      ), // Fix text visibility
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
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    // Dynamic colors for Dark/Light mode
    final fillColor = isDark ? const Color(0xFF2C2C2C) : Colors.grey[50];
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;
    final labelColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: labelColor),
      filled: true,
      fillColor: fillColor,
      contentPadding: EdgeInsets.symmetric(
        horizontal: size.width * 0.030,
        vertical: visibleHeight * 0.005,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(size.width * 0.031),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(size.width * 0.031),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(size.width * 0.031),
        borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(size.width * 0.031),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
    );
  }
}
