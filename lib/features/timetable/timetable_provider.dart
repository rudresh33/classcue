import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/date_time_utils.dart';

enum TimetableViewMode { today, weekly }

/// Manages scoped lecture sessions, Today/Weekly navigation, Faculty non-routine
/// 48h reminders, Open Coverage slots, and Realtime sync on `lecture_sessions`
/// and `base_timetable`.
class TimetableProvider extends ChangeNotifier {
  TimetableProvider(this._service);

  final SupabaseService _service;

  UserProfile? _profile;
  TimetableViewMode _viewMode = TimetableViewMode.today;
  DateTime _selectedWeekMonday = DateTimeUtils.mondayOfWeek(
    DateTimeUtils.todayIst(),
  );
  DateTime _selectedDay = _initialSelectedDay();

  List<LectureSession> _weekSessions = [];
  List<LectureSession> _todaySessions = [];
  List<LectureSession> _upcoming48hNonRoutine = [];
  List<LectureSession> _openCoverageSlots = [];

  bool _loading = false;
  String? _error;

  RealtimeChannel? _sessionsChannel;
  RealtimeChannel? _baseTimetableChannel;
  Timer? _debounceTimer;

  static DateTime _initialSelectedDay() {
    final today = DateTimeUtils.todayIst();
    // If Sunday, default day selector to Monday of the upcoming week
    if (today.weekday == DateTime.sunday) {
      return today.add(const Duration(days: 1));
    }
    return today;
  }

  SupabaseService get service => _service;
  UserProfile? get profile => _profile;
  TimetableViewMode get viewMode => _viewMode;
  DateTime get selectedWeekMonday => _selectedWeekMonday;
  DateTime get selectedDay => _selectedDay;
  bool get isLoading => _loading;
  String? get error => _error;

  List<LectureSession> get todaySessions => List.unmodifiable(_todaySessions);
  List<LectureSession> get weekSessions => List.unmodifiable(_weekSessions);
  List<LectureSession> get upcoming48hNonRoutine =>
      List.unmodifiable(_upcoming48hNonRoutine);

  /// Open slots eligible for the logged-in faculty to cover (`faculty_id != auth.uid()`).
  List<LectureSession> get openCoverageSlots {
    final uid = _profile?.id;
    return _openCoverageSlots
        .where((s) => s.isOpenForCoverage && s.facultyId != uid)
        .toList();
  }

  /// Sessions belonging to the currently logged-in user for the active day view.
  List<LectureSession> get displayedSessions {
    final targetDay = _viewMode == TimetableViewMode.today
        ? DateTimeUtils.todayIst()
        : _selectedDay;
    final source = _viewMode == TimetableViewMode.today
        ? _todaySessions
        : _weekSessions;
    return _filterOwnOrScoped(
      source
          .where((s) => DateTimeUtils.isSameDay(s.sessionDate, targetDay))
          .toList(),
    );
  }

  /// Filters out other faculty's open-coverage-only sessions from My Lectures tab
  /// (so Faculty see their own & covered lectures in My Lectures, and open slots in Open Slots tab).
  List<LectureSession> _filterOwnOrScoped(List<LectureSession> input) {
    final p = _profile;
    if (p == null || !p.isFaculty) return input;
    return input
        .where((s) => s.facultyId == p.id || s.coveringFacultyId == p.id)
        .toList();
  }

  List<LectureSession> get myTodaySessions =>
      _filterOwnOrScoped(_todaySessions);

  int countSessionsOnDay(DateTime day) {
    return _filterOwnOrScoped(
      _weekSessions
          .where((s) => DateTimeUtils.isSameDay(s.sessionDate, day))
          .toList(),
    ).length;
  }

  bool hasExceptionOnDay(DateTime day) {
    return _filterOwnOrScoped(
      _weekSessions
          .where((s) => DateTimeUtils.isSameDay(s.sessionDate, day))
          .toList(),
    ).any((s) => s.hasException);
  }

  void bindProfile(UserProfile? profile) {
    if (_profile?.id == profile?.id && _profile?.role == profile?.role) {
      _profile = profile;
      return;
    }
    _profile = profile;
    _unsubscribe();
    if (profile == null) {
      _weekSessions = [];
      _todaySessions = [];
      _upcoming48hNonRoutine = [];
      _openCoverageSlots = [];
      notifyListeners();
      return;
    }
    _subscribeRealtime();
    refreshAll();
  }

  void setViewMode(TimetableViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    if (mode == TimetableViewMode.weekly) {
      _selectedWeekMonday = DateTimeUtils.mondayOfWeek(_selectedDay);
    }
    notifyListeners();
  }

  void selectDay(DateTime day) {
    _selectedDay = DateTime(day.year, day.month, day.day);
    final monday = DateTimeUtils.mondayOfWeek(_selectedDay);
    if (!DateTimeUtils.isSameDay(monday, _selectedWeekMonday)) {
      _selectedWeekMonday = monday;
      refreshAll();
    } else {
      notifyListeners();
    }
  }

  void shiftWeek(int deltaWeeks) {
    _selectedWeekMonday = _selectedWeekMonday.add(
      Duration(days: deltaWeeks * 7),
    );
    _selectedDay = _selectedDay.add(Duration(days: deltaWeeks * 7));
    notifyListeners();
    refreshAll();
  }

  void jumpToThisWeek() {
    final today = DateTimeUtils.todayIst();
    _selectedWeekMonday = DateTimeUtils.mondayOfWeek(today);
    _selectedDay = today.weekday == DateTime.sunday
        ? today.add(const Duration(days: 1))
        : today;
    notifyListeners();
    refreshAll();
  }

  Future<void> refreshAll({bool silent = false}) async {
    if (_profile == null) return;
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final today = DateTimeUtils.todayIst();
      final weekEnd = _selectedWeekMonday.add(
        const Duration(days: 5),
      ); // Mon..Sat
      final plus48h = today.add(const Duration(days: 2));

      final futures = <Future<dynamic>>[
        _service.fetchSessionsInRange(
          startDate: _selectedWeekMonday,
          endDate: weekEnd,
        ),
        _service.fetchSessionsInRange(startDate: today, endDate: plus48h),
      ];

      if (_profile!.isFaculty) {
        futures.add(_service.fetchOpenCoverageSessions());
      }

      final results = await Future.wait(futures);
      _weekSessions = results[0] as List<LectureSession>;
      final nearSessions = results[1] as List<LectureSession>;
      _todaySessions = nearSessions
          .where((s) => DateTimeUtils.isSameDay(s.sessionDate, today))
          .toList();

      final nowUtc = DateTime.now().toUtc();
      final cutoffUtc = nowUtc.add(const Duration(hours: 48));
      _upcoming48hNonRoutine = _filterOwnOrScoped(nearSessions).where((s) {
        final isNonRoutine = s.isRescheduled || s.isCovered || s.isRoomChanged;
        return isNonRoutine &&
            s.endUtc.isAfter(nowUtc) &&
            s.startUtc.isBefore(cutoffUtc);
      }).toList();

      if (_profile!.isFaculty && results.length > 2) {
        _openCoverageSlots = results[2] as List<LectureSession>;
      } else {
        _openCoverageSlots = [];
      }

      _error = null;
    } catch (e) {
      _error = DateTimeUtils.prettifyError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> optInCoverage(String sessionId, String coveringCourseId) async {
    await _service.optInCoverage(sessionId, coveringCourseId);
    await refreshAll(silent: true);
  }

  Future<void> withdrawCoverage(String sessionId, {String? reason}) async {
    await _service.withdrawCoverage(sessionId, reason: reason);
    await refreshAll(silent: true);
  }

  Future<void> undoLastChange(String sessionId) async {
    await _service.undoLastLectureChange(sessionId);
    await _service.refreshBaseTimetable();
    await refreshAll(silent: true);
  }

  void _subscribeRealtime() {
    final uid = _profile?.id ?? 'anon';
    _sessionsChannel = _service.subscribeToTable(
      channelName: 'classcue_sessions_$uid',
      table: 'lecture_sessions',
      onChange: _scheduleRealtimeRefresh,
    );
    _baseTimetableChannel = _service.subscribeToTable(
      channelName: 'classcue_base_timetable_$uid',
      table: 'base_timetable',
      onChange: () {
        _service.refreshBaseTimetable();
        _scheduleRealtimeRefresh();
      },
    );
  }

  void _scheduleRealtimeRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      refreshAll(silent: true);
    });
  }

  void _unsubscribe() {
    _debounceTimer?.cancel();
    _service.removeChannel(_sessionsChannel);
    _service.removeChannel(_baseTimetableChannel);
    _sessionsChannel = null;
    _baseTimetableChannel = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}
