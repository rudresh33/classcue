import 'package:classcue/core/utils/date_time_utils.dart';
import 'package:classcue/core/widgets/status_badge.dart';
import 'package:classcue/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ClassCueApp renders developer setup screen when Supabase is not configured',
    (WidgetTester tester) async {
      await tester.pumpWidget(const ClassCueApp());

      expect(find.text('Supabase Environment Required'), findsOneWidget);
      expect(
        find.textContaining('--dart-define-from-file=env.json'),
        findsOneWidget,
      );
      expect(find.textContaining('KYUJUSAN 93'), findsOneWidget);
    },
  );

  testWidgets('StatusBadge renders semantic lecture statuses accurately', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              StatusBadge.lecture('scheduled'),
              StatusBadge.lecture('cancelled'),
              StatusBadge.lecture('rescheduling_pending'),
              StatusBadge.lecture('rescheduled'),
              StatusBadge.lecture('covered'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Rescheduling Pending'), findsOneWidget);
    expect(find.text('Rescheduled'), findsOneWidget);
    expect(find.text('Covered'), findsOneWidget);
  });

  test(
    'DateTimeUtils formats SQL dates, SQL times, and IST offsets cleanly',
    () {
      expect(DateTimeUtils.toSqlDate(DateTime(2026, 11, 23)), '2026-11-23');
      expect(
        DateTimeUtils.toSqlTime(const TimeOfDay(hour: 9, minute: 5)),
        '09:05:00',
      );
      expect(
        DateTimeUtils.formatTimeRange('10:30:00', '12:30:00'),
        '10:30 – 12:30',
      );
      final utc = DateTime.utc(2026, 11, 23, 5, 0);
      expect(DateTimeUtils.formatTimestampIst(utc), '23 Nov, 10:30 IST');
    },
  );
}
