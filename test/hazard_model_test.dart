import 'package:flutter_test/flutter_test.dart';
import 'package:riskradar/shared/models/hazard.dart';

void main() {
  group('Hazard.fromMap', () {
    test('round-trips every hazard and assignment field', () {
      final Hazard hazard = Hazard.fromMap({
        'id': 'hazard-1',
        'worker_id': 'worker-1',
        'hazard_type': 'Fire',
        'description': 'Smoke near the main electrical panel.',
        'severity': 'High',
        'latitude': '24.9021',
        'longitude': 67.1155,
        'status': 'resolved',
        'created_at': DateTime.utc(2026, 5, 18, 8),
        'image_url': 'https://example.com/hazard.jpg',
        'voice_note_url': 'https://example.com/hazard.m4a',
        'officer_uid': 98765,
        'current_site_id': 'site-1',
        'orphaned': 0,
        'resolved_at': DateTime.utc(2026, 5, 18, 10),
        'ranking_score': '91.5',
        'assigned_to': 'hse-1',
        'assigned_at': DateTime.utc(2026, 5, 18, 8, 30),
        'started_at': DateTime.utc(2026, 5, 18, 9),
        'resolution_notes': 'Panel isolated and smoke source removed.',
        'resolution_image_url': 'https://example.com/resolution.jpg',
        'resolution_voice_note_url': 'https://example.com/resolution.m4a',
        'report_number': 42,
        'unexpected_column': 'ignored',
      });

      expect(hazard.id, 'hazard-1');
      expect(hazard.workerId, 'worker-1');
      expect(hazard.hazardType, 'Fire');
      expect(hazard.description, 'Smoke near the main electrical panel.');
      expect(hazard.severity, 'High');
      expect(hazard.latitude, 24.9021);
      expect(hazard.longitude, 67.1155);
      expect(hazard.status, 'resolved');
      expect(hazard.createdAt, '2026-05-18 08:00:00.000Z');
      expect(hazard.imageUrl, 'https://example.com/hazard.jpg');
      expect(hazard.voiceNoteUrl, 'https://example.com/hazard.m4a');
      expect(hazard.officerUid, '98765');
      expect(hazard.currentSiteId, 'site-1');
      expect(hazard.orphaned, isFalse);
      expect(hazard.resolvedAt, '2026-05-18 10:00:00.000Z');
      expect(hazard.rankingScore, 91.5);
      expect(hazard.assignedTo, 'hse-1');
      expect(hazard.assignedAt, '2026-05-18 08:30:00.000Z');
      expect(hazard.startedAt, '2026-05-18 09:00:00.000Z');
      expect(hazard.resolutionNotes, 'Panel isolated and smoke source removed.');
      expect(hazard.resolutionImageUrl, 'https://example.com/resolution.jpg');
      expect(hazard.resolutionVoiceNoteUrl, 'https://example.com/resolution.m4a');
      expect(hazard.reportNumber, '42');

      final hazardsMap = hazard.toHazardsMap();
      expect(hazardsMap.keys, containsAll(Hazard.hazardColumns));
      expect(hazardsMap.keys, isNot(contains('assigned_at')));
      expect(hazardsMap.keys, isNot(contains('unexpected_column')));
      expect(hazardsMap['latitude'], 24.9021);
      expect(hazardsMap['orphaned'], isFalse);

      final assignMap = hazard.toAssignHazardsMap();
      expect(assignMap.keys, containsAll(Hazard.assignHazardColumns));
      expect(assignMap.keys, isNot(contains('unexpected_column')));
      expect(assignMap['assigned_at'], '2026-05-18 08:30:00.000Z');
      expect(assignMap['resolution_notes'], 'Panel isolated and smoke source removed.');
      expect(assignMap['report_number'], '42');

      expect(hazard.toMap(), hazardsMap);
      expect(hazard.toMap(assigned: true), assignMap);
    });

    test('normalizes empty, invalid, numeric, and boolean-like values safely', () {
      final Hazard hazard = Hazard.fromMap({
        'id': '',
        'worker_id': null,
        'latitude': 'not-a-number',
        'longitude': 0,
        'orphaned': 'true',
        'ranking_score': null,
      });

      expect(hazard.id, isNull);
      expect(hazard.workerId, isNull);
      expect(hazard.latitude, isNull);
      expect(hazard.longitude, 0.0);
      expect(hazard.orphaned, isTrue);
      expect(hazard.rankingScore, isNull);
    });

    test('sync field sets contain expected upload and resolution columns', () {
      expect(Hazard.localUploadColumns, {'image_paths', 'voice_paths'});
      expect(Hazard.hazardInsertColumns, containsAll(Hazard.hazardColumns));
      expect(Hazard.hazardInsertColumns, containsAll(Hazard.localUploadColumns));
      expect(
        Hazard.assignHazardInsertColumns,
        containsAll(Hazard.assignHazardColumns),
      );
      expect(
        Hazard.assignHazardUpdateColumns,
        containsAll({
          'id',
          'status',
          'started_at',
          'resolved_at',
          'resolution_notes',
          'resolution_image_url',
          'resolution_voice_note_url',
          'report_number',
          'image_paths',
          'voice_paths',
        }),
      );
    });
  });
}
