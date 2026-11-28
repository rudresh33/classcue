import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/date_time_utils.dart';
import 'status_badge.dart';

/// Returns the semantic visual style for an [AvailableSlot.slotSource] tag.
({String label, Color fg, Color bg, Color border, IconData icon})
smartSlotSourceStyle(String slotSource) {
  switch (slotSource) {
    case 'freed_by_cancellation':
      return (
        label: 'Freed Slot',
        fg: const Color(0xFF047857),
        bg: const Color(0xFFD1FAE5),
        border: const Color(0xFF6EE7B7),
        icon: Icons.bolt_rounded,
      );
    case 'saturday_makeup':
      return (
        label: 'Sat Make-up',
        fg: const Color(0xFFB45309),
        bg: const Color(0xFFFEF3C7),
        border: const Color(0xFFFCD34D),
        icon: Icons.weekend_outlined,
      );
    default:
      return (
        label: 'Open Gap',
        fg: const Color(0xFF1D4ED8),
        bg: const Color(0xFFDBEAFE),
        border: const Color(0xFF93C5FD),
        icon: Icons.schedule_rounded,
      );
  }
}

/// Compact Smart Free Slot card used in both RescheduleSheet (single select)
/// and CreatePollSheet (1-tap + Add).
class SmartSlotCard extends StatelessWidget {
  const SmartSlotCard({
    super.key,
    required this.slot,
    this.isSelected = false,
    this.onTap,
    this.trailing,
  });

  final AvailableSlot slot;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tag = smartSlotSourceStyle(slot.slotSource);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryIndigo : AppTheme.cardBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InfoPill(
                        label: tag.label,
                        icon: tag.icon,
                        foreground: tag.fg,
                        background: tag.bg,
                        border: tag.border,
                      ),
                      InfoPill(
                        label: slot.recommendedRoomDisplay,
                        icon: slot.recommendedRoomIsLab
                            ? Icons.computer_rounded
                            : Icons.meeting_room_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateTimeUtils.formatSlotSummary(
                      slot.slotDate,
                      slot.startTime,
                      slot.endTime,
                    ),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkPrimary,
                    ),
                  ),
                  if (slot.slotLabel.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      slot.slotLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (isSelected) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.primaryIndigo,
                size: 22,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
