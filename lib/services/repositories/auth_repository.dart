import '../../shared/models/user_models.dart';
import '../local_storage_service.dart';
import 'officer_repository.dart';
import 'sqlite_cache_store.dart';

class AuthRepository {
  AuthRepository({LocalStorageService? storage, SqliteCacheStore? cacheStore})
    : _storage = storage ?? LocalStorageService.instance,
      _cacheStore = cacheStore ?? SqliteCacheStore.instance;

  static const _workerProfileKey = 'rr_worker_profile';
  static const _hseProfileKey = 'rr_hse_profile';
  static const _workerContextKey = 'rr_worker_context';
  static const _hseContextKey = 'rr_hse_context';

  final LocalStorageService _storage;
  final SqliteCacheStore _cacheStore;

  Future<void> saveRole(String role) => _storage.saveRole(role);

  String? getRole() => _storage.getRole();

  Future<void> saveUserId(String uid) => _storage.saveUserId(uid);

  String? getUserId() => _storage.getUserId();

  Future<void> saveWorkerProfile(Map<String, dynamic> row) {
    final sanitised = Worker.fromMap(row).toMap();
    return _cacheStore.writeJson(_workerProfileKey, sanitised);
  }

  Map<String, dynamic>? getWorkerProfile() =>
      _cacheStore.readMap(_workerProfileKey);

  Future<void> saveWorkerContext({
    required String? siteId,
    required String siteName,
    required String? officerUid,
    required List<String> contractors,
    required List<String> safetyOfficers,
  }) {
    return _cacheStore.writeJson(_workerContextKey, {
      'site_id': siteId,
      'site_name': siteName,
      'officer_uid': officerUid,
      'contractors': contractors,
      'safety_officers': safetyOfficers,
    });
  }

  Map<String, dynamic>? getWorkerContext() =>
      _cacheStore.readMap(_workerContextKey);

  Future<void> saveHseProfile(Map<String, dynamic> row) {
    final sanitised = HseWorker.fromMap(row).toMap();
    return _cacheStore.writeJson(_hseProfileKey, sanitised);
  }

  Map<String, dynamic>? getHseProfile() => _cacheStore.readMap(_hseProfileKey);

  Future<void> saveHseContext(Map<String, dynamic> data) =>
      _cacheStore.writeJson(_hseContextKey, data);

  Map<String, dynamic>? getHseContext() => _cacheStore.readMap(_hseContextKey);

  Future<void> saveOfficerProfile(Map<String, dynamic> row) =>
      OfficerRepository.instance.saveOfficerProfile(row);

  Map<String, dynamic>? getOfficerProfile() =>
      OfficerRepository.instance.getOfficerProfile();

  Future<void> saveProfileForRole(String role, Map<String, dynamic> row) {
    switch (role) {
      case 'worker':
        return saveWorkerProfile(row);
      case 'hse_worker':
        return saveHseProfile(row);
      case 'officer':
        return saveOfficerProfile(row);
      default:
        return Future.value();
    }
  }

  Map<String, dynamic>? getCachedProfile() {
    switch (getRole()) {
      case 'worker':
        return getWorkerProfile();
      case 'hse_worker':
        return getHseProfile();
      case 'officer':
        return getOfficerProfile();
      default:
        return null;
    }
  }

  bool get hasCachedSession => _storage.hasCachedSession;

  Future<void> clearAll() => _storage.clearAll();
}
