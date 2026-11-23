/// Authenticated user profile row from `public.profiles`.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.labBatch,
    this.cohortId,
    this.facultyType,
    this.facultyCode,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String email;
  final String role; // 'student' | 'cr' | 'faculty' | 'admin'
  final String? cohortId;
  final String labBatch; // 'ALL' | 'B1' | 'B2'
  final String? facultyType; // 'permanent' | 'visiting' | 'contributory'
  final String? facultyCode;
  final DateTime? createdAt;

  bool get isStudent => role == 'student';
  bool get isCr => role == 'cr';
  bool get isFaculty => role == 'faculty';
  bool get isAdmin => role == 'admin';

  bool get canCheckConflicts => isCr || isFaculty || isAdmin;
  bool get canCreatePolls => isCr || isFaculty || isAdmin;
  bool get canVoteInPolls => isStudent || isCr;
  bool get canConfirmPolls => isFaculty || isAdmin;
  bool get canEditSessions => isFaculty || isAdmin;

  String get roleDisplayLabel {
    switch (role) {
      case 'student':
        return 'Student';
      case 'cr':
        return 'CR';
      case 'faculty':
        return 'Faculty';
      case 'admin':
        return 'Admin';
      default:
        return role;
    }
  }

  UserProfile copyWith({String? fullName}) {
    return UserProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email,
      role: role,
      cohortId: cohortId,
      labBatch: labBatch,
      facultyType: facultyType,
      facultyCode: facultyCode,
      createdAt: createdAt,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      cohortId: json['cohort_id'] as String?,
      labBatch: json['lab_batch'] as String,
      facultyType: json['faculty_type'] as String?,
      facultyCode: json['faculty_code'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}

/// Public faculty directory entry from `public.profile_directory` view.
class FacultyDirectoryEntry {
  const FacultyDirectoryEntry({
    required this.id,
    required this.fullName,
    this.facultyCode,
  });

  final String id;
  final String fullName;
  final String? facultyCode;

  String get displayLabel => facultyCode != null && facultyCode!.isNotEmpty
      ? '$fullName ($facultyCode)'
      : fullName;

  factory FacultyDirectoryEntry.fromJson(Map<String, dynamic> json) {
    return FacultyDirectoryEntry(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      facultyCode: json['faculty_code'] as String?,
    );
  }
}
