// lib/workers/screens/worker_view_profile_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:riskradar/services/logger_service.dart';
import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/services/sync_service.dart';
import 'package:riskradar/shared/theme/app_colors.dart';
import 'package:riskradar/shared/widgets/full_image_viewer.dart';
import 'package:riskradar/shared/widgets/risk_radar_loader.dart';

class WorkerEditProfileScreen extends StatefulWidget {
  const WorkerEditProfileScreen({super.key});

  @override
  State<WorkerEditProfileScreen> createState() =>
      _WorkerEditProfileScreenState();
}

class _WorkerEditProfileScreenState extends State<WorkerEditProfileScreen> {
  static const String _photoUpdatedMessage = 'Profile photo updated!';
  static const String _photoSavedOfflineMessage =
      'Profile photo saved offline - will sync when online';
  static const String _photoUpdateFailedMessage =
      'Profile photo update failed. Please try again.';

  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  final AuthRepository _authRepository = AuthRepository();
  final SyncRepository _syncRepository = SyncRepository();

  bool _loading = true;
  bool _updatingPhoto = false;
  Map<String, Object?>? _profileData;
  File? _pendingProfileImage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final String? userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final Map<String, Object?>? cachedProfile =
        _authRepository.getWorkerProfile()?.cast<String, Object?>();
    if (cachedProfile != null) {
      _applyProfile(cachedProfile);
      if (mounted) setState(() => _loading = false);
    }

    try {
      final Map<String, Object?>? worker =
          (await _supabase.from('workers').select().eq('id', userId).maybeSingle())
              ?.cast<String, Object?>();
      if (worker != null) {
        _applyProfile(worker);
        await _authRepository.saveWorkerProfile(worker);
      }
    } on SocketException catch (e) {
      LoggerService.warning('Worker profile offline - using cached profile.', e);
    } catch (e, s) {
      LoggerService.error('Error loading worker profile', e, s);
      if (mounted && cachedProfile == null) {
        _showErrorSnack('Failed to load profile: $e');
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  void _applyProfile(Map<String, Object?> profile) {
    _profileData = Map<String, Object?>.from(profile);
  }

  Future<File?> _cropImage(File imageFile) async {
    final CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: imageFile.path,
      uiSettings: <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: 'Center Your Face',
          toolbarColor: AppColors.brandTeal,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          aspectRatioPresets: <CropAspectRatioPreset>[
            CropAspectRatioPreset.square,
          ],
          hideBottomControls: true,
          showCropGrid: false,
        ),
        IOSUiSettings(
          title: 'Center Your Face',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPresets: <CropAspectRatioPreset>[
            CropAspectRatioPreset.square,
          ],
        ),
      ],
    );
    return croppedFile == null ? null : File(croppedFile.path);
  }

  Future<void> _pickAndQueueProfileImage() async {
    if (_updatingPhoto) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image == null) return;

      final File? croppedImage = await _cropImage(File(image.path));
      if (croppedImage == null) return;

      final String? userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        _showErrorSnack('You must be signed in to update your photo.');
        return;
      }

      setState(() {
        _updatingPhoto = true;
        _pendingProfileImage = croppedImage;
      });

      final Map<String, Object?> payload = <String, Object?>{
        'id': userId,
        'profile_image_url': _profileData?['profile_image_url'],
        'image_paths': <String>[croppedImage.path],
      };

      await _syncRepository.enqueueAction(
        id: 'worker_profile_photo_${userId}_${DateTime.now().millisecondsSinceEpoch}',
        table: 'workers',
        action: 'update',
        payload: payload,
      );

      final Map<String, Object?> updatedProfile = <String, Object?>{
        ...?_profileData,
        'id': userId,
        'role': 'worker',
        'profile_image_url': _profileData?['profile_image_url'],
      };
      await _authRepository.saveWorkerProfile(updatedProfile);

      final SyncResult syncResult = await SyncService.instance.run();
      final bool savedOffline = syncResult.reason != null ||
          syncResult.hasFailures ||
          syncResult.pending > 0;

      if (!mounted) return;
      _showSuccessSnack(
        savedOffline ? _photoSavedOfflineMessage : _photoUpdatedMessage,
      );
      if (!savedOffline) {
        await _loadProfile();
        if (mounted) setState(() => _pendingProfileImage = null);
      }
    } catch (e, s) {
      LoggerService.error('Worker profile photo update failed', e, s);
      if (mounted) _showErrorSnack(_photoUpdateFailedMessage);
    } finally {
      if (mounted) setState(() => _updatingPhoto = false);
    }
  }

  void _showSuccessSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.brandTeal,
      ),
    );
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
    if (_loading) {
      return const Scaffold(body: RiskRadarLoader());
    }
    if (_profileData == null) {
      return const Scaffold(body: Center(child: Text('Profile not found')));
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      resizeToAvoidBottomInset: true,
      body: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final String? imageUrl = _profileText('profile_image_url');
    final String fullName = '${_profileText('first_name') ?? ''} '
            '${_profileText('last_name') ?? ''}'
        .trim();
    final ImageProvider<Object>? avatarImage = _pendingProfileImage != null
        ? FileImage(_pendingProfileImage!)
        : imageUrl != null && imageUrl.isNotEmpty
            ? NetworkImage(imageUrl)
            : null;

    return Stack(
      children: <Widget>[
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 280,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.brandTeal,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 60, bottom: 40),
            child: Column(
              children: <Widget>[
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: <Widget>[
                      GestureDetector(
                        onTap: () {
                          if (imageUrl != null && imageUrl.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FullscreenImageViewer(
                                  imageUrls: <String>[imageUrl],
                                  initialIndex: 0,
                                ),
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Hero(
                            tag: imageUrl ?? 'profile_pic',
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: avatarImage,
                              child: _updatingPhoto
                                  ? const RiskRadarLoader(
                                      color: AppColors.brandTeal,
                                      size: 36,
                                    )
                                  : avatarImage == null
                                      ? const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: Colors.grey,
                                        )
                                      : null,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _updatingPhoto ? null : _pickAndQueueProfileImage,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.accentGold,
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  fullName.isEmpty ? 'Worker Profile' : fullName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  (_profileText('work_type') ?? '').toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 30),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'WORKER DETAILS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.brandTeal,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildReadOnlyField(
                        'First Name',
                        _profileText('first_name') ?? '',
                        Icons.person_outline,
                      ),
                      _buildReadOnlyField(
                        'Last Name',
                        _profileText('last_name') ?? '',
                        Icons.person_outline,
                      ),
                      _buildReadOnlyField(
                        'Email ID',
                        _profileText('email') ?? '',
                        Icons.email_outlined,
                      ),
                      _buildReadOnlyField(
                        'Work Type',
                        _profileText('work_type') ?? '',
                        Icons.engineering_outlined,
                      ),
                      _buildReadOnlyField(
                        'Contractor UID',
                        _profileText('officer_uid') ?? '',
                        Icons.admin_panel_settings_outlined,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Workers can update their profile photo only. Contact your officer for detail changes.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 20,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ],
    );
  }

  String? _profileText(String key) {
    final Object? value = _profileData?[key];
    if (value == null) return null;
    final String text = value.toString();
    return text.isEmpty ? null : text;
  }

  Widget _buildReadOnlyField(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: value,
            readOnly: true,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: AppColors.accentGold),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
