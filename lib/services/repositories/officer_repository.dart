import '../../shared/models/user_models.dart';
import 'sqlite_cache_store.dart';

class OfficerRepository {
  OfficerRepository._();

  static final OfficerRepository instance = OfficerRepository._();

  static const _profileKey = 'rr_officer_profile';
  static const _dashboardKey = 'rr_officer_dashboard';
  static const _sitesKey = 'rr_officer_sites';
  static const _workersKey = 'rr_officer_workers';
  static const _hseWorkersKey = 'rr_officer_hse_workers';
  static const _analyticsKey = 'rr_officer_analytics';
  static const _sitePersonnelKey = 'rr_officer_site_personnel';
  static const _emergencyDetailsKey = 'rr_officer_emergency_details';

  final SqliteCacheStore _cacheStore = SqliteCacheStore.instance;

  Future<void> saveOfficerProfile(Map<String, dynamic> row) {
    final sanitised = Officer.fromMap(row).toMap();
    return _cacheStore.writeJson(_profileKey, sanitised);
  }

  Map<String, dynamic>? getOfficerProfile() => _cacheStore.readMap(_profileKey);

  Future<void> saveOfficerDashboard(Map<String, dynamic> data) =>
      _cacheStore.writeJson(_dashboardKey, data);

  Map<String, dynamic>? getOfficerDashboard() =>
      _cacheStore.readMap(_dashboardKey);

  Future<void> saveOfficerSites(List<dynamic> rows) =>
      _cacheStore.writeJson(_sitesKey, rows);

  List<Map<String, dynamic>>? getOfficerSites() =>
      _cacheStore.readMapList(_sitesKey);

  Future<void> saveOfficerWorkers(List<dynamic> rows) =>
      _cacheStore.writeJson(_workersKey, rows);

  List<Map<String, dynamic>>? getOfficerWorkers() =>
      _cacheStore.readMapList(_workersKey);

  Future<void> saveOfficerHseWorkers(List<dynamic> rows) =>
      _cacheStore.writeJson(_hseWorkersKey, rows);

  List<Map<String, dynamic>>? getOfficerHseWorkers() =>
      _cacheStore.readMapList(_hseWorkersKey);

  Future<void> saveOfficerAnalytics(Map<String, dynamic> data) =>
      _cacheStore.writeJson(_analyticsKey, data);

  Map<String, dynamic>? getOfficerAnalytics() =>
      _cacheStore.readMap(_analyticsKey);

  Future<void> saveOfficerSitePersonnel(
    String siteId,
    Map<String, dynamic> data,
  ) async {
    final all = _cacheStore.readMap(_sitePersonnelKey) ?? {};
    all[siteId] = data;
    await _cacheStore.writeJson(_sitePersonnelKey, all);
  }

  Map<String, dynamic>? getOfficerSitePersonnel(String siteId) {
    final all = _cacheStore.readMap(_sitePersonnelKey);
    final data = all?[siteId];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<void> saveOfficerEmergencyDetails(
    String officerId,
    Map<String, dynamic> data,
  ) async {
    final all = _cacheStore.readMap(_emergencyDetailsKey) ?? {};
    all[officerId] = data;
    await _cacheStore.writeJson(_emergencyDetailsKey, all);
  }

  Map<String, dynamic>? getOfficerEmergencyDetails(String officerId) {
    final all = _cacheStore.readMap(_emergencyDetailsKey);
    final data = all?[officerId];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }
}
