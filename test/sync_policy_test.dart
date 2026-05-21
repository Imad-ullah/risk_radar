import 'package:flutter_test/flutter_test.dart';
import 'package:riskradar/services/sync_policy.dart';

void main() {
  const SyncPolicy policy = SyncPolicy();

  group('allowedColumnsFor', () {
    test('returns whitelists for every supported table and action', () {
      expect(policy.allowedColumnsFor('hazards', 'insert'), isNotNull);
      expect(policy.allowedColumnsFor('hazards', 'update'), isNotNull);
      expect(policy.allowedColumnsFor('hazards', 'delete'), {'id'});
      expect(policy.allowedColumnsFor('assign_hazards', 'insert'), isNotNull);
      expect(policy.allowedColumnsFor('assign_hazards', 'update'), isNotNull);
      expect(policy.allowedColumnsFor('assign_hazards', 'delete'), {'id'});
      expect(policy.allowedColumnsFor('resolved_hazards', 'insert'), isNotNull);
      expect(policy.allowedColumnsFor('sites', 'insert'), isNotNull);
      expect(policy.allowedColumnsFor('sites', 'update'), isNotNull);
      expect(policy.allowedColumnsFor('sites', 'delete'), {'id'});
      expect(policy.allowedColumnsFor('officers', 'update'), isNotNull);
      expect(policy.allowedColumnsFor('workers', 'update'), isNotNull);
      expect(policy.allowedColumnsFor('workers', 'delete'), {'id'});
      expect(policy.allowedColumnsFor('hse_workers', 'update'), isNotNull);
      expect(policy.allowedColumnsFor('hse_workers', 'delete'), {'id'});
      expect(
        policy.allowedColumnsFor('officer_emergency_contacts', 'insert'),
        isNotNull,
      );
      expect(
        policy.allowedColumnsFor('officer_emergency_contacts', 'update'),
        isNotNull,
      );
    });

    test('returns null for unsupported table and action pairs', () {
      expect(policy.allowedColumnsFor('resolved_hazards', 'update'), isNull);
      expect(policy.allowedColumnsFor('officers', 'insert'), isNull);
      expect(policy.allowedColumnsFor('unknown_table', 'insert'), isNull);
    });
  });

  group('validateSyncAction allows valid operations', () {
    test('worker inserts own hazard with local upload fields', () {
      final ValidatedSyncAction action = policy.validateSyncAction(
        item: {'table': 'hazards', 'action': 'insert'},
        payload: {
          'id': 'hazard-1',
          'worker_id': 'worker-1',
          'hazard_type': 'Fire',
          'description': 'Smoke near panel',
          'severity': 'High',
          'latitude': 24.9,
          'longitude': 67.1,
          'status': 'reported',
          'image_paths': ['local-image.jpg'],
          'voice_paths': ['local-audio.m4a'],
        },
        role: 'worker',
        currentUserId: 'worker-1',
      );

      expect(action.table, 'hazards');
      expect(action.action, 'insert');
      expect(action.payload['image_paths'], ['local-image.jpg']);
      expect(action.payload['voice_paths'], ['local-audio.m4a']);
    });

    test('officer updates and deletes hazards', () {
      final ValidatedSyncAction updateAction = policy.validateSyncAction(
        item: {'table': 'hazards', 'action': 'update'},
        payload: {
          'id': 'hazard-1',
          'status': 'resolved',
          'resolved_at': '2026-05-18T00:00:00Z',
        },
        role: 'officer',
        currentUserId: 'officer-1',
      );
      final ValidatedSyncAction deleteAction = policy.validateSyncAction(
        item: {'table': 'hazards', 'action': 'delete'},
        payload: {'id': 'hazard-1'},
        role: 'officer',
        currentUserId: 'officer-1',
      );

      expect(updateAction.action, 'update');
      expect(deleteAction.action, 'delete');
    });

    test('officer manages sites and emergency contacts', () {
      expect(
        policy.validateSyncAction(
          item: {'table': 'sites', 'action': 'insert'},
          payload: {
            'id': 'site-1',
            'name': 'North Yard',
            'description': 'Main operational area',
            'officer_uid': 'officer-1',
          },
          role: 'officer',
          currentUserId: 'officer-1',
        ).table,
        'sites',
      );
      expect(
        policy.validateSyncAction(
          item: {'table': 'officer_emergency_contacts', 'action': 'insert'},
          payload: {
            'id': 'contact-1',
            'officer_id': 'officer-1',
            'officer_uid': 'officer-1',
            'contact_name': 'Site Supervisor',
            'emergency_contact_phone': '+920000000000',
          },
          role: 'officer',
          currentUserId: 'officer-1',
        ).table,
        'officer_emergency_contacts',
      );
    });

    test('officer updates own profile and manages profile records', () {
      expect(
        policy.validateSyncAction(
          item: {'table': 'officers', 'action': 'update'},
          payload: {
            'id': 'officer-1',
            'first_name': 'Amina',
            'last_name': 'Khan',
            'email': 'amina@example.com',
            'dob': '1990-01-01',
            'image_paths': ['profile.jpg'],
          },
          role: 'officer',
          currentUserId: 'officer-1',
        ).table,
        'officers',
      );
      expect(
        policy.validateSyncAction(
          item: {'table': 'workers', 'action': 'update'},
          payload: {'id': 'worker-1', 'current_site_id': 'site-1'},
          role: 'officer',
          currentUserId: 'officer-1',
        ).table,
        'workers',
      );
      expect(
        policy.validateSyncAction(
          item: {'table': 'hse_workers', 'action': 'update'},
          payload: {
            'id': 'hse-1',
            'current_site_id': 'site-1',
            'is_available': true,
          },
          role: 'officer',
          currentUserId: 'officer-1',
        ).table,
        'hse_workers',
      );
    });

    test('worker can update only own worker profile photo', () {
      final ValidatedSyncAction action = policy.validateSyncAction(
        item: {'table': 'workers', 'action': 'update'},
        payload: {
          'id': 'worker-1',
          'profile_image_url': 'https://example.com/profile.jpg',
          'image_paths': ['profile.jpg'],
        },
        role: 'worker',
        currentUserId: 'worker-1',
      );

      expect(action.table, 'workers');
      expect(action.payload['profile_image_url'], contains('profile.jpg'));
    });

    test('hse worker updates own availability', () {
      final ValidatedSyncAction action = policy.validateSyncAction(
        item: {'table': 'hse_workers', 'action': 'update'},
        payload: {'id': 'hse-1', 'is_available': false},
        role: 'hse_worker',
        currentUserId: 'hse-1',
      );

      expect(action.table, 'hse_workers');
      expect(action.payload['is_available'], false);
    });

    test('officer inserts, hse worker updates, and officer deletes assignments', () {
      expect(
        policy.validateSyncAction(
          item: {'table': 'assign_hazards', 'action': 'insert'},
          payload: {
            'id': 'assign-1',
            'assigned_to': 'hse-1',
            'status': 'assigned',
          },
          role: 'officer',
          currentUserId: 'officer-1',
        ).action,
        'insert',
      );
      expect(
        policy.validateSyncAction(
          item: {'table': 'assign_hazards', 'action': 'update'},
          payload: {
            'id': 'assign-1',
            'status': 'in_progress',
            'started_at': '2026-05-18T01:00:00Z',
          },
          role: 'hse_worker',
          currentUserId: 'hse-1',
        ).action,
        'update',
      );
      expect(
        policy.validateSyncAction(
          item: {'table': 'assign_hazards', 'action': 'delete'},
          payload: {'id': 'assign-1'},
          role: 'officer',
          currentUserId: 'officer-1',
        ).action,
        'delete',
      );
    });

    test('officer inserts resolved hazards', () {
      final ValidatedSyncAction action = policy.validateSyncAction(
        item: {'table': 'resolved_hazards', 'action': 'insert'},
        payload: {
          'id': 'resolved-1',
          'status': 'resolved',
          'resolved_at': '2026-05-18T02:00:00Z',
          'resolution_notes': 'Area made safe.',
        },
        role: 'officer',
        currentUserId: 'officer-1',
      );

      expect(action.table, 'resolved_hazards');
    });
  });

  group('validateSyncAction rejects invalid operations', () {
    test('rejects missing table, missing action, and unsupported actions', () {
      expect(
        () => policy.validateSyncAction(
          item: {'action': 'insert'},
          payload: {'id': 'row-1'},
          role: 'officer',
          currentUserId: 'officer-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
      expect(
        () => policy.validateSyncAction(
          item: {'table': 'hazards'},
          payload: {'id': 'row-1'},
          role: 'officer',
          currentUserId: 'officer-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
      expect(
        () => policy.validateSyncAction(
          item: {'table': 'hazards', 'action': 'upsert'},
          payload: {'id': 'row-1'},
          role: 'officer',
          currentUserId: 'officer-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
    });

    test('rejects unsupported table action combinations', () {
      expect(
        () => policy.validateSyncAction(
          item: {'table': 'resolved_hazards', 'action': 'update'},
          payload: {'id': 'resolved-1'},
          role: 'officer',
          currentUserId: 'officer-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
    });

    test('rejects unknown columns before role validation', () {
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

    test('rejects missing required fields', () {
      expect(
        () => policy.validateSyncAction(
          item: {'table': 'hazards', 'action': 'insert'},
          payload: {
            'id': 'hazard-1',
            'worker_id': 'worker-1',
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
      expect(
        () => policy.validateSyncAction(
          item: {'table': 'hazards', 'action': 'delete'},
          payload: {'id': ' '},
          role: 'officer',
          currentUserId: 'officer-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
    });

    test('rejects unsupported statuses', () {
      expect(
        () => policy.validateSyncAction(
          item: {'table': 'assign_hazards', 'action': 'update'},
          payload: {'id': 'assign-1', 'status': 'done-ish'},
          role: 'hse_worker',
          currentUserId: 'hse-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
    });

    test('rejects missing role and disallowed role combinations', () {
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
          },
          role: null,
          currentUserId: 'worker-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
      expect(
        () => policy.validateSyncAction(
          item: {'table': 'sites', 'action': 'insert'},
          payload: {'id': 'site-1', 'name': 'North Yard'},
          role: 'worker',
          currentUserId: 'worker-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
    });

    test('rejects payload owner mismatches', () {
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
      expect(
        () => policy.validateSyncAction(
          item: {'table': 'officers', 'action': 'update'},
          payload: {'id': 'officer-2', 'first_name': 'Amina'},
          role: 'officer',
          currentUserId: 'officer-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
      expect(
        () => policy.validateSyncAction(
          item: {'table': 'hse_workers', 'action': 'update'},
          payload: {'id': 'hse-2', 'is_available': true},
          role: 'hse_worker',
          currentUserId: 'hse-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
    });

    test('rejects worker profile updates beyond profile photo fields', () {
      expect(
        () => policy.validateSyncAction(
          item: {'table': 'workers', 'action': 'update'},
          payload: {'id': 'worker-1', 'current_site_id': 'site-1'},
          role: 'worker',
          currentUserId: 'worker-1',
        ),
        throwsA(isA<SyncValidationException>()),
      );
    });
  });

  group('validateRpcAction', () {
    test('allows officer assignment RPC and normalizes parameters', () {
      final ValidatedRpcAction action = policy.validateRpcAction(
        item: {'action': 'rpc', 'rpc': 'assign_hazard_to_hse'},
        payload: {
          'hazard_id': 'hazard-1',
          'assigned_to': 'hse-1',
          'assigned_at': '2026-05-18T00:00:00Z',
        },
        role: 'officer',
      );

      expect(action.name, 'assign_hazard_to_hse');
      expect(action.params['p_hazard_id'], 'hazard-1');
      expect(action.params['p_assigned_to'], 'hse-1');
      expect(action.params['p_assigned_at'], '2026-05-18T00:00:00Z');
    });

    test('rejects invalid RPC role, name, columns, and required fields', () {
      expect(
        () => policy.validateRpcAction(
          item: {'action': 'rpc', 'rpc': 'assign_hazard_to_hse'},
          payload: {'hazard_id': 'hazard-1', 'assigned_to': 'hse-1'},
          role: 'worker',
        ),
        throwsA(isA<SyncValidationException>()),
      );
      expect(
        () => policy.validateRpcAction(
          item: {'action': 'rpc', 'rpc': 'unknown_rpc'},
          payload: {'hazard_id': 'hazard-1', 'assigned_to': 'hse-1'},
          role: 'officer',
        ),
        throwsA(isA<SyncValidationException>()),
      );
      expect(
        () => policy.validateRpcAction(
          item: {'action': 'rpc', 'rpc': 'assign_hazard_to_hse'},
          payload: {
            'hazard_id': 'hazard-1',
            'assigned_to': 'hse-1',
            'off_schema': true,
          },
          role: 'officer',
        ),
        throwsA(isA<SyncValidationException>()),
      );
      expect(
        () => policy.validateRpcAction(
          item: {'action': 'rpc', 'rpc': 'assign_hazard_to_hse'},
          payload: {'hazard_id': 'hazard-1'},
          role: 'officer',
        ),
        throwsA(isA<SyncValidationException>()),
      );
    });
  });
}
