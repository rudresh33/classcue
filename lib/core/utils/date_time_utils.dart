import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// IST (Asia/Kolkata, UTC+05:30) and campus schedule formatting utilities.
class DateTimeUtils {
  const DateTimeUtils._();

  static const Duration istOffset = Duration(hours: 5, minutes: 30);

  /// Current wall-clock instant represented as IST components inside a UTC DateTime.
  static DateTime nowIst() {
    return DateTime.now().toUtc().add(istOffset);
  }

  /// Today's calendar date on campus (IST, time zeroed to 00:00).
  static DateTime todayIst() {
    final now = nowIst();
    return DateTime(now.year, now.month, now.day);
  }

  /// Converts any [DateTime] to IST wall-clock components.
  static DateTime toIst(DateTime dt) {
    return dt.toUtc().add(istOffset);
  }

  /// Converts a local-IST DateTime (year/month/day/hour/minute) to true UTC for DB writes.
  static DateTime istWallToUtc(DateTime istWall) {
    return DateTime.utc(
      istWall.year,
      istWall.month,
      istWall.day,
      istWall.hour,
      istWall.minute,
      istWall.second,
    ).subtract(istOffset);
  }

  /// Monday of the ISO week containing [date].
  static DateTime mondayOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  /// Formats a [DateTime] as `YYYY-MM-DD` for Postgres DATE parameters.
  static String toSqlDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Parses `YYYY-MM-DD` into a date-only [DateTime].
  static DateTime parseSqlDate(String value) {
    final parts = value.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// Formats [TimeOfDay] as `HH:MM:SS` for Postgres TIME parameters.
  static String toSqlTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  /// Parses `HH:MM:SS` or `HH:MM` into [TimeOfDay].
  static TimeOfDay parseSqlTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  /// Formats `HH:MM:SS` into compact 24h display `HH:MM`.
  static String formatSqlTime(String sqlTime) {
    final parts = sqlTime.split(':');
    if (parts.length < 2) return sqlTime;
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  /// Formats a [TimeOfDay] as `HH:MM`.
  static String formatTimeOfDay(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Formats a time range `10:30 – 12:30`.
  static String formatTimeRange(String startSql, String endSql) {
    return '${formatSqlTime(startSql)} – ${formatSqlTime(endSql)}';
  }

  /// Formats slot duration between `startSql` and `endSql` like `2h`, `4h`, `1h 30m`, or `45m`.
  static String formatDurationLabel(String startSql, String endSql) {
    final start = parseSqlTime(startSql);
    final end = parseSqlTime(endSql);
    final totalMinutes = timeOfDayToMinutes(end) - timeOfDayToMinutes(start);
    if (totalMinutes <= 0) return '';
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours > 0 && mins > 0) return '${hours}h ${mins}m';
    if (hours > 0) return '${hours}h';
    return '${mins}m';
  }

  /// Formats a campus date like `Mon, 23 Nov`.
  static String formatCampusDate(DateTime date) {
    return DateFormat('EEE, d MMM').format(date);
  }

  /// Formats a campus date with year like `Mon, 23 Nov 2026`.
  static String formatCampusDateFull(DateTime date) {
    return DateFormat('EEE, d MMM yyyy').format(date);
  }

  /// Formats a campus slot like `Mon, 23 Nov · 10:30 – 12:30`.
  static String formatSlotSummary(
    DateTime date,
    String startSql,
    String endSql,
  ) {
    return '${formatCampusDate(date)} · ${formatTimeRange(startSql, endSql)}';
  }

  /// Formats a UTC timestamp in IST like `23 Nov, 16:30 IST`.
  static String formatTimestampIst(DateTime utcDateTime) {
    final ist = toIst(utcDateTime);
    return '${DateFormat('d MMM, HH:mm').format(ist)} IST';
  }

  /// Formats relative IST timestamp for notifications/history.
  static String formatRelativeIst(DateTime utcDateTime) {
    final diff = DateTime.now().toUtc().difference(utcDateTime.toUtc());
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatTimestampIst(utcDateTime);
  }

  /// Compares two [TimeOfDay] values (minutes from midnight).
  static int timeOfDayToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  /// Converts minutes from midnight into a [TimeOfDay] clamped to 00:00–23:59.
  static TimeOfDay minutesToTimeOfDay(int minutes) {
    final clamped = minutes.clamp(0, 23 * 60 + 59);
    return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
  }

  /// Formats a duration in minutes like `1h`, `1.5h`, `2h`, `4h`, or `45m`.
  static String formatMinutesShort(int minutes) {
    if (minutes <= 0) return '';
    if (minutes % 60 == 0) return '${minutes ~/ 60}h';
    if (minutes % 30 == 0 && minutes > 60) {
      return '${(minutes / 60).toStringAsFixed(1)}h';
    }
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// Checks if two date-only DateTimes fall on the same calendar day.
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Combines a campus date (`YYYY-MM-DD`) and SQL time (`HH:MM:SS`) into a real UTC DateTime
  /// assuming the date/time is in IST.
  static DateTime campusSlotToUtc(DateTime date, String sqlTime) {
    final t = parseSqlTime(sqlTime);
    return istWallToUtc(
      DateTime(date.year, date.month, date.day, t.hour, t.minute),
    );
  }

  /// Day-of-week label from ISO 1..6.
  static String weekdayShort(int isoDay) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (isoDay < 1 || isoDay > 7) return '';
    return labels[isoDay - 1];
  }

  /// Converts PostgREST / Auth / generic exceptions into concise user-friendly messages.
  static String prettifyError(Object error) {
    if (error is PostgrestException) {
      final msg = error.message.trim();
      if (msg.isNotEmpty) {
        if (msg.contains('duplicate key') &&
            msg.contains('uq_one_open_poll_per_session')) {
          return 'An open reschedule poll already exists for this lecture session.';
        }
        if (msg.contains('row-level security')) {
          return 'You do not have permission to perform this action on this record.';
        }
        return msg;
      }
      if (error.details != null && error.details.toString().trim().isNotEmpty) {
        return error.details.toString().trim();
      }
      return 'Database error (${error.code ?? 'unknown'}). Please try again.';
    }
    if (error is AuthException) {
      return error.message;
    }
    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
