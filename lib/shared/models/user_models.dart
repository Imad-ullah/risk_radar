abstract interface class AppUser {
  dynamic get id;
  dynamic get firstName;
  dynamic get lastName;
  dynamic get email;
  dynamic get role;
  dynamic get officerUid;
  dynamic get profileImageUrl;

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
  final dynamic id;
  @override
  final dynamic firstName;
  @override
  final dynamic lastName;
  @override
  final dynamic email;
  @override
  final dynamic role;
  @override
  final dynamic officerUid;
  final dynamic workType;
  @override
  final dynamic profileImageUrl;
  final dynamic isActive;
  final dynamic defaultSiteId;
  final dynamic currentSiteId;

  factory Worker.fromMap(Map<String, dynamic> row) {
    return Worker(
      id: row['id'],
      firstName: row['first_name'],
      lastName: row['last_name'],
      email: row['email'],
      role: row['role'],
      officerUid: row['officer_uid'],
      workType: row['work_type'],
      profileImageUrl: row['profile_image_url'],
      isActive: row['is_active'],
      defaultSiteId: row['default_site_id'],
      currentSiteId: row['current_site_id'],
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
  final dynamic id;
  @override
  final dynamic firstName;
  @override
  final dynamic lastName;
  @override
  final dynamic email;
  @override
  final dynamic role;
  @override
  final dynamic officerUid;
  final dynamic designation;
  @override
  final dynamic profileImageUrl;
  final dynamic isActive;
  final dynamic isAvailable;
  final dynamic currentSiteId;

  factory HseWorker.fromMap(Map<String, dynamic> row) {
    return HseWorker(
      id: row['id'],
      firstName: row['first_name'],
      lastName: row['last_name'],
      email: row['email'],
      role: row['role'],
      officerUid: row['officer_uid'],
      designation: row['designation'],
      profileImageUrl: row['profile_image_url'],
      isActive: row['is_active'],
      isAvailable: row['is_available'],
      currentSiteId: row['current_site_id'],
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
  final dynamic id;
  @override
  final dynamic firstName;
  @override
  final dynamic lastName;
  @override
  final dynamic email;
  @override
  final dynamic role;
  @override
  final dynamic officerUid;
  @override
  final dynamic profileImageUrl;
  final String? dob;

  factory Officer.fromMap(Map<String, dynamic> row) {
    return Officer(
      id: row['id'],
      firstName: row['first_name'],
      lastName: row['last_name'],
      email: row['email'],
      role: row['role'],
      officerUid: row['officer_uid'],
      profileImageUrl: row['profile_image_url'],
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
