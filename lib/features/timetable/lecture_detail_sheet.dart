import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../reschedule/reschedule_sheet.dart';
import 'timetable_provider.dart';

/// Detailed Lecture Bottom Sheet with full metadata, course-aware coverage display,
/// faculty/covering faculty names, Change History timeline, owner update/undo actions,
/// and dedicated "Give Slot Back" (`withdraw_coverage`) action for covering faculty.
class LectureDetailSheet extends StatefulWidget {
  const LectureDetailSheet({
    super.key,
    required this.session,
    this.onCreatePoll,
  });

  final LectureSession session;
  final VoidCallback? onCreatePoll;

  static Future<void> show(
    BuildContext context,
    LectureSession session, {
    VoidCallback? onCreatePoll,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) =>
          LectureDetailSheet(session: session, onCreatePoll: onCreatePoll),
    );
  }

  @override
  State<LectureDetailSheet> createState() => _LectureDetailSheetState();
}

class _LectureDetailSheetState extends State<LectureDetailSheet> {
  late LectureSession _session;
  List<ChangeHistoryEntry> _history = [];
  bool _loadingHistory = true;
  bool _busyAction = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final service = context.read<AuthProvider>().service;
    try {
      final results = await Future.wait([
        service.fetchSessionById(_session.id),
        service.fetchChangeHistory(lectureSessionId: _session.id, limit: 15),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0] != null) {
          _session = results[0] as LectureSession;
        }
        _history = results[1] as List<ChangeHistoryEntry>;
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  bool _isCoveringFaculty(UserProfile profile) {
    return _session.isCovered &&
        profile.isFaculty &&
        _session.coveringFacultyId == profile.id &&
        _session.facultyId != profile.id;
  }

  bool _canEditAsOwnerOrAdmin(UserProfile profile) {
    if (profile.isAdmin) return true;
    if (profile.isFaculty && _session.facultyId == profile.id) {
      return true;
    }
    return false;
  }

  bool _canUndoLatest(UserProfile profile) {
    if (!_canEditAsOwnerOrAdmin(profile) || _history.isEmpty) return false;
    final latest = _history.first;
    if (latest.isUndo || latest.isUndone) return false;
    if (profile.isAdmin) return true;
    return latest.changedBy == profile.id;
  }

  Future<void> _handleUndo() async {
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: 'Undo Last Change?',
      subtitle: 'This atomically reverts the lecture session (and any linked permanent timetable shift or poll confirmation) to its previous state.',
      rows: [
        ConfirmationDetailRow(
          label: 'Reverting Action',
          value: _history.first.actionLabel,
        ),
        ConfirmationDetailRow(
          label: 'Recorded At',
          value: DateTimeUtils.formatTimestampIst(_history.first.createdAt),
        ),
      ],
      confirmLabel: 'Undo Change',
      confirmColor: AppTheme.pendingStyle.foreground,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyAction = true);
    try {
      await context.read<TimetableProvider>().undoLastChange(_session.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Last lecture change reverted.')),
      );
      await _loadDetails();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DateTimeUtils.prettifyError(e))));
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _handleWithdrawCoverage() async {
    final service = context.read<AuthProvider>().service;
    final activeCourse = service.courseById(_session.activeCourseId);
    final origCourse = service.courseById(_session.courseId);
    String reasonText = '';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.cancelledStyle.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.assignment_return_outlined,
                  size: 20,
                  color: AppTheme.cancelledStyle.foreground,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Give Slot Back?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will withdraw your ${activeCourse?.code ?? 'replacement'} lecture and re-open the cancelled ${origCourse?.code ?? ''} slot for other eligible faculty. Affected students and the primary instructor will be notified.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkMuted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'e.g., Unexpected schedule conflict',
                  ),
                  onChanged: (val) => reasonText = val,
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Keep Slot'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.cancelledStyle.foreground,
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Give Slot Back'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busyAction = true);
    try {
      await context.read<TimetableProvider>().withdrawCoverage(
        _session.id,
        reason: reasonText,
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Coverage withdrawn. Slot is open again for other eligible faculty.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyAction = false);
      messenger.showSnackBar(
        SnackBar(content: Text(DateTimeUtils.prettifyError(e))),
      );
    }
  }

  Future<void> _openRescheduleSheet() async {
    final messenger = ScaffoldMessenger.of(context);
    final timetable = context.read<TimetableProvider>();
    final updated = await RescheduleSheet.show(context, _session);
    if (!updated || !mounted) return;

    await timetable.refreshAll(silent: true);
    await _loadDetails();
    if (!mounted) return;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 7),
        content: const Text('Lecture update published & alerts sent.'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            try {
              await timetable.undoLastChange(_session.id);
              messenger.showSnackBar(
                const SnackBar(content: Text('Change undone.')),
              );
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text(DateTimeUtils.prettifyError(e))),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile!;
    final service = auth.service;
    final originalCourse = service.courseById(_session.courseId);
    final coveringCourse = service.courseById(_session.coveringCourseId);
    final room = service.roomById(_session.roomId);
    final originalRoom = service.roomById(_session.originalRoomId);
    final faculty = service.facultyById(_session.facultyId);
    final coveringFaculty = service.facultyById(_session.coveringFacultyId);

    final bool isCancelledForCohort = service.isCoveredByOtherCohortForUser(
      _session,
      profile,
    );
    final bool isCourseAwareCovered =
        _session.isCovered &&
        _session.coveringCourseId != null &&
        !isCancelledForCohort;

    final Course? displayCourse = isCourseAwareCovered
        ? (coveringCourse ?? originalCourse)
        : originalCourse;
    final String effectiveStatus = isCancelledForCohort
        ? 'cancelled'
        : _session.status;
    final cohorts = service.cohortsForCourse(
      isCourseAwareCovered ? _session.activeCourseId : _session.courseId,
    );

    final bool isCoveringFaculty = _isCoveringFaculty(profile);
    final bool canEdit = _canEditAsOwnerOrAdmin(profile);
    final bool canUndo = _canUndoLatest(profile);
    final bool canManagePoll =
        !isCoveringFaculty &&
        (profile.isAdmin ||
            profile.isCr ||
            (profile.isFaculty && _session.facultyId == profile.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.cardBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
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
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isCourseAwareCovered
                              ? AppTheme.coveredStyle.foreground
                              : AppTheme.primaryIndigo,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displayCourse?.name ?? 'Lecture Session',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: isCancelledForCohort || _session.isCancelled
                              ? AppTheme.inkMuted
                              : AppTheme.inkPrimary,
                          decoration:
                              isCancelledForCohort || _session.isCancelled
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

            if (isCancelledForCohort) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppTheme.cancelledStyle.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cancelledStyle.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: AppTheme.cancelledStyle.foreground,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cancelled for your cohort · Slot taken by another cohort',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.cancelledStyle.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isCourseAwareCovered && originalCourse != null) ...[
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  text: 'Taking cancelled ',
                  style: const TextStyle(
                    fontSize: 12.5,
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
              ),
              if (_session.isPartiallyCovered) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    InfoPill(
                      label:
                          'Partial Cover · ${DateTimeUtils.formatDurationLabel(_session.startTime, _session.endTime)} of ${DateTimeUtils.formatDurationLabel(_session.preCoverageStartTime!, _session.preCoverageEndTime!)}',
                      icon: Icons.pie_chart_outline_rounded,
                      foreground: const Color(0xFF0F766E),
                      background: const Color(0xFFCCFBF1),
                      border: const Color(0xFF5EEAD4),
                    ),
                  ],
                ),
              ],
            ],

            const SizedBox(height: 14),

            // Slot details card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceTint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailLine(
                    icon: Icons.calendar_today_rounded,
                    label: 'Schedule',
                    value: DateTimeUtils.formatSlotSummary(
                      _session.sessionDate,
                      _session.startTime,
                      _session.endTime,
                    ),
                    oldValue:
                        _session.isPartiallyCovered && !isCancelledForCohort
                        ? DateTimeUtils.formatSlotSummary(
                            _session.sessionDate,
                            _session.preCoverageStartTime!,
                            _session.preCoverageEndTime!,
                          )
                        : _session.hasOriginalSnapshot
                        ? DateTimeUtils.formatSlotSummary(
                            _session.originalDate!,
                            _session.originalStartTime!,
                            _session.originalEndTime!,
                          )
                        : null,
                  ),
                  const Divider(height: 18),
                  _DetailLine(
                    icon: Icons.meeting_room_outlined,
                    label: 'Room',
                    value:
                        '${room?.displayLabel ?? 'Room TBD'} · ${room?.building ?? 'GBS'} (Cap ${room?.capacity ?? 40})',
                    oldValue: _session.isRoomChanged
                        ? originalRoom?.displayLabel
                        : null,
                  ),
                  if (isCourseAwareCovered && coveringFaculty != null) ...[
                    const Divider(height: 18),
                    _DetailLine(
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Covering Instructor',
                      value: coveringFaculty.displayLabel,
                    ),
                    const Divider(height: 18),
                    _DetailLine(
                      icon: Icons.person_outline_rounded,
                      label: 'Original Instructor (Cancelled)',
                      value:
                          '${faculty?.displayLabel ?? 'Faculty'}${originalCourse != null ? ' · ${originalCourse.code}' : ''}',
                    ),
                  ] else ...[
                    const Divider(height: 18),
                    _DetailLine(
                      icon: Icons.person_outline_rounded,
                      label: 'Primary Faculty',
                      value: faculty?.displayLabel ?? 'Assigned Faculty',
                    ),
                    if (!isCancelledForCohort && coveringFaculty != null) ...[
                      const Divider(height: 18),
                      _DetailLine(
                        icon: Icons.person_add_alt_1_rounded,
                        label: 'Covering Faculty',
                        value: coveringFaculty.displayLabel,
                      ),
                    ],
                  ],
                  const Divider(height: 18),
                  _DetailLine(
                    icon: Icons.groups_outlined,
                    label: 'Cohort & Batch',
                    value:
                        '${cohorts.map((c) => c.name).join(' & ')} · ${_session.batch == 'ALL' ? 'All Students' : 'Batch ${_session.batch}'}',
                  ),
                  if (_session.reason != null &&
                      _session.reason!.trim().isNotEmpty) ...[
                    const Divider(height: 18),
                    _DetailLine(
                      icon: Icons.notes_rounded,
                      label: 'Reason / Note',
                      value: _session.reason!.trim(),
                    ),
                  ],
                ],
              ),
            ),

            // Covering Faculty dedicated action (Give Slot Back)
            if (isCoveringFaculty) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.cancelledStyle.foreground,
                ),
                onPressed: _busyAction ? null : _handleWithdrawCoverage,
                icon: _busyAction
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.assignment_return_outlined, size: 18),
                label: const Text('Give Slot Back'),
              ),
            ]
            // Owner / Admin / CR Action Buttons
            else if (canEdit || canManagePoll) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canEdit)
                    FilledButton.icon(
                      onPressed: _busyAction ? null : _openRescheduleSheet,
                      icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                      label: const Text('Update / Reschedule'),
                    ),
                  if (canUndo)
                    OutlinedButton.icon(
                      onPressed: _busyAction ? null : _handleUndo,
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Undo Last Change'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.pendingStyle.foreground,
                        side: BorderSide(color: AppTheme.pendingStyle.border),
                      ),
                    ),
                  if (canManagePoll && widget.onCreatePoll != null)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onCreatePoll!();
                      },
                      icon: const Icon(Icons.how_to_vote_outlined, size: 18),
                      label: const Text('Open Reschedule Poll'),
                    ),
                ],
              ),
            ],

            // Change History Timeline
            const SizedBox(height: 22),
            const Text(
              'Change History',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (_loadingHistory)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_history.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: const Text(
                  'No changes recorded for this session yet. Following the base timetable.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
                ),
              )
            else
              ..._history.map((entry) {
                final actor = service.resolveActorName(
                  entry.changedBy,
                  currentUid: profile.id,
                );
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          InfoPill(
                            label: entry.actionLabel,
                            foreground: entry.isUndo
                                ? AppTheme.pendingStyle.foreground
                                : AppTheme.primaryIndigo,
                            background: entry.isUndo
                                ? AppTheme.pendingStyle.background
                                : const Color(0xFFEEF2FF),
                            border: entry.isUndo
                                ? AppTheme.pendingStyle.border
                                : const Color(0xFFC7D2FE),
                          ),
                          if (entry.isUndone) ...[
                            const SizedBox(width: 6),
                            const InfoPill(label: 'Undone'),
                          ],
                          const Spacer(),
                          Text(
                            DateTimeUtils.formatTimestampIst(entry.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.inkMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'By $actor · ${entry.previousState['status'] ?? ''} → ${entry.newState['status'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.inkPrimary,
                        ),
                      ),
                      if (entry.reason != null &&
                          entry.reason!.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          entry.reason!.trim(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondarySlate,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
    this.oldValue,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? oldValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppTheme.primaryIndigo),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkMuted,
                ),
              ),
              const SizedBox(height: 2),
              if (oldValue != null)
                Text(
                  oldValue!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.inkMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
