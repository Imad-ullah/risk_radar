// Your file: api_service.dart or hazard_notifier.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<Map<String, dynamic>?> fetchFullHazardData(String hazardId) async {
  try {
    final supabase = Supabase.instance.client;

    // 1. Fetch the full hazard record.
    final hazard = await supabase
        .from('hazards')
        .select() // Select all fields
        .eq('id', hazardId)
        .maybeSingle();

    if (hazard == null) {
      return null; // Hazard not found
    }

    final String? workerId = hazard['worker_id'];
    String reporterName = 'Unknown Reporter';

    if (workerId != null) {
      // ✅ CORRECTED LOGIC: Fetch first_name and last_name from the 'workers' table.
      final worker = await supabase
          .from('workers')
          .select('first_name, last_name')
          .eq('id', workerId)
          .maybeSingle();

      if (worker != null) {
        final String firstName = worker['first_name'] ?? '';
        final String lastName = worker['last_name'] ?? '';
        reporterName = '$firstName $lastName'.trim();
      }
    }

    // 4. Add the combined reporter's name to the data map before returning.
    hazard['reporter_name'] = reporterName;
    return hazard;
  } catch (e) {
    debugPrint('Error fetching full hazard data: $e');
    return null;
  }
}
