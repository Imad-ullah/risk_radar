// lib/hse_workers/screens/hazard_resolution_verification_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/shared/hazards/voice_note_recorder.dart';
import 'package:riskradar/shared/security/input_sanitizer.dart';
import 'package:riskradar/shared/theme/app_colors.dart';

class HazardResolutionVerificationScreen extends StatefulWidget {
  final Map<String, dynamic> taskData;
  final String assignmentId;

  const HazardResolutionVerificationScreen({
    super.key,
    required this.taskData,
    required this.assignmentId,
  });

  @override
  State<HazardResolutionVerificationScreen> createState() =>
      _HazardResolutionVerificationScreenState();
}

class _HazardResolutionVerificationScreenState
    extends State<HazardResolutionVerificationScreen> {
  final TextEditingController _workDoneController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final HazardRepository _hazardRepository = HazardRepository();
  final SyncRepository _syncRepository = SyncRepository();

  final List<XFile> _selectedImages = [];

  bool _isSubmitting = false;
  bool _hasNotes = false;
  bool _hasVoiceNote = false;

  // Voice Recording States
  final GlobalKey<VoiceNoteRecorderState> _voiceRecorderKey =
      GlobalKey<VoiceNoteRecorderState>();
  bool _isRecording = false;
  bool _isAudioPlaying = false;

  // Semantic Colors
  static const Color _successGreen = Color(0xFF10B981);
  static const Color _errorColor = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _workDoneController.addListener(() {
      setState(() {
        _hasNotes = _workDoneController.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _workDoneController.dispose();
    super.dispose();
  }

  // --- Voice State Handlers ---
  void _handleRecordingStateChanged(bool isRecording) {
    if (mounted) {
      setState(() => _isRecording = isRecording);
    }
  }

  void _handlePlaybackStateChanged(bool isPlaying) {
    if (mounted) setState(() => _isAudioPlaying = isPlaying);
  }

  void _toggleRecording() {
    if (_isAudioPlaying) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please stop playback first.")),
      );
      return;
    }

    if (_isRecording) {
      _voiceRecorderKey.currentState?.stopRecording();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _hasVoiceNote =
                _voiceRecorderKey.currentState
                    ?.getAllRecordedFiles()
                    .isNotEmpty ??
                false;
          });
        }
      });
    } else {
      _voiceRecorderKey.currentState?.startRecording();
    }
  }

  // --- Image Picking (Camera Only, Multiple Allowed) ---
  Future<void> _pickImage() async {
    if (_isRecording || _isAudioPlaying) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isRecording
                ? "Please stop recording first."
                : "Please stop playback first.",
            style: const TextStyle(
              color: AppColors.brandTeal,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: AppColors.accentGold,
        ),
      );
      return;
    }

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (pickedFile != null && mounted) {
        setState(() {
          _selectedImages.add(pickedFile);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to open camera. Please try again.'),
          backgroundColor: _errorColor,
        ),
      );
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  // --- Submission Logic ---
  Future<bool> _isOnline() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _submitVerification() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Step 1: Please capture at least one live site photo.',
            style: TextStyle(
              color: AppColors.brandTeal,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: AppColors.accentGold,
        ),
      );
      return;
    }
    if (!_hasNotes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Step 2: Please describe the work done.',
            style: TextStyle(
              color: AppColors.brandTeal,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: AppColors.accentGold,
        ),
      );
      return;
    }
    final String? notesError = InputSanitizer.validateLongText(
      _workDoneController.text,
      maxLength: 800,
    );
    if (notesError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notesError), backgroundColor: _errorColor),
      );
      return;
    }
    if (_isRecording || _isAudioPlaying) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please stop recording/playback before submitting.",
            style: TextStyle(
              color: AppColors.brandTeal,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: AppColors.accentGold,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final resolvedTimestamp = DateTime.now().toUtc().toIso8601String();
      final resolutionNotes = InputSanitizer.cleanText(
        _workDoneController.text,
        maxLength: 800,
      );
      final recordedVoiceFiles =
          _voiceRecorderKey.currentState?.getAllRecordedFiles() ?? [];

      if (!await _isOnline()) {
        final payload = {
          'id': widget.assignmentId,
          'status': 'resolved',
          'resolved_at': resolvedTimestamp,
          'resolution_notes': resolutionNotes,
          'image_paths': _selectedImages.map((image) => image.path).toList(),
          'voice_paths': recordedVoiceFiles.map((file) => file.path).toList(),
        };

        await _syncRepository.enqueueAction(
          id: 'hse_resolution_${widget.assignmentId}_${DateTime.now().millisecondsSinceEpoch}',
          table: 'assign_hazards',
          action: 'update',
          payload: payload,
        );
        await _applyResolutionLocally(payload);

        if (mounted) {
          await _showSuccessDialog();
          if (mounted) Navigator.pop(context, true);
        }
        return;
      }

      final supabase = Supabase.instance.client;
      List<String> imageUrls = [];
      List<String> voiceNoteUrls = [];
      List<Future> uploadTasks = [];

      // Upload Images
      for (var imageFile in _selectedImages) {
        final fileBytes = await imageFile.readAsBytes();
        final fileName = "${const Uuid().v4()}_${widget.assignmentId}.jpg";

        uploadTasks.add(
          supabase.storage
              .from('resolutions')
              .uploadBinary(fileName, fileBytes)
              .then((_) {
                final imageUrl = supabase.storage
                    .from('resolutions')
                    .getPublicUrl(fileName);
                imageUrls.add(imageUrl);
              }),
        );
      }

      // Upload Voice Notes
      for (final voiceFile in recordedVoiceFiles) {
        final fileName =
            "${const Uuid().v4()}_${voiceFile.path.split('/').last}";

        uploadTasks.add(
          supabase.storage.from('resolutions').upload(fileName, voiceFile).then(
            (_) {
              final voiceUrl = supabase.storage
                  .from('resolutions')
                  .getPublicUrl(fileName);
              voiceNoteUrls.add(voiceUrl);
            },
          ),
        );
      }

      if (uploadTasks.isNotEmpty) {
        await Future.wait(uploadTasks);
      }

      // Update Database
      final updateData = {
        'status': 'resolved',
        'resolved_at': resolvedTimestamp,
        'resolution_notes': resolutionNotes,
        'resolution_image_url': imageUrls.isNotEmpty
            ? imageUrls.join(',')
            : null,
        'resolution_voice_note_url': voiceNoteUrls.isNotEmpty
            ? voiceNoteUrls.join(',')
            : null,
      };
      await supabase
          .from('assign_hazards')
          .update(updateData)
          .eq('id', widget.assignmentId);
      await _applyResolutionLocally({'id': widget.assignmentId, ...updateData});

      // Success
      if (mounted) {
        await _showSuccessDialog();
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      debugPrint("Submit Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to submit resolution. Please try again.'),
            backgroundColor: _errorColor,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _applyResolutionLocally(Map<String, dynamic> updateData) async {
    final cachedTasks = await _hazardRepository.getHseAssignedTasks() ?? [];
    Map<String, dynamic>? resolvedTask;

    for (final task in cachedTasks) {
      if (task['id']?.toString() == widget.assignmentId) {
        task.addAll(updateData);
        resolvedTask = Map<String, dynamic>.from(task);
      }
    }

    await _hazardRepository.saveHseAssignedTasks(cachedTasks);

    final resolved = await _hazardRepository.getHseResolvedHazards() ?? [];
    resolvedTask ??= {...widget.taskData, ...updateData};
    resolved.removeWhere(
      (item) => item['id']?.toString() == widget.assignmentId,
    );
    resolved.insert(0, resolvedTask);
    await _hazardRepository.saveHseResolvedHazards(resolved);
  }

  // --- Custom Success Dialog (✅ UPDATED TO MATCH APP POPUP THEME) ---
  Future<void> _showSuccessDialog() async {
    HapticFeedback.heavyImpact();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.brandTeal,
                  Color(0xDA1B3D3D), // brandTeal with alpha: 0.85
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: _successGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "All done!",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Hazard has been marked as safe and updated in the log.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) Navigator.pop(context);
  }

  // --- UI Building ---
  @override
  Widget build(BuildContext context) {
    final hazardType = widget.taskData['hazard_type'] ?? 'General Hazard';
    final description =
        widget.taskData['description'] ?? 'No description provided';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 1,
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        title: const Text(
          "Get Verified",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- Header Hero Section ---
              Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    size: 80,
                    color: AppColors.accentGold,
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(
                      Icons.star,
                      size: 20,
                      color: (isDark ? Colors.white : AppColors.brandTeal)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: -10,
                    child: Icon(
                      Icons.star,
                      size: 16,
                      color: (isDark ? Colors.white : AppColors.brandTeal)
                          .withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                "Complete steps to resolve",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.brandTeal,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Submit live photos & details to close this hazard\nand verify the site is safe.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // --- Hazard Context Card ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey.shade800
                            : AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.accentGold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hazardType,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.brandTeal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // --- Step 1: Photo Verification (Multiple) ---
              _buildStepCard(
                title: "Live Site Photos",
                icon: Icons.camera_alt_outlined,
                isComplete: _selectedImages.isNotEmpty,
                content: _buildPhotoSection(isDark),
              ),
              const SizedBox(height: 16),

              // --- Step 2: Work Completed Notes ---
              _buildStepCard(
                title: "Resolution Notes",
                icon: Icons.edit_document,
                isComplete: _hasNotes,
                content: Container(
                  margin: const EdgeInsets.only(top: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.grey.shade800
                        : AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _workDoneController,
                    inputFormatters: const <TextInputFormatter>[
                      SanitizingTextInputFormatter(),
                    ],
                    maxLines: 4,
                    textInputAction: TextInputAction.done,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: "Describe actions taken...",
                      hintStyle: TextStyle(
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // --- Step 3: Voice Notes (Optional) ---
              _buildStepCard(
                title: "Voice Notes (Optional)",
                icon: Icons.mic_none,
                isComplete: _hasVoiceNote,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _toggleRecording,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: _isRecording
                              ? Colors.red.withValues(alpha: 0.1)
                              : (isDark
                                    ? Colors.grey.shade800
                                    : AppColors.backgroundLight),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isRecording
                                ? Colors.red
                                : (isDark
                                      ? Colors.grey.shade700
                                      : Colors.grey.shade300),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isRecording ? Icons.stop_circle : Icons.mic,
                              color: _isRecording
                                  ? Colors.red
                                  : (isDark
                                        ? Colors.white
                                        : AppColors.brandTeal),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isRecording
                                  ? "Tap to Stop Recording"
                                  : "Tap to Record Voice Note",
                              style: TextStyle(
                                color: _isRecording
                                    ? Colors.red
                                    : (isDark
                                          ? Colors.white
                                          : AppColors.brandTeal),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    VoiceNoteRecorder(
                      key: _voiceRecorderKey,
                      onRecordingStateChanged: _handleRecordingStateChanged,
                      onPlaybackStateChanged: _handlePlaybackStateChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // --- Submit Button ---
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandTeal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                    shadowColor: AppColors.brandTeal.withValues(alpha: 0.4),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Text(
                          "Submit Details",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper: Horizontal Photo List ---
  Widget _buildPhotoSection(bool isDark) {
    if (_selectedImages.isEmpty) {
      return GestureDetector(
        onTap: _pickImage,
        child: Container(
          height: 140,
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade800 : AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.add_a_photo,
                  color: isDark ? Colors.white : AppColors.brandTeal,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Tap to open camera",
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : AppColors.brandTeal,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 120,
      margin: const EdgeInsets.only(top: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length + 1,
        itemBuilder: (context, index) {
          if (index == _selectedImages.length) {
            return GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 100,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.shade800
                      : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo,
                      color: isDark ? Colors.white : AppColors.brandTeal,
                      size: 24,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Add More",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : AppColors.brandTeal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final imageFile = _selectedImages[index];
          return Container(
            width: 100,
            margin: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(imageFile.path), fit: BoxFit.cover),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeImage(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Helper Widget: Checklist Step Card ---
  Widget _buildStepCard({
    required String title,
    required IconData icon,
    required bool isComplete,
    required Widget content,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: isDark ? Colors.white : AppColors.brandTeal,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.brandTeal,
                  ),
                ),
              ),
              if (isComplete)
                const Icon(Icons.check_circle, color: _successGreen, size: 24)
              else
                Icon(
                  Icons.radio_button_unchecked,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                  size: 24,
                ),
            ],
          ),
          content,
        ],
      ),
    );
  }
}
