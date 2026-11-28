import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../utils/date_time_utils.dart';

/// Complete typed data, reference-cache, RPC, and Realtime service for ClassCue.
///
/// Strictly obeys least-privilege column grants and view boundaries:
/// - `profile_directory` is fetched separately and NEVER joined in `.select()`.
/// - `profiles` updates ONLY `full_name`.
/// - `notifications` updates ONLY `is_read`.
/// - `lecture_sessions` mutations ONLY go through SECURITY DEFINER RPCs.
/// - `poll_votes` NEVER uses `.upsert()`; uses separate `.insert()` or `.update({'option_id': ...})`.
class SupabaseService {
  SupabaseService(this._client);

  final SupabaseClient _client;

  SupabaseClient get client => _client;
  User? get currentAuthUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;

  // Cached reference metadata & faculty directory
  final Map<String, FacultyDirectoryEntry> _facultyDirectory = {};
  final Map<String, Cohort> _cohorts = {};
  final Map<String, Room> _rooms = {};
  final Map<String, Course> _courses = {};
  final Map<String, List<String>> _courseCohortIds = {};
  final Map<String, List<CourseFaculty>> _courseFaculty = {};
  final Map<String, BaseTimetableEntry> _baseTimetable = {};

  bool _referenceLoaded = false;

  bool get isReferenceLoaded => _referenceLoaded;
  Map<String, FacultyDirectoryEntry> get facultyDirectory =>
      Map.unmodifiable(_facultyDirectory);
  List<Cohort> get cohorts =>
      _cohorts.values.toList()
        ..sort((a, b) => a.semester.compareTo(b.semester));
  List<Room> get rooms =>
      _rooms.values.toList()
        ..sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
  List<Course> get courses =>
      _courses.values.toList()..sort((a, b) => a.code.compareTo(b.code));
  List<BaseTimetableEntry> get baseTimetableEntries =>
      _baseTimetable.values.toList();

  Cohort? cohortById(String? id) => id == null ? null : _cohorts[id];
  Room? roomById(String? id) => id == null ? null : _rooms[id];
  Course? courseById(String? id) => id == null ? null : _courses[id];
  FacultyDirectoryEntry? facultyById(String? id) =>
      id == null ? null : _facultyDirectory[id];
  BaseTimetableEntry? baseTimetableById(String? id) =>
      id == null ? null : _baseTimetable[id];

  List<Cohort> cohortsForCourse(String courseId) {
    final ids = _courseCohortIds[courseId] ?? const [];
    return ids.map((id) => _cohorts[id]).whereType<Cohort>().toList()
      ..sort((a, b) => a.semester.compareTo(b.semester));
  }

  bool isSharedCourse(String courseId) =>
      (_courseCohortIds[courseId]?.length ?? 0) > 1;

  String sharedCourseLabel(String courseId) {
    final list = cohortsForCourse(courseId);
    if (list.length <= 1) return '';
    return 'Shared · ${list.map((c) => c.shortLabel).join(' & ')}';
  }

  bool isFacultyAssignedToCourse(String courseId, String facultyId) {
    final assignments = _courseFaculty[courseId] ?? const [];
    return assignments.any((cf) => cf.facultyId == facultyId);
  }

  /// Returns true if [cohortId] is enrolled in [courseId] according to cached `course_cohorts`.
  bool isCohortEnrolledInCourse(String cohortId, String courseId) {
    final cohortIds = _courseCohortIds[courseId] ?? const [];
    return cohortIds.contains(cohortId);
  }

  /// Returns all courses assigned to [facultyId] that share at least one cohort
  /// with [session.courseId], sorted by course code.
  List<Course> eligibleCoveringCoursesForSession(
    LectureSession session,
    String facultyId,
  ) {
    final sessionCohortIds = (_courseCohortIds[session.courseId] ?? const [])
        .toSet();
    if (sessionCohortIds.isEmpty) return const [];

    final eligible = <Course>[];
    for (final entry in _courseFaculty.entries) {
      final candidateCourseId = entry.key;
      final isAssigned = entry.value.any((cf) => cf.facultyId == facultyId);
      if (!isAssigned) continue;

      final candidateCohorts = _courseCohortIds[candidateCourseId] ?? const [];
      if (candidateCohorts.any(sessionCohortIds.contains)) {
        final course = _courses[candidateCourseId];
        if (course != null) {
          eligible.add(course);
        }
      }
    }
    eligible.sort((a, b) => a.code.compareTo(b.code));
    return eligible;
  }

  /// Returns true when a covered session is being conducted for a course that does NOT
  /// include the logged-in Student/CR's cohort (so for them, the slot is cancelled).
  bool isCoveredByOtherCohortForUser(
    LectureSession session,
    UserProfile? profile,
  ) {
    if (!session.isCovered || session.coveringCourseId == null) return false;
    if (profile == null) return false;
    if (!(profile.isStudent || profile.isCr)) return false;
    final cohortId = profile.cohortId;
    if (cohortId == null) return false;
    return !isCohortEnrolledInCourse(cohortId, session.coveringCourseId!);
  }

  /// Resolves `change_history.changed_by` safely without querying other users' profiles.
  String resolveActorName(String changedBy, {String? currentUid}) {
    final uid = currentUid ?? currentUserId;
    if (uid != null && changedBy == uid) {
      return 'You';
    }
    final faculty = _facultyDirectory[changedBy];
    if (faculty != null) {
      return faculty.fullName;
    }
    return 'Course Admin';
  }

  void clearCaches() {
    _facultyDirectory.clear();
    _cohorts.clear();
    _rooms.clear();
    _courses.clear();
    _courseCohortIds.clear();
    _courseFaculty.clear();
    _baseTimetable.clear();
    _referenceLoaded = false;
  }

  // ===========================================================================
  // AUTH & PROFILE
  // ===========================================================================

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() async {
    clearCaches();
    await _client.auth.signOut();
  }

  Future<UserProfile?> fetchCurrentProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final row = await _client
        .from('profiles')
        .select(
          'id, full_name, email, role, cohort_id, lab_batch, faculty_type, faculty_code, created_at',
        )
        .eq('id', uid)
        .maybeSingle();
    if (row == null) return null;
    return UserProfile.fromJson(row);
  }

  /// Least-privilege profile update: ONLY `full_name` is granted to authenticated users.
  Future<void> updateOwnFullName(String fullName) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('Not authenticated.');
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) throw Exception('Full name cannot be empty.');
    await _client.from('profiles').update({'full_name': trimmed}).eq('id', uid);
  }

  // ===========================================================================
  // REFERENCE METADATA & FACULTY DIRECTORY CACHE
  // ===========================================================================

  Future<void> loadReferenceData({bool force = false}) async {
    if (_referenceLoaded && !force) return;

    final results = await Future.wait([
      _client.from('profile_directory').select('id, full_name, faculty_code'),
      _client.from('cohorts').select('id, name, program, semester'),
      _client
          .from('rooms')
          .select('id, room_number, building, is_lab, capacity'),
      _client.from('courses').select('id, code, name, is_elective'),
      _client.from('course_cohorts').select('course_id, cohort_id'),
      _client
          .from('course_faculty')
          .select('course_id, faculty_id, is_primary'),
      _client
          .from('base_timetable')
          .select(
            'id, course_id, faculty_id, room_id, day_of_week, start_time, end_time, batch, session_type, effective_from, effective_to',
          ),
    ]);

    _facultyDirectory.clear();
    for (final row in (results[0] as List<dynamic>)) {
      final entry = FacultyDirectoryEntry.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      _facultyDirectory[entry.id] = entry;
    }

    _cohorts.clear();
    for (final row in (results[1] as List<dynamic>)) {
      final item = Cohort.fromJson(Map<String, dynamic>.from(row as Map));
      _cohorts[item.id] = item;
    }

    _rooms.clear();
    for (final row in (results[2] as List<dynamic>)) {
      final item = Room.fromJson(Map<String, dynamic>.from(row as Map));
      _rooms[item.id] = item;
    }

    _courses.clear();
    for (final row in (results[3] as List<dynamic>)) {
      final item = Course.fromJson(Map<String, dynamic>.from(row as Map));
      _courses[item.id] = item;
    }

    _courseCohortIds.clear();
    for (final row in (results[4] as List<dynamic>)) {
      final cc = CourseCohort.fromJson(Map<String, dynamic>.from(row as Map));
      _courseCohortIds.putIfAbsent(cc.courseId, () => []).add(cc.cohortId);
    }

    _courseFaculty.clear();
    for (final row in (results[5] as List<dynamic>)) {
      final cf = CourseFaculty.fromJson(Map<String, dynamic>.from(row as Map));
      _courseFaculty.putIfAbsent(cf.courseId, () => []).add(cf);
    }

    _baseTimetable.clear();
    for (final row in (results[6] as List<dynamic>)) {
      final bt = BaseTimetableEntry.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      _baseTimetable[bt.id] = bt;
    }

    _referenceLoaded = true;
  }

  Future<void> refreshBaseTimetable() async {
    final rows = await _client
        .from('base_timetable')
        .select(
          'id, course_id, faculty_id, room_id, day_of_week, start_time, end_time, batch, session_type, effective_from, effective_to',
        );
    _baseTimetable.clear();
    for (final row in (rows as List<dynamic>)) {
      final bt = BaseTimetableEntry.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      _baseTimetable[bt.id] = bt;
    }
  }

  // ===========================================================================
  // LECTURE SESSIONS (READ-ONLY DIRECT SELECT; ALL MUTATIONS VIA RPCS)
  // ===========================================================================

  Future<List<LectureSession>> fetchSessionsInRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final rows = await _client
        .from('lecture_sessions')
        .select(
          'id, base_timetable_id, course_id, faculty_id, covering_faculty_id, covering_course_id, '
          'pre_coverage_start_time, pre_coverage_end_time, room_id, '
          'session_date, start_time, end_time, batch, original_date, original_start_time, '
          'original_end_time, original_room_id, status, change_scope, reason, '
          'is_open_for_coverage, version, updated_by, updated_at',
        )
        .gte('session_date', DateTimeUtils.toSqlDate(startDate))
        .lte('session_date', DateTimeUtils.toSqlDate(endDate))
        .order('session_date', ascending: true)
        .order('start_time', ascending: true);

    return (rows as List<dynamic>)
        .map(
          (row) =>
              LectureSession.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<LectureSession?> fetchSessionById(String sessionId) async {
    final row = await _client
        .from('lecture_sessions')
        .select(
          'id, base_timetable_id, course_id, faculty_id, covering_faculty_id, covering_course_id, '
          'pre_coverage_start_time, pre_coverage_end_time, room_id, '
          'session_date, start_time, end_time, batch, original_date, original_start_time, '
          'original_end_time, original_room_id, status, change_scope, reason, '
          'is_open_for_coverage, version, updated_by, updated_at',
        )
        .eq('id', sessionId)
        .maybeSingle();
    if (row == null) return null;
    return LectureSession.fromJson(row);
  }

  Future<List<LectureSession>> fetchOpenCoverageSessions() async {
    final todayStr = DateTimeUtils.toSqlDate(DateTimeUtils.todayIst());
    final rows = await _client
        .from('lecture_sessions')
        .select(
          'id, base_timetable_id, course_id, faculty_id, covering_faculty_id, covering_course_id, '
          'pre_coverage_start_time, pre_coverage_end_time, room_id, '
          'session_date, start_time, end_time, batch, original_date, original_start_time, '
          'original_end_time, original_room_id, status, change_scope, reason, '
          'is_open_for_coverage, version, updated_by, updated_at',
        )
        .eq('is_open_for_coverage', true)
        .gte('session_date', todayStr)
        .order('session_date', ascending: true)
        .order('start_time', ascending: true);

    return (rows as List<dynamic>)
        .map(
          (row) =>
              LectureSession.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  // ===========================================================================
  // EXACT RPC CALLS (PARAMETER NAMES MATCH DEPLOYED MIGRATIONS VERBATIM)
  // ===========================================================================

  /// 1. `check_slot_conflicts` (CR, Faculty, Admin ONLY — never call as Student).
  Future<SlotConflictResult> checkSlotConflicts({
    required String courseId,
    required DateTime sessionDate,
    required String startTime,
    required String endTime,
    required String? roomId,
    required String facultyId,
    required String batch,
    String? excludeSessionId,
  }) async {
    final data = await _client.rpc(
      'check_slot_conflicts',
      params: {
        'p_course_id': courseId,
        'p_session_date': DateTimeUtils.toSqlDate(sessionDate),
        'p_start_time': startTime,
        'p_end_time': endTime,
        'p_room_id': roomId,
        'p_faculty_id': facultyId,
        'p_batch': batch,
        'p_exclude_session_id': excludeSessionId,
      },
    );

    return SlotConflictResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// 2. `update_lecture_session` (Faculty, Admin only).
  Future<Map<String, dynamic>> updateLectureSession({
    required String sessionId,
    required String status,
    DateTime? sessionDate,
    String? startTime,
    String? endTime,
    String? roomId,
    String changeScope = 'temporary',
    String? reason,
    bool isOpenForCoverage = false,
  }) async {
    final isCancelOrPending =
        status == 'cancelled' || status == 'rescheduling_pending';

    final data = await _client.rpc(
      'update_lecture_session',
      params: {
        'p_session_id': sessionId,
        'p_status': status,
        'p_session_date': isCancelOrPending || sessionDate == null
            ? null
            : DateTimeUtils.toSqlDate(sessionDate),
        'p_start_time': isCancelOrPending ? null : startTime,
        'p_end_time': isCancelOrPending ? null : endTime,
        'p_room_id': isCancelOrPending ? null : roomId,
        'p_change_scope': changeScope,
        'p_reason': (reason == null || reason.trim().isEmpty)
            ? null
            : reason.trim(),
        'p_is_open_for_coverage': isOpenForCoverage,
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  /// 3. `opt_in_coverage` (Faculty only, course-aware + optional partial duration window).
  Future<Map<String, dynamic>> optInCoverage(
    String sessionId,
    String coveringCourseId, {
    String? startTime,
    String? endTime,
  }) async {
    final data = await _client.rpc(
      'opt_in_coverage',
      params: {
        'p_session_id': sessionId,
        'p_covering_course_id': coveringCourseId,
        'p_start_time': startTime,
        'p_end_time': endTime,
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  /// 3b. `withdraw_coverage` (Covering Faculty / Admin): gives the slot back and re-opens it.
  Future<void> withdrawCoverage(String sessionId, {String? reason}) async {
    await _client.rpc(
      'withdraw_coverage',
      params: {
        'p_session_id': sessionId,
        'p_reason': (reason == null || reason.trim().isEmpty)
            ? null
            : reason.trim(),
      },
    );
  }

  /// 4. `undo_last_lecture_change` (Faculty, Admin only).
  Future<Map<String, dynamic>> undoLastLectureChange(String sessionId) async {
    final data = await _client.rpc(
      'undo_last_lecture_change',
      params: {'p_session_id': sessionId},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  /// 5. `confirm_poll_option` (Assigned Faculty, Admin ONLY).
  Future<Map<String, dynamic>> confirmPollOption({
    required String pollId,
    required String optionId,
    String? reason,
    bool allowEarlyClose = false,
  }) async {
    final data = await _client.rpc(
      'confirm_poll_option',
      params: {
        'p_poll_id': pollId,
        'p_option_id': optionId,
        'p_reason': (reason == null || reason.trim().isEmpty)
            ? null
            : reason.trim(),
        'p_allow_early_close': allowEarlyClose,
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  /// 6. `get_poll_results` (All scoped roles).
  Future<List<PollOptionResult>> getPollResults(String pollId) async {
    final rows = await _client.rpc(
      'get_poll_results',
      params: {'p_poll_id': pollId},
    );
    return (rows as List<dynamic>)
        .map(
          (row) =>
              PollOptionResult.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  /// 7. `generate_lecture_sessions` (Admin only). Returns inserted row count.
  Future<int> generateLectureSessions({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final count = await _client.rpc(
      'generate_lecture_sessions',
      params: {
        'p_start_date': DateTimeUtils.toSqlDate(startDate),
        'p_end_date': DateTimeUtils.toSqlDate(endDate),
      },
    );
    return (count as num).toInt();
  }

  /// 8. `expire_stale_polls` (Admin only). Returns closed poll count.
  Future<int> expireStalePolls() async {
    final count = await _client.rpc('expire_stale_polls', params: {});
    return (count as num).toInt();
  }

  /// 9. `get_available_slots` (CR, Faculty, Admin ONLY).
  Future<List<AvailableSlot>> getAvailableSlots({
    required String sessionId,
    DateTime? fromDate,
    int daysAhead = 7,
    int? durationMinutes,
    bool includeSaturday = true,
    bool skipLunch = true,
    int limit = 12,
    int maxPerDay = 3,
    int minLeadMinutes = 60,
  }) async {
    final rows = await _client.rpc(
      'get_available_slots',
      params: {
        'p_session_id': sessionId,
        'p_from_date': fromDate != null
            ? DateTimeUtils.toSqlDate(fromDate)
            : null,
        'p_days_ahead': daysAhead,
        'p_duration_minutes': durationMinutes,
        'p_include_saturday': includeSaturday,
        'p_skip_lunch': skipLunch,
        'p_limit': limit,
        'p_max_per_day': maxPerDay,
        'p_min_lead_minutes': minLeadMinutes,
      },
    );

    return (rows as List<dynamic>)
        .map(
          (row) =>
              AvailableSlot.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  // ===========================================================================
  // POLLS & VOTES (COLUMN-RESTRICTED WRITES; NO UPSERT ON POLL_VOTES)
  // ===========================================================================

  Future<List<ReschedulePoll>> fetchPolls() async {
    final rows = await _client
        .from('reschedule_polls')
        .select(
          'id, lecture_session_id, created_by, expected_session_version, status, closes_at, created_at',
        )
        .order('created_at', ascending: false);

    return (rows as List<dynamic>)
        .map(
          (row) =>
              ReschedulePoll.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<ReschedulePoll> createPollWithOptions({
    required String lectureSessionId,
    required DateTime closesAtUtc,
    required List<PollOptionDraft> options,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('Not authenticated.');
    if (options.length < 2) {
      throw Exception('Please add at least 2 proposed slots for a poll.');
    }

    final pollRow = await _client
        .from('reschedule_polls')
        .insert({
          'lecture_session_id': lectureSessionId,
          'created_by': uid,
          'closes_at': closesAtUtc.toUtc().toIso8601String(),
        })
        .select(
          'id, lecture_session_id, created_by, expected_session_version, status, closes_at, created_at',
        )
        .single();

    final poll = ReschedulePoll.fromJson(pollRow);

    final optionPayloads = options
        .map(
          (opt) => {
            'poll_id': poll.id,
            'proposed_date': DateTimeUtils.toSqlDate(opt.proposedDate),
            'proposed_start_time': opt.proposedStartTime,
            'proposed_end_time': opt.proposedEndTime,
            'proposed_room_id': opt.proposedRoomId,
          },
        )
        .toList();

    try {
      await _client.from('poll_options').insert(optionPayloads);
    } catch (e) {
      // Best-effort fallback close if options failed validation after poll row insert
      try {
        await closePollAsCancelledFallback(poll.id);
      } catch (_) {}
      rethrow;
    }

    return poll;
  }

  /// Allowed client UPDATE on `reschedule_polls`: ONLY `status` (to `'cancelled_fallback'`).
  Future<void> closePollAsCancelledFallback(String pollId) async {
    await _client
        .from('reschedule_polls')
        .update({'status': 'cancelled_fallback'})
        .eq('id', pollId);
  }

  /// Safe vote submission on `poll_votes`: NEVER uses `.upsert()`.
  /// Inserts when [hasExistingVote] is false; updates ONLY `option_id` when true.
  Future<void> submitPollVote({
    required String pollId,
    required String optionId,
    required bool hasExistingVote,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('Not authenticated.');

    if (!hasExistingVote) {
      await _client.from('poll_votes').insert({
        'poll_id': pollId,
        'option_id': optionId,
        'student_id': uid,
      });
    } else {
      await _client
          .from('poll_votes')
          .update({'option_id': optionId})
          .eq('poll_id', pollId)
          .eq('student_id', uid);
    }
  }

  // ===========================================================================
  // CHANGE HISTORY & NOTIFICATIONS
  // ===========================================================================

  Future<List<ChangeHistoryEntry>> fetchChangeHistory({
    String? lectureSessionId,
    int limit = 60,
  }) async {
    var query = _client
        .from('change_history')
        .select(
          'id, lecture_session_id, changed_by, action_type, previous_state, new_state, '
          'side_effects, reason, reverts_history_id, undone_at, created_at',
        );
    if (lectureSessionId != null) {
      query = query.eq('lecture_session_id', lectureSessionId);
    }
    final rows = await query.order('created_at', ascending: false).limit(limit);

    return (rows as List<dynamic>)
        .map(
          (row) => ChangeHistoryEntry.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  Future<List<AppNotification>> fetchNotifications({int limit = 60}) async {
    final rows = await _client
        .from('notifications')
        .select(
          'id, user_id, lecture_session_id, title, body, type, is_read, created_at',
        )
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .map(
          (row) =>
              AppNotification.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  /// Least-privilege update on `notifications`: ONLY `{'is_read': true}`.
  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  /// Least-privilege bulk mark-read on `notifications`: ONLY `{'is_read': true}`.
  Future<void> markAllNotificationsRead() async {
    final uid = currentUserId;
    if (uid == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
  }

  // ===========================================================================
  // ADMIN OVERVIEW COUNTS
  // ===========================================================================

  Future<Map<String, int>> fetchAdminOverviewCounts() async {
    final todayStr = DateTimeUtils.toSqlDate(DateTimeUtils.todayIst());
    final results = await Future.wait([
      _client.from('lecture_sessions').select('id, status, session_date'),
      _client.from('reschedule_polls').select('id, status, closes_at'),
      _client.from('base_timetable').select('id'),
    ]);

    final sessions = results[0] as List<dynamic>;
    final polls = results[1] as List<dynamic>;
    final baseSlots = results[2] as List<dynamic>;

    final upcomingSessions = sessions
        .where((s) => (s['session_date'] as String).compareTo(todayStr) >= 0)
        .length;
    final openPolls = polls.where((p) => p['status'] == 'open').length;
    final staleCutoff = DateTime.now().toUtc().subtract(
      const Duration(hours: 48),
    );
    final stalePolls = polls.where((p) {
      if (p['status'] != 'open') return false;
      final closesAt = DateTime.parse(p['closes_at'] as String).toUtc();
      return closesAt.isBefore(staleCutoff);
    }).length;

    return {
      'total_sessions': sessions.length,
      'upcoming_sessions': upcomingSessions,
      'base_slots': baseSlots.length,
      'open_polls': openPolls,
      'stale_polls': stalePolls,
    };
  }

  // ===========================================================================
  // REALTIME SUBSCRIPTIONS
  // ===========================================================================

  RealtimeChannel subscribeToTable({
    required String channelName,
    required String table,
    required VoidCallback onChange,
  }) {
    final channel = _client.channel(channelName);
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }

  Future<void> removeChannel(RealtimeChannel? channel) async {
    if (channel != null) {
      await _client.removeChannel(channel);
    }
  }
}
