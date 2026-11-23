import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../timetable/timetable_provider.dart';

/// Faculty Open Slots Tab: displays sessions where `is_open_for_coverage == true && faculty_id != auth.uid()`,
/// allowing faculty to volunteer via `opt_in_coverage` after a confirmation dialog.
class OpenSlotsTab extends StatefulWidget {
  const OpenSlotsTab({super.key});

  @override
  State<OpenSlotsTab> createState() => _OpenSlotsTabState();
}

class _OpenSlotsTabState extends State<OpenSlotsTab> {
  String? _busySessionId;

  Future<void> _offerToCover(LectureSession session) async {
    final service = context.read<AuthProvider>().service;
    final course = service.courseById(session.courseId);
    final room = service.roomById(session.roomId);
    final faculty = service.facultyById(session.facultyId);

    final confirmed = await ConfirmActionDialog.show(
      context,
      title: 'Offer to Cover Lecture?',
      subtitle: 'You will be assigned as the covering instructor for this slot. The database will atomically verify you have no overlapping lecture.',
      rows: [
        ConfirmationDetailRow(
          label: 'Course',
          value: '${course?.code ?? ''} — ${course?.name ?? 'Lecture'}',
        ),
        ConfirmationDetailRow(
          label: 'Primary Faculty',
          value: faculty?.displayLabel ?? 'Faculty',
        ),
        ConfirmationDetailRow(
          label: 'Slot & Room',
          value:
              '${DateTimeUtils.formatSlotSummary(session.sessionDate, session.startTime, session.endTime)} · ${room?.displayLabel ?? 'Room'}',
        ),
        ConfirmationDetailRow(
          label: 'Batch',
          value: session.batch == 'ALL'
              ? 'All Students'
              : 'Batch ${session.batch}',
        ),
      ],
      confirmLabel: 'Confirm Coverage',
      confirmColor: AppTheme.coveredStyle.foreground,
    );

    if (!confirmed || !mounted) return;

    setState(() => _busySessionId = session.id);
    try {
      await context.read<TimetableProvider>().optInCoverage(session.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You are now covering ${course?.code ?? 'this lecture'}. Students & primary faculty notified.',
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
    final service = context.read<AuthProvider>().service;
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
                    'Cancelled or pending slots opened by colleagues appear here. Opting in automatically notifies affected students and locks the slot.',
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
              subtitle: 'When another faculty member marks a cancelled or pending lecture as open for coverage, it will appear here in real time.',
            )
          else
            ...slots.map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LectureCard(
                  session: session,
                  service: service,
                  showDate: true,
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
              ),
            ),
        ],
      ),
    );
  }
}
