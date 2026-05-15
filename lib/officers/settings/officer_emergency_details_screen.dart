// lib/officer_emergency_details_screen.dart
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';

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

  // Controllers
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
    // Dispose all controllers to prevent memory leaks
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

  // --- Data Logic (Unchanged) ---
  Future<void> _loadEmergencyDetails() async {
    setState(() => _loading = true);
    final cached =
        OfficerRepository.instance.getOfficerEmergencyDetails(widget.officerId);
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
          SnackBar(content: Text('Failed to load details: ${e.toString()}')),
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
      'contact_name': _contactNameController.text.trim(),
      'relationship': _relationshipController.text.trim(),
      'personal': phoneNumbers,
      'blood_type': _bloodType,
      'allergies': _allergiesController.text.trim(),
      'chronic_conditions': _conditionsController.text.trim(),
      'ambulance': _ambulanceController.text.trim(),
      'fire_brigade': _fireBrigadeController.text.trim(),
      'supervisor': _supervisorController.text.trim(),
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
        {
          if (_emergencyId != null) 'id': _emergencyId,
          ...data,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Emergency details saved successfully'),
          backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } on SocketException {
      final offlineId = _emergencyId ?? const Uuid().v4();
      final offlineData = {
        'id': offlineId,
        ...data,
      };
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
            content: Text('Emergency details saved offline - will sync when online'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving emergency details: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _addPhoneNumber() {
    setState(() {
      _phoneControllers.add(TextEditingController());
    });
  }

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

  // --- UI Build Method ---
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // A theme-aware input decoration with dark borders
    final inputDecoration = InputDecoration(
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: colorScheme.outline, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: colorScheme.primary, width: 2.0),
      ),
      filled: true,
      fillColor: colorScheme.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Emergency Details'),
        backgroundColor: colorScheme.surfaceContainerLowest,
        elevation: 0,
        foregroundColor: colorScheme.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          children: [
            _buildSectionCard(
              context: context,
              title: 'Personal Contact',
              icon: Icons.person_rounded,
              children: [
                TextFormField(
                  controller: _contactNameController,
                  decoration: inputDecoration.copyWith(
                      labelText: 'Contact Name',
                      hintText: 'e.g., Jane Doe'),
                  validator: (value) =>
                  value!.isEmpty ? 'Please enter a contact name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _relationshipController,
                  decoration: inputDecoration.copyWith(
                      labelText: 'Relationship',
                      hintText: 'e.g., Spouse, Sibling'),
                ),
                const SizedBox(height: 16),
                ..._phoneControllers.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: TextFormField(
                      controller: entry.value,
                      decoration: inputDecoration.copyWith(
                        labelText: 'Phone Number ${entry.key + 1}',
                        suffixIcon: IconButton(
                          icon: Icon(
                              _phoneControllers.length > 1
                                  ? Icons.remove_circle_outline
                                  : Icons.add_circle_outline,
                              color: _phoneControllers.length > 1
                                  ? colorScheme.error
                                  : colorScheme.primary),
                          onPressed: () => _phoneControllers.length > 1
                              ? _removePhoneNumber(entry.key)
                              : _addPhoneNumber(),
                        ),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) => value!.isEmpty
                          ? 'Please enter a phone number'
                          : null,
                    ),
                  );
                }),
              ],
            ),
            _buildSectionCard(
              context: context,
              title: 'Medical Information',
              icon: Icons.medical_services_rounded,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _bloodType,
                  items: [
                    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
                  ]
                      .map((type) =>
                      DropdownMenuItem(value: type, child: Text(type)))
                      .toList(),
                  onChanged: (value) => setState(() => _bloodType = value),
                  decoration:
                  inputDecoration.copyWith(labelText: 'Blood Type'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _allergiesController,
                  decoration: inputDecoration.copyWith(
                      labelText: 'Allergies',
                      hintText: 'e.g., Penicillin, Peanuts'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _conditionsController,
                  decoration: inputDecoration.copyWith(
                      labelText: 'Chronic Conditions',
                      hintText: 'e.g., Asthma, Diabetes'),
                ),
              ],
            ),
            _buildSectionCard(
              context: context,
              title: 'Emergency Services',
              icon: Icons.local_hospital_rounded,
              children: [
                TextFormField(
                  controller: _ambulanceController,
                  decoration:
                  inputDecoration.copyWith(labelText: 'Ambulance Number'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fireBrigadeController,
                  decoration: inputDecoration.copyWith(
                      labelText: 'Fire Brigade Number'),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
            _buildSectionCard(
              context: context,
              title: 'Contact For Workers',
              icon: Icons.work_rounded,
              children: [
                Text(
                  'This number will be visible to your Team for emergency contact.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _supervisorController,
                  decoration: inputDecoration.copyWith(
                    labelText: 'Your Contact Number',
                    hintText: 'Enter professional contact number',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) => value!.trim().isEmpty
                      ? 'This contact number is required'
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loading ? null : _saveEmergencyDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Save All Details'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// A cleaner, more minimalist card widget.
  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 20),
      // ✅ Shape no longer has a 'side' property, removing the border.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: colorScheme.outline,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(icon,
                        color: colorScheme.onPrimaryContainer, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 16, thickness: 0.5),
            ...children,
          ],
        ),
      ),
    );
  }
}

