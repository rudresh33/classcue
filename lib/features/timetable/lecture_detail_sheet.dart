import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../reschedule/reschedule_sheet.dart';
import 'timetable_provider.dart';

/// Detailed Lecture Bottom Sheet with full metadata, faculty/covering faculty names,
/// Change History timeline, contextual role actions, and Undo Last Change support.
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

  bool _canEditSession(UserProfile profile) {
    if (profile.isAdmin) return true;
    if (profile.isFaculty &&
        (_session.facultyId == profile.id ||
            _session.coveringFacultyId == profile.id)) {
      return true;
    }
    return false;
  }

  bool _canUndoLatest(UserProfile profile) {
    if (!_canEditSession(profile) || _history.isEmpty) return false;
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
    final course = service.courseById(_session.courseId);
    final room = service.roomById(_session.roomId);
    final originalRoom = service.roomById(_session.originalRoomId);
    final faculty = service.facultyById(_session.facultyId);
    final coveringFaculty = service.facultyById(_session.coveringFacultyId);
    final cohorts = service.cohortsForCourse(_session.courseId);
    final canEdit = _canEditSession(profile);
    final canUndo = _canUndoLatest(profile);
    final canManagePoll =
        profile.isAdmin ||
        profile.isCr ||
        (profile.isFaculty &&
            (_session.facultyId == profile.id ||
                _session.coveringFacultyId == profile.id));

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
                        course?.code ?? 'Course',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryIndigo,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        course?.name ?? 'Lecture Session',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.inkPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge.lecture(_session.status),
              ],
            ),
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
                    oldValue: _session.hasOriginalSnapshot
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
                  const Divider(height: 18),
                  _DetailLine(
                    icon: Icons.person_outline_rounded,
                    label: 'Primary Faculty',
                    value: faculty?.displayLabel ?? 'Assigned Faculty',
                  ),
                  if (coveringFaculty != null) ...[
                    const Divider(height: 18),
                    _DetailLine(
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Covering Faculty',
                      value: coveringFaculty.displayLabel,
                    ),
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

            // Action Buttons (Role-aware)
            if (canEdit || canManagePoll) ...[
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
