abstract interface class AppUser {
  String? get id;
  String? get firstName;
  String? get lastName;
  String? get email;
  String? get role;
  String? get officerUid;
  String? get profileImageUrl;

  Map<String, dynamic> toMap();
}

class Worker implements AppUser {
  const Worker({
    this.id,
    this.firstName,
    this.lastName,
    this.email,
    this.role,
    this.officerUid,
    this.workType,
    this.profileImageUrl,
    this.isActive,
    this.defaultSiteId,
    this.currentSiteId,
  });

  @override
  final String? id;
  @override
  final String? firstName;
  @override
  final String? lastName;
  @override
  final String? email;
  @override
  final String? role;
  @override
  final String? officerUid;
  final String? workType;
  @override
  final String? profileImageUrl;
  final bool? isActive;
  final String? defaultSiteId;
  final String? currentSiteId;

  factory Worker.fromMap(Map<String, dynamic> row) {
    return Worker(
      id: _toStringOrNull(row['id']),
      firstName: _toStringOrNull(row['first_name']),
      lastName: _toStringOrNull(row['last_name']),
      email: _toStringOrNull(row['email']),
      role: _toStringOrNull(row['role']),
      officerUid: _toStringOrNull(row['officer_uid']),
      workType: _toStringOrNull(row['work_type']),
      profileImageUrl: _toStringOrNull(row['profile_image_url']),
      isActive: _toBoolOrNull(row['is_active']),
      defaultSiteId: _toStringOrNull(row['default_site_id']),
      currentSiteId: _toStringOrNull(row['current_site_id']),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'role': role,
      'officer_uid': officerUid,
      'work_type': workType,
      'profile_image_url': profileImageUrl,
      'is_active': isActive,
      'default_site_id': defaultSiteId,
      'current_site_id': currentSiteId,
    };
  }
}

class HseWorker implements AppUser {
  const HseWorker({
    this.id,
    this.firstName,
    this.lastName,
    this.email,
    this.role,
    this.officerUid,
    this.designation,
    this.profileImageUrl,
    this.isActive,
    this.isAvailable,
    this.currentSiteId,
  });

  @override
  final String? id;
  @override
  final String? firstName;
  @override
  final String? lastName;
  @override
  final String? email;
  @override
  final String? role;
  @override
  final String? officerUid;
  final String? designation;
  @override
  final String? profileImageUrl;
  final bool? isActive;
  final bool? isAvailable;
  final String? currentSiteId;

  factory HseWorker.fromMap(Map<String, dynamic> row) {
    return HseWorker(
      id: _toStringOrNull(row['id']),
      firstName: _toStringOrNull(row['first_name']),
      lastName: _toStringOrNull(row['last_name']),
      email: _toStringOrNull(row['email']),
      role: _toStringOrNull(row['role']),
      officerUid: _toStringOrNull(row['officer_uid']),
      designation: _toStringOrNull(row['designation']),
      profileImageUrl: _toStringOrNull(row['profile_image_url']),
      isActive: _toBoolOrNull(row['is_active']),
      isAvailable: _toBoolOrNull(row['is_available']),
      currentSiteId: _toStringOrNull(row['current_site_id']),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'role': role,
      'officer_uid': officerUid,
      'designation': designation,
      'profile_image_url': profileImageUrl,
      'is_active': isActive,
      'is_available': isAvailable,
      'current_site_id': currentSiteId,
    };
  }
}

class Officer implements AppUser {
  const Officer({
    this.id,
    this.firstName,
    this.lastName,
    this.email,
    this.role,
    this.officerUid,
    this.profileImageUrl,
    this.dob,
  });

  @override
  final String? id;
  @override
  final String? firstName;
  @override
  final String? lastName;
  @override
  final String? email;
  @override
  final String? role;
  @override
  final String? officerUid;
  @override
  final String? profileImageUrl;
  final String? dob;

  factory Officer.fromMap(Map<String, dynamic> row) {
    return Officer(
      id: _toStringOrNull(row['id']),
      firstName: _toStringOrNull(row['first_name']),
      lastName: _toStringOrNull(row['last_name']),
      email: _toStringOrNull(row['email']),
      role: _toStringOrNull(row['role']),
      officerUid: _toStringOrNull(row['officer_uid']),
      profileImageUrl: _toStringOrNull(row['profile_image_url']),
      dob: row['dob']?.toString(),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'role': role,
      'officer_uid': officerUid,
      'profile_image_url': profileImageUrl,
      'dob': dob,
    };
  }
}

String? _toStringOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString();
  return text.isEmpty ? null : text;
}

bool? _toBoolOrNull(Object? value) {
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
