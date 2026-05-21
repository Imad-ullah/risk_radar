import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riskradar/services/database/database_helper.dart';
import 'package:riskradar/services/repositories/sqlite_cache_store.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('offline SQLite storage', () {
    setUp(() async {
      await DatabaseHelper.instance.clearHazards();
      await DatabaseHelper.instance.clearSyncQueue();
      await SqliteCacheStore.instance.init();
      await SqliteCacheStore.instance.clear();
    });

    testWidgets('stores and reads hazard cache rows', (_) async {
      final hazard = {
        'id': 'integration-hazard-1',
        'worker_id': 'worker-1',
        'hazard_type': 'Fire',
        'description': 'Smoke near panel',
        'severity': 'High',
        'latitude': 24.9,
        'longitude': 67.1,
        'status': 'reported',
        'created_at': '2026-05-15T00:00:00Z',
      };

      await DatabaseHelper.instance.upsertHazard(
        id: 'integration-hazard-1',
        sourceTable: DatabaseHelper.hazardsTable,
        payload: hazard,
      );

      final rows = await DatabaseHelper.instance.getHazards(
        sourceTable: DatabaseHelper.hazardsTable,
      );
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'integration-hazard-1');
      expect(rows.single['status'], 'reported');
    });

    testWidgets(
        'queues an offline hazard in SQLite and removes it after sync mock',
        (_) async {
      final repository = SyncRepository();
      final hazardPayload = {
        'id': 'integration-hazard-2',
        'worker_id': 'worker-1',
        'hazard_type': 'Fire',
        'description': 'Smoke near panel',
        'severity': 'High',
        'latitude': 24.9,
        'longitude': 67.1,
        'status': 'reported',
        'created_at': '2026-05-15T00:00:00Z',
        'image_paths': ['local-hazard-photo.jpg'],
      };

      await repository.enqueueAction(
        id: 'integration-sync-1',
        table: 'hazards',
        action: 'insert',
        payload: hazardPayload,
      );

      final pending = await repository.getPendingActions();
      expect(pending, hasLength(1));
      expect(pending.single['id'], 'integration-sync-1');
      expect(pending.single['table'], 'hazards');
      expect(pending.single['action'], 'insert');
      expect(pending.single['payload'], hazardPayload);

      final rawQueueRows = await DatabaseHelper.instance.getSyncActions();
      expect(rawQueueRows, hasLength(1));
      expect(rawQueueRows.single['payload'], hazardPayload);
      expect(await DatabaseHelper.instance.getSyncQueueCount(), 1);

      // The production sync service removes the queue item after a successful
      // remote write. This repository call is the success-side mock.
      await repository.removeAction('integration-sync-1');

      final afterRemove = await repository.getPendingActions();
      expect(afterRemove, isEmpty);
      expect(await DatabaseHelper.instance.getSyncQueueCount(), 0);
    });

    testWidgets('stores and clears generic SQLite cache entries', (_) async {
      final cache = SqliteCacheStore.instance;

      await cache.writeJson('integration-cache-key', {
        'name': 'RiskRadar',
        'offline': true,
      });

      final value = cache.readMap('integration-cache-key');
      expect(value?['name'], 'RiskRadar');
      expect(value?['offline'], isTrue);

      await cache.delete('integration-cache-key');
      expect(cache.readMap('integration-cache-key'), isNull);
    });
  });
}
