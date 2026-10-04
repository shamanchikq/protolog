import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/reminder_schedule.dart';

// Frozen "now": Wed 2026-05-18 07:40 (matches the design's week strip).
final now = DateTime(2026, 5, 18, 7, 40);

Reminder interval({
  required double days,
  required DateTime anchor,
  bool enabled = true,
}) => Reminder(
      id: 'i', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
      scheduleMode: 'interval', intervalDays: days, hour: anchor.hour,
      minute: anchor.minute, enabled: enabled, anchorDate: anchor,
    );

Reminder custom(List<ReminderSlot> slots, {bool enabled = true, DateTime? ack}) =>
    Reminder(
      id: 'c', compoundBase: 'BPC-157', compoundEster: 'None',
      scheduleMode: 'custom', intervalDays: 0, hour: 0, minute: 0,
      customSlots: slots, enabled: enabled, acknowledgedUntil: ack,
    );

void main() {
  group('expectedDose', () {
    test('interval returns the anchor even when in the past', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 6, 0));
      expect(expectedDose(r, now), DateTime(2026, 5, 18, 6, 0));
    });

    test('custom returns next slot >= now', () {
      // Mon/Wed/Fri 20:30; now is Wed 07:40 -> today 20:30
      final r = custom([
        ReminderSlot(weekday: 1, hour: 20, minute: 30),
        ReminderSlot(weekday: 3, hour: 20, minute: 30),
        ReminderSlot(weekday: 5, hour: 20, minute: 30),
      ]);
      expect(expectedDose(r, now), DateTime(2026, 5, 18, 20, 30));
    });
  });

  group('nextOccurrence', () {
    test('interval future anchor returns the anchor', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 8, 0));
      expect(nextOccurrence(r, now), DateTime(2026, 5, 18, 8, 0));
    });

    test('interval overdue anchor rolls forward by whole intervals', () {
      // anchor 06:00 today, 3.5d spacing -> next future occurrence = +3.5d
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 6, 0));
      expect(nextOccurrence(r, now), DateTime(2026, 5, 21, 18, 0));
    });

    test('custom rolls a passed slot to next week', () {
      // only Monday 07:00 (before now=07:40); now Mon -> next Monday (May 25)
      final r = custom([ReminderSlot(weekday: 1, hour: 7, minute: 0)]);
      expect(nextOccurrence(r, now), DateTime(2026, 5, 25, 7, 0));
    });

    test('custom respects acknowledgedUntil', () {
      // Mon 20:30 acknowledged -> next is next Mon (May 25)
      // (now=Mon May 18 07:40; ack=May 18 20:30 is after now -> threshold=ack)
      final r = custom(
        [ReminderSlot(weekday: 1, hour: 20, minute: 30)],
        ack: DateTime(2026, 5, 18, 20, 30),
      );
      expect(nextOccurrence(r, now), DateTime(2026, 5, 25, 20, 30));
    });
  });

  group('reminderState', () {
    test('paused when disabled', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 8, 0), enabled: false);
      expect(reminderState(r, now), ReminderState.paused);
    });
    test('interval overdue when anchor is before now', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 6, 0));
      expect(reminderState(r, now), ReminderState.overdue);
    });
    test('interval due when anchor within 12h ahead', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 8, 0));
      expect(reminderState(r, now), ReminderState.due);
    });
    test('interval on when anchor far in the future', () {
      final r = interval(days: 7, anchor: DateTime(2026, 5, 22, 8, 0));
      expect(reminderState(r, now), ReminderState.on);
    });
    test('custom is never overdue (on when > 12h away)', () {
      final r = custom([ReminderSlot(weekday: 3, hour: 20, minute: 30)]);
      expect(reminderState(r, now), ReminderState.on);
    });
  });

  group('advance', () {
    test('skip interval moves anchor forward one interval', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 6, 0));
      final r2 = advanceAfterSkip(r, now: now);
      expect(r2.anchorDate, DateTime(2026, 5, 21, 18, 0));
    });
    test('dose interval re-bases anchor to takenAt + interval', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 6, 0));
      final taken = DateTime(2026, 5, 18, 7, 40);
      final r2 = advanceAfterDose(r, taken);
      expect(r2.anchorDate, taken.add(const Duration(days: 3, hours: 12)));
    });
    test('skip custom sets acknowledgedUntil to the current slot', () {
      // weekday 1 = Monday = today (May 18); the Mon 20:30 slot is acknowledged,
      // so the next occurrence rolls to the following Monday (May 25).
      final r = custom([ReminderSlot(weekday: 1, hour: 20, minute: 30)]);
      final r2 = advanceAfterSkip(r, now: now);
      expect(r2.acknowledgedUntil, DateTime(2026, 5, 18, 20, 30));
      expect(nextOccurrence(r2, now), DateTime(2026, 5, 25, 20, 30));
    });
    test('dose custom sets acknowledgedUntil to takenAt', () {
      final r = custom([ReminderSlot(weekday: 3, hour: 20, minute: 30)]);
      final taken = DateTime(2026, 5, 18, 19, 0);
      final r2 = advanceAfterDose(r, taken);
      expect(r2.acknowledgedUntil, taken);
    });
  });

  group('advanceAfterDose is forward-only (A4)', () {
    // Weekly, next dose Mon May 25 08:00.
    final weekly = interval(days: 7, anchor: DateTime(2026, 5, 25, 8, 0));

    test('a back-dated dose leaves the schedule alone', () {
      // Backfilled from three weeks ago: +7 d lands in the past.
      final r2 = advanceAfterDose(weekly, DateTime(2026, 4, 27, 8, 0), now: now);
      expect(identical(r2, weekly), isTrue);
      expect(reminderState(r2, now), isNot(ReminderState.overdue));
    });

    test('a dose on schedule re-anchors to takenAt + interval', () {
      final taken = DateTime(2026, 5, 25, 8, 10);
      final r2 = advanceAfterDose(weekly, taken, now: taken);
      expect(r2.anchorDate, DateTime(2026, 6, 1, 8, 10));
    });

    test('an early dose still re-anchors (its next dose is after the old anchor)', () {
      final taken = DateTime(2026, 5, 24, 8, 0); // Sunday instead of Monday
      final r2 = advanceAfterDose(weekly, taken, now: taken);
      expect(r2.anchorDate, DateTime(2026, 5, 31, 8, 0));
    });

    test('a late dose on an overdue reminder moves it forward', () {
      final overdue = interval(days: 7, anchor: DateTime(2026, 5, 11, 8, 0));
      final r2 = advanceAfterDose(overdue, DateTime(2026, 5, 17, 9, 0), now: now);
      expect(r2.anchorDate, DateTime(2026, 5, 24, 9, 0));
    });

    test('custom acknowledgement never regresses', () {
      final acked = custom(
        [const ReminderSlot(weekday: 3, hour: 8, minute: 0)],
        ack: DateTime(2026, 5, 20, 8, 0),
      );
      expect(identical(advanceAfterDose(acked, DateTime(2026, 5, 10, 8, 0)), acked), isTrue);
      expect(advanceAfterDose(acked, DateTime(2026, 5, 21, 9, 0)).acknowledgedUntil,
          DateTime(2026, 5, 21, 9, 0));
    });

    test('legacy reminder without an anchor: only a current dose anchors it', () {
      // Floats at "today 08:00" until a dose gives it a rhythm.
      const legacy = Reminder(
        id: 'legacy', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
        intervalDays: 7, hour: 8, minute: 0, enabled: true,
      );
      expect(advanceAfterDose(legacy, DateTime(2026, 4, 27, 8, 0), now: now).anchorDate, isNull);
      expect(advanceAfterDose(legacy, now, now: now).anchorDate, now.add(const Duration(days: 7)));
    });
  });

  group('custom slots honour acknowledgedUntil (A3)', () {
    // Mon/Wed/Fri 08:00; "now" = Sun May 17 20:00.
    final sun = DateTime(2026, 5, 17, 20, 0);
    const mwf = [
      ReminderSlot(weekday: 1, hour: 8, minute: 0),
      ReminderSlot(weekday: 3, hour: 8, minute: 0),
      ReminderSlot(weekday: 5, hour: 8, minute: 0),
    ];

    test('Skip before a slot silences that slot only', () {
      final skipped = advanceAfterSkip(custom(mwf), now: sun);
      expect(skipped.acknowledgedUntil, DateTime(2026, 5, 18, 8, 0));
      expect(customSlotOccurrences(skipped, sun), [
        DateTime(2026, 5, 25, 8, 0), // Monday's dose skipped -> next week
        DateTime(2026, 5, 20, 8, 0),
        DateTime(2026, 5, 22, 8, 0),
      ]);
      // The Reminders tab and the scheduler agree on what's next.
      expect(expectedDose(skipped, sun), DateTime(2026, 5, 20, 8, 0));

      final plans = customSlotPlans(skipped, sun);
      expect(plans.map((p) => p.slotIndex), [0, 1, 2]);
      expect(plans.map((p) => p.repeatsWeekly), [false, true, true]);
      // A repeating trigger can't start past Monday's acknowledged dose,
      // so Monday gets weekly one-shots from the first owed occurrence.
      final mon = plans.first.fireTimes;
      expect(mon, hasLength(kAckedSlotOneShots));
      expect(mon.first, DateTime(2026, 5, 25, 8, 0));
      expect(mon[1], DateTime(2026, 6, 1, 8, 0));
      expect(plans[1].fireTimes.single, DateTime(2026, 5, 20, 8, 0));
      expect(plans[2].fireTimes.single, DateTime(2026, 5, 22, 8, 0));
    });

    test('a dose logged ahead of a slot silences it the same way', () {
      final logged = advanceAfterDose(custom(mwf), DateTime(2026, 5, 18, 8, 0));
      expect(expectedDose(logged, sun), DateTime(2026, 5, 20, 8, 0));
      expect(customSlotPlans(logged, sun).first.repeatsWeekly, isFalse);
    });

    test('Skip on a fired custom notification leaves the next slot alone', () {
      // Monday's 08:00 notification fired; Skip tapped on it at 08:01.
      final r = custom(mwf);
      final at = DateTime(2026, 5, 18, 8, 1);
      expect(identical(advanceAfterNotificationSkip(r, now: at), r), isTrue);
      expect(customSlotPlans(r, at).every((p) => p.repeatsWeekly), isTrue);
      // The in-app Skip at that moment means the row's next slot (Wednesday).
      expect(advanceAfterSkip(r, now: at).acknowledgedUntil, DateTime(2026, 5, 20, 8, 0));
    });

    test('Skip on an interval notification skips the dose it announced', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 6, 0));
      expect(advanceAfterNotificationSkip(r, now: now).anchorDate, DateTime(2026, 5, 21, 18, 0));
    });

    test('an acknowledgement in the past is a no-op', () {
      final r = custom(mwf, ack: DateTime(2026, 5, 10, 8, 0));
      expect(customSlotOccurrences(r, sun), [
        DateTime(2026, 5, 18, 8, 0),
        DateTime(2026, 5, 20, 8, 0),
        DateTime(2026, 5, 22, 8, 0),
      ]);
      expect(customSlotPlans(r, sun).every((p) => p.repeatsWeekly), isTrue);
    });

    test('a slot later today is today; one earlier today is next week', () {
      // now = Mon May 18 07:40
      final r = custom(const [
        ReminderSlot(weekday: 1, hour: 20, minute: 30),
        ReminderSlot(weekday: 1, hour: 7, minute: 0),
      ]);
      expect(customSlotOccurrences(r, now), [
        DateTime(2026, 5, 18, 20, 30),
        DateTime(2026, 5, 25, 7, 0),
      ]);
      expect(customSlotPlans(r, now).every((p) => p.repeatsWeekly), isTrue);
    });

    test('corrupt slots are skipped, never looped on', () {
      final r = custom(const [
        ReminderSlot(weekday: 0, hour: 8, minute: 0),
        ReminderSlot(weekday: 8, hour: 8, minute: 0),
        ReminderSlot(weekday: 3, hour: 24, minute: 0),
        ReminderSlot(weekday: 3, hour: 8, minute: 60),
        ReminderSlot(weekday: 5, hour: 8, minute: 0),
      ]);
      expect(customSlotOccurrences(r, sun), [null, null, null, null, DateTime(2026, 5, 22, 8, 0)]);
      expect(customSlotPlans(r, sun).single.slotIndex, 4);
      expect(expectedDose(r, sun), DateTime(2026, 5, 22, 8, 0));

      final allBad = custom(const [ReminderSlot(weekday: 0, hour: 8, minute: 0)]);
      expect(() => expectedDose(allBad, sun), returnsNormally);
      expect(customSlotPlans(allBad, sun), isEmpty);
      expect(() => formatSchedule(allBad), returnsNormally);
      expect(() => weekAgenda([allBad], sun, 7, (_) => const Color(0xFF000000)), returnsNormally);
    });

    test('slot time holds across a DST change (calendar-day stepping)', () {
      // Europe/Kyiv springs forward Sun 2026-03-29 03:00 -> 04:00; stepping
      // by 24 h would land the Sunday 08:00 slot at 09:00. (Meaningful under
      // TZ=Europe/Kyiv; trivially true in UTC.)
      const sunday8 = [ReminderSlot(weekday: 7, hour: 8, minute: 0)];
      final fri = DateTime(2026, 3, 27, 9, 0);
      expect(expectedDose(custom(sunday8), fri), DateTime(2026, 3, 29, 8, 0));

      // Acknowledged Mar 22 slot: the one-shots that replace the weekly
      // repeat all stay at 08:00 on the far side of the change.
      final acked = custom(sunday8, ack: DateTime(2026, 3, 22, 8, 0));
      final plan = customSlotPlans(acked, DateTime(2026, 3, 20, 9, 0)).single;
      expect(plan.repeatsWeekly, isFalse);
      expect(plan.fireTimes.first, DateTime(2026, 3, 29, 8, 0));
      expect(plan.fireTimes.every((t) => t.hour == 8 && t.weekday == 7), isTrue);
    });

    test('notification id offsets fit the per-reminder cancel sweep', () {
      final offsets = <int>{
        for (var s = 0; s < kMaxCustomSlots; s++) ...[
          customSlotIdOffset(s),
          for (var w = 0; w < kAckedSlotOneShots; w++) customSlotIdOffset(s, oneShot: w),
        ],
      };
      expect(offsets, hasLength(kMaxCustomSlots * (1 + kAckedSlotOneShots))); // all distinct
      expect(offsets.every((o) => o >= 1 && o < kNotificationIdsPerReminder), isTrue);
    });
  });

  group('corrupt intervals never throw or hang (A7)', () {
    for (final days in [0.0, -1.0, double.nan, double.infinity, 1e9]) {
      test('intervalDays $days', () {
        // Anchor in the past, so the roll-forward arithmetic would run.
        final r = interval(days: days, anchor: DateTime(2026, 5, 10, 8, 0));
        expect(() => nextOccurrence(r, now), returnsNormally);
        expect(intervalOccurrences(r, now, 10), isEmpty);
        expect(() => advanceAfterSkip(r, now: now), returnsNormally);
        expect(() => advanceAfterDose(r, now, now: now), returnsNormally);
        expect(() => formatSchedule(r), returnsNormally);
        expect(weekAgenda([r], now, 7, (_) => const Color(0xFF000000)).every((d) => d.isEmpty),
            isTrue);
      });
    }

    test('intervalOccurrences steps whole intervals from the next occurrence', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 6, 0)); // overdue
      expect(intervalOccurrences(r, now, 3), [
        DateTime(2026, 5, 21, 18, 0),
        DateTime(2026, 5, 25, 6, 0),
        DateTime(2026, 5, 28, 18, 0),
      ]);
    });
  });

  group('formatSchedule', () {
    test('interval fractional', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 8, 0));
      expect(formatSchedule(r), 'Every 3.5 days · 08:00');
    });
    test('interval whole number', () {
      final r = interval(days: 7, anchor: DateTime(2026, 5, 18, 8, 0));
      expect(formatSchedule(r), 'Every 7 days · 08:00');
    });
    test('custom weekdays', () {
      final r = custom([
        for (var w = 1; w <= 5; w++) ReminderSlot(weekday: w, hour: 8, minute: 0),
      ]);
      expect(formatSchedule(r), 'Weekdays · 08:00');
    });
    test('custom MWF uses letters', () {
      final r = custom([
        ReminderSlot(weekday: 1, hour: 20, minute: 30),
        ReminderSlot(weekday: 3, hour: 20, minute: 30),
        ReminderSlot(weekday: 5, hour: 20, minute: 30),
      ]);
      expect(formatSchedule(r), 'M / W / F · 20:30');
    });
    test('custom two days uses short names', () {
      final r = custom([
        ReminderSlot(weekday: 2, hour: 9, minute: 0),
        ReminderSlot(weekday: 6, hour: 9, minute: 0),
      ]);
      expect(formatSchedule(r), 'Tue / Sat · 09:00');
    });
    test('custom single day pluralizes', () {
      final r = custom([ReminderSlot(weekday: 7, hour: 9, minute: 0)]);
      expect(formatSchedule(r), 'Sundays · 09:00');
    });
  });

  group('relativeDayLabel', () {
    test('today/tomorrow/yesterday', () {
      expect(relativeDayLabel(DateTime(2026, 5, 18, 8), now), 'Today');
      expect(relativeDayLabel(DateTime(2026, 5, 19, 8), now), 'Tomorrow');
      expect(relativeDayLabel(DateTime(2026, 5, 17, 8), now), 'Yesterday');
    });
    test('further out shows weekday + month + day', () {
      expect(relativeDayLabel(DateTime(2026, 5, 21, 8), now), 'Thu May 21');
    });
  });

  group('reminderNotificationBody', () {
    const testCyp = CompoundDefinition(
      id: 'test_cyp', base: 'Testosterone', ester: 'Cypionate',
      type: CompoundType.steroid, graphType: GraphType.curve,
      halfLife: 5.0, timeToPeak: 1.8, ratio: 0.69,
      unit: Unit.mg, colorValue: 0xFFA8C9E8,
    );
    Injection inj(DateTime when, double mg) => Injection(
          id: when.toIso8601String(), compoundId: 'test_cyp',
          date: when, dosage: mg, snapshot: testCyp,
        );

    test('plain label when the compound has never been logged', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 8, 0));
      expect(reminderNotificationBody(r, const []),
          'Time to administer Testosterone Cypionate');
    });

    test('includes the most recent dose when history exists', () {
      final r = interval(days: 3.5, anchor: DateTime(2026, 5, 18, 8, 0));
      final body = reminderNotificationBody(r, [
        inj(DateTime(2026, 5, 10, 8, 0), 200),
        inj(DateTime(2026, 5, 14, 8, 0), 250), // latest wins
      ]);
      expect(body, 'Time to administer Testosterone Cypionate · last dose 250 mg');
    });

    test('omits "None" ester and trims trailing zeros', () {
      final r = custom([ReminderSlot(weekday: 1, hour: 8, minute: 0)]);
      const bpc = CompoundDefinition(
        id: 'bpc', base: 'BPC-157', ester: 'None',
        type: CompoundType.peptide, graphType: GraphType.activeWindow,
        halfLife: 0.2, timeToPeak: 0.05, ratio: 1.0,
        unit: Unit.mcg, colorValue: 0xFF8FC5A8,
      );
      final body = reminderNotificationBody(r, [
        Injection(
          id: 'x', compoundId: 'bpc',
          date: DateTime(2026, 5, 17, 8, 0), dosage: 250.0, snapshot: bpc,
        ),
      ]);
      expect(body, 'Time to administer BPC-157 · last dose 250 mcg');
    });
  });

  group('weekAgenda', () {
    test('places compound colors on the correct days', () {
      const red = Color(0xFFFF0000);
      const blue = Color(0xFF0000FF);
      // interval every 7d anchored today (Mon May 18) 08:00 -> hits day 0 only in the window
      final a = interval(days: 7, anchor: DateTime(2026, 5, 18, 8, 0));
      // custom Friday 09:00 -> May 22 = day index 4 (Mon May 18 is index 0)
      final b = custom([ReminderSlot(weekday: 5, hour: 9, minute: 0)]);
      final agenda = weekAgenda([a, b], now, 7, (r) => r.id == 'i' ? red : blue);
      expect(agenda.length, 7);
      expect(agenda[0], contains(red));   // today (Mon)
      expect(agenda[4], contains(blue));  // Friday
      expect(agenda[1], isEmpty);         // Tuesday: nothing
    });
    test('skips disabled reminders', () {
      const red = Color(0xFFFF0000);
      final a = interval(days: 7, anchor: DateTime(2026, 5, 18, 8, 0), enabled: false);
      final agenda = weekAgenda([a], now, 7, (_) => red);
      expect(agenda.every((d) => d.isEmpty), isTrue);
    });
  });
}
