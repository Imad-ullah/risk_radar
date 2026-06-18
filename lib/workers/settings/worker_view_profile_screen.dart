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
import 'package:riskradar/shared/utils/profile_photo_permission.dart';
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

    final Map<String, Object?>? cachedProfile = _authRepository
        .getWorkerProfile()
        ?.cast<String, Object?>();
    if (cachedProfile != null) {
      _applyProfile(cachedProfile);
      if (mounted) setState(() => _loading = false);
    }

    try {
      final Map<String, Object?>? worker =
          (await _supabase
                  .from('workers')
                  .select()
                  .eq('id', userId)
                  .maybeSingle())
              ?.cast<String, Object?>();
      if (worker != null) {
        _applyProfile(worker);
        await _authRepository.saveWorkerProfile(worker);
      }
    } on SocketException catch (e) {
      LoggerService.warning(
        'Worker profile offline - using cached profile.',
        e,
      );
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
      final bool hasPermission = await requestProfilePhotoPermission(
        context,
        ImageSource.gallery,
      );
      if (!hasPermission) {
        return;
      }

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
      final bool savedOffline =
          syncResult.reason != null ||
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
      SnackBar(content: Text(message), backgroundColor: AppColors.brandTeal),
    );
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: RiskRadarLoader());
    }
    if (_profileData == null) {
      return Scaffold(body: Center(child: Text('Profile not found')));
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      resizeToAvoidBottomInset: true,
      body: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    final String? imageUrl = _profileText('profile_image_url');
    final String fullName =
        '${_profileText('first_name') ?? ''} '
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
          height: visibleHeight * 0.310,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.brandTeal,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(size.width * 0.077),
                bottomRight: Radius.circular(size.width * 0.077),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              top: visibleHeight * 0.078,
              bottom: visibleHeight * 0.040,
            ),
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
                          padding: EdgeInsets.all(size.width * 0.010),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Hero(
                            tag: imageUrl ?? 'profile_pic',
                            child: CircleAvatar(
                              radius: size.width * 0.145,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: avatarImage,
                              child: _updatingPhoto
                                  ? RiskRadarLoader(
                                      color: AppColors.brandTeal,
                                      size: size.width * 0.096,
                                    )
                                  : avatarImage == null
                                  ? Icon(
                                      Icons.person,
                                      size: size.width * 0.145,
                                      color: Colors.grey,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _updatingPhoto
                            ? null
                            : _pickAndQueueProfileImage,
                        child: Container(
                          padding: EdgeInsets.all(size.width * 0.018),
                          decoration: BoxDecoration(
                            color: AppColors.accentGold,
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: size.width * 0.049,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: visibleHeight * 0.012),
                Text(
                  fullName.isEmpty ? 'Worker Profile' : fullName,
                  style: TextStyle(
                    fontSize: size.width * 0.052,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: visibleHeight * 0.004),
                Text(
                  (_profileText('work_type') ?? '').toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: size.width * 0.028,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: visibleHeight * 0.026),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: size.width * 0.050),
                  padding: EdgeInsets.all(size.width * 0.052),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(size.width * 0.053),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: size.width * 0.053,
                        offset: Offset(size.width * 0.0, visibleHeight * 0.013),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'WORKER DETAILS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: size.width * 0.038,
                          color: AppColors.brandTeal,
                        ),
                      ),
                      SizedBox(height: visibleHeight * 0.018),
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
                      SizedBox(height: visibleHeight * 0.006),
                      Text(
                        'Workers can update their profile photo only. Contact your officer for detail changes.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: size.width * 0.028,
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
          left: size.width * 0.053,
          child: SafeArea(
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios, color: Colors.white),
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
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: visibleHeight * 0.018),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: size.width * 0.031,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: visibleHeight * 0.006),
          TextFormField(
            initialValue: value,
            readOnly: true,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
              fontSize: size.width * 0.036,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(
                icon,
                color: AppColors.accentGold,
                size: size.width * 0.056,
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: EdgeInsets.symmetric(
                vertical: visibleHeight * 0.014,
                horizontal: size.width * 0.050,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(size.width * 0.077),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(size.width * 0.077),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
