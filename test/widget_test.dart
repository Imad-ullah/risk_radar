import 'package:flutter_test/flutter_test.dart';
import 'package:riskradar/shared/models/hazard.dart';

void main() {
  test('Hazard model normalizes hazard rows', () {
    final hazard = Hazard.fromMap({
      'id': 'hazard-1',
      'worker_id': 'worker-1',
      'officer_uid': 42,
      'current_site_id': 'site-1',
      'hazard_type': 'Fire',
      'description': 'Smoke near panel',
      'severity': 'High',
      'latitude': 24.9,
      'longitude': 67.1,
      'status': 'reported',
      'created_at': '2026-05-15T00:00:00Z',
      'unexpected_column': 'ignored',
    });

    final map = hazard.toHazardsMap();

    expect(map['id'], 'hazard-1');
    expect(map['worker_id'], 'worker-1');
    expect(map['officer_uid'], 42);
    expect(map['status'], 'reported');
    expect(map.containsKey('unexpected_column'), isFalse);
  });

  test('Hazard model normalizes assigned hazard rows', () {
    final hazard = Hazard.fromMap({
      'id': 'assign-1',
      'worker_id': 'worker-1',
      'assigned_to': 'hse-1',
      'assigned_at': DateTime.utc(2026, 5, 15),
      'started_at': DateTime.utc(2026, 5, 15, 1),
      'resolved_at': DateTime.utc(2026, 5, 15, 2),
      'resolution_notes': 'Resolved safely',
      'resolution_image_url': 'https://example.com/image.jpg',
      'resolution_voice_note_url': 'https://example.com/audio.mp3',
      'report_number': 12,
      'unexpected_column': 'ignored',
    });

    final map = hazard.toAssignHazardsMap();

    expect(map['id'], 'assign-1');
    expect(map['assigned_to'], 'hse-1');
    expect(map['assigned_at'], '2026-05-15 00:00:00.000Z');
    expect(map['started_at'], '2026-05-15 01:00:00.000Z');
    expect(map['resolved_at'], '2026-05-15 02:00:00.000Z');
    expect(map['report_number'], 12);
    expect(map.containsKey('unexpected_column'), isFalse);
  });

  test('Hazard model exposes sync field sets', () {
    expect(Hazard.hazardInsertColumns, containsAll(Hazard.hazardColumns));
    expect(Hazard.hazardInsertColumns, containsAll(Hazard.localUploadColumns));
    expect(
      Hazard.assignHazardInsertColumns,
      containsAll(Hazard.assignHazardColumns),
    );
    expect(
      Hazard.assignHazardUpdateColumns,
      containsAll({'id', 'status', 'resolution_notes'}),
    );
  });
}
