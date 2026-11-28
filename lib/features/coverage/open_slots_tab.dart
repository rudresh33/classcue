import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../timetable/timetable_provider.dart';

class _CoverageWindowOption {
  const _CoverageWindowOption({
    required this.key,
    required this.label,
    required this.start,
    required this.end,
    required this.isFull,
  });

  final String key;
  final String label;
  final TimeOfDay start;
  final TimeOfDay end;
  final bool isFull;
}

class _CoverageSelectionResult {
  const _CoverageSelectionResult({
    required this.courseId,
    this.startTime,
    this.endTime,
  });

  final String courseId;
  final String? startTime; // null when full slot
  final String? endTime; // null when full slot
}

/// Faculty Open Slots Tab: displays cohort-eligible sessions where
/// `is_open_for_coverage == true && faculty_id != auth.uid()`, showing eligible
/// courses and slot duration, and letting faculty pick both which of their assigned
/// courses to conduct AND whether to take the full slot or a partial window via
/// `opt_in_coverage(p_session_id, p_covering_course_id, p_start_time, p_end_time)`.
class OpenSlotsTab extends StatefulWidget {
  const OpenSlotsTab({super.key});

  @override
  State<OpenSlotsTab> createState() => _OpenSlotsTabState();
}

class _OpenSlotsTabState extends State<OpenSlotsTab> {
  String? _busySessionId;

  List<_CoverageWindowOption> _buildWindowPresets(LectureSession session) {
    final slotStart = DateTimeUtils.parseSqlTime(session.startTime);
    final slotEnd = DateTimeUtils.parseSqlTime(session.endTime);
    final startMin = DateTimeUtils.timeOfDayToMinutes(slotStart);
    final endMin = DateTimeUtils.timeOfDayToMinutes(slotEnd);
    final totalMins = endMin - startMin;

    final presets = <_CoverageWindowOption>[
      _CoverageWindowOption(
        key: 'full',
        label:
            'Full Slot (${DateTimeUtils.formatTimeRange(session.startTime, session.endTime)})',
        start: slotStart,
        end: slotEnd,
        isFull: true,
      ),
    ];

    if (totalMins <= 60) return presets;

    // Quick 1-hour chunks
    final first1hEnd = DateTimeUtils.minutesToTimeOfDay(startMin + 60);
    presets.add(
      _CoverageWindowOption(
        key: 'first_1h',
        label:
            'First 1h (${DateTimeUtils.formatTimeOfDay(slotStart)} – ${DateTimeUtils.formatTimeOfDay(first1hEnd)})',
        start: slotStart,
        end: first1hEnd,
        isFull: false,
      ),
    );

    if (startMin + 120 <= endMin) {
      final second1hEnd = DateTimeUtils.minutesToTimeOfDay(startMin + 120);
      presets.add(
        _CoverageWindowOption(
          key: 'second_1h',
          label:
              'Second 1h (${DateTimeUtils.formatTimeOfDay(first1hEnd)} – ${DateTimeUtils.formatTimeOfDay(second1hEnd)})',
          start: first1hEnd,
          end: second1hEnd,
          isFull: false,
        ),
      );
    } else if (endMin - 60 > startMin) {
      final last1hStart = DateTimeUtils.minutesToTimeOfDay(endMin - 60);
      presets.add(
        _CoverageWindowOption(
          key: 'last_1h',
          label:
              'Last 1h (${DateTimeUtils.formatTimeOfDay(last1hStart)} – ${DateTimeUtils.formatTimeOfDay(slotEnd)})',
          start: last1hStart,
          end: slotEnd,
          isFull: false,
        ),
      );
    }

    // For 4h (or >= 3.5h) lab slots, also include First 2h and Second 2h presets
    if (totalMins >= 210) {
      final first2hEnd = DateTimeUtils.minutesToTimeOfDay(startMin + 120);
      presets.add(
        _CoverageWindowOption(
          key: 'first_2h',
          label:
              'First 2h (${DateTimeUtils.formatTimeOfDay(slotStart)} – ${DateTimeUtils.formatTimeOfDay(first2hEnd)})',
          start: slotStart,
          end: first2hEnd,
          isFull: false,
        ),
      );
      if (startMin + 240 <= endMin) {
        final second2hEnd = DateTimeUtils.minutesToTimeOfDay(startMin + 240);
        presets.add(
          _CoverageWindowOption(
            key: 'second_2h',
            label:
                'Second 2h (${DateTimeUtils.formatTimeOfDay(first2hEnd)} – ${DateTimeUtils.formatTimeOfDay(second2hEnd)})',
            start: first2hEnd,
            end: second2hEnd,
            isFull: false,
          ),
        );
      }
    }

    return presets;
  }

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
    final slotStart = DateTimeUtils.parseSqlTime(session.startTime);
    final slotEnd = DateTimeUtils.parseSqlTime(session.endTime);
    final slotStartMin = DateTimeUtils.timeOfDayToMinutes(slotStart);
    final slotEndMin = DateTimeUtils.timeOfDayToMinutes(slotEnd);
    final totalMins = slotEndMin - slotStartMin;
    final showDurationSelector = totalMins > 60;
    final presets = _buildWindowPresets(session);

    String? selectedCourseId = eligibleCourses.isNotEmpty
        ? eligibleCourses.first.id
        : null;
    String selectedWindowKey = 'full';
    TimeOfDay customStart = slotStart;
    TimeOfDay customEnd = totalMins > 60
        ? DateTimeUtils.minutesToTimeOfDay(slotStartMin + 60)
        : slotEnd;

    final result = await showDialog<_CoverageSelectionResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final Course? chosenCourse = selectedCourseId != null
                ? eligibleCourses.firstWhere((c) => c.id == selectedCourseId)
                : null;

            final bool isCustom = selectedWindowKey == 'custom';
            final _CoverageWindowOption activePreset = isCustom
                ? presets.first
                : presets.firstWhere(
                    (p) => p.key == selectedWindowKey,
                    orElse: () => presets.first,
                  );

            final TimeOfDay effectiveStart = isCustom
                ? customStart
                : activePreset.start;
            final TimeOfDay effectiveEnd = isCustom
                ? customEnd
                : activePreset.end;
            final int effStartMin = DateTimeUtils.timeOfDayToMinutes(
              effectiveStart,
            );
            final int effEndMin = DateTimeUtils.timeOfDayToMinutes(
              effectiveEnd,
            );

            String? windowValidationError;
            if (effEndMin <= effStartMin) {
              windowValidationError = 'End time must be after start time.';
            } else if (effEndMin - effStartMin < 30) {
              windowValidationError =
                  'Partial coverage must be at least 30 minutes long.';
            } else if (effStartMin < slotStartMin || effEndMin > slotEndMin) {
              windowValidationError =
                  'Chosen window must stay within ${DateTimeUtils.formatTimeRange(session.startTime, session.endTime)}.';
            }

            final bool isPartialWindow =
                windowValidationError == null &&
                (effStartMin > slotStartMin || effEndMin < slotEndMin);

            final String chosenDurationLabel = windowValidationError == null
                ? DateTimeUtils.formatMinutesShort(effEndMin - effStartMin)
                : DateTimeUtils.formatDurationLabel(
                    session.startTime,
                    session.endTime,
                  );

            final String chosenRangeText =
                '${DateTimeUtils.formatTimeOfDay(effectiveStart)} – ${DateTimeUtils.formatTimeOfDay(effectiveEnd)}';

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
                            'You will conduct ${chosenCourse.code} · ${chosenCourse.name} in place of cancelled ${origCourse?.code ?? 'lecture'} ($chosenRangeText · $chosenDurationLabel slot).',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.coveredStyle.foreground,
                              height: 1.35,
                            ),
                          ),
                        ),

                      // Partial-Duration Coverage Selector when open slot > 60 min
                      if (showDurationSelector) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Coverage Duration',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.inkPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ...presets.map(
                              (preset) => ChoiceChip(
                                label: Text(
                                  preset.label,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                selected: selectedWindowKey == preset.key,
                                onSelected: (_) => setDialogState(
                                  () => selectedWindowKey = preset.key,
                                ),
                              ),
                            ),
                            ChoiceChip(
                              label: const Text(
                                'Custom',
                                style: TextStyle(fontSize: 11.5),
                              ),
                              selected: isCustom,
                              onSelected: (_) => setDialogState(
                                () => selectedWindowKey = 'custom',
                              ),
                            ),
                          ],
                        ),
                        if (isCustom) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: ctx,
                                      initialTime: customStart,
                                    );
                                    if (picked != null) {
                                      setDialogState(
                                        () => customStart = picked,
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.schedule_rounded,
                                    size: 15,
                                  ),
                                  label: Text(
                                    'Start ${DateTimeUtils.formatTimeOfDay(customStart)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: ctx,
                                      initialTime: customEnd,
                                    );
                                    if (picked != null) {
                                      setDialogState(() => customEnd = picked);
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.schedule_rounded,
                                    size: 15,
                                  ),
                                  label: Text(
                                    'End ${DateTimeUtils.formatTimeOfDay(customEnd)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (windowValidationError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            windowValidationError,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.cancelledStyle.foreground,
                            ),
                          ),
                        ] else if (isPartialWindow) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCCFBF1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF5EEAD4),
                              ),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 15,
                                  color: Color(0xFF0F766E),
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Only your chosen window will be booked; the remaining time stays free for rescheduling.',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F766E),
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
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
                            label: 'Full Open Slot & Room',
                            value:
                                '${DateTimeUtils.formatSlotSummary(session.sessionDate, session.startTime, session.endTime)} · ${room?.displayLabel ?? 'Room'}',
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
                  onPressed:
                      (selectedCourseId == null ||
                          windowValidationError != null)
                      ? null
                      : () => Navigator.of(dialogCtx).pop(
                          _CoverageSelectionResult(
                            courseId: selectedCourseId!,
                            startTime: isPartialWindow
                                ? DateTimeUtils.toSqlTime(effectiveStart)
                                : null,
                            endTime: isPartialWindow
                                ? DateTimeUtils.toSqlTime(effectiveEnd)
                                : null,
                          ),
                        ),
                  child: const Text('Confirm Coverage'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    final chosenCourse = service.courseById(result.courseId);
    setState(() => _busySessionId = session.id);
    try {
      await context.read<TimetableProvider>().optInCoverage(
        session.id,
        result.courseId,
        startTime: result.startTime,
        endTime: result.endTime,
      );
      if (!mounted) return;
      final partialMsg = result.startTime != null && result.endTime != null
          ? ' (${DateTimeUtils.formatTimeRange(result.startTime!, result.endTime!)})'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Slot confirmed for ${chosenCourse?.code ?? 'your course'}$partialMsg. Enrolled students & primary faculty notified.',
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
                    'Cancelled or pending slots for cohorts you teach appear here. Take the full slot or a partial window to conduct your own assigned course.',
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
