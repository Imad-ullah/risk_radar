import 'package:flutter_test/flutter_test.dart';
import 'package:riskradar/services/sync_policy.dart';

void main() {
  const policy = SyncPolicy();

  test('allows worker hazard inserts with local upload fields', () {
    final action = policy.validateSyncAction(
      item: {'table': 'hazards', 'action': 'insert'},
      payload: {
        'id': 'hazard-1',
        'worker_id': 'worker-1',
        'hazard_type': 'Fire',
        'severity': 'High',
        'latitude': 24.9,
        'longitude': 67.1,
        'status': 'reported',
        'image_paths': ['local-image.jpg'],
      },
      role: 'worker',
      currentUserId: 'worker-1',
    );

    expect(action.table, 'hazards');
    expect(action.action, 'insert');
    expect(action.payload['image_paths'], ['local-image.jpg']);
  });

  test('rejects unknown sync columns', () {
    expect(
      () => policy.validateSyncAction(
        item: {'table': 'hazards', 'action': 'insert'},
        payload: {
          'id': 'hazard-1',
          'worker_id': 'worker-1',
          'hazard_type': 'Fire',
          'severity': 'High',
          'latitude': 24.9,
          'longitude': 67.1,
          'status': 'reported',
          'off_schema': true,
        },
        role: 'worker',
        currentUserId: 'worker-1',
      ),
      throwsA(isA<SyncValidationException>()),
    );
  });

  test('rejects worker inserting hazard for another user', () {
    expect(
      () => policy.validateSyncAction(
        item: {'table': 'hazards', 'action': 'insert'},
        payload: {
          'id': 'hazard-1',
          'worker_id': 'worker-2',
          'hazard_type': 'Fire',
          'severity': 'High',
          'latitude': 24.9,
          'longitude': 67.1,
          'status': 'reported',
        },
        role: 'worker',
        currentUserId: 'worker-1',
      ),
      throwsA(isA<SyncValidationException>()),
    );
  });

  test('rejects unsupported status values', () {
    expect(
      () => policy.validateSyncAction(
        item: {'table': 'assign_hazards', 'action': 'update'},
        payload: {
          'id': 'assign-1',
          'status': 'done-ish',
        },
        role: 'hse_worker',
        currentUserId: 'hse-1',
      ),
      throwsA(isA<SyncValidationException>()),
    );
  });

  test('validates assign hazard rpc payload', () {
    final action = policy.validateRpcAction(
      item: {'action': 'rpc', 'rpc': 'assign_hazard_to_hse'},
      payload: {
        'hazard_id': 'hazard-1',
        'assigned_to': 'hse-1',
        'assigned_at': '2026-05-15T00:00:00Z',
      },
      role: 'officer',
    );

    expect(action.name, 'assign_hazard_to_hse');
    expect(action.params['p_hazard_id'], 'hazard-1');
    expect(action.params['p_assigned_to'], 'hse-1');
  });
}
