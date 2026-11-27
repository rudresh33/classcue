import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_time_utils.dart';
import 'status_badge.dart';

/// Structured Lecture Card implementing Visibility of System Status (Nielsen #1):
/// - High-contrast status chip (`Scheduled`, `Cancelled`, `Rescheduling Pending`, `Rescheduled`, `Covered`)
/// - Course-aware coverage display: shows covering course + covering faculty prominently with
///   muted/struck-through original cancelled course line underneath, OR shows `Cancelled` for
///   Students/CRs whose cohort is not enrolled in `coveringCourseId`.
/// - Strikethrough original date/time/room beside highlighted updated slot when `originalDate != null`
/// - `Temporary` vs `Permanent` scope pill and explicit `Room Changed` badge when `originalRoomId != roomId`
/// - `B1` / `B2` lab batch pills and `Shared · Sem VII & IX` badge on cross-cohort courses
/// - Zero accidental toggles: tapping opens the detail/action bottom sheet.
class LectureCard extends StatelessWidget {
  const LectureCard({
    super.key,
    required this.session,
    required this.service,
    required this.onTap,
    this.viewerProfile,
    this.showDate = false,
    this.extraPills = const [],
    this.trailingAction,
  });

  final LectureSession session;
  final SupabaseService service;
  final VoidCallback onTap;
  final UserProfile? viewerProfile;
  final bool showDate;
  final List<Widget> extraPills;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final originalCourse = service.courseById(session.courseId);
    final coveringCourse = service.courseById(session.coveringCourseId);
    final room = service.roomById(session.roomId);
    final originalRoom = service.roomById(session.originalRoomId);
    final faculty = service.facultyById(session.facultyId);
    final coveringFaculty = service.facultyById(session.coveringFacultyId);
    final baseEntry = service.baseTimetableById(session.baseTimetableId);

    final bool isCancelledForCohort = service.isCoveredByOtherCohortForUser(
      session,
      viewerProfile,
    );
    final bool isCourseAwareCovered =
        session.isCovered &&
        session.coveringCourseId != null &&
        !isCancelledForCohort;

    final Course? displayCourse = isCourseAwareCovered
        ? (coveringCourse ?? originalCourse)
        : originalCourse;

    final String effectiveStatus = isCancelledForCohort
        ? 'cancelled'
        : session.status;
    final bool strikeTitle = session.isCancelled || isCancelledForCohort;

    final String sharedLabel = service.sharedCourseLabel(
      isCourseAwareCovered ? session.activeCourseId : session.courseId,
    );
    final style = AppTheme.statusStyleFor(effectiveStatus);

    final bool isLabSession =
        session.batch != 'ALL' || baseEntry?.sessionType == 'practical';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: style.foreground, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Course code + status badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayCourse?.code ?? 'Course',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isCourseAwareCovered
                                ? AppTheme.coveredStyle.foreground
                                : AppTheme.primaryIndigo,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayCourse?.name ?? 'Scheduled Lecture',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: strikeTitle
                                ? AppTheme.inkMuted
                                : AppTheme.inkPrimary,
                            decoration: strikeTitle
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge.lecture(effectiveStatus),
                ],
              ),

              // Course-aware coverage sub-lines
              if (isCancelledForCohort) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: AppTheme.cancelledStyle.foreground,
                    ),
                    const SizedBox(width: 5),
                    const Expanded(
                      child: Text(
                        'Cancelled for your cohort · Slot taken by another cohort',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (isCourseAwareCovered && originalCourse != null) ...[
                const SizedBox(height: 5),
                Text.rich(
                  TextSpan(
                    text: 'Taking cancelled ',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.inkMuted,
                    ),
                    children: [
                      TextSpan(
                        text: '${originalCourse.code} · ${originalCourse.name}',
                        style: const TextStyle(
                          decoration: TextDecoration.lineThrough,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: ' slot'),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 10),

              // Time + Room row (with Original vs Updated strikethrough comparison)
              if (session.hasOriginalSnapshot) ...[
                _OriginalVsUpdatedBox(
                  session: session,
                  currentRoom: room,
                  originalRoom: originalRoom,
                ),
                const SizedBox(height: 8),
              ] else ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 15,
                          color: AppTheme.secondarySlate,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          showDate
                              ? DateTimeUtils.formatSlotSummary(
                                  session.sessionDate,
                                  session.startTime,
                                  session.endTime,
                                )
                              : DateTimeUtils.formatTimeRange(
                                  session.startTime,
                                  session.endTime,
                                ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.inkPrimary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (room?.isLab ?? false)
                              ? Icons.computer_rounded
                              : Icons.meeting_room_outlined,
                          size: 15,
                          color: AppTheme.secondarySlate,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          room?.displayLabel ?? 'Room TBD',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.inkPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Faculty row
              Row(
                children: [
                  Icon(
                    isCourseAwareCovered
                        ? Icons.person_add_alt_1_rounded
                        : Icons.person_outline_rounded,
                    size: 15,
                    color: isCourseAwareCovered
                        ? AppTheme.coveredStyle.foreground
                        : AppTheme.inkMuted,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      isCancelledForCohort
                          ? faculty?.displayLabel ?? 'Assigned Faculty'
                          : isCourseAwareCovered && coveringFaculty != null
                          ? coveringFaculty.displayLabel
                          : coveringFaculty != null
                          ? 'Covered by ${coveringFaculty.fullName} (for ${faculty?.fullName ?? 'Faculty'})'
                          : faculty?.displayLabel ?? 'Assigned Faculty',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isCourseAwareCovered && coveringFaculty != null
                            ? AppTheme.coveredStyle.foreground
                            : AppTheme.inkMuted,
                        fontWeight:
                            isCourseAwareCovered && coveringFaculty != null
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              // Contextual metadata pills
              const SizedBox(height: 9),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (session.batch != 'ALL')
                    InfoPill(
                      label:
                          'Batch ${session.batch}${isLabSession ? ' · Lab' : ''}',
                      icon: Icons.science_outlined,
                      foreground: const Color(0xFF0F766E),
                      background: const Color(0xFFCCFBF1),
                      border: const Color(0xFF5EEAD4),
                    )
                  else if (isLabSession)
                    const InfoPill(
                      label: 'Practical',
                      icon: Icons.science_outlined,
                    ),
                  if (sharedLabel.isNotEmpty)
                    InfoPill(
                      label: sharedLabel,
                      icon: Icons.groups_outlined,
                      foreground: const Color(0xFF4338CA),
                      background: const Color(0xFFEEF2FF),
                      border: const Color(0xFFC7D2FE),
                    ),
                  if (session.hasOriginalSnapshot || session.isPermanent)
                    InfoPill(
                      label: session.isPermanent ? 'Permanent' : 'Temporary',
                      icon: session.isPermanent
                          ? Icons.repeat_rounded
                          : Icons.today_rounded,
                      foreground: session.isPermanent
                          ? const Color(0xFF7C2D12)
                          : const Color(0xFF1D4ED8),
                      background: session.isPermanent
                          ? const Color(0xFFFFEDD5)
                          : const Color(0xFFEFF6FF),
                      border: session.isPermanent
                          ? const Color(0xFFFDBA74)
                          : const Color(0xFFBFDBFE),
                    ),
                  if (session.isRoomChanged)
                    const InfoPill(
                      label: 'Room Changed',
                      icon: Icons.swap_horiz_rounded,
                      foreground: Color(0xFFB45309),
                      background: Color(0xFFFEF3C7),
                      border: Color(0xFFFCD34D),
                    ),
                  if (session.isOpenForCoverage)
                    const InfoPill(
                      label: 'Open for Coverage',
                      icon: Icons.volunteer_activism_outlined,
                      foreground: Color(0xFF6D28D9),
                      background: Color(0xFFEDE9FE),
                      border: Color(0xFFC4B5FD),
                    ),
                  ...extraPills,
                ],
              ),

              if (session.reason != null &&
                  session.reason!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Text(
                    session.reason!.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondarySlate,
                      height: 1.35,
                    ),
                  ),
                ),
              ],

              if (trailingAction != null) ...[
                const SizedBox(height: 10),
                trailingAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OriginalVsUpdatedBox extends StatelessWidget {
  const _OriginalVsUpdatedBox({
    required this.session,
    required this.currentRoom,
    required this.originalRoom,
  });

  final LectureSession session;
  final Room? currentRoom;
  final Room? originalRoom;

  @override
  Widget build(BuildContext context) {
    final oldSummary =
        '${DateTimeUtils.formatSlotSummary(session.originalDate!, session.originalStartTime!, session.originalEndTime!)} · ${originalRoom?.roomNumber ?? 'Room'}';
    final newSummary =
        '${DateTimeUtils.formatSlotSummary(session.sessionDate, session.startTime, session.endTime)} · ${currentRoom?.displayLabel ?? 'Room'}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 13,
                color: AppTheme.inkMuted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  oldSummary,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.inkMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              const Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  newSummary,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
