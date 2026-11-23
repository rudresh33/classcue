/// Academic cohort from `public.cohorts`.
class Cohort {
  const Cohort({
    required this.id,
    required this.name,
    required this.program,
    required this.semester,
  });

  final String id;
  final String name;
  final String program;
  final int semester;

  String get shortLabel {
    if (name.contains('Sem ')) {
      return name.substring(name.indexOf('Sem '));
    }
    return 'Sem $semester';
  }

  factory Cohort.fromJson(Map<String, dynamic> json) {
    return Cohort(
      id: json['id'] as String,
      name: json['name'] as String,
      program: json['program'] as String,
      semester: (json['semester'] as num).toInt(),
    );
  }
}

/// Classroom or lab from `public.rooms`.
class Room {
  const Room({
    required this.id,
    required this.roomNumber,
    required this.building,
    required this.isLab,
    required this.capacity,
  });

  final String id;
  final String roomNumber;
  final String building;
  final bool isLab;
  final int capacity;

  String get displayLabel => isLab ? '$roomNumber (Lab)' : roomNumber;

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String,
      roomNumber: json['room_number'] as String,
      building: json['building'] as String? ?? 'GBS',
      isLab: json['is_lab'] as bool? ?? false,
      capacity: (json['capacity'] as num?)?.toInt() ?? 40,
    );
  }
}

/// Course record from `public.courses`.
class Course {
  const Course({
    required this.id,
    required this.code,
    required this.name,
    required this.isElective,
  });

  final String id;
  final String code;
  final String name;
  final bool isElective;

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      isElective: json['is_elective'] as bool? ?? false,
    );
  }
}

/// Join table record from `public.course_cohorts`.
class CourseCohort {
  const CourseCohort({required this.courseId, required this.cohortId});

  final String courseId;
  final String cohortId;

  factory CourseCohort.fromJson(Map<String, dynamic> json) {
    return CourseCohort(
      courseId: json['course_id'] as String,
      cohortId: json['cohort_id'] as String,
    );
  }
}

/// Join table record from `public.course_faculty`.
class CourseFaculty {
  const CourseFaculty({
    required this.courseId,
    required this.facultyId,
    required this.isPrimary,
  });

  final String courseId;
  final String facultyId;
  final bool isPrimary;

  factory CourseFaculty.fromJson(Map<String, dynamic> json) {
    return CourseFaculty(
      courseId: json['course_id'] as String,
      facultyId: json['faculty_id'] as String,
      isPrimary: json['is_primary'] as bool? ?? false,
    );
  }
}

/// Weekly recurring base timetable slot from `public.base_timetable`.
class BaseTimetableEntry {
  const BaseTimetableEntry({
    required this.id,
    required this.courseId,
    required this.facultyId,
    required this.roomId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.batch,
    required this.sessionType,
    required this.effectiveFrom,
    this.effectiveTo,
  });

  final String id;
  final String courseId;
  final String facultyId;
  final String roomId;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String batch;
  final String sessionType; // 'theory' | 'practical' | 'mentoring'
  final String effectiveFrom;
  final String? effectiveTo;

  factory BaseTimetableEntry.fromJson(Map<String, dynamic> json) {
    return BaseTimetableEntry(
      id: json['id'] as String,
      courseId: json['course_id'] as String,
      facultyId: json['faculty_id'] as String,
      roomId: json['room_id'] as String,
      dayOfWeek: (json['day_of_week'] as num).toInt(),
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      batch: json['batch'] as String,
      sessionType: json['session_type'] as String? ?? 'theory',
      effectiveFrom: json['effective_from'] as String,
      effectiveTo: json['effective_to'] as String?,
    );
  }
}
