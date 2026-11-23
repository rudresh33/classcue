import 'package:material_ui/material_ui.dart';

import '../models/models.dart';

/// Compact role + cohort/batch chip displayed in the top AppBar.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.profile, this.cohort, this.onTap});

  final UserProfile profile;
  final Cohort? cohort;
  final VoidCallback? onTap;

  String get _label {
    if (profile.isStudent) {
      final sem = cohort?.shortLabel ?? '';
      final parts = ['Student', if (sem.isNotEmpty) sem, profile.labBatch];
      return parts.join(' · ');
    }
    if (profile.isCr) {
      final sem = cohort?.shortLabel ?? '';
      return sem.isNotEmpty ? 'CR · $sem' : 'CR';
    }
    if (profile.isFaculty) {
      final code = profile.facultyCode;
      return code != null && code.isNotEmpty ? 'Faculty · $code' : 'Faculty';
    }
    return 'Admin · GBS';
  }

  Color get _accent {
    switch (profile.role) {
      case 'faculty':
        return const Color(0xFF3730A3);
      case 'cr':
        return const Color(0xFF0F766E);
      case 'admin':
        return const Color(0xFF7C2D12);
      default:
        return const Color(0xFF1D4ED8);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: TextStyle(
                color: _accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 15, color: _accent),
            ],
          ],
        ),
      ),
    );
  }
}
