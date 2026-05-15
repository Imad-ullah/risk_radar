// lib/workers/screens/worker_emergency_details_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
          SnackBar(
            content: Text('Failed to load details: ${e.toString()}'),
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
      'contact_name': _contactNameController.text.trim(),
      'relationship': _relationshipController.text.trim(),
      'phone': phoneNumbers,
      'blood_type': _bloodType,
      'allergies': _allergiesController.text.trim(),
      'chronic_conditions': _conditionsController.text.trim(),
      'ambulance': _ambulanceController.text.trim(),
      'fire_brigade': _fireBrigadeController.text.trim(),
    };

    try {
      await Supabase.instance.client
          .from('worker_emergency_contacts')
          .upsert(data, onConflict: 'worker_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Emergency details saved successfully!'),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving details: $e'),
              backgroundColor: Colors.red),
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
    // Detect Theme
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Define colors based on theme
    final bgColor = isDark ? const Color(0xFF121212) : AppColors.backgroundLight;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('My Emergency Details',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        // Standardized Back Button
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _relationshipController,
                    label: 'Relationship',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  ..._phoneControllers.asMap().entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _buildTextField(
                        controller: entry.value,
                        label: 'Phone Number ${entry.key + 1}',
                        isDark: isDark,
                        inputType: TextInputType.phone,
                        suffixIcon: _phoneControllers.length > 1
                            ? IconButton(
                          icon: const Icon(Icons.remove_circle,
                              color: Colors.redAccent),
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
                      icon: const Icon(Icons.add_rounded,
                          color: AppColors.brandTeal),
                      label: const Text(
                        'Add Number',
                        style: TextStyle(
                            color: AppColors.brandTeal,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionCard(
                title: 'Medical Information',
                icon: Icons.medical_services_rounded,
                isDark: isDark,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _bloodType,
                    items: [
                      'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
                    ]
                        .map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(
                            type,
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87
                            )
                        )
                    ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _bloodType = value),
                    dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                    decoration: _inputDecoration('Blood Type', isDark),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _allergiesController,
                    label: 'Allergies',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _conditionsController,
                    label: 'Chronic Conditions',
                    isDark: isDark,
                  ),
                ],
              ),
              const SizedBox(height: 20),
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
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _fireBrigadeController,
                    label: 'Fire Brigade Number',
                    isDark: isDark,
                    inputType: TextInputType.phone,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _saveEmergencyDetails,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    'Save My Details',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brandTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.brandTeal, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
      style: TextStyle(color: isDark ? Colors.white : Colors.black87), // Fix text visibility
      decoration: _inputDecoration(label, isDark).copyWith(suffixIcon: suffixIcon),
      keyboardType: inputType,
      validator: validator,
    );
  }

  InputDecoration _inputDecoration(String label, bool isDark) {
    // Dynamic colors for Dark/Light mode
    final fillColor = isDark ? const Color(0xFF2C2C2C) : Colors.grey[50];
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;
    final labelColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: labelColor),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
