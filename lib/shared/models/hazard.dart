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
    ...localUploadColumns,
  };

  final dynamic id;
  final dynamic workerId;
  final dynamic hazardType;
  final dynamic description;
  final dynamic severity;
  final dynamic latitude;
  final dynamic longitude;
  final dynamic status;
  final String? createdAt;
  final dynamic imageUrl;
  final dynamic orphaned;
  final String? resolvedAt;
  final dynamic rankingScore;
  final dynamic officerUid;
  final dynamic voiceNoteUrl;
  final dynamic assignedTo;
  final dynamic currentSiteId;
  final String? assignedAt;
  final String? startedAt;
  final dynamic resolutionNotes;
  final dynamic resolutionImageUrl;
  final dynamic resolutionVoiceNoteUrl;
  final dynamic reportNumber;

  factory Hazard.fromMap(Map<String, dynamic> row) {
    return Hazard(
      id: row['id'],
      workerId: row['worker_id'],
      hazardType: row['hazard_type'],
      description: row['description'],
      severity: row['severity'],
      latitude: row['latitude'],
      longitude: row['longitude'],
      status: row['status'],
      createdAt: row['created_at']?.toString(),
      imageUrl: row['image_url'],
      orphaned: row['orphaned'],
      resolvedAt: row['resolved_at']?.toString(),
      rankingScore: row['ranking_score'],
      officerUid: row['officer_uid'],
      voiceNoteUrl: row['voice_note_url'],
      assignedTo: row['assigned_to'],
      currentSiteId: row['current_site_id'],
      assignedAt: row['assigned_at']?.toString(),
      startedAt: row['started_at']?.toString(),
      resolutionNotes: row['resolution_notes'],
      resolutionImageUrl: row['resolution_image_url'],
      resolutionVoiceNoteUrl: row['resolution_voice_note_url'],
      reportNumber: row['report_number'],
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
}
