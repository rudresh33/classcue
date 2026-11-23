import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../admin/admin_tools_tab.dart';
import '../auth/auth_provider.dart';
import '../auth/profile_sheet.dart';
import '../coverage/open_slots_tab.dart';
import '../notifications/alerts_log_tab.dart';
import '../notifications/notifications_provider.dart';
import '../polls/polls_tab.dart';
import '../timetable/timetable_provider.dart';
import '../timetable/timetable_tab.dart';

class _TabSpec {
  const _TabSpec({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
  final int badgeCount;
}

/// Role-aware application shell wrapping all tabs inside `MobileShellFrame`
/// with the shared Top AppBar (`ClassCue`, `RoleBadge`, Profile Sheet trigger)
/// and role-specific bottom `NavigationBar`.
class RoleShellScreen extends StatefulWidget {
  const RoleShellScreen({super.key, required this.roleKey});

  final String roleKey;

  @override
  State<RoleShellScreen> createState() => _RoleShellScreenState();
}

class _RoleShellScreenState extends State<RoleShellScreen> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant RoleShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roleKey != widget.roleKey) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final timetable = context.watch<TimetableProvider>();
    final notifications = context.watch<NotificationsProvider>();
    final profile = auth.profile;

    if (profile == null) {
      return const MobileShellFrame(
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final unreadCount = notifications.unreadCount;
    final openCoverageCount = timetable.openCoverageSlots.length;

    final tabs = _buildTabs(
      role: profile.role,
      unreadCount: unreadCount,
      openCoverageCount: openCoverageCount,
    );

    final safeIndex = _selectedIndex.clamp(0, tabs.length - 1);

    return MobileShellFrame(
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.primaryIndigo,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              const Text('ClassCue'),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: RoleBadge(
                profile: profile,
                cohort: auth.userCohort,
                onTap: () => ProfileSheet.show(context),
              ),
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1),
          ),
        ),
        body: IndexedStack(
          index: safeIndex,
          children: tabs.map((t) => t.page).toList(),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: safeIndex,
          onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
          destinations: tabs.map((t) {
            return NavigationDestination(
              icon: _BadgedIcon(icon: t.icon, count: t.badgeCount),
              selectedIcon: _BadgedIcon(
                icon: t.selectedIcon,
                count: t.badgeCount,
                selected: true,
              ),
              label: t.label,
            );
          }).toList(),
        ),
      ),
    );
  }

  List<_TabSpec> _buildTabs({
    required String role,
    required int unreadCount,
    required int openCoverageCount,
  }) {
    if (role == 'faculty') {
      return [
        const _TabSpec(
          label: 'My Lectures',
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_rounded,
          page: TimetableTab(),
        ),
        _TabSpec(
          label: 'Open Slots',
          icon: Icons.volunteer_activism_outlined,
          selectedIcon: Icons.volunteer_activism_rounded,
          page: const OpenSlotsTab(),
          badgeCount: openCoverageCount,
        ),
        const _TabSpec(
          label: 'Polls',
          icon: Icons.how_to_vote_outlined,
          selectedIcon: Icons.how_to_vote_rounded,
          page: PollsTab(),
        ),
        _TabSpec(
          label: 'Alerts & Log',
          icon: Icons.notifications_outlined,
          selectedIcon: Icons.notifications_rounded,
          page: const AlertsLogTab(),
          badgeCount: unreadCount,
        ),
      ];
    }

    if (role == 'admin') {
      return [
        const _TabSpec(
          label: 'Timetable',
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_rounded,
          page: TimetableTab(),
        ),
        const _TabSpec(
          label: 'Polls',
          icon: Icons.how_to_vote_outlined,
          selectedIcon: Icons.how_to_vote_rounded,
          page: PollsTab(),
        ),
        _TabSpec(
          label: 'Alerts & Log',
          icon: Icons.notifications_outlined,
          selectedIcon: Icons.notifications_rounded,
          page: const AlertsLogTab(),
          badgeCount: unreadCount,
        ),
        const _TabSpec(
          label: 'Admin Tools',
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings_rounded,
          page: AdminToolsTab(),
        ),
      ];
    }

    // Student & CR
    return [
      const _TabSpec(
        label: 'Timetable',
        icon: Icons.calendar_today_outlined,
        selectedIcon: Icons.calendar_today_rounded,
        page: TimetableTab(),
      ),
      const _TabSpec(
        label: 'Polls',
        icon: Icons.how_to_vote_outlined,
        selectedIcon: Icons.how_to_vote_rounded,
        page: PollsTab(),
      ),
      _TabSpec(
        label: 'Alerts & Log',
        icon: Icons.notifications_outlined,
        selectedIcon: Icons.notifications_rounded,
        page: const AlertsLogTab(),
        badgeCount: unreadCount,
      ),
    ];
  }
}

class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({
    required this.icon,
    required this.count,
    this.selected = false,
  });

  final IconData icon;
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      icon,
      color: selected ? AppTheme.primaryIndigo : AppTheme.inkMuted,
    );
    if (count <= 0) return iconWidget;
    return Badge.count(count: count, maxCount: 99, child: iconWidget);
  }
}
