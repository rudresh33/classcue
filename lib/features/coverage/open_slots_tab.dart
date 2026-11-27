import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../timetable/timetable_provider.dart';

/// Faculty Open Slots Tab: displays cohort-eligible sessions where
/// `is_open_for_coverage == true && faculty_id != auth.uid()`, showing eligible
/// courses and slot duration, and letting faculty pick which of their assigned
/// courses to conduct via `opt_in_coverage(p_session_id, p_covering_course_id)`.
class OpenSlotsTab extends StatefulWidget {
  const OpenSlotsTab({super.key});

  @override
  State<OpenSlotsTab> createState() => _OpenSlotsTabState();
}

class _OpenSlotsTabState extends State<OpenSlotsTab> {
  String? _busySessionId;

  Future<void> _offerToCover(LectureSession session) async {
    final auth = context.read<AuthProvider>();
    final service = auth.service;
    final profile = auth.profile!;
    final origCourse = service.courseById(session.courseId);
    final room = service.roomById(session.roomId);
    final faculty = service.facultyById(session.facultyId);
    final eligibleCourses = service.eligibleCoveringCoursesForSession(
      session,
      profile.id,
    );
    final durationLabel = DateTimeUtils.formatDurationLabel(
      session.startTime,
      session.endTime,
    );

    String? selectedCourseId = eligibleCourses.isNotEmpty
        ? eligibleCourses.first.id
        : null;

    final chosenCourseId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final Course? chosenCourse = selectedCourseId != null
                ? eligibleCourses.firstWhere((c) => c.id == selectedCourseId)
                : null;

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
                      color: AppTheme.coveredStyle.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 20,
                      color: AppTheme.coveredStyle.foreground,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Offer to Cover Slot',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eligibleCourses.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.cancelledStyle.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.cancelledStyle.border,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.block_rounded,
                              size: 18,
                              color: AppTheme.cancelledStyle.foreground,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'None of your assigned courses share a cohort with ${origCourse?.code ?? 'this cancelled lecture'}, so you cannot take this slot.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.cancelledStyle.foreground,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      if (eligibleCourses.length > 1) ...[
                        const Text(
                          'Select which of your assigned courses to conduct:',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.inkPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: selectedCourseId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Course to Conduct',
                            prefixIcon: Icon(Icons.book_outlined),
                            isDense: true,
                          ),
                          items: eligibleCourses
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(
                                    '${c.code} · ${c.name}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setDialogState(() => selectedCourseId = val);
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (chosenCourse != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.coveredStyle.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.coveredStyle.border,
                            ),
                          ),
                          child: Text(
                            'You will conduct ${chosenCourse.code} · ${chosenCourse.name} in place of cancelled ${origCourse?.code ?? 'lecture'}${durationLabel.isNotEmpty ? ' ($durationLabel slot)' : ''}.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.coveredStyle.foreground,
                              height: 1.35,
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceTint,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DialogSummaryRow(
                            label: 'Cancelled Lecture',
                            value:
                                '${origCourse?.code ?? ''} — ${origCourse?.name ?? 'Lecture'}',
                          ),
                          const Divider(height: 12),
                          _DialogSummaryRow(
                            label: 'Primary Faculty',
                            value: faculty?.displayLabel ?? 'Faculty',
                          ),
                          const Divider(height: 12),
                          _DialogSummaryRow(
                            label: 'Slot & Room',
                            value:
                                '${DateTimeUtils.formatSlotSummary(session.sessionDate, session.startTime, session.endTime)}${durationLabel.isNotEmpty ? ' ($durationLabel)' : ''} · ${room?.displayLabel ?? 'Room'}',
                          ),
                          const Divider(height: 12),
                          _DialogSummaryRow(
                            label: 'Batch',
                            value: session.batch == 'ALL'
                                ? 'All Students'
                                : 'Batch ${session.batch}',
                          ),
                          if (session.reason != null &&
                              session.reason!.trim().isNotEmpty) ...[
                            const Divider(height: 12),
                            _DialogSummaryRow(
                              label: 'Cancellation Reason',
                              value: session.reason!.trim(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'The database will atomically verify you have no schedule conflicts and notify enrolled students.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.coveredStyle.foreground,
                  ),
                  onPressed: selectedCourseId == null
                      ? null
                      : () => Navigator.of(dialogCtx).pop(selectedCourseId),
                  child: const Text('Confirm Coverage'),
                ),
              ],
            );
          },
        );
      },
    );

    if (chosenCourseId == null || !mounted) return;

    final chosenCourse = service.courseById(chosenCourseId);
    setState(() => _busySessionId = session.id);
    try {
      await context.read<TimetableProvider>().optInCoverage(
        session.id,
        chosenCourseId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Slot confirmed for ${chosenCourse?.code ?? 'your course'}. Enrolled students & primary faculty notified.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DateTimeUtils.prettifyError(e))));
    } finally {
      if (mounted) setState(() => _busySessionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetable = context.watch<TimetableProvider>();
    final auth = context.read<AuthProvider>();
    final service = auth.service;
    final profile = auth.profile!;
    final slots = timetable.openCoverageSlots;

    return RefreshIndicator(
      onRefresh: () => timetable.refreshAll(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.coveredStyle.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.coveredStyle.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.volunteer_activism_outlined,
                  color: AppTheme.coveredStyle.foreground,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Cancelled or pending slots for cohorts you teach appear here. Take a slot to conduct your own assigned course—enrolled students are notified automatically.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (timetable.isLoading && slots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (slots.isEmpty)
            const EmptyStateView(
              icon: Icons.event_available_outlined,
              title: 'No open slots for coverage',
              subtitle: 'When another faculty member marks a cancelled or pending lecture in one of your cohorts as open for coverage, it will appear here in real time.',
            )
          else
            ...slots.map((session) {
              final eligible = service.eligibleCoveringCoursesForSession(
                session,
                profile.id,
              );
              final durationLabel = DateTimeUtils.formatDurationLabel(
                session.startTime,
                session.endTime,
              );
              final extraPills = <Widget>[
                if (durationLabel.isNotEmpty)
                  InfoPill(
                    label: '$durationLabel slot',
                    icon: Icons.timelapse_rounded,
                  ),
                if (eligible.isNotEmpty)
                  InfoPill(
                    label:
                        'Eligible: ${eligible.map((c) => c.code).join(', ')}',
                    icon: Icons.check_circle_outline_rounded,
                    foreground: AppTheme.scheduledStyle.foreground,
                    background: AppTheme.scheduledStyle.background,
                    border: AppTheme.scheduledStyle.border,
                  )
                else
                  InfoPill(
                    label: 'No eligible course',
                    icon: Icons.block_rounded,
                    foreground: AppTheme.pendingStyle.foreground,
                    background: AppTheme.pendingStyle.background,
                    border: AppTheme.pendingStyle.border,
                  ),
              ];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LectureCard(
                  session: session,
                  service: service,
                  viewerProfile: profile,
                  showDate: true,
                  extraPills: extraPills,
                  onTap: () => _offerToCover(session),
                  trailingAction: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.coveredStyle.foreground,
                      ),
                      onPressed: _busySessionId == session.id
                          ? null
                          : () => _offerToCover(session),
                      icon: _busySessionId == session.id
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 18,
                            ),
                      label: const Text('Offer to Cover'),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _DialogSummaryRow extends StatelessWidget {
  const _DialogSummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.inkPrimary,
          ),
        ),
      ],
    );
  }
}
