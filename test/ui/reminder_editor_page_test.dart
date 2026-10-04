import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/reminder_editor_page.dart';

import '../support/finders.dart';

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

  group('editing an existing reminder', () {
    final now = DateTime(2026, 5, 18, 7, 0);

    Future<List<Reminder>> pump(WidgetTester tester, Reminder editing,
        {VoidCallback? onDelete}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 2000);
      addTearDown(tester.view.reset);
      final saved = <Reminder>[];
      // A fresh app each time: Save pops the page.
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: ReminderEditorPage(
          editing: editing, userCompounds: const [], now: now,
          onSave: saved.add, onDelete: onDelete ?? () {},
        ),
      ));
      return saved;
    }

    final interval = Reminder(
      id: 'r', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
      scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
      enabled: false, anchorDate: DateTime(2026, 5, 19, 6, 30), notificationSeed: 77,
    );

    testWidgets('an interval reminder prefills compound, interval, time and first dose',
        (tester) async {
      final saved = await pump(tester, interval);
      expect(find.text('Edit reminder'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Testosterone · Cypionate'), findsOneWidget);
      expect(find.text('3.5'), findsOneWidget);
      expect(find.text('06:30'), findsOneWidget, reason: "the anchor's time, not hour/minute");
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('Tomorrow · 06:30'), findsOneWidget); // next-dose preview

      // Saved untouched: the same reminder, identity and pause state kept.
      await tester.tap(find.text('Save reminder'));
      await tester.pump();
      final r = saved.single;
      expect((r.id, r.compoundBase, r.compoundEster), ('r', 'Testosterone', 'Cypionate'));
      expect((r.scheduleMode, r.intervalDays), ('interval', 3.5));
      expect(r.anchorDate, DateTime(2026, 5, 19, 6, 30));
      expect((r.hour, r.minute), (6, 30));
      expect(r.enabled, isFalse);
      expect(r.notificationSeed, 77);
    });

    testWidgets('interval edits reach the payload', (tester) async {
      final saved = await pump(tester, interval);
      await tester.tap(find.text('+'));
      await tester.pump();
      await tester.tap(find.text('›')); // first dose one day later
      await tester.pump();
      await tester.tap(find.text('Save reminder'));
      await tester.pump();
      expect(saved.single.intervalDays, 4);
      expect(saved.single.anchorDate, DateTime(2026, 5, 20, 6, 30));
    });

    testWidgets('a custom reminder prefills its slots and saves them sorted, with edits',
        (tester) async {
      final custom = Reminder(
        id: 'c', compoundBase: 'BPC-157', compoundEster: 'None',
        scheduleMode: 'custom', intervalDays: 0, hour: 8, minute: 0, enabled: true,
        notificationSeed: 90,
        customSlots: const [
          ReminderSlot(weekday: 5, hour: 7, minute: 15),
          ReminderSlot(weekday: 2, hour: 20, minute: 30),
        ],
      );
      var saved = await pump(tester, custom);
      expect(find.text('BPC-157'), findsOneWidget); // ester None isn't shown
      expect(find.text('Tue'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
      expect(find.text('20:30'), findsOneWidget);
      expect(find.text('07:15'), findsOneWidget);

      await tester.tap(find.text('Save reminder'));
      await tester.pump();
      List<(int, int, int)> slots(Reminder r) =>
          [for (final s in r.customSlots) (s.weekday, s.hour, s.minute)];
      expect(slots(saved.single), [(2, 20, 30), (5, 7, 15)]);
      expect((saved.single.id, saved.single.scheduleMode, saved.single.notificationSeed),
          ('c', 'custom', 90));

      // Monday added (at the 08:00 default), Friday dropped.
      saved = await pump(tester, custom);
      await tester.tap(find.text('M'));
      await tester.pump();
      await tester.tap(find.text('F'));
      await tester.pump();
      expect(find.text('Fri'), findsNothing);
      await tester.tap(find.text('Save reminder'));
      await tester.pump();
      expect(slots(saved.single), [(1, 8, 0), (2, 20, 30)]);
    });

    testWidgets('Delete asks first, then calls onDelete', (tester) async {
      var deleted = 0;
      await pump(tester, interval, onDelete: () => deleted++);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete reminder?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, 0);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(deleted, 1);
    });
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

  group('compound colors use the live resolver (B26)', () {
    Color resolver(String base) => base == 'Testosterone' ? userColor : Colors.grey;

    Future<void> pump(WidgetTester tester, {Reminder? editing}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 2000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ReminderEditorPage(
          editing: editing, userCompounds: const [], now: DateTime(2026, 5, 18, 7, 0),
          onSave: (_) {}, colorResolver: resolver,
        ),
      ));
    }

    testWidgets('picker cards and the chip of a picked compound', (tester) async {
      await pump(tester);
      expect(coloredWith(userColor), findsOneWidget, reason: 'the Testosterone card');

      await tester.tap(find.text('Testosterone'));
      await tester.pump();
      await tester.tap(find.text('Cypionate'));
      await tester.pump();
      expect(find.text('Testosterone · Cypionate'), findsOneWidget);
      expect(coloredWith(userColor), findsOneWidget, reason: 'the chip');
    });

    testWidgets("an edited reminder's chip", (tester) async {
      await pump(tester,
          editing: Reminder(
            id: 'r', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
            scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
            enabled: true, anchorDate: DateTime(2026, 5, 18, 8, 0),
          ));
      expect(coloredWith(userColor), findsOneWidget);
    });
  });

  group('applyReminderEdit', () {
    final openedAt = DateTime(2026, 5, 18, 7, 0);
    final opened = Reminder(
      id: 'r', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
      scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
      enabled: true, anchorDate: DateTime(2026, 5, 19, 8, 0, 30), notificationSeed: 40,
    );
    // Moved on while the editor was open, and paused from the list.
    final current = opened.copyWith(anchorDate: DateTime(2026, 5, 22, 20, 0), enabled: false);
    Reminder saved({double interval = 3.5, DateTime? anchor, String base = 'Testosterone'}) =>
        Reminder(
          id: 'r', compoundBase: base, compoundEster: 'Cypionate',
          scheduleMode: 'interval', intervalDays: interval, hour: 8, minute: 0,
          enabled: true, anchorDate: anchor ?? DateTime(2026, 5, 19, 8, 0), notificationSeed: 40,
        );
    Reminder apply(Reminder s, {Reminder? from, Reminder? now}) => applyReminderEdit(
        opened: from ?? opened, saved: s, current: now ?? current, openedAt: openedAt);

    test('an unchanged interval schedule keeps the current anchor (seconds aside)', () {
      final r = apply(saved(base: 'Nandrolone'));
      expect(r.anchorDate, current.anchorDate);
      expect(r.compoundBase, 'Nandrolone', reason: 'the compound is not the schedule');
      expect(r.enabled, isFalse, reason: 'enabled always comes from the current reminder');
      expect(r.notificationSeed, 40);
    });

    test('a changed interval, first day or time is saved as edited', () {
      for (final s in [
        saved(interval: 4),
        saved(anchor: DateTime(2026, 5, 20, 8, 0)),
        saved(anchor: DateTime(2026, 5, 19, 9, 0)),
      ]) {
        final r = apply(s);
        expect(r.anchorDate, s.anchorDate);
        expect(r.intervalDays, s.intervalDays);
        expect(r.enabled, isFalse);
      }
    });

    test('a legacy reminder without an anchor started on the day it was opened', () {
      final legacy = Reminder(
        id: 'r', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
        intervalDays: 3.5, hour: 8, minute: 0, enabled: true,
      );
      final advanced = legacy.copyWith(anchorDate: DateTime(2026, 5, 21, 20, 0));
      expect(apply(saved(anchor: DateTime(2026, 5, 18, 8, 0)), from: legacy, now: advanced)
          .anchorDate, advanced.anchorDate);
      // Never advanced: the editor's anchor is all there is.
      expect(apply(saved(anchor: DateTime(2026, 5, 18, 8, 0)), from: legacy, now: legacy)
          .anchorDate, DateTime(2026, 5, 18, 8, 0));
    });

    group('custom', () {
      const slots = [ReminderSlot(weekday: 3, hour: 9, minute: 0), ReminderSlot(weekday: 1, hour: 9, minute: 0)];
      final custom = Reminder(
        id: 'c', compoundBase: 'BPC-157', compoundEster: 'None', scheduleMode: 'custom',
        intervalDays: 0, hour: 8, minute: 0, customSlots: slots, enabled: true,
      );
      final acked = custom.copyWith(acknowledgedUntil: DateTime(2026, 5, 18, 9, 0));
      Reminder savedSlots(List<ReminderSlot> s) => Reminder(
            id: 'c', compoundBase: 'BPC-157', compoundEster: 'None', scheduleMode: 'custom',
            intervalDays: 0, hour: 8, minute: 0, customSlots: s, enabled: true,
          );

      test('the same slots (in any order) keep the acknowledgement', () {
        final r = applyReminderEdit(
            opened: custom, saved: savedSlots(slots.reversed.toList()), current: acked,
            openedAt: openedAt);
        expect(r.acknowledgedUntil, acked.acknowledgedUntil);
      });

      test('changed slots or a mode switch drop it', () {
        for (final s in [
          savedSlots(const [ReminderSlot(weekday: 1, hour: 9, minute: 0)]),
          savedSlots(const [ReminderSlot(weekday: 1, hour: 10, minute: 0), ReminderSlot(weekday: 3, hour: 9, minute: 0)]),
          saved(),
        ]) {
          expect(applyReminderEdit(opened: custom, saved: s, current: acked, openedAt: openedAt)
              .acknowledgedUntil, isNull, reason: '$s');
        }
      });
    });
  });
}
