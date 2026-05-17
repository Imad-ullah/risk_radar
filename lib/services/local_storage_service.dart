import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database/database_helper.dart';
import 'logger_service.dart';
import 'repositories/sqlite_cache_store.dart';

class LocalStorageService {
  LocalStorageService._();

  static final LocalStorageService instance = LocalStorageService._();

  static const _roleKey = 'rr_role';
  static const _userIdKey = 'rr_user_id';

  static const _sqliteCacheKeys = {
    'rr_worker_profile',
    'rr_hse_profile',
    'rr_officer_profile',
    'rr_hazards',
    'rr_assign_hazards',
    'rr_sync_queue',
    'rr_worker_context',
    'rr_ongoing_hazards',
    'rr_resolved_hazards',
    'rr_hse_assigned_tasks',
    'rr_hse_site_hazards',
    'rr_hse_team_members',
    'rr_hse_resolved_hazards',
    'rr_hse_context',
    'rr_officer_dashboard',
    'rr_officer_sites',
    'rr_officer_workers',
    'rr_officer_hse_workers',
    'rr_officer_active_hazards',
    'rr_officer_resolved_hazards',
    'rr_officer_analytics',
    'rr_officer_site_personnel',
    'rr_officer_emergency_details',
  };

  static const _legacyKeys = {
    _roleKey,
    _userIdKey,
    ..._sqliteCacheKeys,
  };
  static const _secureKeys = {
    _roleKey,
    _userIdKey,
  };

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
  );
  final SqliteCacheStore _cacheStore = SqliteCacheStore.instance;
  final Map<String, String> _memory = {};

  late SharedPreferences _prefs;
  bool _secureStorageAvailable = true;
  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;

    _prefs = await SharedPreferences.getInstance();
    await _loadLegacySecureValues();
    await _loadSqliteCacheValues();
    await _migratePlaintextValues();
    await _migrateLegacyCacheValuesToSqlite();
    _initialised = true;
  }

  Future<void> saveRole(String role) => _writeString(_roleKey, role);

  String? getRole() => _readString(_roleKey);

  Future<void> saveUserId(String uid) => _writeString(_userIdKey, uid);

  String? getUserId() => _readString(_userIdKey);

  bool get hasCachedSession =>
      _containsKey(_roleKey) && _containsKey(_userIdKey);

  Future<void> clearAll() async {
    await Future.wait([
      for (final key in _legacyKeys) _delete(key),
    ]);
    await DatabaseHelper.instance.clearSyncQueue();
    await DatabaseHelper.instance.clearHazards();
    await _cacheStore.clear();
  }

  Future<void> _loadLegacySecureValues() async {
    try {
      for (final key in _secureKeys) {
        final value = await _secureStorage.read(key: key);
        if (value != null) _memory[key] = value;
      }
    } catch (e) {
      _secureStorageAvailable = false;
      LoggerService.warning(
        'Secure storage unavailable, using migration fallback',
        e,
      );
    }
  }

  Future<void> _loadSqliteCacheValues() async {
    try {
      await _cacheStore.init();
      _memory.addAll(_cacheStore.snapshot());
    } catch (e) {
      LoggerService.warning('SQLite cache unavailable during startup', e);
    }
  }

  Future<void> _migratePlaintextValues() async {
    for (final key in _legacyKeys) {
      final plaintextValue = _prefs.getString(key);
      if (plaintextValue == null) continue;
      if (!_memory.containsKey(key)) {
        await _writeString(key, plaintextValue);
      }
      if (_secureStorageAvailable) await _prefs.remove(key);
    }
  }

  Future<void> _migrateLegacyCacheValuesToSqlite() async {
    for (final key in _sqliteCacheKeys) {
      final value = _memory[key] ?? _prefs.getString(key);
      if (value == null) continue;
      try {
        await _cacheStore.writeString(key, value);
        await _deleteLegacyString(key);
      } catch (e) {
        LoggerService.warning('SQLite cache migration failed for $key', e);
      }
    }
  }

  Future<void> _writeString(String key, String value) async {
    _memory[key] = value;
    if (_sqliteCacheKeys.contains(key)) {
      try {
        await _cacheStore.writeString(key, value);
        await _deleteLegacyString(key);
        return;
      } catch (e) {
        LoggerService.warning('SQLite cache write failed, using fallback', e);
      }
    }

    if (_secureStorageAvailable) {
      try {
        await _secureStorage.write(key: key, value: value);
        await _prefs.remove(key);
        return;
      } catch (e) {
        _secureStorageAvailable = false;
        LoggerService.warning('Secure storage write failed, using fallback', e);
      }
    }
    await _prefs.setString(key, value);
  }

  String? _readString(String key) =>
      _memory[key] ?? _cacheStore.readString(key) ?? _prefs.getString(key);

  Future<void> _delete(String key) async {
    _memory.remove(key);
    if (_sqliteCacheKeys.contains(key)) {
      try {
        await _cacheStore.delete(key);
      } catch (e) {
        LoggerService.warning('SQLite cache delete failed', e);
      }
    }
    await _deleteLegacyString(key);
  }

  Future<void> _deleteLegacyString(String key) async {
    if (_secureStorageAvailable) {
      try {
        await _secureStorage.delete(key: key);
      } catch (e) {
        LoggerService.warning('Secure storage delete failed', e);
      }
    }
    await _prefs.remove(key);
  }

  bool _containsKey(String key) =>
      _memory.containsKey(key) || _prefs.containsKey(key);
}
