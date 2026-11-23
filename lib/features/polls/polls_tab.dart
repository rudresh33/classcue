import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../timetable/timetable_provider.dart';
import 'create_poll_sheet.dart';
import 'polls_provider.dart';

/// Polls Tab:
/// - Anonymous voting with live progress bars from `get_poll_results`
/// - CR/Faculty/Admin can create new polls (`+ New Poll` FAB) and close open polls as `Cancelled (Fallback)`
/// - Assigned Faculty & Admin ONLY see "Confirm Winning Slot" (never CRs), with early-close
///   checkbox when `isVotingOpen == true` and >48h expiry warning when past confirmation window.
class PollsTab extends StatefulWidget {
  const PollsTab({super.key});

  @override
  State<PollsTab> createState() => _PollsTabState();
}

class _PollsTabState extends State<PollsTab> {
  bool _showClosed = false;
  String? _busyPollId;

  Future<void> _openCreatePoll() async {
    final created = await CreatePollSheet.show(context);
    if (created && mounted) {
      await context.read<PollsProvider>().refreshAll(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reschedule poll opened & notifications sent.'),
        ),
      );
    }
  }

  Future<void> _castVote(PollViewData data, PollOptionResult option) async {
    if (!data.isVotingOpen) return;
    if (option.votedByMe) return;

    setState(() => _busyPollId = data.poll.id);
    try {
      await context.read<PollsProvider>().vote(
        pollData: data,
        optionId: option.optionId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data.hasUserVoted
                ? 'Your anonymous vote has been updated.'
                : 'Your anonymous vote has been recorded.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DateTimeUtils.prettifyError(e))));
    } finally {
      if (mounted) setState(() => _busyPollId = null);
    }
  }

  Future<void> _confirmWinningOption(PollViewData data) async {
    if (data.options.isEmpty) return;
    final service = context.read<AuthProvider>().service;

    // Default to highest-voted option
    final sorted = [...data.options]
      ..sort((a, b) => b.voteCount.compareTo(a.voteCount));
    String selectedOptionId = sorted.first.optionId;
    bool allowEarlyClose = !data.isVotingOpen;
    final reasonCtrl = TextEditingController(
      text: 'Confirmed via class reschedule poll',
    );

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                'Confirm Replacement Slot',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select the slot to confirm. The lecture session will be moved atomically after conflict verification.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...data.options.map((opt) {
                      final room = service.roomById(opt.proposedRoomId);
                      final isChosen = opt.optionId == selectedOptionId;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isChosen
                                ? AppTheme.primaryIndigo
                                : AppTheme.cardBorder,
                            width: isChosen ? 1.5 : 1,
                          ),
                          color: isChosen
                              ? const Color(0xFFEEF2FF)
                              : Colors.white,
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            isChosen
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: isChosen
                                ? AppTheme.primaryIndigo
                                : AppTheme.inkMuted,
                          ),
                          title: Text(
                            DateTimeUtils.formatSlotSummary(
                              opt.proposedDate,
                              opt.proposedStartTime,
                              opt.proposedEndTime,
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${room?.displayLabel ?? 'Original room'} · ${opt.voteCount} ${opt.voteCount == 1 ? 'vote' : 'votes'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => setDialogState(
                            () => selectedOptionId = opt.optionId,
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Confirmation note',
                        isDense: true,
                      ),
                    ),
                    if (data.isVotingOpen) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'Close voting early & confirm now',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Voting is scheduled to close ${DateTimeUtils.formatTimestampIst(data.poll.closesAt)}.',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        value: allowEarlyClose,
                        onChanged: (v) =>
                            setDialogState(() => allowEarlyClose = v ?? false),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: (data.isVotingOpen && !allowEarlyClose)
                      ? null
                      : () => Navigator.of(dialogCtx).pop(true),
                  child: const Text('Confirm Slot'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true || !mounted) {
      reasonCtrl.dispose();
      return;
    }

    setState(() => _busyPollId = data.poll.id);
    try {
      await context.read<PollsProvider>().confirmOption(
        pollId: data.poll.id,
        optionId: selectedOptionId,
        reason: reasonCtrl.text,
        allowEarlyClose: data.isVotingOpen ? allowEarlyClose : false,
      );
      if (!mounted) return;
      await context.read<TimetableProvider>().refreshAll(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Winning slot confirmed & timetable updated!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DateTimeUtils.prettifyError(e))));
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _busyPollId = null);
    }
  }

  Future<void> _closeAsFallback(PollViewData data) async {
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: 'Close Poll as Cancelled (Fallback)?',
      subtitle: 'No proposed replacement slot will be confirmed. The poll will close with Cancelled (Fallback) status.',
      rows: [
        ConfirmationDetailRow(
          label: 'Votes Cast',
          value: '${data.totalVotes} anonymous votes',
        ),
      ],
      confirmLabel: 'Close as Fallback',
      confirmColor: AppTheme.cancelledStyle.foreground,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyPollId = data.poll.id);
    try {
      await context.read<PollsProvider>().closeAsFallback(data.poll.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poll closed as Cancelled (Fallback).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DateTimeUtils.prettifyError(e))));
    } finally {
      if (mounted) setState(() => _busyPollId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final pollsProvider = context.watch<PollsProvider>();
    final profile = auth.profile!;
    final list = _showClosed
        ? pollsProvider.closedPolls
        : pollsProvider.openPolls;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => pollsProvider.refreshAll(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text('Open (${pollsProvider.openPolls.length})'),
                    icon: const Icon(Icons.how_to_vote_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Closed (${pollsProvider.closedPolls.length})'),
                    icon: const Icon(Icons.inventory_2_outlined, size: 17),
                  ),
                ],
                selected: {_showClosed},
                showSelectedIcon: false,
                onSelectionChanged: (sel) =>
                    setState(() => _showClosed = sel.first),
              ),
              const SizedBox(height: 12),

              if (pollsProvider.isLoading && list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (pollsProvider.error != null && list.isEmpty)
                EmptyStateView(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load polls',
                  subtitle: pollsProvider.error!,
                  action: FilledButton(
                    onPressed: () => pollsProvider.refreshAll(),
                    child: const Text('Retry'),
                  ),
                )
              else if (list.isEmpty)
                EmptyStateView(
                  icon: Icons.how_to_vote_outlined,
                  title: _showClosed
                      ? 'No closed polls yet'
                      : 'No open reschedule polls',
                  subtitle: _showClosed
                      ? 'Confirmed, fallback-cancelled, and superseded polls appear here.'
                      : profile.canCreatePolls
                      ? 'Tap "+ New Poll" to collect anonymous student preferences for a replacement lecture slot.'
                      : 'When your CR or faculty proposes replacement slots for a cancelled class, you can vote anonymously here.',
                )
              else
                ...list.map(
                  (data) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PollCard(
                      data: data,
                      profile: profile,
                      service: auth.service,
                      isBusy: _busyPollId == data.poll.id,
                      onVote: (opt) => _castVote(data, opt),
                      onConfirm: () => _confirmWinningOption(data),
                      onCloseFallback: () => _closeAsFallback(data),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (profile.canCreatePolls)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _openCreatePoll,
              backgroundColor: AppTheme.primaryIndigo,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Poll'),
            ),
          ),
      ],
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({
    required this.data,
    required this.profile,
    required this.service,
    required this.isBusy,
    required this.onVote,
    required this.onConfirm,
    required this.onCloseFallback,
  });

  final PollViewData data;
  final UserProfile profile;
  final dynamic service;
  final bool isBusy;
  final ValueChanged<PollOptionResult> onVote;
  final VoidCallback onConfirm;
  final VoidCallback onCloseFallback;

  bool get _canConfirm {
    if (!data.poll.isOpen ||
        data.isStale ||
        data.poll.isPastConfirmationWindow) {
      return false;
    }
    // NEVER show Confirm button to CRs — only Assigned Faculty & Admin
    if (profile.isAdmin) return true;
    if (profile.isFaculty && data.session != null) {
      return data.session!.facultyId == profile.id ||
          data.session!.coveringFacultyId == profile.id;
    }
    return false;
  }

  bool get _canCloseFallback {
    if (!data.poll.isOpen) return false;
    if (profile.isAdmin) return true;
    if (data.poll.createdBy == profile.id) return true;
    if (profile.isFaculty && data.session != null) {
      return data.session!.facultyId == profile.id ||
          data.session!.coveringFacultyId == profile.id;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final session = data.session;
    final course = session != null
        ? service.courseById(session.courseId)
        : null;
    final total = data.totalVotes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course?.code ?? 'Reschedule Poll',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryIndigo,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        course?.name ?? 'Replacement Slot Poll',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.inkPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge.poll(
                  data.poll.status,
                  isVotingOpen: data.isVotingOpen,
                ),
              ],
            ),
            if (session != null) ...[
              const SizedBox(height: 6),
              Text(
                'Original slot: ${DateTimeUtils.formatSlotSummary(session.sessionDate, session.startTime, session.endTime)}${session.batch != 'ALL' ? ' · Batch ${session.batch}' : ''}',
                style: const TextStyle(fontSize: 12, color: AppTheme.inkMuted),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              data.isVotingOpen
                  ? 'Voting closes ${DateTimeUtils.formatTimestampIst(data.poll.closesAt)} · $total anonymous ${total == 1 ? 'vote' : 'votes'}'
                  : 'Closed ${DateTimeUtils.formatTimestampIst(data.poll.closesAt)} · $total anonymous ${total == 1 ? 'vote' : 'votes'}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.secondarySlate,
              ),
            ),

            if (data.poll.isOpen && data.poll.isPastConfirmationWindow) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.cancelledStyle.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cancelledStyle.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.timer_off_outlined,
                      size: 16,
                      color: AppTheme.cancelledStyle.foreground,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Voting closed more than 48 hours ago. This poll can no longer be confirmed—close as Cancelled (Fallback) or open a new poll.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.cancelledStyle.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (data.poll.isOpen && data.isStale) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.pendingStyle.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.pendingStyle.border),
                ),
                child: const Text(
                  'This lecture session was modified after this poll was created. Close as fallback and create a fresh poll if needed.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Poll option rows with anonymous vote progress bars
            ...data.options.map((opt) {
              final pct = total == 0 ? 0.0 : opt.voteCount / total;
              final room = service.roomById(opt.proposedRoomId);
              final canTapToVote =
                  profile.canVoteInPolls && data.isVotingOpen && !isBusy;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: canTapToVote ? () => onVote(opt) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: opt.isSelected
                          ? AppTheme.rescheduledStyle.background
                          : opt.votedByMe
                          ? const Color(0xFFEEF2FF)
                          : AppTheme.surfaceTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: opt.isSelected
                            ? AppTheme.rescheduledStyle.border
                            : opt.votedByMe
                            ? AppTheme.primaryIndigo
                            : AppTheme.cardBorder,
                        width: (opt.votedByMe || opt.isSelected) ? 1.4 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (opt.isSelected)
                              Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: AppTheme.rescheduledStyle.foreground,
                              )
                            else if (profile.canVoteInPolls &&
                                data.isVotingOpen)
                              Icon(
                                opt.votedByMe
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 16,
                                color: opt.votedByMe
                                    ? AppTheme.primaryIndigo
                                    : AppTheme.inkMuted,
                              ),
                            if (opt.isSelected ||
                                (profile.canVoteInPolls && data.isVotingOpen))
                              const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                DateTimeUtils.formatSlotSummary(
                                  opt.proposedDate,
                                  opt.proposedStartTime,
                                  opt.proposedEndTime,
                                ),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.inkPrimary,
                                ),
                              ),
                            ),
                            Text(
                              '${opt.voteCount} (${(pct * 100).round()}%)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.inkPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              room?.displayLabel ?? 'Same room as original',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.inkMuted,
                              ),
                            ),
                            if (opt.votedByMe) ...[
                              const SizedBox(width: 8),
                              const Text(
                                '· Your vote',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryIndigo,
                                ),
                              ),
                            ],
                            if (opt.isSelected) ...[
                              const SizedBox(width: 8),
                              Text(
                                '· Confirmed Winner',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.rescheduledStyle.foreground,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 6,
                            backgroundColor: AppTheme.cardBorder,
                            color: opt.isSelected
                                ? AppTheme.rescheduledStyle.foreground
                                : AppTheme.primaryIndigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            if (_canConfirm || _canCloseFallback) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_canConfirm)
                    FilledButton.icon(
                      onPressed: isBusy ? null : onConfirm,
                      icon: const Icon(Icons.verified_outlined, size: 17),
                      label: const Text('Confirm Winning Slot'),
                    ),
                  if (_canCloseFallback)
                    OutlinedButton.icon(
                      onPressed: isBusy ? null : onCloseFallback,
                      icon: const Icon(Icons.event_busy_outlined, size: 17),
                      label: const Text('Cancelled (Fallback)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.cancelledStyle.foreground,
                        side: BorderSide(color: AppTheme.cancelledStyle.border),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
