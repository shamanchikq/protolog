import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/reminder_editor_page.dart';

void main() {
  testWidgets('new reminder: picker visible, save disabled until compound chosen', (tester) async {
    Reminder? saved;
    await tester.pumpWidget(MaterialApp(
      home: ReminderEditorPage(
        userCompounds: const [],
        now: DateTime(2026, 5, 18, 8, 0),
        onSave: (r) => saved = r,
      ),
    ));
    expect(find.text('New reminder'), findsOneWidget);
    expect(find.text('Injectable'), findsWidgets);
    // tapping save without a compound does nothing
    await tester.tap(find.text('Save reminder'));
    await tester.pump();
    expect(saved, isNull);
  });

  testWidgets('editing an existing reminder shows Edit title + Delete', (tester) async {
    final r = Reminder(
      id: 'r', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
      scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
      enabled: true, anchorDate: DateTime(2026, 5, 18, 8, 0),
    );
    await tester.pumpWidget(MaterialApp(
      home: ReminderEditorPage(
        editing: r, userCompounds: const [], now: DateTime(2026, 5, 18, 8, 0),
        onSave: (_) {}, onDelete: () {},
      ),
    ));
    expect(find.text('Edit reminder'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Every 3.5 days · 08:00'), findsNothing); // formatSchedule not shown in editor; preview uses "Next dose"
    expect(find.text('NEXT DOSE'), findsOneWidget); // _label() upper-cases its text
  });

  group('first-dose stepper moves one calendar day per tap (B27)', () {
    // Meaningful under TZ=Europe/Kyiv: Oct 25 2026 is 25 h long and
    // Mar 29 2026 is 23 h long, so 24 h steps lose or skip a day.
    Future<void> pump(WidgetTester tester, DateTime now) async {
      // Tall enough that the whole (lazily built) form is laid out.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 2000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ReminderEditorPage(userCompounds: const [], now: now, onSave: (_) {}),
      ));
    }

    testWidgets('forward across fall-back', (tester) async {
      await pump(tester, DateTime(2026, 10, 25, 10, 0));
      expect(find.text('Today'), findsOneWidget);
      await tester.tap(find.text('›'));
      await tester.pump();
      expect(find.text('Tomorrow'), findsOneWidget);
    });

    testWidgets('back across spring-forward', (tester) async {
      await pump(tester, DateTime(2026, 3, 30, 10, 0));
      await tester.tap(find.text('‹'));
      await tester.pump();
      expect(find.text('Yesterday'), findsOneWidget);
      await tester.tap(find.text('‹'));
      await tester.pump();
      expect(find.text('Sat Mar 28'), findsOneWidget);
    });
  });

  group('a time picked after the editor is gone is dropped', () {
    // The editor route is removed while its time picker is open (e.g. the
    // app navigates away); confirming the picker must not setState on the
    // disposed editor.
    Future<void> pickAfterClose(WidgetTester tester, Reminder? editing, Finder timeField) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 2000);
      addTearDown(tester.view.reset);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const SizedBox()));
      final route = MaterialPageRoute<void>(
        builder: (_) => ReminderEditorPage(
          editing: editing, userCompounds: const [], now: DateTime(2026, 5, 18, 8, 0), onSave: (_) {},
        ),
      );
      nav.currentState!.push(route);
      await tester.pumpAndSettle();
      await tester.tap(timeField);
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);

      nav.currentState!.removeRoute(route);
      await tester.pumpAndSettle();
      expect(find.byType(ReminderEditorPage), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('interval time', (tester) async {
      await pickAfterClose(tester, null, find.text('TIME'));
    });

    testWidgets('custom day time', (tester) async {
      final custom = Reminder(
        id: 'c', compoundBase: 'BPC-157', compoundEster: 'None',
        scheduleMode: 'custom', intervalDays: 0, hour: 8, minute: 0, enabled: true,
        customSlots: const [ReminderSlot(weekday: 2, hour: 9, minute: 15)],
      );
      await pickAfterClose(tester, custom, find.byKey(const ValueKey('slot-time-2')));
    });
  });

  group('times read 24-hour like the rest of the app', () {
    Future<void> pump(WidgetTester tester, {Reminder? editing}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 2000);
      addTearDown(tester.view.reset);
      // The test locale is en_US, whose TimeOfDay.format is "8:00 AM".
      await tester.pumpWidget(MaterialApp(
        home: ReminderEditorPage(
          editing: editing, userCompounds: const [], now: DateTime(2026, 5, 18, 7, 0), onSave: (_) {},
        ),
      ));
    }

    testWidgets('interval time field and its picker', (tester) async {
      await pump(tester);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('8:00 AM'), findsNothing);
      await tester.tap(find.text('TIME'));
      await tester.pumpAndSettle();
      expect(find.text('AM'), findsNothing, reason: '24-hour dial, no AM/PM toggle');
    });

    testWidgets('custom day times and the next-dose preview', (tester) async {
      await pump(
        tester,
        editing: Reminder(
          id: 'c', compoundBase: 'BPC-157', compoundEster: 'None',
          scheduleMode: 'custom', intervalDays: 0, hour: 8, minute: 0, enabled: true,
          customSlots: const [ReminderSlot(weekday: 2, hour: 20, minute: 30)],
        ),
      );
      expect(find.text('Tue'), findsOneWidget);
      expect(find.text('20:30'), findsOneWidget);
      expect(find.text('8:30 PM'), findsNothing);
      expect(find.text('Tomorrow · 20:30'), findsOneWidget);
    });
  });

  testWidgets('picker: one card per base, steroid esters behind a drill-down', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 2000);
    addTearDown(tester.view.reset);
    Reminder? saved;
    await tester.pumpWidget(MaterialApp(
      home: ReminderEditorPage(userCompounds: const [], now: DateTime(2026, 5, 18, 7, 0), onSave: (r) => saved = r),
    ));
    expect(find.text('Testosterone'), findsOneWidget);
    expect(find.textContaining('esters ›'), findsWidgets);

    await tester.tap(find.text('Testosterone'));
    await tester.pump();
    expect(find.text('Testosterone · select ester'), findsOneWidget);
    await tester.tap(find.text('Cypionate'));
    await tester.pump();
    expect(find.text('Testosterone · Cypionate'), findsOneWidget);

    await tester.tap(find.text('Save reminder'));
    await tester.pump();
    expect((saved!.compoundBase, saved!.compoundEster), ('Testosterone', 'Cypionate'));
  });
}

