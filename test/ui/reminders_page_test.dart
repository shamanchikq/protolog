import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/reminders_page.dart';

void main() {
  testWidgets('empty state shows CTA', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RemindersPage(
          reminders: const [],
          userCompounds: const [],
          onEditReminder: (_) {},
          onToggleEnabled: (_) {},
          onLogNow: (_) {},
          onSkip: (_) {},
        ),
      ),
    ));
    expect(find.text('No reminders yet'), findsOneWidget);
    expect(find.text('+ New reminder'), findsOneWidget);
  });

  testWidgets('renders a reminder row with state + schedule', (tester) async {
    final now = DateTime(2026, 5, 18, 7, 40);
    final r = Reminder(
      id: 'r', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
      scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
      enabled: true, anchorDate: DateTime(2026, 5, 18, 6, 0),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RemindersPage(
          reminders: [r], userCompounds: const [], now: now,
          onEditReminder: (_) {}, onToggleEnabled: (_) {},
          onLogNow: (_) {}, onSkip: (_) {},
        ),
      ),
    ));
    expect(find.text('Testosterone Cypionate'), findsOneWidget);
    // formatSchedule uses the anchor's time-of-day (06:00), not hour/minute.
    expect(find.text('Every 3.5 days · 06:00'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Log now'), findsOneWidget);
  });
}
