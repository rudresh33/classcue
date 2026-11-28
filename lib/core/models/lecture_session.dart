import '../utils/date_time_utils.dart';

/// Concrete dated lecture session from `public.lecture_sessions`.
class LectureSession {
  const LectureSession({
    required this.id,
    this.baseTimetableId,
    required this.courseId,
    required this.facultyId,
    this.coveringFacultyId,
    this.coveringCourseId,
    this.preCoverageStartTime,
    this.preCoverageEndTime,
    required this.roomId,
    required this.sessionDate,
    required this.startTime,
    required this.endTime,
    required this.batch,
    this.originalDate,
    this.originalStartTime,
    this.originalEndTime,
    this.originalRoomId,
    required this.status,
    required this.changeScope,
    this.reason,
    required this.isOpenForCoverage,
    required this.version,
    this.updatedBy,
    required this.updatedAt,
  });

  final String id;
  final String? baseTimetableId;
  final String courseId;
  final String facultyId;
  final String? coveringFacultyId;
  final String? coveringCourseId;
  final String? preCoverageStartTime; // HH:MM:SS
  final String? preCoverageEndTime; // HH:MM:SS
  final String roomId;

  final DateTime sessionDate;
  final String startTime; // HH:MM:SS
  final String endTime; // HH:MM:SS
  final String batch; // 'ALL' | 'B1' | 'B2'

  final DateTime? originalDate;
  final String? originalStartTime;
  final String? originalEndTime;
  final String? originalRoomId;

  /// 'scheduled' | 'cancelled' | 'rescheduling_pending' | 'rescheduled' | 'covered'
  final String status;

  /// 'temporary' | 'permanent'
  final String changeScope;
  final String? reason;
  final bool isOpenForCoverage;
  final int version;
  final String? updatedBy;
  final DateTime updatedAt;

  bool get hasOriginalSnapshot => originalDate != null;

  bool get isRoomChanged => originalRoomId != null && originalRoomId != roomId;

  bool get isTimeOrDateChanged =>
      hasOriginalSnapshot &&
      (!DateTimeUtils.isSameDay(originalDate!, sessionDate) ||
          originalStartTime != startTime ||
          originalEndTime != endTime);

  bool get isCancelled => status == 'cancelled';
  bool get isPending => status == 'rescheduling_pending';
  bool get isRescheduled => status == 'rescheduled';
  bool get isCovered => status == 'covered';
  bool get isScheduled => status == 'scheduled';
  bool get isActive => isScheduled || isRescheduled || isCovered;
  bool get isPermanent => changeScope == 'permanent';
  bool get isPartiallyCovered =>
      isCovered && preCoverageStartTime != null && preCoverageEndTime != null;
  bool get hasException =>
      isCancelled || isPending || isRescheduled || isCovered || isRoomChanged;

  String get effectiveFacultyId => coveringFacultyId ?? facultyId;
  String get activeCourseId => coveringCourseId ?? courseId;

  int get durationMinutes {
    final start = DateTimeUtils.parseSqlTime(startTime);
    final end = DateTimeUtils.parseSqlTime(endTime);
    return DateTimeUtils.timeOfDayToMinutes(end) -
        DateTimeUtils.timeOfDayToMinutes(start);
  }

  /// Baseline duration in minutes (restores pre-coverage duration if partially covered).
  int get baselineDurationMinutes {
    final s = preCoverageStartTime ?? startTime;
    final e = preCoverageEndTime ?? endTime;
    return DateTimeUtils.timeOfDayToMinutes(DateTimeUtils.parseSqlTime(e)) -
        DateTimeUtils.timeOfDayToMinutes(DateTimeUtils.parseSqlTime(s));
  }

  DateTime get startUtc =>
      DateTimeUtils.campusSlotToUtc(sessionDate, startTime);
  DateTime get endUtc => DateTimeUtils.campusSlotToUtc(sessionDate, endTime);

  factory LectureSession.fromJson(Map<String, dynamic> json) {
    return LectureSession(
      id: json['id'] as String,
      baseTimetableId: json['base_timetable_id'] as String?,
      courseId: json['course_id'] as String,
      facultyId: json['faculty_id'] as String,
      coveringFacultyId: json['covering_faculty_id'] as String?,
      coveringCourseId: json['covering_course_id'] as String?,
      preCoverageStartTime: json['pre_coverage_start_time'] as String?,
      preCoverageEndTime: json['pre_coverage_end_time'] as String?,
      roomId: json['room_id'] as String,
      sessionDate: DateTimeUtils.parseSqlDate(json['session_date'] as String),
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      batch: json['batch'] as String? ?? 'ALL',
      originalDate: json['original_date'] != null
          ? DateTimeUtils.parseSqlDate(json['original_date'] as String)
          : null,
      originalStartTime: json['original_start_time'] as String?,
      originalEndTime: json['original_end_time'] as String?,
      originalRoomId: json['original_room_id'] as String?,
      status: json['status'] as String,
      changeScope: json['change_scope'] as String? ?? 'temporary',
      reason: json['reason'] as String?,
      isOpenForCoverage: json['is_open_for_coverage'] as bool? ?? false,
      version: (json['version'] as num?)?.toInt() ?? 1,
      updatedBy: json['updated_by'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
