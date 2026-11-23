import 'package:material_ui/material_ui.dart';

/// Semantic color tuple for high-contrast academic status chips and callouts.
class StatusStyle {
  const StatusStyle({
    required this.label,
    required this.shortLabel,
    required this.foreground,
    required this.background,
    required this.border,
    required this.icon,
  });

  final String label;
  final String shortLabel;
  final Color foreground;
  final Color background;
  final Color border;
  final IconData icon;
}

/// Material 3 Indigo/Slate academic palette and semantic status tokens for ClassCue.
class AppTheme {
  const AppTheme._();

  static const Color primaryIndigo = Color(0xFF3730A3);
  static const Color secondarySlate = Color(0xFF475569);
  static const Color surfaceTint = Color(0xFFF8FAFC);
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color inkPrimary = Color(0xFF0F172A);
  static const Color inkMuted = Color(0xFF64748B);

  // Semantic status colors (WCAG AA high contrast on light backgrounds)
  static const StatusStyle scheduledStyle = StatusStyle(
    label: 'Scheduled',
    shortLabel: 'Scheduled',
    foreground: Color(0xFF15803D),
    background: Color(0xFFDCFCE7),
    border: Color(0xFF86EFAC),
    icon: Icons.check_circle_outline_rounded,
  );

  static const StatusStyle cancelledStyle = StatusStyle(
    label: 'Cancelled',
    shortLabel: 'Cancelled',
    foreground: Color(0xFFB91C1C),
    background: Color(0xFFFEE2E2),
    border: Color(0xFFFCA5A5),
    icon: Icons.cancel_outlined,
  );

  static const StatusStyle pendingStyle = StatusStyle(
    label: 'Rescheduling Pending',
    shortLabel: 'Pending',
    foreground: Color(0xFFB45309),
    background: Color(0xFFFEF3C7),
    border: Color(0xFFFCD34D),
    icon: Icons.schedule_rounded,
  );

  static const StatusStyle rescheduledStyle = StatusStyle(
    label: 'Rescheduled',
    shortLabel: 'Rescheduled',
    foreground: Color(0xFF1D4ED8),
    background: Color(0xFFDBEAFE),
    border: Color(0xFF93C5FD),
    icon: Icons.event_repeat_rounded,
  );

  static const StatusStyle coveredStyle = StatusStyle(
    label: 'Covered',
    shortLabel: 'Covered',
    foreground: Color(0xFF6D28D9),
    background: Color(0xFFEDE9FE),
    border: Color(0xFFC4B5FD),
    icon: Icons.person_add_alt_1_rounded,
  );

  static StatusStyle statusStyleFor(String status) {
    switch (status) {
      case 'scheduled':
        return scheduledStyle;
      case 'cancelled':
        return cancelledStyle;
      case 'rescheduling_pending':
        return pendingStyle;
      case 'rescheduled':
        return rescheduledStyle;
      case 'covered':
        return coveredStyle;
      default:
        return scheduledStyle;
    }
  }

  static StatusStyle pollStatusStyleFor(
    String status, {
    bool isVotingOpen = false,
  }) {
    switch (status) {
      case 'open':
        return isVotingOpen
            ? const StatusStyle(
                label: 'Voting Open',
                shortLabel: 'Open',
                foreground: Color(0xFF15803D),
                background: Color(0xFFDCFCE7),
                border: Color(0xFF86EFAC),
                icon: Icons.how_to_vote_rounded,
              )
            : const StatusStyle(
                label: 'Awaiting Confirmation',
                shortLabel: 'Closed',
                foreground: Color(0xFFB45309),
                background: Color(0xFFFEF3C7),
                border: Color(0xFFFCD34D),
                icon: Icons.hourglass_bottom_rounded,
              );
      case 'confirmed':
        return const StatusStyle(
          label: 'Confirmed',
          shortLabel: 'Confirmed',
          foreground: Color(0xFF1D4ED8),
          background: Color(0xFFDBEAFE),
          border: Color(0xFF93C5FD),
          icon: Icons.verified_rounded,
        );
      case 'cancelled_fallback':
        return const StatusStyle(
          label: 'Cancelled (Fallback)',
          shortLabel: 'Fallback',
          foreground: Color(0xFFB91C1C),
          background: Color(0xFFFEE2E2),
          border: Color(0xFFFCA5A5),
          icon: Icons.event_busy_rounded,
        );
      case 'superseded':
        return const StatusStyle(
          label: 'Superseded',
          shortLabel: 'Superseded',
          foreground: Color(0xFF475569),
          background: Color(0xFFF1F5F9),
          border: Color(0xFFCBD5E1),
          icon: Icons.layers_clear_rounded,
        );
      default:
        return scheduledStyle;
    }
  }

  static ThemeData lightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryIndigo,
      brightness: Brightness.light,
      primary: primaryIndigo,
      secondary: secondarySlate,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceTint,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: inkPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: inkPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: cardBorder),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: primaryIndigo.withValues(alpha: 0.12),
        elevation: 2,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primaryIndigo : inkMuted,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryIndigo, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryIndigo,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: inkPrimary,
          side: const BorderSide(color: cardBorder),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: cardBorder),
      ),
      dividerTheme: const DividerThemeData(
        color: cardBorder,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
