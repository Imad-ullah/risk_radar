import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static const _databaseName = 'riskradar.db';
  static const _databaseVersion = 4;

  static const syncQueueTable = 'sync_queue';
  static const hazardsTable = 'hazards';
  static const sitesTable = 'sites';
  static const cacheTable = 'cache_entries';

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final dbPath = await getDatabasesPath();
    final path = _joinPath(dbPath, _databaseName);
    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _database = db;
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createSyncQueueTable(db);
    await _createHazardsTable(db);
    await _createSitesTable(db);
    await _createCacheTable(db);
    await _createIndexes(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _createSyncQueueTable(db);
    await _createSitesTable(db);
    await _migrateHazardsTableIfNeeded(db);

    if (oldVersion < 3) {
      await _createCacheTable(db);
    }

    if (oldVersion < 4) {
      await _migrateCacheKeyColumn(db);
    }

    await _createIndexes(db);
  }

  Future<void> _createSyncQueueTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncQueueTable (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        action TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createHazardsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $hazardsTable (
        id TEXT NOT NULL,
        source_table TEXT NOT NULL,
        status TEXT,
        payload_json TEXT NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        PRIMARY KEY (id, source_table)
      )
    ''');
  }

  Future<void> _createSitesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $sitesTable (
        id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createCacheTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $cacheTable (
        cache_key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_created_at '
      'ON $syncQueueTable(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_hazards_status '
      'ON $hazardsTable(status)',
    );
  }

  Future<void> _migrateHazardsTableIfNeeded(Database db) async {
    final tableInfo = await db.rawQuery('PRAGMA table_info($hazardsTable)');
    if (tableInfo.isEmpty) {
      await _createHazardsTable(db);
      return;
    }

    final columnNames = tableInfo.map((row) => row['name'] as String).toSet();
    const requiredColumns = {
      'id',
      'source_table',
      'status',
      'payload_json',
      'created_at',
      'updated_at',
    };
    if (requiredColumns.every(columnNames.contains)) return;

    final legacyTable = '${hazardsTable}_legacy';
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.execute('DROP TABLE IF EXISTS $legacyTable');
      await txn.execute('ALTER TABLE $hazardsTable RENAME TO $legacyTable');
      await _createHazardsTable(txn);

      final legacyRows = await txn.query(legacyTable);
      for (final row in legacyRows) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;

        final payloadJson = row['payload_json']?.toString();
        await txn.insert(
          hazardsTable,
          {
            'id': id,
            'source_table': row['source_table']?.toString() ?? hazardsTable,
            'status': row['status']?.toString(),
            'payload_json': payloadJson == null || payloadJson.isEmpty
                ? jsonEncode(row)
                : payloadJson,
            'created_at': row['created_at']?.toString(),
            'updated_at': row['updated_at']?.toString() ?? now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.execute('DROP TABLE IF EXISTS $legacyTable');
    });
  }

  Future<void> _migrateCacheKeyColumn(Database db) async {
    final tableInfo = await db.rawQuery('PRAGMA table_info($cacheTable)');
    if (tableInfo.isEmpty) {
      await _createCacheTable(db);
      return;
    }

    final columnNames = tableInfo.map((row) => row['name']).toSet();
    final hasOldKeyColumn = columnNames.contains('key');
    final hasCacheKeyColumn = columnNames.contains('cache_key');
    if (!hasOldKeyColumn || hasCacheKeyColumn) return;

    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE ${cacheTable}_new (
          cache_key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await txn.execute('''
        INSERT INTO ${cacheTable}_new (cache_key, value, updated_at)
        SELECT "key", value, updated_at FROM $cacheTable
      ''');
      await txn.execute('DROP TABLE $cacheTable');
      await txn.execute('ALTER TABLE ${cacheTable}_new RENAME TO $cacheTable');
    });
  }

  Future<void> upsertSyncAction({
    required String id,
    required String table,
    required String action,
    required Map<String, dynamic> payload,
    String? createdAt,
  }) async {
    final db = await database;
    await db.insert(
      syncQueueTable,
      {
        'id': id,
        'table_name': table,
        'action': action,
        'payload_json': jsonEncode(payload),
        'created_at': createdAt ?? DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getSyncActions() async {
    final db = await database;
    final rows = await db.query(
      syncQueueTable,
      orderBy: 'created_at ASC',
    );

    return rows.map(_decodeSyncAction).toList();
  }

  Future<void> removeSyncAction(String id) async {
    final db = await database;
    await db.delete(syncQueueTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearSyncQueue() async {
    final db = await database;
    await db.delete(syncQueueTable);
  }

  Future<void> clearHazards() async {
    final db = await database;
    await db.delete(hazardsTable);
  }

  Future<void> writeCacheEntry(String key, String value) async {
    final db = await database;
    await db.insert(
      cacheTable,
      {
        'cache_key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> readCacheEntry(String key) async {
    final db = await database;
    final rows = await db.query(
      cacheTable,
      columns: ['value'],
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<Map<String, String>> readAllCacheEntries() async {
    final db = await database;
    final rows = await db.query(cacheTable);
    return {
      for (final row in rows) row['cache_key'] as String: row['value'] as String,
    };
  }

  Future<void> deleteCacheEntry(String key) async {
    final db = await database;
    await db.delete(cacheTable, where: 'cache_key = ?', whereArgs: [key]);
  }

  Future<void> clearCacheEntries() async {
    final db = await database;
    await db.delete(cacheTable);
  }

  Future<int> getSyncQueueCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $syncQueueTable',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> upsertHazard({
    required String id,
    required String sourceTable,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    await db.insert(
      hazardsTable,
      {
        'id': id,
        'source_table': sourceTable,
        'status': payload['status']?.toString(),
        'payload_json': jsonEncode(payload),
        'created_at': payload['created_at']?.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceHazardsForSource({
    required String sourceTable,
    required Iterable<Map<String, Object?>> rows,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        hazardsTable,
        where: 'source_table = ?',
        whereArgs: [sourceTable],
      );

      for (final row in rows) {
        final String? id = row['id']?.toString();
        if (id == null || id.isEmpty) {
          continue;
        }

        await txn.insert(
          hazardsTable,
          {
            'id': id,
            'source_table': sourceTable,
            'status': row['status']?.toString(),
            'payload_json': jsonEncode(row),
            'created_at': row['created_at']?.toString(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getHazards({String? sourceTable}) async {
    final db = await database;
    final rows = await db.query(
      hazardsTable,
      where: sourceTable == null ? null : 'source_table = ?',
      whereArgs: sourceTable == null ? null : [sourceTable],
      orderBy: 'created_at DESC',
    );

    return rows.map((row) {
      final payload = jsonDecode(row['payload_json'] as String);
      return Map<String, dynamic>.from(payload as Map);
    }).toList();
  }

  String _joinPath(String dir, String fileName) {
    if (dir.endsWith('/') || dir.endsWith('\\')) return '$dir$fileName';
    return '$dir/$fileName';
  }

  Map<String, dynamic> _decodeSyncAction(Map<String, dynamic> row) {
    final payload = jsonDecode(row['payload_json'] as String);
    return {
      'id': row['id'],
      'table': row['table_name'],
      'action': row['action'],
      'payload': Map<String, dynamic>.from(payload as Map),
      'createdAt': row['created_at'],
    };
  }
}
