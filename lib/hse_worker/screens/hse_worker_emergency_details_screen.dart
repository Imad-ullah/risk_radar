// lib/hse_workers/screens/hse_worker_emergency_details_screen.dart
import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/shared/security/input_sanitizer.dart';
import 'package:riskradar/shared/theme/app_colors.dart'; // Standardized color import

class HSEWorkerEmergencyDetailsScreen extends StatefulWidget {
  final String hseWorkerId;

  const HSEWorkerEmergencyDetailsScreen({super.key, required this.hseWorkerId});

  @override
  State<HSEWorkerEmergencyDetailsScreen> createState() =>
      _HSEWorkerEmergencyDetailsScreenState();
}

class _HSEWorkerEmergencyDetailsScreenState
    extends State<HSEWorkerEmergencyDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _supervisorController = TextEditingController();
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
    _supervisorController.dispose();
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
          .from('hse_emergency_contacts')
          .select()
          .eq('hse_worker_id', widget.hseWorkerId)
          .maybeSingle();

      if (response != null) {
        final data = response;
        _supervisorController.text = data['supervisor'] ?? '';
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
      debugPrint('Error loading HSE emergency details: $e');
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
      'hse_worker_id': widget.hseWorkerId,
      'supervisor': InputSanitizer.cleanText(
        _supervisorController.text,
        maxLength: 80,
      ),
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
          .from('hse_emergency_contacts')
          .upsert(data, onConflict: 'hse_worker_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('HSE Emergency details updated!'),
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
    R.init(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF121212)
        : AppColors.backgroundLight;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          'Emergency Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                children: [
                  _buildSectionCard(
                    isDark: isDark,
                    title: 'Hierarchy & Supervision',
                    icon: Icons.admin_panel_settings_rounded,
                    children: [
                      _buildTextField(
                        isDark: isDark,
                        controller: _supervisorController,
                        label: 'Site Contractor / Supervisor Number',
                        inputType: TextInputType.phone,
                        validator: (value) => value!.isEmpty
                            ? 'Supervisor number required'
                            : null,
                      ),
                    ],
                  ),

                  _buildSectionCard(
                    isDark: isDark,
                    title: 'Personal Emergency Contact',
                    icon: Icons.person_pin_rounded,
                    children: [
                      _buildTextField(
                        isDark: isDark,
                        controller: _contactNameController,
                        label: 'Primary Contact Name',
                        validator: (value) =>
                            value!.isEmpty ? 'Name is required' : null,
                      ),
                      SizedBox(height: R.blockV * 2),
                      _buildTextField(
                        isDark: isDark,
                        controller: _relationshipController,
                        label: 'Relationship',
                      ),
                      SizedBox(height: R.blockV * 2),
                      ..._phoneControllers.asMap().entries.map((entry) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: R.blockV * 1.5),
                          child: _buildTextField(
                            isDark: isDark,
                            controller: entry.value,
                            label: 'Contact Phone ${entry.key + 1}',
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
                            validator: (value) =>
                                value!.isEmpty ? 'Number is required' : null,
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
                            'Add Phone Number',
                            style: TextStyle(
                              color: AppColors.brandTeal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  _buildSectionCard(
                    isDark: isDark,
                    title: 'Medical Information',
                    icon: Icons.medical_services_rounded,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _bloodType,
                        dropdownColor: isDark
                            ? const Color(0xFF2C2C2C)
                            : Colors.white,
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
                        decoration: _inputDecoration('Blood Type', isDark),
                      ),
                      SizedBox(height: R.blockV * 2),
                      _buildTextField(
                        isDark: isDark,
                        controller: _allergiesController,
                        label: 'Allergies',
                      ),
                      SizedBox(height: R.blockV * 2),
                      _buildTextField(
                        isDark: isDark,
                        controller: _conditionsController,
                        label: 'Chronic Conditions',
                      ),
                    ],
                  ),

                  _buildSectionCard(
                    isDark: isDark,
                    title: 'Quick Emergency Services',
                    icon: Icons.emergency_rounded,
                    children: [
                      _buildTextField(
                        isDark: isDark,
                        controller: _ambulanceController,
                        label: 'Ambulance Service',
                        inputType: TextInputType.phone,
                      ),
                      SizedBox(height: R.blockV * 2),
                      _buildTextField(
                        isDark: isDark,
                        controller: _fireBrigadeController,
                        label: 'Fire Brigade',
                        inputType: TextInputType.phone,
                      ),
                    ],
                  ),

                  SizedBox(height: R.blockV * 4),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _saveEmergencyDetails,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: R.blockV * 2.25,
                        ),
                        backgroundColor: AppColors.brandTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: Text(
                        'UPDATE EMERGENCY PROFILE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: R.blockV * 5),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: R.blockV * 3),
      padding: EdgeInsets.all(R.blockH * 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(R.blockH * 2),
                decoration: BoxDecoration(
                  color: AppColors.brandTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.accentGold, size: 24),
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
    required bool isDark,
    required TextEditingController controller,
    required String label,
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
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: isDark ? Colors.grey[400] : Colors.grey[600],
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[50],
      contentPadding: EdgeInsets.symmetric(
        horizontal: R.blockH * 4,
        vertical: R.blockV * 2,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.brandTeal, width: 2),
      ),
    );
  }
}
