import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestProfilePhotoPermission(
  BuildContext context,
  ImageSource source,
) async {
  final PermissionStatus status = source == ImageSource.camera
      ? await Permission.camera.request()
      : await _requestGalleryPermission();

  if (status.isGranted || status.isLimited) {
    return true;
  }

  if (!context.mounted) {
    return false;
  }

  if (status.isPermanentlyDenied || status.isRestricted) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text(
          source == ImageSource.camera
              ? 'Please enable camera access in Settings to take a profile photo.'
              : 'Please enable photo access in Settings to upload your profile picture.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
    return false;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        source == ImageSource.camera
            ? 'Camera permission denied.'
            : 'Photo permission denied. Please allow gallery access to upload a photo.',
      ),
    ),
  );
  return false;
}

Future<PermissionStatus> _requestGalleryPermission() async {
  if (Platform.isAndroid) {
    final PermissionStatus photosStatus = await Permission.photos.request();
    if (photosStatus.isGranted ||
        photosStatus.isLimited ||
        photosStatus.isPermanentlyDenied) {
      return photosStatus;
    }

    final PermissionStatus storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted ||
        storageStatus.isLimited ||
        storageStatus.isPermanentlyDenied) {
      return storageStatus;
    }

    return photosStatus;
  }

  return Permission.photos.request();
}
