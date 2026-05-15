import '../database/database_helper.dart';
import 'sqlite_cache_store.dart';

class SyncRepository {
  SyncRepository({
    DatabaseHelper? databaseHelper,
    SqliteCacheStore? cacheStore,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _cacheStore = cacheStore ?? SqliteCacheStore.instance;

  static const _legacySyncQueueKey = 'rr_sync_queue';

  final DatabaseHelper _databaseHelper;
  final SqliteCacheStore _cacheStore;

  Future<void> enqueueAction({
    required String id,
    required String table,
    required String action,
    required Map<String, dynamic> payload,
    String? createdAt,
  }) {
    return _databaseHelper.upsertSyncAction(
      id: id,
      table: table,
      action: action,
      payload: payload,
      createdAt: createdAt,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingActions() async {
    await migrateLegacyQueue();
    return _databaseHelper.getSyncActions();
  }

  Future<void> removeAction(String id) async {
    await _databaseHelper.removeSyncAction(id);
    await _removeLegacyAction(id);
  }

  Future<void> clear() async {
    await _databaseHelper.clearSyncQueue();
    await _cacheStore.delete(_legacySyncQueueKey);
  }

  Future<bool> hasPendingActions() async {
    await migrateLegacyQueue();
    return (await _databaseHelper.getSyncQueueCount()) > 0;
  }

  Future<void> migrateLegacyQueue() async {
    final legacyQueue = _cacheStore.readMapList(_legacySyncQueueKey) ?? [];
    if (legacyQueue.isEmpty) return;

    for (final item in legacyQueue) {
      final id = item['id']?.toString();
      final table = item['table']?.toString();
      final action = item['action']?.toString();
      final payload = item['payload'];

      if (id == null || table == null || action == null || payload is! Map) {
        continue;
      }

      await enqueueAction(
        id: id,
        table: table,
        action: action,
        payload: Map<String, dynamic>.from(payload),
        createdAt: item['createdAt']?.toString(),
      );
    }
  }

  Future<void> _removeLegacyAction(String id) async {
    final legacyQueue = _cacheStore.readMapList(_legacySyncQueueKey);
    if (legacyQueue == null || legacyQueue.isEmpty) return;

    legacyQueue.removeWhere((item) => item['id'] == id);
    if (legacyQueue.isEmpty) {
      await _cacheStore.delete(_legacySyncQueueKey);
    } else {
      await _cacheStore.writeJson(_legacySyncQueueKey, legacyQueue);
    }
  }
}
