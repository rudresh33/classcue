import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../polls/create_poll_sheet.dart';
import '../polls/polls_provider.dart';
import 'lecture_detail_sheet.dart';
import 'timetable_provider.dart';

/// Main Timetable / My Lectures tab implementing:
/// - Today's Commute Snapshot card (Student/CR — Nielsen #1, course-aware coverage)
/// - Pinned Non-Routine Lecture Reminder banner (Faculty — Nielsen #6, active covering course)
/// - Today / Weekly segmented toggle, week switcher, Mon–Sat horizontal day selector
/// - Lecture Cards opening LectureDetailSheet
/// - Privacy assurance note for Student role
class TimetableTab extends StatelessWidget {
  const TimetableTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final timetable = context.watch<TimetableProvider>();
    final profile = auth.profile!;
    final service = auth.service;
    final sessions = timetable.displayedSessions;

    return RefreshIndicator(
      onRefresh: () => timetable.refreshAll(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // 1. Role-specific top certainty banner
          if (profile.isStudent || profile.isCr)
            _CommuteSnapshotCard(
              todaySessions: timetable.myTodaySessions,
              service: service,
              profile: profile,
            )
          else if (profile.isFaculty &&
              timetable.upcoming48hNonRoutine.isNotEmpty)
            _NonRoutineReminderBanner(
              sessions: timetable.upcoming48hNonRoutine,
              service: service,
              onTapSession: (s) => _openDetail(context, s),
            ),

          const SizedBox(height: 14),

          // 2. Today / Weekly segmented toggle
          SegmentedButton<TimetableViewMode>(
            segments: const [
              ButtonSegment(
                value: TimetableViewMode.today,
                label: Text('Today'),
                icon: Icon(Icons.today_rounded, size: 17),
              ),
              ButtonSegment(
                value: TimetableViewMode.weekly,
                label: Text('Weekly'),
                icon: Icon(Icons.calendar_view_week_rounded, size: 17),
              ),
            ],
            selected: {timetable.viewMode},
            showSelectedIcon: false,
            onSelectionChanged: (sel) => timetable.setViewMode(sel.first),
          ),

          // 3. Weekly switcher + Mon-Sat horizontal selector
          if (timetable.viewMode == TimetableViewMode.weekly) ...[
            const SizedBox(height: 12),
            _WeekSwitcherBar(
              weekMonday: timetable.selectedWeekMonday,
              onPrev: () => timetable.shiftWeek(-1),
              onThisWeek: timetable.jumpToThisWeek,
              onNext: () => timetable.shiftWeek(1),
            ),
            const SizedBox(height: 10),
            _DaySelectorStrip(
              weekMonday: timetable.selectedWeekMonday,
              selectedDay: timetable.selectedDay,
              countForDay: timetable.countSessionsOnDay,
              hasExceptionOnDay: timetable.hasExceptionOnDay,
              onSelectDay: timetable.selectDay,
            ),
          ] else ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  DateTimeUtils.formatCampusDateFull(DateTimeUtils.todayIst()),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${sessions.length} ${sessions.length == 1 ? 'session' : 'sessions'}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          // 4. Content state
          if (timetable.isLoading && sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (timetable.error != null && sessions.isEmpty)
            EmptyStateView(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load timetable',
              subtitle: timetable.error!,
              action: FilledButton(
                onPressed: () => timetable.refreshAll(),
                child: const Text('Retry'),
              ),
            )
          else if (sessions.isEmpty)
            EmptyStateView(
              icon: Icons.event_available_rounded,
              title: timetable.viewMode == TimetableViewMode.today
                  ? 'No lectures scheduled today'
                  : 'No lectures on ${DateTimeUtils.formatCampusDate(timetable.selectedDay)}',
              subtitle: timetable.viewMode == TimetableViewMode.today
                  ? 'Switch to Weekly view to inspect upcoming days.'
                  : 'Select another day above or switch weeks.',
              action: timetable.viewMode == TimetableViewMode.today
                  ? OutlinedButton(
                      onPressed: () =>
                          timetable.setViewMode(TimetableViewMode.weekly),
                      child: const Text('Open Weekly View'),
                    )
                  : null,
            )
          else
            ...sessions.map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LectureCard(
                  session: session,
                  service: service,
                  viewerProfile: profile,
                  onTap: () => _openDetail(context, session),
                ),
              ),
            ),

          // 5. Privacy boundary note for students
          if (profile.isStudent) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 16,
                    color: AppTheme.secondarySlate,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scoped strictly to your cohort & lab batch. Private faculty calendars remain protected by database RLS.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.inkMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, LectureSession session) {
    final profile = context.read<AuthProvider>().profile!;
    final isCoveringFacultyOnly =
        session.isCovered &&
        profile.isFaculty &&
        session.coveringFacultyId == profile.id &&
        session.facultyId != profile.id;
    final canPoll =
        !isCoveringFacultyOnly &&
        (profile.isAdmin ||
            profile.isCr ||
            (profile.isFaculty && session.facultyId == profile.id));

    LectureDetailSheet.show(
      context,
      session,
      onCreatePoll: canPoll
          ? () async {
              final created = await CreatePollSheet.show(
                context,
                initialSession: session,
              );
              if (created && context.mounted) {
                context.read<PollsProvider>().refreshAll(silent: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Reschedule poll created & cohort notified.'),
                  ),
                );
              }
            }
          : null,
    );
  }
}

/// Top "Today's Commute Snapshot" card (Nielsen #1 — Commuter Certainty).
class _CommuteSnapshotCard extends StatelessWidget {
  const _CommuteSnapshotCard({
    required this.todaySessions,
    required this.service,
    required this.profile,
  });

  final List<LectureSession> todaySessions;
  final SupabaseService service;
  final UserProfile profile;

  bool _isCancelledForCohort(LectureSession s) =>
      service.isCoveredByOtherCohortForUser(s, profile);

  bool _isEffectivelyActive(LectureSession s) =>
      s.isActive && !_isCancelledForCohort(s);

  bool _isEffectivelyCancelled(LectureSession s) =>
      s.isCancelled || _isCancelledForCohort(s);

  @override
  Widget build(BuildContext context) {
    final activeCount = todaySessions.where(_isEffectivelyActive).length;
    final cancelledCount = todaySessions.where(_isEffectivelyCancelled).length;
    final coveredCount = todaySessions
        .where((s) => s.isCovered && !_isCancelledForCohort(s))
        .length;
    final pendingCount = todaySessions.where((s) => s.isPending).length;
    final rescheduledCount = todaySessions.where((s) => s.isRescheduled).length;
    final roomChangedCount = todaySessions.where((s) => s.isRoomChanged).length;

    final nowUtc = DateTime.now().toUtc();
    LectureSession? nextActive;
    for (final s in todaySessions) {
      if (_isEffectivelyActive(s) && s.endUtc.isAfter(nowUtc)) {
        nextActive = s;
        break;
      }
    }

    final hasAlerts =
        cancelledCount > 0 ||
        coveredCount > 0 ||
        pendingCount > 0 ||
        rescheduledCount > 0 ||
        roomChangedCount > 0;

    final alertParts = <String>[
      if (cancelledCount > 0) '$cancelledCount Cancelled',
      if (coveredCount > 0) '$coveredCount Covered',
      if (pendingCount > 0) '$pendingCount Pending',
      if (rescheduledCount > 0) '$rescheduledCount Rescheduled',
      if (roomChangedCount > 0) '$roomChangedCount Room Changed',
    ];

    final nextCourse = nextActive != null
        ? service.courseById(nextActive.activeCourseId)
        : null;
    final nextCourseLabel = nextCourse != null
        ? (nextActive!.isCovered
              ? '${nextCourse.code} · ${nextCourse.name}'
              : nextCourse.code)
        : 'Lecture';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF4338CA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.directions_bus_outlined,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 7),
              const Text(
                "Today's Commute Snapshot",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$activeCount / ${todaySessions.length} active',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (todaySessions.isEmpty)
            const Text(
              'No lectures on campus today — no commute required.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (activeCount == 0)
            const Text(
              'All classes today are cancelled or pending — check alerts before commuting.',
              style: TextStyle(
                color: Color(0xFFFEE2E2),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (nextActive != null)
            Text(
              'Next: $nextCourseLabel at ${DateTimeUtils.formatSqlTime(nextActive.startTime)} · ${service.roomById(nextActive.roomId)?.roomNumber ?? 'Room'} (${AppTheme.statusStyleFor(nextActive.status).shortLabel})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            const Text(
              'All scheduled lectures for today have finished.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (hasAlerts) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    size: 15,
                    color: Color(0xFF92400E),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Changes today: ${alertParts.join(' · ')}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pinned Non-Routine Lecture Reminder banner for Faculty (Nielsen #6 — Recognition over Recall).
class _NonRoutineReminderBanner extends StatelessWidget {
  const _NonRoutineReminderBanner({
    required this.sessions,
    required this.service,
    required this.onTapSession,
  });

  final List<LectureSession> sessions;
  final SupabaseService service;
  final ValueChanged<LectureSession> onTapSession;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA5B4FC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.push_pin_rounded,
                size: 16,
                color: AppTheme.primaryIndigo,
              ),
              SizedBox(width: 6),
              Text(
                'Non-Routine Lecture Reminder (Next 48h)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryIndigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...sessions.take(3).map((s) {
            final course = service.courseById(s.activeCourseId);
            final room = service.roomById(s.roomId);
            final courseText = course != null
                ? (s.isCovered
                      ? '${course.code} · ${course.name}'
                      : course.code)
                : '';
            return InkWell(
              onTap: () => onTapSession(s),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    StatusBadge.lecture(s.status, compact: true),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$courseText · ${DateTimeUtils.formatSlotSummary(s.sessionDate, s.startTime, s.endTime)} · ${room?.roomNumber ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.inkPrimary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppTheme.inkMuted,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _WeekSwitcherBar extends StatelessWidget {
  const _WeekSwitcherBar({
    required this.weekMonday,
    required this.onPrev,
    required this.onThisWeek,
    required this.onNext,
  });

  final DateTime weekMonday;
  final VoidCallback onPrev;
  final VoidCallback onThisWeek;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final weekSat = weekMonday.add(const Duration(days: 5));
    final rangeLabel =
        '${DateFormat('d MMM').format(weekMonday)} – ${DateFormat('d MMM').format(weekSat)}';

    return Row(
      children: [
        IconButton.outlined(
          visualDensity: VisualDensity.compact,
          onPressed: onPrev,
          tooltip: 'Previous week',
          icon: const Icon(Icons.chevron_left_rounded, size: 19),
        ),
        Expanded(
          child: Center(
            child: TextButton(
              onPressed: onThisWeek,
              child: Text(
                rangeLabel,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkPrimary,
                ),
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: onThisWeek,
          child: const Text(
            'This Week',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton.outlined(
          visualDensity: VisualDensity.compact,
          onPressed: onNext,
          tooltip: 'Next week',
          icon: const Icon(Icons.chevron_right_rounded, size: 19),
        ),
      ],
    );
  }
}

class _DaySelectorStrip extends StatelessWidget {
  const _DaySelectorStrip({
    required this.weekMonday,
    required this.selectedDay,
    required this.countForDay,
    required this.hasExceptionOnDay,
    required this.onSelectDay,
  });

  final DateTime weekMonday;
  final DateTime selectedDay;
  final int Function(DateTime) countForDay;
  final bool Function(DateTime) hasExceptionOnDay;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final today = DateTimeUtils.todayIst();
    return Row(
      children: List.generate(6, (index) {
        final day = weekMonday.add(Duration(days: index));
        final isSelected = DateTimeUtils.isSameDay(day, selectedDay);
        final isToday = DateTimeUtils.isSameDay(day, today);
        final count = countForDay(day);
        final hasAlert = hasExceptionOnDay(day);

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < 5 ? 6 : 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelectDay(day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryIndigo : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryIndigo
                        : (isToday
                              ? AppTheme.primaryIndigo.withValues(alpha: 0.5)
                              : AppTheme.cardBorder),
                    width: isToday && !isSelected ? 1.4 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      DateTimeUtils.weekdayShort(day.weekday),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.85)
                            : AppTheme.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.white : AppTheme.inkPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: count == 0
                                ? Colors.transparent
                                : hasAlert
                                ? (isSelected
                                      ? const Color(0xFFFDE047)
                                      : const Color(0xFFD97706))
                                : (isSelected
                                      ? Colors.white
                                      : AppTheme.primaryIndigo),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
