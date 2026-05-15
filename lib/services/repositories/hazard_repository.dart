import '../database/database_helper.dart';
import 'sqlite_cache_store.dart';

class HazardRepository {
  HazardRepository({
    DatabaseHelper? databaseHelper,
    SqliteCacheStore? cacheStore,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _cacheStore = cacheStore ?? SqliteCacheStore.instance;

  static const _hazardsKey = 'rr_hazards';
  static const _assignHazardsKey = 'rr_assign_hazards';
  static const _ongoingHazardsKey = 'rr_ongoing_hazards';
  static const _resolvedHazardsKey = 'rr_resolved_hazards';
  static const _hseAssignedTasksKey = 'rr_hse_assigned_tasks';
  static const _hseSiteHazardsKey = 'rr_hse_site_hazards';
  static const _hseResolvedHazardsKey = 'rr_hse_resolved_hazards';
  static const _officerActiveHazardsKey = 'rr_officer_active_hazards';
  static const _officerResolvedHazardsKey = 'rr_officer_resolved_hazards';

  final DatabaseHelper _databaseHelper;
  final SqliteCacheStore _cacheStore;

  Future<void> saveHazards(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      await _upsert(row, sourceTable: DatabaseHelper.hazardsTable);
    }
  }

  Future<List<Map<String, dynamic>>> getHazards() {
    return _getOrMigrate(
      sourceTable: DatabaseHelper.hazardsTable,
      legacyCacheKey: _hazardsKey,
      legacyDefault: const [],
    );
  }

  Future<void> appendHazard(Map<String, dynamic> row) async {
    await _upsert(row, sourceTable: DatabaseHelper.hazardsTable);
  }

  Future<void> updateHazard(Map<String, dynamic> updated) async {
    await _upsert(updated, sourceTable: DatabaseHelper.hazardsTable);
  }

  Future<void> saveAssignHazards(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      await _upsert(row, sourceTable: 'assign_hazards');
    }
  }

  Future<List<Map<String, dynamic>>> getAssignHazards() {
    return _getOrMigrate(
      sourceTable: 'assign_hazards',
      legacyCacheKey: _assignHazardsKey,
      legacyDefault: const [],
    );
  }

  Future<void> updateAssignHazard(Map<String, dynamic> updated) async {
    await _upsert(updated, sourceTable: 'assign_hazards');
  }

  Future<void> saveOngoingHazards(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      await _upsert(row, sourceTable: 'ongoing_hazards');
    }
  }

  Future<List<Map<String, dynamic>>> getOngoingHazards() {
    return _getOrMigrate(
      sourceTable: 'ongoing_hazards',
      legacyCacheKey: _ongoingHazardsKey,
      legacyDefault: const [],
    );
  }

  Future<void> saveResolvedHazards(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      await _upsert(row, sourceTable: 'resolved_hazards');
    }
  }

  Future<List<Map<String, dynamic>>> getResolvedHazards() {
    return _getOrMigrate(
      sourceTable: 'resolved_hazards',
      legacyCacheKey: _resolvedHazardsKey,
      legacyDefault: const [],
    );
  }

  Future<void> saveHseAssignedTasks(List<dynamic> rows) async {
    await _upsertAllDynamic(rows, sourceTable: 'hse_assigned_tasks');
  }

  Future<List<Map<String, dynamic>>?> getHseAssignedTasks() {
    return _getOrMigrateNullable(
      sourceTable: 'hse_assigned_tasks',
      legacyCacheKey: _hseAssignedTasksKey,
    );
  }

  Future<void> saveHseSiteHazards(List<dynamic> rows) async {
    await _upsertAllDynamic(rows, sourceTable: 'hse_site_hazards');
  }

  Future<List<Map<String, dynamic>>?> getHseSiteHazards() {
    return _getOrMigrateNullable(
      sourceTable: 'hse_site_hazards',
      legacyCacheKey: _hseSiteHazardsKey,
    );
  }

  Future<void> saveHseResolvedHazards(List<dynamic> rows) async {
    await _upsertAllDynamic(rows, sourceTable: 'hse_resolved_hazards');
  }

  Future<List<Map<String, dynamic>>?> getHseResolvedHazards() {
    return _getOrMigrateNullable(
      sourceTable: 'hse_resolved_hazards',
      legacyCacheKey: _hseResolvedHazardsKey,
    );
  }

  Future<void> saveOfficerActiveHazards(List<dynamic> rows) async {
    await _upsertAllDynamic(rows, sourceTable: 'officer_active_hazards');
  }

  Future<List<Map<String, dynamic>>?> getOfficerActiveHazards() {
    return _getOrMigrateNullable(
      sourceTable: 'officer_active_hazards',
      legacyCacheKey: _officerActiveHazardsKey,
    );
  }

  Future<void> saveOfficerResolvedHazards(List<dynamic> rows) async {
    await _upsertAllDynamic(rows, sourceTable: 'officer_resolved_hazards');
  }

  Future<List<Map<String, dynamic>>?> getOfficerResolvedHazards() {
    return _getOrMigrateNullable(
      sourceTable: 'officer_resolved_hazards',
      legacyCacheKey: _officerResolvedHazardsKey,
    );
  }

  Future<List<Map<String, dynamic>>> _getOrMigrate({
    required String sourceTable,
    required String legacyCacheKey,
    required List<Map<String, dynamic>> legacyDefault,
  }) async {
    final sqliteRows = await _databaseHelper.getHazards(
      sourceTable: sourceTable,
    );
    if (sqliteRows.isNotEmpty) return sqliteRows;

    final rows = _cacheStore.readMapList(legacyCacheKey) ?? legacyDefault;
    if (rows.isNotEmpty) {
      await _upsertAllDynamic(rows, sourceTable: sourceTable);
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>?> _getOrMigrateNullable({
    required String sourceTable,
    required String legacyCacheKey,
  }) async {
    final sqliteRows = await _databaseHelper.getHazards(
      sourceTable: sourceTable,
    );
    if (sqliteRows.isNotEmpty) return sqliteRows;

    final rows = _cacheStore.readMapList(legacyCacheKey);
    if (rows != null && rows.isNotEmpty) {
      await _upsertAllDynamic(rows, sourceTable: sourceTable);
    }
    return rows;
  }

  Future<void> _upsertAllDynamic(
    List<dynamic> rows, {
    required String sourceTable,
  }) async {
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        await _upsert(row, sourceTable: sourceTable);
      } else if (row is Map) {
        await _upsert(Map<String, dynamic>.from(row), sourceTable: sourceTable);
      }
    }
  }

  Future<void> _upsert(
    Map<String, dynamic> row, {
    required String sourceTable,
  }) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;

    await _databaseHelper.upsertHazard(
      id: id,
      sourceTable: sourceTable,
      payload: row,
    );
  }
}
