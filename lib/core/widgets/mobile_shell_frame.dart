import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Mobile-first responsive shell:
/// - On desktop Chrome viewports wider than 520px, centers a clean 480px phone preview frame
///   with subtle elevation and border.
/// - On mobile viewports (<= 520px), renders edge-to-edge.
class MobileShellFrame extends StatelessWidget {
  const MobileShellFrame({super.key, required this.child});

  final Widget child;

  static const double desktopBreakpoint = 520;
  static const double maxPhoneWidth = 480;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= desktopBreakpoint) {
          return child;
        }
        return Container(
          color: const Color(0xFFE2E8F0),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.surfaceTint,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F0F172A),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(23),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
