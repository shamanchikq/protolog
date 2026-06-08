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
}
