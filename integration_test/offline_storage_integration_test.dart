import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riskradar/services/database/database_helper.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
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
      final repository = HazardRepository();
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

      await repository.saveHazards([hazard]);

      final rows = await repository.getHazards();
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'integration-hazard-1');
      expect(rows.single['status'], 'reported');
    });

    testWidgets('persists and removes sync queue actions', (_) async {
      final repository = SyncRepository();

      await repository.enqueueAction(
        id: 'integration-sync-1',
        table: 'hazards',
        action: 'insert',
        payload: {
          'id': 'integration-hazard-2',
          'worker_id': 'worker-1',
          'hazard_type': 'Fire',
          'severity': 'High',
          'latitude': 24.9,
          'longitude': 67.1,
          'status': 'reported',
        },
      );

      final pending = await repository.getPendingActions();
      expect(pending, hasLength(1));
      expect(pending.single['id'], 'integration-sync-1');

      await repository.removeAction('integration-sync-1');

      final afterRemove = await repository.getPendingActions();
      expect(afterRemove, isEmpty);
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
