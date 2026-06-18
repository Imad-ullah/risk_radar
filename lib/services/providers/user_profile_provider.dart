import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riskradar/services/repositories/auth_repository.dart';

final userProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((
  Ref ref,
) async {
  return AuthRepository().getCachedProfile();
});
