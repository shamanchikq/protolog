import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/reminders_page.dart';

import '../support/finders.dart';

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

  testWidgets('row stripe and week-strip dots use the live resolver (B26)', (tester) async {
    final now = DateTime(2026, 5, 18, 7, 40);
    final r = Reminder(
      id: 'r', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
      scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
      enabled: true, anchorDate: DateTime(2026, 5, 19, 8, 0),
    );
    Future<void> pump({Color Function(String base)? resolver}) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: RemindersPage(
              reminders: [r], userCompounds: const [], now: now,
              onEditReminder: (_) {}, onToggleEnabled: (_) {},
              onLogNow: (_) {}, onSkip: (_) {},
              colorResolver: resolver,
            ),
          ),
        ));

    await pump(resolver: (base) => base == 'Testosterone' ? userColor : Colors.grey);
    // The row's stripe plus the week strip's dots for the doses on the 19th
    // and (3.5 days on) the 22nd.
    expect(coloredWith(userColor), findsNWidgets(3));

    await pump(); // no resolver: the static palette
    expect(coloredWith(userColor), findsNothing);
    expect(coloredWith(const Color(0xFF5DC59C)), findsNWidgets(3));
  });

  group('row actions hand over the row\'s reminder', () {
    final now = DateTime(2026, 5, 18, 7, 40);
    // Overdue (anchor two hours ago) — Log now / Skip are offered.
    final due = Reminder(
      id: 'due', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
      scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
      enabled: true, anchorDate: DateTime(2026, 5, 18, 6, 0),
    );
    // Next dose in three days — nothing to act on yet.
    final later = Reminder(
      id: 'later', compoundBase: 'BPC-157', compoundEster: 'None',
      scheduleMode: 'interval', intervalDays: 7, hour: 9, minute: 0,
      enabled: true, anchorDate: DateTime(2026, 5, 21, 9, 0),
    );
    // Paused: its toggle resumes it.
    final paused = Reminder(
      id: 'paused', compoundBase: 'HCG', compoundEster: 'None',
      scheduleMode: 'interval', intervalDays: 3, hour: 8, minute: 0,
      enabled: false, anchorDate: DateTime(2026, 5, 18, 6, 0),
    );

    late List<String> calls;
    Future<void> pump(WidgetTester tester) {
      calls = [];
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 2000);
      addTearDown(tester.view.reset);
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RemindersPage(
            reminders: [due, later, paused], userCompounds: const [], now: now,
            onEditReminder: (r) => calls.add('edit:${r?.id}'),
            onToggleEnabled: (r) => calls.add('toggle:${r.id}'),
            onLogNow: (r) => calls.add('log:${r.id}'),
            onSkip: (r) => calls.add('skip:${r.id}'),
          ),
        ),
      ));
    }

    testWidgets('Log now and Skip only on the due row', (tester) async {
      await pump(tester);
      expect(find.text('Log now'), findsOneWidget, reason: 'not for later or paused');
      expect(find.text('Skip'), findsOneWidget);
      await tester.tap(find.text('Log now'));
      await tester.tap(find.text('Skip'));
      expect(calls, ['log:due', 'skip:due']);
    });

    testWidgets('each pause toggle pauses or resumes its own reminder', (tester) async {
      await pump(tester);
      expect(find.text('Paused'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reminder-toggle-later')));
      await tester.tap(find.byKey(const ValueKey('reminder-toggle-paused')));
      await tester.tap(find.byKey(const ValueKey('reminder-toggle-due')));
      expect(calls, ['toggle:later', 'toggle:paused', 'toggle:due']);
    });

    testWidgets('tapping a row edits that reminder; the empty state creates one', (tester) async {
      await pump(tester);
      await tester.tap(find.text('BPC-157'));
      await tester.tap(find.text('Testosterone Cypionate'));
      expect(calls, ['edit:later', 'edit:due']);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RemindersPage(
            reminders: const [], userCompounds: const [], now: now,
            onEditReminder: (r) => calls.add('edit:${r?.id}'),
            onToggleEnabled: (_) {}, onLogNow: (_) {}, onSkip: (_) {},
          ),
        ),
      ));
      await tester.tap(find.text('+ New reminder'));
      expect(calls.last, 'edit:null');
    });
  });
}
