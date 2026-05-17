// lib/workers/screens/worker_hazard_report_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import 'package:riskradar/shared/hazards/select_hazard_type_screen.dart';
import 'package:riskradar/workers/screens/worker_home_screen.dart';
import 'package:riskradar/shared/hazards/voice_note_recorder.dart';
import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/services/logger_service.dart';

class WorkerReportHazardScreen extends StatefulWidget {
  final VoidCallback? onHazardReported;

  // Parameters to accept AI Data
  final File? initialImage;
  final String? initialDescription;
  final String? initialSeverity;
  final List<String>? initialHazardTypes;

  const WorkerReportHazardScreen({
    super.key,
    this.onHazardReported,
    this.initialImage,
    this.initialDescription,
    this.initialSeverity,
    this.initialHazardTypes,
  });

  @override
  State<WorkerReportHazardScreen> createState() =>
      _WorkerReportHazardScreenState();
}

class _WorkerReportHazardScreenState extends State<WorkerReportHazardScreen> {
  static const int _descriptionMinLength = 10;
  static const int _descriptionMaxLength = 500;
  static const String _hazardTypeRequiredMessage =
      'Select at least one hazard type.';
  static const String _descriptionRequiredMessage =
      'Describe the hazard before submitting.';
  static const String _descriptionTooShortMessage =
      'Description must be at least 10 characters.';
  static const String _descriptionTooLongMessage =
      'Description must be 500 characters or fewer.';
  static const String _severityRequiredMessage = 'Select a severity level.';
  static const String _locationRequiredMessage =
      'Location is required before submitting.';
  static const String _locationDeniedMessage =
      'Location permission denied. Enable location access to report a hazard.';
  static const String _locationServiceDisabledMessage =
      'Location services are disabled. Turn them on to report a hazard.';
  static const String _photoRequiredMessage =
      'Capture at least one photo of the hazard.';
  static const String _formValidationMessage =
      'Please fix the highlighted fields before submitting.';
  static const String _stopRecordingMessage = 'Please stop recording first.';
  static const String _stopPlaybackMessage = 'Please stop playback first.';
  static const Set<String> _allowedSeverityLevels = <String>{
    'Low',
    'Moderate',
    'High',
  };

  // State variables
  List<String> _selectedHazardTypes = [];
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _descriptionController = TextEditingController();
  String _severity = 'Low';
  final List<XFile> _selectedImages = [];
  Position? _currentPosition;
  bool _isSubmitting = false;
  bool _isLoadingLocation = false;
  AutovalidateMode _autovalidateMode = AutovalidateMode.onUserInteraction;
  String? _hazardTypeError;
  String? _severityError;
  String? _locationError;
  String? _imageError;
  bool _hasSubmittedOnce = false;
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  final AuthRepository _authRepository = AuthRepository();
  final HazardRepository _hazardRepository = HazardRepository();
  final SyncRepository _syncRepository = SyncRepository();

  // Worker details
  String? _currentSiteId;
  String? _officerUid;

  // Recorder/player interaction
  final GlobalKey<VoiceNoteRecorderState> _voiceRecorderKey =
  GlobalKey<VoiceNoteRecorderState>();
  bool _isRecording = false;
  bool _isAudioPlaying = false;

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(_handleDescriptionChanged);
    _getCurrentLocation();
    _fetchWorkerDetails();

    if (widget.initialDescription != null) {
      _descriptionController.text = widget.initialDescription!;
    }
    if (widget.initialSeverity != null) {
      _severity = _normalizeSeverity(widget.initialSeverity!);
    }
    if (widget.initialHazardTypes != null) {
      _selectedHazardTypes = widget.initialHazardTypes!;
    }
    if (widget.initialImage != null) {
      _selectedImages.add(XFile(widget.initialImage!.path));
    }
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_handleDescriptionChanged);
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleDescriptionChanged() {
    if (!mounted) return;
    if (_hasSubmittedOnce) {
      _formKey.currentState?.validate();
    }
    setState(() {});
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FETCH WORKER DETAILS — cache first, Supabase fallback
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _fetchWorkerDetails() async {
    if (!mounted) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return;
    }

    // ── Step 1: Read from cache immediately ───────────────────────────────
    final cached = _authRepository.getWorkerProfile();
    if (cached != null) {
      _currentSiteId = cached['current_site_id']?.toString();
      _officerUid = cached['officer_uid']?.toString();
      // Still try a background refresh to get latest site assignment
      _refreshWorkerDetailsFromSupabase(userId);
      return;
    }

    // ── Step 2: No cache — must hit Supabase ─────────────────────────────
    await _refreshWorkerDetailsFromSupabase(userId);
  }

  Future<void> _refreshWorkerDetailsFromSupabase(String userId) async {
    try {
      final workerData = await supabase
          .from('workers')
          .select('current_site_id, officer_uid')
          .eq('id', userId)
          .single();

      if (mounted) {
        setState(() {
          _currentSiteId = workerData['current_site_id']?.toString();
          _officerUid = workerData['officer_uid']?.toString();
        });
      }
    } on SocketException catch (e) {
      // Offline — cached values already applied, nothing to do
      LoggerService.warning(
        '[ReportHazard] Offline, using cached worker details.',
        e,
      );
    } catch (e, s) {
      LoggerService.error('[ReportHazard] Worker details fetch error', e, s);
      if (mounted) {
        // Only show snackbar if we also have no cached data
        if (_currentSiteId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not verify your site assignment: $e'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CONNECTIVITY CHECK
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> _isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _normalizeSeverity(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'high') return 'High';
    if (normalized == 'medium' || normalized == 'moderate') return 'Moderate';
    if (normalized == 'low') return 'Low';
    return 'Low';
  }

  String? _validateDescription(String? value) {
    final String description = value?.trim() ?? '';
    if (description.isEmpty) {
      return _descriptionRequiredMessage;
    }
    if (description.length < _descriptionMinLength) {
      return _descriptionTooShortMessage;
    }
    if (description.length > _descriptionMaxLength) {
      return _descriptionTooLongMessage;
    }
    return null;
  }

  bool get _isReportFormValid {
    return _validateDescription(_descriptionController.text) == null &&
        _selectedHazardTypes.isNotEmpty &&
        _allowedSeverityLevels.contains(_severity) &&
        _currentPosition != null &&
        _selectedImages.isNotEmpty;
  }

  String? _validateHazardTypes() {
    return _selectedHazardTypes.isEmpty ? _hazardTypeRequiredMessage : null;
  }

  String? _validateSeverity() {
    return _allowedSeverityLevels.contains(_severity)
        ? null
        : _severityRequiredMessage;
  }

  String? _validateLocation() {
    if (_currentPosition != null) {
      return null;
    }
    return _locationError ?? _locationRequiredMessage;
  }

  String? _validateImages() {
    return _selectedImages.isEmpty ? _photoRequiredMessage : null;
  }

  bool _validateReportForm({required bool showErrors}) {
    final bool isTextValid = _formKey.currentState?.validate() ?? false;
    final String? hazardTypeError = _validateHazardTypes();
    final String? severityError = _validateSeverity();
    final String? locationError = _validateLocation();
    final String? imageError = _validateImages();

    if (showErrors && mounted) {
      setState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
        _hasSubmittedOnce = true;
        _hazardTypeError = hazardTypeError;
        _severityError = severityError;
        _locationError = locationError;
        _imageError = imageError;
      });
    }

    return isTextValid &&
        hazardTypeError == null &&
        severityError == null &&
        locationError == null &&
        imageError == null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SUBMIT HAZARD — online: normal upload | offline: sync queue
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _submitHazard() async {
    if (_isSubmitting) return;

    if (_isRecording || _isAudioPlaying) {
      _showSnack(
        _isRecording ? _stopRecordingMessage : _stopPlaybackMessage,
        isError: true,
      );
      return;
    }

    if (!_validateReportForm(showErrors: true)) {
      _showSnack(_formValidationMessage, isError: true);
      return;
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnack("User not logged in", isError: true);
      return;
    }

    if (_currentSiteId == null || _officerUid == null) {
      await _showNoSiteAssignedDialog();
      return;
    }

    setState(() => _isSubmitting = true);

    final online = await _isOnline();
    final String description = _descriptionController.text.trim();

    // ── OFFLINE PATH ──────────────────────────────────────────────────────
    if (!online) {
      final recordedVoiceFiles =
          _voiceRecorderKey.currentState?.getAllRecordedFiles() ?? [];

      final localId = const Uuid().v4();
      final payload = {
        'id': localId,
        'worker_id': userId,
        'officer_uid': _officerUid,
        'current_site_id': _currentSiteId,
        'hazard_type': _selectedHazardTypes.join(', '),
        'description': description,
        'severity': _severity,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'status': 'reported',
        'image_url': null,
        'voice_note_url': null,
        'image_paths': _selectedImages.map((image) => image.path).toList(),
        'voice_paths': recordedVoiceFiles.map((file) => file.path).toList(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      await _syncRepository.enqueueAction(
        id: localId,
        table: 'hazards',
        action: 'insert',
        payload: payload,
      );

      // Append to local hazards cache so worker sees it immediately
      await _hazardRepository.appendHazard(payload);

      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '📴 Saved offline — will sync automatically when online.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
        _navigateHome();
      }
      return;
    }

    // ── ONLINE PATH ───────────────────────────────────────────────────────
    final List<String> imageUrls = <String>[];
    final List<String> voiceNoteUrls = <String>[];

    try {
      final recordedVoiceFiles =
          _voiceRecorderKey.currentState?.getAllRecordedFiles() ?? [];

      final List<Future<void>> uploadTasks = <Future<void>>[];

      for (final XFile imageFile in _selectedImages) {
        final fileBytes = await imageFile.readAsBytes();
        final fileName = "${const Uuid().v4()}_${imageFile.name}";
        uploadTasks.add(
          supabase.storage
              .from('hazard-images')
              .uploadBinary(fileName, fileBytes)
              .then((_) {
            final imageUrl =
            supabase.storage.from('hazard-images').getPublicUrl(fileName);
            imageUrls.add(imageUrl);
          }),
        );
      }

      for (final voiceFile in recordedVoiceFiles) {
        final fileName =
            "voice_notes/${const Uuid().v4()}_${voiceFile.path.split('/').last}";
        uploadTasks.add(
          supabase.storage
              .from('voice_notes')
              .upload(fileName, voiceFile)
              .then((_) {
            final voiceUrl =
            supabase.storage.from('voice_notes').getPublicUrl(fileName);
            voiceNoteUrls.add(voiceUrl);
          }),
        );
      }

      if (uploadTasks.isNotEmpty) {
        await Future.wait(uploadTasks);
      }

      final newHazard = {
        'worker_id': userId,
        'officer_uid': _officerUid,
        'current_site_id': _currentSiteId,
        'hazard_type': _selectedHazardTypes.join(', '),
        'description': description,
        'severity': _severity,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'status': 'reported',
        'image_url': imageUrls.isNotEmpty ? imageUrls.join(',') : null,
        'voice_note_url':
        voiceNoteUrls.isNotEmpty ? voiceNoteUrls.join(',') : null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final inserted = await supabase
          .from('hazards')
          .insert(newHazard)
          .select()
          .single();

      // Append to local cache immediately
      await _hazardRepository.appendHazard(Map<String, dynamic>.from(inserted));

      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hazard reported successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
        _navigateHome();
        widget.onHazardReported?.call();
      }
    } catch (e, s) {
      LoggerService.error('[ReportHazard] Submit error', e, s);
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reporting hazard: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _navigateHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerHomeScreen(
          currentThemeMode: ThemeMode.system,
          onThemeChanged: (ThemeMode mode) {},
        ),
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DIALOGS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _showNoSiteAssignedDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('No Site Assigned'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('You do not have any site assigned.'),
                SizedBox(height: 8),
                Text(
                    'To report a hazard, you must be assigned to a site. Please contact your supervisor.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // ignore: unused_element
  void _showOfflineFilesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text('No Internet'),
          ],
        ),
        content: const Text(
          'You are offline. Images and voice notes require an internet connection to upload.\n\n'
              'Remove all images and voice notes to save a text-only report offline — '
              'it will sync automatically when you reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RECORDER & CAMERA HELPERS — unchanged
  // ══════════════════════════════════════════════════════════════════════════

  void _handleRecordingStateChanged(bool isRecording) {
    if (mounted) setState(() => _isRecording = isRecording);
  }

  void _handlePlaybackStateChanged(bool isPlaying) {
    if (mounted) setState(() => _isAudioPlaying = isPlaying);
  }

  void _toggleRecording() {
    if (_isAudioPlaying) return;
    if (_isRecording) {
      _voiceRecorderKey.currentState?.stopRecording();
    } else {
      _voiceRecorderKey.currentState?.startRecording();
    }
  }

  Future<void> _pickImage() async {
    if (_isRecording || _isAudioPlaying) {
      _showSnack(
        _isRecording ? _stopRecordingMessage : _stopPlaybackMessage,
        isError: true,
      );
      return;
    }
    try {
      final permissionStatus = await Permission.camera.request();
      if (!permissionStatus.isGranted) {
        if (!mounted) return;
        _showSnack("Camera permission denied", isError: true);
        return;
      }
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (pickedFile != null && mounted) {
        setState(() {
          _selectedImages.add(pickedFile);
          _imageError = null;
        });
      }
    } catch (e, s) {
      LoggerService.error('[ReportHazard] Image capture failed', e, s);
      if (!mounted) return;
      _showSnack("Failed to capture image: $e", isError: true);
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    setState(() => _isLoadingLocation = true);
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _currentPosition = null;
          _isLoadingLocation = false;
          _locationError = _locationServiceDisabledMessage;
        });
        _showSnack(_locationServiceDisabledMessage, isError: true);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _currentPosition = null;
          _isLoadingLocation = false;
          _locationError = _locationDeniedMessage;
        });
        _showSnack(_locationDeniedMessage, isError: true);
        return;
      }
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (!mounted) return;
          setState(() {
            _currentPosition = null;
            _isLoadingLocation = false;
            _locationError = _locationDeniedMessage;
          });
          _showSnack(_locationDeniedMessage, isError: true);
          return;
        }
      }
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
        _locationError = null;
      });
    } catch (e, s) {
      LoggerService.error('[ReportHazard] Location capture failed', e, s);
      if (!mounted) return;
      setState(() {
        _currentPosition = null;
        _isLoadingLocation = false;
        _locationError = "Failed to get location: $e";
      });
      _showSnack("Failed to get location: $e", isError: true);
    }
  }

  Future<void> _selectHazardType() async {
    final selectedTypes = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => const SelectHazardTypeScreen()),
    );
    if (selectedTypes != null &&
        selectedTypes is List<String> &&
        mounted) {
      setState(() {
        _selectedHazardTypes = selectedTypes;
        _hazardTypeError = _validateHazardTypes();
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD — completely unchanged from original
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isLightTheme = Theme.of(context).brightness == Brightness.light;

    return Form(
      key: _formKey,
      autovalidateMode: _autovalidateMode,
      child: Scaffold(
        backgroundColor: isLightTheme ? const Color(0xFFF5F5F5) : null,
        appBar: AppBar(
          title: const Text("Report Hazard"),
          centerTitle: true,
          backgroundColor: const Color(0xFF1B3D3D),
          foregroundColor: Colors.white,
        ),
        bottomNavigationBar: _buildInputBarSection(),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHazardTypeCard()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildInlineError(
                  _hazardTypeError ?? _validateHazardTypes(),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildSeveritySection()),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildLocationSection()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildInlineError(
                  _isLoadingLocation
                      ? null
                      : _locationError ?? _validateLocation(),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildImagePreview()),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildVoiceNotesSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBarSection() {
    final theme = Theme.of(context);
    final isLightTheme = theme.brightness == Brightness.light;

    final canSubmit = !_isSubmitting &&
        !_isRecording &&
        !_isAudioPlaying &&
        _isReportFormValid;

    final isInputDisabled = _isRecording || _isAudioPlaying;

    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 8,
          left: 8,
          right: 8,
          top: 8),
      color: isLightTheme
          ? const Color(0xFFF5F5F5)
          : theme.scaffoldBackgroundColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isLightTheme
                    ? Colors.white
                    : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color:
                    theme.colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextFormField(
                        controller: _descriptionController,
                        enabled: !isInputDisabled,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: _descriptionMaxLength,
                        validator: _validateDescription,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          errorMaxLines: 2,
                          hintText: _isRecording
                              ? "Recording..."
                              : (_isAudioPlaying
                              ? "Playing..."
                              : "Type a description..."),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.camera_alt,
                        color: isInputDisabled
                            ? Colors.grey
                            : theme.colorScheme.primary),
                    onPressed: isInputDisabled ? null : _pickImage,
                  ),
                  IconButton(
                    icon: Icon(
                      _isRecording
                          ? Icons.stop_circle_outlined
                          : Icons.mic,
                      color: _isAudioPlaying
                          ? Colors.grey
                          : (_isRecording
                          ? Colors.red
                          : theme.colorScheme.primary),
                      size: 26,
                    ),
                    onPressed: _isAudioPlaying ? null : _toggleRecording,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            width: 56,
            child: ElevatedButton(
              onPressed: canSubmit ? _submitHazard : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                canSubmit ? Colors.blue : Colors.grey.shade400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24.0),
                ),
                padding: EdgeInsets.zero,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: Colors.white))
                  : Icon(
                Icons.send,
                color: canSubmit
                    ? Colors.black
                    : Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceNotesSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: VoiceNoteRecorder(
        key: _voiceRecorderKey,
        onRecordingStateChanged: _handleRecordingStateChanged,
        onPlaybackStateChanged: _handlePlaybackStateChanged,
      ),
    );
  }

  Widget _buildHazardTypeCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _selectHazardType,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Hazard Type",
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(
                        _selectedHazardTypes.isEmpty
                            ? "Tap to select hazard types"
                            : _selectedHazardTypes.join(', '),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeveritySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Severity Level",
              style:
              TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSeverityChip('Low', Colors.green),
              const SizedBox(width: 8),
              _buildSeverityChip('Moderate', Colors.orange),
              const SizedBox(width: 8),
              _buildSeverityChip('High', Colors.red),
            ],
          ),
          _buildInlineError(_severityError ?? _validateSeverity()),
        ],
      ),
    );
  }

  Widget _buildSeverityChip(String level, Color color) {
    final isSelected = _severity == level;
    final isLightTheme = Theme.of(context).brightness == Brightness.light;

    IconData getIconForLevel() {
      switch (level) {
        case 'Low':
          return Icons.check_circle;
        case 'Moderate':
          return Icons.warning;
        case 'High':
          return Icons.error;
        default:
          return Icons.circle;
      }
    }

    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _severity = level;
          _severityError = _validateSeverity();
        }),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? color
                : (isLightTheme
                ? Colors.white
                : color.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? null
                : Border.all(color: color.withValues(alpha: 0.3)),
            boxShadow: isLightTheme && !isSelected
                ? [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                blurRadius: 5,
                offset: const Offset(0, 2),
              )
            ]
                : [],
          ),
          child: Column(
            children: [
              Icon(getIconForLevel(),
                  color: isSelected ? Colors.white : color, size: 20),
              const SizedBox(height: 4),
              Text(level,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _currentPosition != null
                ? [Colors.green.shade400, Colors.teal.shade600]
                : [Colors.red.shade400, Colors.red.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color:
              (_currentPosition != null ? Colors.green : Colors.red)
                  .withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _isLoadingLocation
              ? const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
              SizedBox(width: 12),
              Text("Getting your location...",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          )
              : _currentPosition != null
              ? Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.location_on,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Location Captured",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      "${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}",
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white
                              .withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.refresh,
                    color: Colors.white),
                tooltip: "Refresh location",
              ),
            ],
          )
              : Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.location_off,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                  child: Text("Location Required",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold))),
              ElevatedButton(
                onPressed: _getCurrentLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
                child: const Text("Get Location"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_selectedImages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: _buildInlineError(_imageError ?? _validateImages()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: _selectedImages.length,
            itemBuilder: (context, index) {
              final XFile imageFile = _selectedImages[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 120,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(imageFile.path), fit: BoxFit.cover),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                            icon: const CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close,
                                  color: Colors.white, size: 16),
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedImages.removeAt(index);
                                _imageError = _validateImages();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildInlineError(_imageError),
        ),
      ],
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
