class Hazard {
  const Hazard({
    this.id,
    this.workerId,
    this.hazardType,
    this.description,
    this.severity,
    this.latitude,
    this.longitude,
    this.status,
    this.createdAt,
    this.imageUrl,
    this.orphaned,
    this.resolvedAt,
    this.rankingScore,
    this.officerUid,
    this.voiceNoteUrl,
    this.assignedTo,
    this.currentSiteId,
    this.assignedAt,
    this.startedAt,
    this.resolutionNotes,
    this.resolutionImageUrl,
    this.resolutionVoiceNoteUrl,
    this.reportNumber,
  });

  static const localUploadColumns = {'image_paths', 'voice_paths'};

  static const hazardColumns = {
    'id',
    'worker_id',
    'hazard_type',
    'description',
    'severity',
    'latitude',
    'longitude',
    'status',
    'created_at',
    'image_url',
    'voice_note_url',
    'officer_uid',
    'current_site_id',
    'orphaned',
    'resolved_at',
    'ranking_score',
    'assigned_to',
  };

  static const assignHazardColumns = {
    ...hazardColumns,
    'assigned_at',
    'started_at',
    'resolution_notes',
    'resolution_image_url',
    'resolution_voice_note_url',
    'report_number',
  };

  static const hazardInsertColumns = {
    ...hazardColumns,
    ...localUploadColumns,
  };

  static const assignHazardInsertColumns = {
    ...assignHazardColumns,
    ...localUploadColumns,
  };

  static const hazardStatusUpdateColumns = {
    'id',
    'status',
    'resolved_at',
  };

  static const assignHazardUpdateColumns = {
    'id',
    'status',
    'assigned_to',
    'assigned_at',
    'started_at',
    'resolved_at',
    'resolution_notes',
    'resolution_image_url',
    'resolution_voice_note_url',
    'report_number',
    ...localUploadColumns,
  };

  final String? id;
  final String? workerId;
  final String? hazardType;
  final String? description;
  final String? severity;
  final double? latitude;
  final double? longitude;
  final String? status;
  final String? createdAt;
  final String? imageUrl;
  final bool? orphaned;
  final String? resolvedAt;
  final double? rankingScore;
  final String? officerUid;
  final String? voiceNoteUrl;
  final String? assignedTo;
  final String? currentSiteId;
  final String? assignedAt;
  final String? startedAt;
  final String? resolutionNotes;
  final String? resolutionImageUrl;
  final String? resolutionVoiceNoteUrl;
  final String? reportNumber;

  factory Hazard.fromMap(Map<String, dynamic> row) {
    return Hazard(
      id: _toStringOrNull(row['id']),
      workerId: _toStringOrNull(row['worker_id']),
      hazardType: _toStringOrNull(row['hazard_type']),
      description: _toStringOrNull(row['description']),
      severity: _toStringOrNull(row['severity']),
      latitude: _toDoubleOrNull(row['latitude']),
      longitude: _toDoubleOrNull(row['longitude']),
      status: _toStringOrNull(row['status']),
      createdAt: row['created_at']?.toString(),
      imageUrl: _toStringOrNull(row['image_url']),
      orphaned: _toBoolOrNull(row['orphaned']),
      resolvedAt: row['resolved_at']?.toString(),
      rankingScore: _toDoubleOrNull(row['ranking_score']),
      officerUid: _toStringOrNull(row['officer_uid']),
      voiceNoteUrl: _toStringOrNull(row['voice_note_url']),
      assignedTo: _toStringOrNull(row['assigned_to']),
      currentSiteId: _toStringOrNull(row['current_site_id']),
      assignedAt: row['assigned_at']?.toString(),
      startedAt: row['started_at']?.toString(),
      resolutionNotes: _toStringOrNull(row['resolution_notes']),
      resolutionImageUrl: _toStringOrNull(row['resolution_image_url']),
      resolutionVoiceNoteUrl: _toStringOrNull(row['resolution_voice_note_url']),
      reportNumber: _toStringOrNull(row['report_number']),
    );
  }

  Map<String, dynamic> toHazardsMap() {
    return {
      'id': id,
      'worker_id': workerId,
      'hazard_type': hazardType,
      'description': description,
      'severity': severity,
      'latitude': latitude,
      'longitude': longitude,
      'status': status,
      'created_at': createdAt,
      'image_url': imageUrl,
      'orphaned': orphaned,
      'resolved_at': resolvedAt,
      'ranking_score': rankingScore,
      'officer_uid': officerUid,
      'voice_note_url': voiceNoteUrl,
      'assigned_to': assignedTo,
      'current_site_id': currentSiteId,
    };
  }

  Map<String, dynamic> toAssignHazardsMap() {
    return {
      ...toHazardsMap(),
      'assigned_at': assignedAt,
      'started_at': startedAt,
      'resolution_notes': resolutionNotes,
      'resolution_image_url': resolutionImageUrl,
      'resolution_voice_note_url': resolutionVoiceNoteUrl,
      'report_number': reportNumber,
    };
  }

  Map<String, dynamic> toMap({bool assigned = false}) {
    return assigned ? toAssignHazardsMap() : toHazardsMap();
  }

  static String? _toStringOrNull(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static double? _toDoubleOrNull(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  static bool? _toBoolOrNull(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return null;
  }
}
