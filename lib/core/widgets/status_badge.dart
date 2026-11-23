import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// High-contrast semantic status badge for lecture sessions and polls.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.style,
    this.compact = false,
    this.showIcon = true,
  });

  factory StatusBadge.lecture(String status, {bool compact = false}) {
    return StatusBadge(
      style: AppTheme.statusStyleFor(status),
      compact: compact,
    );
  }

  factory StatusBadge.poll(
    String status, {
    bool isVotingOpen = false,
    bool compact = false,
  }) {
    return StatusBadge(
      style: AppTheme.pollStatusStyleFor(status, isVotingOpen: isVotingOpen),
      compact: compact,
    );
  }

  final StatusStyle style;
  final bool compact;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(style.icon, size: compact ? 13 : 14, color: style.foreground),
            const SizedBox(width: 4),
          ],
          Text(
            compact ? style.shortLabel : style.label,
            style: TextStyle(
              color: style.foreground,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small neutral or tinted pill used for batch (`B1`/`B2`), scope (`Temporary`/`Permanent`),
/// shared courses (`Shared · Sem VII & IX`), and `Room Changed` highlights.
class InfoPill extends StatelessWidget {
  const InfoPill({
    super.key,
    required this.label,
    this.icon,
    this.foreground = AppTheme.secondarySlate,
    this.background = const Color(0xFFF1F5F9),
    this.border = const Color(0xFFCBD5E1),
  });

  final String label;
  final IconData? icon;
  final Color foreground;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
