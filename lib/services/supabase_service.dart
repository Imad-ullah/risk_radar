import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;
  final String _bucket = 'profile-images';

  Future<String?> uploadProfileImage(
    File imageFile,
    String firstName,
    String lastName,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      debugPrint("❌ No logged-in user");
      return null;
    }

    // Clean and format the filename
    final fileExt = path.extension(imageFile.path); // e.g. .jpg
    final cleanedName =
        '${firstName.trim().toLowerCase()}_${lastName.trim().toLowerCase()}'
            .replaceAll(RegExp(r'\s+'), '_') // Replace spaces with _
            .replaceAll(RegExp(r'[^a-z0-9_]'), ''); // Remove special chars

    final fileName = '$cleanedName$fileExt'; // imad_ullah.jpg
    final filePath = '${user.id}/$fileName'; // UID/imad_ullah.jpg

    debugPrint("📁 Uploading to: $filePath");

    try {
      await _client.storage
          .from(_bucket)
          .upload(
            filePath,
            imageFile,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = _client.storage.from(_bucket).getPublicUrl(filePath);

      debugPrint("✅ Public URL: $publicUrl");
      return publicUrl;
    } catch (e) {
      debugPrint("❌ Exception during upload: $e");
      return null;
    }
  }
}
