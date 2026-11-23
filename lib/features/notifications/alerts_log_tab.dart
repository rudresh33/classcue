import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_provider.dart';
import 'notifications_provider.dart';

enum _AlertsSection { notifications, changeLog }

/// Alerts & Log Tab with segmented switch between Notifications (tap to mark read,
/// "Mark all read" button) and filterable Timetable Change History audit trail.
class AlertsLogTab extends StatefulWidget {
  const AlertsLogTab({super.key});

  @override
  State<AlertsLogTab> createState() => _AlertsLogTabState();
}

class _AlertsLogTabState extends State<AlertsLogTab> {
  _AlertsSection _section = _AlertsSection.notifications;
  String _historyFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<NotificationsProvider>();
    final profile = auth.profile!;
    final service = auth.service;

    final filteredHistory = _historyFilter == 'all'
        ? provider.history
        : provider.history
              .where((h) => h.actionType == _historyFilter)
              .toList();

    return RefreshIndicator(
      onRefresh: () => provider.refreshAll(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          SegmentedButton<_AlertsSection>(
            segments: [
              ButtonSegment(
                value: _AlertsSection.notifications,
                label: Text(
                  provider.unreadCount > 0
                      ? 'Notifications (${provider.unreadCount})'
                      : 'Notifications',
                ),
                icon: const Icon(Icons.notifications_outlined, size: 17),
              ),
              const ButtonSegment(
                value: _AlertsSection.changeLog,
                label: Text('Change Log'),
                icon: Icon(Icons.history_rounded, size: 17),
              ),
            ],
            selected: {_section},
            showSelectedIcon: false,
            onSelectionChanged: (sel) => setState(() => _section = sel.first),
          ),
          const SizedBox(height: 12),

          if (_section == _AlertsSection.notifications) ...[
            if (provider.unreadCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Text(
                      '${provider.unreadCount} unread',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryIndigo,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => provider.markAllRead(),
                      icon: const Icon(Icons.done_all_rounded, size: 16),
                      label: const Text('Mark all read'),
                    ),
                  ],
                ),
              ),
            if (provider.isLoading && provider.notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (provider.notifications.isEmpty)
              const EmptyStateView(
                icon: Icons.notifications_none_rounded,
                title: 'All caught up',
                subtitle: 'Cancellations, reschedules, room changes, coverage openings, and new polls will appear here in real time.',
              )
            else
              ...provider.notifications.map(
                (n) => _NotificationTile(
                  notification: n,
                  onTap: () => provider.markRead(n),
                ),
              ),
          ] else ...[
            // Filter chips for Change History
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in const [
                    ('all', 'All'),
                    ('cancel', 'Cancelled'),
                    ('reschedule', 'Rescheduled'),
                    ('room_change', 'Room'),
                    ('cover_opt_in', 'Covered'),
                    ('permanent_update', 'Permanent'),
                    ('undo', 'Undo'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(item.$2),
                        selected: _historyFilter == item.$1,
                        onSelected: (_) =>
                            setState(() => _historyFilter = item.$1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (provider.isLoading && filteredHistory.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredHistory.isEmpty)
              const EmptyStateView(
                icon: Icons.history_toggle_off_rounded,
                title: 'No timetable changes logged',
                subtitle: 'Every cancellation, reschedule, room change, coverage opt-in, and undo is permanently audited here.',
              )
            else
              ...filteredHistory.map((entry) {
                final courseId =
                    entry.newState['course_id'] as String? ??
                    entry.previousState['course_id'] as String?;
                final course = service.courseById(courseId);
                final actor = service.resolveActorName(
                  entry.changedBy,
                  currentUid: profile.id,
                );
                return _HistoryCard(
                  entry: entry,
                  courseLabel: course != null
                      ? '${course.code} — ${course.name}'
                      : 'Lecture Session',
                  actorName: actor,
                  roomLookup: (id) => service.roomById(id)?.roomNumber,
                );
              }),
          ],
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  IconData get _icon {
    switch (notification.type) {
      case 'cancellation':
        return Icons.cancel_outlined;
      case 'reschedule':
        return Icons.event_repeat_rounded;
      case 'room_change':
        return Icons.meeting_room_outlined;
      case 'poll':
        return Icons.how_to_vote_outlined;
      case 'coverage_open':
        return Icons.volunteer_activism_outlined;
      default:
        return Icons.notifications_active_outlined;
    }
  }

  Color get _color {
    switch (notification.type) {
      case 'cancellation':
        return AppTheme.cancelledStyle.foreground;
      case 'reschedule':
        return AppTheme.rescheduledStyle.foreground;
      case 'room_change':
        return AppTheme.pendingStyle.foreground;
      case 'poll':
        return AppTheme.primaryIndigo;
      case 'coverage_open':
        return AppTheme.coveredStyle.foreground;
      default:
        return AppTheme.secondarySlate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: unread ? const Color(0xFFF5F7FF) : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, size: 18, color: _color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: AppTheme.inkPrimary,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryIndigo,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.secondarySlate,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${DateTimeUtils.formatRelativeIst(notification.createdAt)} · ${DateTimeUtils.formatTimestampIst(notification.createdAt)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.courseLabel,
    required this.actorName,
    required this.roomLookup,
  });

  final ChangeHistoryEntry entry;
  final String courseLabel;
  final String actorName;
  final String? Function(String?) roomLookup;

  @override
  Widget build(BuildContext context) {
    final prevStatus = entry.previousState['status'] as String? ?? '';
    final newStatus = entry.newState['status'] as String? ?? '';
    final newDate = entry.newState['session_date'] as String?;
    final newStart = entry.newState['start_time'] as String?;
    final newRoom = roomLookup(entry.newState['room_id'] as String?);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InfoPill(
                  label: entry.actionLabel,
                  foreground: entry.actionType == 'cancel'
                      ? AppTheme.cancelledStyle.foreground
                      : entry.isUndo
                      ? AppTheme.pendingStyle.foreground
                      : AppTheme.primaryIndigo,
                  background: entry.actionType == 'cancel'
                      ? AppTheme.cancelledStyle.background
                      : entry.isUndo
                      ? AppTheme.pendingStyle.background
                      : const Color(0xFFEEF2FF),
                  border: entry.actionType == 'cancel'
                      ? AppTheme.cancelledStyle.border
                      : entry.isUndo
                      ? AppTheme.pendingStyle.border
                      : const Color(0xFFC7D2FE),
                ),
                if (entry.isUndone) ...[
                  const SizedBox(width: 6),
                  const InfoPill(label: 'Reverted'),
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
            const SizedBox(height: 7),
            Text(
              courseLabel,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Updated by $actorName · $prevStatus → $newStatus'
              '${newDate != null ? ' · $newDate' : ''}'
              '${newStart != null ? ' ${DateTimeUtils.formatSqlTime(newStart)}' : ''}'
              '${newRoom != null ? ' · $newRoom' : ''}',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.secondarySlate,
              ),
            ),
            if (entry.reason != null && entry.reason!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Note: ${entry.reason!.trim()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.inkMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
