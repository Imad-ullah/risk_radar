import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:riskradar/services/logger_service.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/services/sync_service.dart';
import 'package:riskradar/shared/hazards/voice_note_recorder.dart';
import 'package:riskradar/shared/models/hazard.dart';
import 'package:riskradar/shared/theme/app_colors.dart';
import 'package:riskradar/shared/widgets/risk_radar_loader.dart';

class HseWorkerResolutionFormScreen extends StatefulWidget {
  const HseWorkerResolutionFormScreen({
    super.key,
    required this.hazard,
  });

  final Hazard hazard;

  @override
  State<HseWorkerResolutionFormScreen> createState() =>
      _HseWorkerResolutionFormScreenState();
}

class _HseWorkerResolutionFormScreenState
    extends State<HseWorkerResolutionFormScreen> {
  static const int _maxResolutionPhotos = 3;
  static const int _reportNumberModulo = 100000;
  static const String _notesRequiredMessage =
      'Resolution notes are required.';
  static const String _photoRequiredMessage =
      'Capture at least one resolution photo.';
  static const String _maxPhotoMessage =
      'You can attach up to 3 resolution photos.';
  static const String _stopRecordingMessage = 'Please stop recording first.';
  static const String _stopPlaybackMessage = 'Please stop playback first.';
  static const String _genericSubmitError =
      'Failed to submit resolution. Please try again.';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<VoiceNoteRecorderState> _voiceRecorderKey =
      GlobalKey<VoiceNoteRecorderState>();
  final TextEditingController _notesController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final HazardRepository _hazardRepository = HazardRepository();
  final SyncRepository _syncRepository = SyncRepository();

  final List<XFile> _selectedPhotos = <XFile>[];
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  String? _photoError;
  bool _isSubmitting = false;
  bool _isRecording = false;
  bool _isAudioPlaying = false;

  @override
  void initState() {
    super.initState();
    _notesController.addListener(_handleFormChanged);
  }

  @override
  void dispose() {
    _notesController.removeListener(_handleFormChanged);
    _notesController.dispose();
    super.dispose();
  }

  void _handleFormChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String? _validateNotes(String? value) {
    final String notes = value?.trim() ?? '';
    return notes.isEmpty ? _notesRequiredMessage : null;
  }

  String? _validatePhotos() {
    if (_selectedPhotos.isEmpty) {
      return _photoRequiredMessage;
    }
    if (_selectedPhotos.length > _maxResolutionPhotos) {
      return _maxPhotoMessage;
    }
    return null;
  }

  bool get _canSubmit {
    return !_isSubmitting &&
        !_isRecording &&
        !_isAudioPlaying &&
        _validateNotes(_notesController.text) == null &&
        _validatePhotos() == null;
  }

  void _handleRecordingStateChanged(bool isRecording) {
    if (!mounted) return;
    setState(() => _isRecording = isRecording);
  }

  void _handlePlaybackStateChanged(bool isPlaying) {
    if (!mounted) return;
    setState(() => _isAudioPlaying = isPlaying);
  }

  void _toggleRecording() {
    if (_isAudioPlaying) {
      _showErrorSnack(_stopPlaybackMessage);
      return;
    }

    if (_isRecording) {
      _voiceRecorderKey.currentState?.stopRecording();
    } else {
      _voiceRecorderKey.currentState?.startRecording();
    }
  }

  Future<void> _pickPhoto() async {
    if (_isRecording || _isAudioPlaying) {
      _showErrorSnack(
        _isRecording ? _stopRecordingMessage : _stopPlaybackMessage,
      );
      return;
    }

    if (_selectedPhotos.length >= _maxResolutionPhotos) {
      setState(() => _photoError = _maxPhotoMessage);
      _showErrorSnack(_maxPhotoMessage);
      return;
    }

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (!mounted || photo == null) {
        return;
      }

      setState(() {
        _selectedPhotos.add(photo);
        _photoError = _validatePhotos();
      });
    } catch (e, s) {
      LoggerService.error('[HSE Resolution] Photo capture failed', e, s);
      if (!mounted) return;
      _showErrorSnack('Failed to capture photo: $e');
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _selectedPhotos.removeAt(index);
      _photoError = _validatePhotos();
    });
  }

  Future<void> _submitResolution() async {
    if (_isSubmitting) {
      return;
    }

    if (_isRecording || _isAudioPlaying) {
      _showErrorSnack(
        _isRecording ? _stopRecordingMessage : _stopPlaybackMessage,
      );
      return;
    }

    final bool isNotesValid = _formKey.currentState?.validate() ?? false;
    final String? photoError = _validatePhotos();
    setState(() {
      _autovalidateMode = AutovalidateMode.onUserInteraction;
      _photoError = photoError;
    });

    if (!isNotesValid || photoError != null) {
      _showErrorSnack('Please fix the highlighted fields before submitting.');
      return;
    }

    final String? assignmentId = widget.hazard.id;
    if (assignmentId == null || assignmentId.isEmpty) {
      _showErrorSnack('This task is missing an assignment id.');
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final String resolvedAt = DateTime.now().toUtc().toIso8601String();
    final List<File> voiceFiles =
        _voiceRecorderKey.currentState?.getAllRecordedFiles() ?? <File>[];
    final String reportNumber = _generateReportNumber();
    final Map<String, Object?> payload = <String, Object?>{
      'id': assignmentId,
      'status': 'resolved',
      'resolved_at': resolvedAt,
      'resolution_notes': _notesController.text.trim(),
      'report_number': reportNumber,
      'image_paths': _selectedPhotos.map((XFile photo) => photo.path).toList(),
      'voice_paths': voiceFiles.map((File file) => file.path).toList(),
    };

    try {
      await _syncRepository.enqueueAction(
        id: 'hse_resolution_${assignmentId}_${const Uuid().v4()}',
        table: 'assign_hazards',
        action: 'update',
        payload: payload,
      );

      await _applyResolutionLocally(payload);
      final SyncResult syncResult = await SyncService.instance.run();

      if (!mounted) {
        return;
      }

      setState(() => _isSubmitting = false);
      final bool savedOffline = syncResult.reason != null ||
          syncResult.hasFailures ||
          syncResult.pending > 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedOffline
                ? 'Resolution saved offline. It will sync when online.'
                : 'Resolution submitted successfully.',
          ),
          backgroundColor:
              savedOffline ? Colors.orange.shade700 : AppColors.brandTeal,
        ),
      );
      Navigator.pop(context, true);
    } catch (e, s) {
      LoggerService.error('[HSE Resolution] Submit failed', e, s);
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showErrorSnack(_genericSubmitError);
    }
  }

  Future<void> _applyResolutionLocally(Map<String, Object?> payload) async {
    final List<Map<String, Object?>> cachedTasks =
        (await _hazardRepository.getHseAssignedTasks() ??
                <Map<String, Object?>>[])
            .map((row) => Map<String, Object?>.from(row))
            .toList();
    Map<String, Object?> resolvedTask = <String, Object?>{
      ...widget.hazard.toAssignHazardsMap(),
      ...payload,
    };

    for (final Map<String, Object?> task in cachedTasks) {
      if (task['id']?.toString() == widget.hazard.id) {
        task.addAll(payload);
        resolvedTask = Map<String, Object?>.from(task);
      }
    }

    await _hazardRepository.saveHseAssignedTasks(cachedTasks);

    final List<Map<String, Object?>> resolvedTasks =
        (await _hazardRepository.getHseResolvedHazards() ??
                <Map<String, Object?>>[])
            .map((row) => Map<String, Object?>.from(row))
            .toList();
    resolvedTasks.removeWhere(
      (Map<String, Object?> task) => task['id']?.toString() == widget.hazard.id,
    );
    resolvedTasks.insert(0, resolvedTask);
    await _hazardRepository.saveHseResolvedHazards(resolvedTasks);
  }

  String _generateReportNumber() {
    final DateTime now = DateTime.now();
    final int numericSuffix =
        now.microsecondsSinceEpoch.remainder(_reportNumberModulo);
    return 'RR-${now.year}-${numericSuffix.toString().padLeft(5, '0')}';
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.grey.shade900 : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Resolve Hazard'),
        centerTitle: true,
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: _autovalidateMode,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            _buildHazardSummary(isDark),
            const SizedBox(height: 20),
            _buildNotesField(isDark),
            const SizedBox(height: 20),
            _buildPhotoSection(isDark),
            const SizedBox(height: 20),
            _buildVoiceNoteSection(isDark),
            const SizedBox(height: 28),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _canSubmit ? _submitResolution : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandTeal,
                  disabledBackgroundColor: Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSubmitting
                    ? const RiskRadarLoader(color: Colors.white, size: 28)
                    : const Text(
                        'Submit Resolution',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHazardSummary(bool isDark) {
    final String hazardType = widget.hazard.hazardType ?? 'General Hazard';
    final String severity = widget.hazard.severity ?? 'Unknown severity';
    final String description =
        widget.hazard.description ?? 'No description provided.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  color: AppColors.accentGold,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      hazardType,
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.brandTeal,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      severity,
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: TextStyle(
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesField(bool isDark) {
    return _buildSectionCard(
      isDark: isDark,
      title: 'Resolution Notes',
      icon: Icons.edit_note_rounded,
      child: TextFormField(
        controller: _notesController,
        validator: _validateNotes,
        maxLines: 5,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: 'Describe the corrective actions taken...',
          filled: true,
          fillColor: isDark ? Colors.grey.shade800 : AppColors.backgroundLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          errorMaxLines: 2,
        ),
      ),
    );
  }

  Widget _buildPhotoSection(bool isDark) {
    return _buildSectionCard(
      isDark: isDark,
      title: 'Resolution Photos',
      icon: Icons.camera_alt_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_selectedPhotos.isEmpty)
            _buildAddPhotoTile(isDark)
          else
            SizedBox(
              height: 126,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedPhotos.length +
                    (_selectedPhotos.length < _maxResolutionPhotos ? 1 : 0),
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (BuildContext context, int index) {
                  if (index == _selectedPhotos.length) {
                    return _buildCompactAddPhotoTile(isDark);
                  }
                  return _buildPhotoPreview(index);
                },
              ),
            ),
          _buildInlineError(_photoError ?? _validatePhotos()),
        ],
      ),
    );
  }

  Widget _buildAddPhotoTile(bool isDark) {
    return InkWell(
      onTap: _pickPhoto,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 132,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accentGold),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.add_a_photo_rounded,
              color: AppColors.accentGold,
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              'Capture resolution photo',
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.brandTeal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactAddPhotoTile(bool isDark) {
    return InkWell(
      onTap: _pickPhoto,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 108,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accentGold),
        ),
        child: const Icon(
          Icons.add_a_photo_rounded,
          color: AppColors.accentGold,
        ),
      ),
    );
  }

  Widget _buildPhotoPreview(int index) {
    final XFile photo = _selectedPhotos[index];
    return SizedBox(
      width: 108,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.file(File(photo.path), fit: BoxFit.cover),
            Positioned(
              top: 6,
              right: 6,
              child: InkWell(
                onTap: () => _removePhoto(index),
                child: const CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceNoteSection(bool isDark) {
    return _buildSectionCard(
      isDark: isDark,
      title: 'Voice Note',
      icon: Icons.mic_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Optional. Add extra context for officers reviewing the closure.',
            style: TextStyle(
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isAudioPlaying ? null : _toggleRecording,
            icon: Icon(
              _isRecording ? Icons.stop_circle_rounded : Icons.mic_rounded,
            ),
            label: Text(_isRecording ? 'Stop Recording' : 'Record Voice Note'),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  _isRecording ? Colors.red.shade700 : AppColors.brandTeal,
              side: BorderSide(
                color: _isRecording ? Colors.red.shade700 : AppColors.brandTeal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          VoiceNoteRecorder(
            key: _voiceRecorderKey,
            onRecordingStateChanged: _handleRecordingStateChanged,
            onPlaybackStateChanged: _handlePlaybackStateChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: AppColors.brandTeal),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : AppColors.brandTeal,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildInlineError(String? message) {
    if (message == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        message,
        style: TextStyle(
          color: Colors.red.shade700,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
