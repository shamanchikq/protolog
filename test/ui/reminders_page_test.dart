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

  testWidgets('week strip shows seven distinct dates across fall-back (B27)', (tester) async {
    // Thu Oct 22 2026; Europe/Kyiv falls back on Sun Oct 25, so 24 h steps
    // from midnight read 22, 23, 24, 25, 25, 26, 27. Meaningful under
    // TZ=Europe/Kyiv.
    final now = DateTime(2026, 10, 22, 12, 0);
    final r = Reminder(
      id: 'r', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
      scheduleMode: 'interval', intervalDays: 7, hour: 8, minute: 0,
      enabled: true, anchorDate: DateTime(2026, 10, 26, 8, 0),
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
    for (final day in [22, 23, 24, 25, 26, 27, 28]) {
      expect(find.text('$day'), findsOneWidget, reason: 'Oct $day');
    }
    for (final wd in ['Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed']) {
      expect(find.text(wd), findsOneWidget, reason: wd);
    }
  });

  group('notifications-off banner (B20)', () {
    const title = "Notifications are off — reminders won't alert you";

    Future<void> pump(WidgetTester tester,
        {bool disabled = false, VoidCallback? onAllow, List<Reminder> reminders = const []}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RemindersPage(
            reminders: reminders, userCompounds: const [],
            now: DateTime(2026, 5, 18, 7, 40),
            onEditReminder: (_) {}, onToggleEnabled: (_) {},
            onLogNow: (_) {}, onSkip: (_) {},
            notificationsDisabled: disabled,
            onRequestNotificationPermission: onAllow,
          ),
        ),
      ));
    }

    testWidgets('hidden while notifications are allowed', (tester) async {
      await pump(tester, onAllow: () {});
      expect(find.text(title), findsNothing);
      expect(find.text('Allow'), findsNothing);
    });

    testWidgets('Allow asks for the permission; the hint covers a permanent denial',
        (tester) async {
      var asked = 0;
      await pump(tester, disabled: true, onAllow: () => asked++);
      expect(find.text(title), findsOneWidget);
      expect(find.textContaining('Android Settings'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      expect(asked, 1);
      // Shown above the empty state too: the user is about to set one up.
      expect(find.text('No reminders yet'), findsOneWidget);
    });

    testWidgets('without a permission callback it only points to Settings', (tester) async {
      await pump(tester, disabled: true);
      expect(find.text(title), findsOneWidget);
      expect(find.text('Allow'), findsNothing);
      expect(find.textContaining('Android Settings'), findsOneWidget);
    });
  });
}

