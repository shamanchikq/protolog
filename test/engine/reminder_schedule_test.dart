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
}
