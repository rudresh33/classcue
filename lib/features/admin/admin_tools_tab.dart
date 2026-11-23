import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../polls/polls_provider.dart';
import '../timetable/timetable_provider.dart';

/// Admin Tools Tab for `admin` role:
/// - Live counts overview
/// - Date-range picker calling `generate_lecture_sessions(p_start_date, p_end_date)`
/// - Button calling `expire_stale_polls()`
class AdminToolsTab extends StatefulWidget {
  const AdminToolsTab({super.key});

  @override
  State<AdminToolsTab> createState() => _AdminToolsTabState();
}

class _AdminToolsTabState extends State<AdminToolsTab> {
  late DateTime _startDate;
  late DateTime _endDate;
  Map<String, int>? _counts;
  bool _loadingCounts = true;
  bool _generating = false;
  bool _expiring = false;

  @override
  void initState() {
    super.initState();
    final today = DateTimeUtils.todayIst();
    _startDate = DateTimeUtils.mondayOfWeek(today);
    _endDate = _startDate.add(const Duration(days: 20)); // 3 weeks default
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    setState(() => _loadingCounts = true);
    try {
      final service = context.read<AuthProvider>().service;
      final counts = await service.fetchAdminOverviewCounts();
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _loadingCounts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCounts = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DateTimeUtils.prettifyError(e))));
    }
  }

  Future<void> _pickDateRange() async {
    final today = DateTimeUtils.todayIst();
    final range = await showDateRangePicker(
      context: context,
      firstDate: today.subtract(const Duration(days: 30)),
      lastDate: today.add(const Duration(days: 180)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      helpText: 'Select date range (max 90 days)',
    );
    if (range != null) {
      if (range.duration.inDays > 90) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Range cannot exceed 90 days in a single generate_lecture_sessions call.',
            ),
          ),
        );
        return;
      }
      setState(() {
        _startDate = range.start;
        _endDate = range.end;
      });
    }
  }

  Future<void> _generateSessions() async {
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: 'Generate Dated Sessions?',
      subtitle: 'Idempotently materializes lecture sessions from the weekly base timetable for dates not already generated, cancelled, or rescheduled.',
      rows: [
        ConfirmationDetailRow(
          label: 'Date Range',
          value:
              '${DateTimeUtils.formatCampusDateFull(_startDate)} → ${DateTimeUtils.formatCampusDateFull(_endDate)} (${_endDate.difference(_startDate).inDays + 1} days)',
        ),
      ],
      confirmLabel: 'Generate Sessions',
    );
    if (!confirmed || !mounted) return;

    setState(() => _generating = true);
    try {
      final service = context.read<AuthProvider>().service;
      final inserted = await service.generateLectureSessions(
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      await Future.wait([
        _loadCounts(),
        context.read<TimetableProvider>().refreshAll(silent: true),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inserted == 0
                ? 'All sessions in this range were already materialized (0 inserted).'
                : 'Generated $inserted new dated lecture sessions.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DateTimeUtils.prettifyError(e))));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _expireStalePolls() async {
    setState(() => _expiring = true);
    try {
      final service = context.read<AuthProvider>().service;
      final closed = await service.expireStalePolls();
      if (!mounted) return;
      await Future.wait([
        _loadCounts(),
        context.read<PollsProvider>().refreshAll(silent: true),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            closed == 0
                ? 'No stale polls (>48h past close) found.'
                : 'Closed $closed stale poll(s) as Cancelled (Fallback).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DateTimeUtils.prettifyError(e))));
    } finally {
      if (mounted) setState(() => _expiring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<AuthProvider>().service;
    final counts = _counts;

    return RefreshIndicator(
      onRefresh: _loadCounts,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const Text(
            'Campus Database Overview',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.inkPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingCounts && counts == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.75,
              children: [
                _StatTile(
                  label: 'Weekly Base Slots',
                  value:
                      '${counts?['base_slots'] ?? service.baseTimetableEntries.length}',
                  icon: Icons.calendar_view_week_rounded,
                ),
                _StatTile(
                  label: 'Upcoming Sessions',
                  value: '${counts?['upcoming_sessions'] ?? 0}',
                  icon: Icons.event_note_rounded,
                ),
                _StatTile(
                  label: 'Total Sessions',
                  value: '${counts?['total_sessions'] ?? 0}',
                  icon: Icons.storage_rounded,
                ),
                _StatTile(
                  label: 'Open / Stale Polls',
                  value:
                      '${counts?['open_polls'] ?? 0} / ${counts?['stale_polls'] ?? 0}',
                  icon: Icons.how_to_vote_outlined,
                ),
              ],
            ),

          const SizedBox(height: 20),

          // Session Generator Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_motion_rounded,
                        color: AppTheme.primaryIndigo,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Session Generator',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.inkPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Materializes dated lecture sessions from the active base_timetable using the idempotent generate_lecture_sessions RPC (up to 90 days).',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkMuted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(
                      '${DateTimeUtils.formatCampusDate(_startDate)} – ${DateTimeUtils.formatCampusDate(_endDate)} (${_endDate.difference(_startDate).inDays + 1}d)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _generating ? null : _generateSessions,
                    icon: _generating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 19),
                    label: const Text('Generate Lecture Sessions'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Stale Polls Cleanup Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.cleaning_services_outlined,
                        color: AppTheme.pendingStyle.foreground,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Expire Stale Polls',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.inkPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Closes open polls whose voting deadline passed more than 48 hours ago as Cancelled (Fallback) via expire_stale_polls().',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkMuted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _expiring ? null : _expireStalePolls,
                    icon: _expiring
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.timer_off_outlined, size: 18),
                    label: const Text('Run Expire Stale Polls'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  InfoPill(label: '${service.cohorts.length} Cohorts'),
                  InfoPill(label: '${service.courses.length} Courses'),
                  InfoPill(label: '${service.rooms.length} Rooms'),
                  InfoPill(label: '${service.facultyDirectory.length} Faculty'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppTheme.primaryIndigo),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
