import 'dart:convert';

import '../database/database_helper.dart';

class SqliteCacheStore {
  SqliteCacheStore._();

  static final SqliteCacheStore instance = SqliteCacheStore._();

  final Map<String, String> _values = {};
  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    final entries = await DatabaseHelper.instance.readAllCacheEntries();
    _values
      ..clear()
      ..addAll(entries);
    _initialised = true;
  }

  Map<String, String> snapshot() => Map.unmodifiable(_values);

  String? readString(String key) => _values[key];

  Object? readJson(String key) {
    final raw = readString(key);
    if (raw == null) return null;
    return jsonDecode(raw);
  }

  Future<void> writeString(String key, String value) async {
    _values[key] = value;
    await DatabaseHelper.instance.writeCacheEntry(key, value);
  }

  Map<String, dynamic>? readMap(String key) {
    final raw = readString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>>? readMapList(String key) {
    final raw = readString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) =>
      writeString(key, jsonEncode(value));

  Future<void> delete(String key) async {
    _values.remove(key);
    await DatabaseHelper.instance.deleteCacheEntry(key);
  }

  Future<void> clear() async {
    _values.clear();
    await DatabaseHelper.instance.clearCacheEntries();
  }
}
