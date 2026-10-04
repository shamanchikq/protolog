import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/engine/reminder_notification_plan.dart';
import 'package:protolog_tracker/engine/reminder_schedule.dart';
import 'package:protolog_tracker/models.dart';

const _seed = 1000;

// Mon 2026-05-18 07:40.
final _now = DateTime(2026, 5, 18, 7, 40);
// Sun 2026-05-17 20:00.
final _sun = DateTime(2026, 5, 17, 20, 0);

Reminder _interval({
  double days = 3.5,
  DateTime? anchor,
  bool enabled = true,
  int? seed = _seed,
}) =>
    Reminder(
      id: 'iv',
      compoundBase: 'Testosterone',
      compoundEster: 'Enanthate',
      scheduleMode: 'interval',
      intervalDays: days,
      hour: 8,
      minute: 0,
      enabled: enabled,
      anchorDate: anchor ?? DateTime(2026, 5, 18, 8, 0),
      notificationSeed: seed,
    );

Reminder _custom(List<ReminderSlot> slots, {bool enabled = true, DateTime? ack}) => Reminder(
      id: 'cu',
      compoundBase: 'BPC-157',
      compoundEster: 'None',
      scheduleMode: 'custom',
      intervalDays: 0,
      hour: 0,
      minute: 0,
      customSlots: slots,
      enabled: enabled,
      acknowledgedUntil: ack,
      notificationSeed: _seed,
    );

const _mwf = [
  ReminderSlot(weekday: 1, hour: 8, minute: 0),
  ReminderSlot(weekday: 3, hour: 8, minute: 0),
  ReminderSlot(weekday: 5, hour: 8, minute: 0),
];

const _testE = CompoundDefinition(
  id: 'test_e',
  base: 'Testosterone',
  ester: 'Enanthate',
  type: CompoundType.steroid,
  graphType: GraphType.curve,
  halfLife: 4.5,
  timeToPeak: 1.5,
  ratio: 0.72,
  unit: Unit.mg,
  colorValue: 0xFF5DC59C,
);

List<PlannedNotification> _plan(Reminder r, DateTime now, {List<Injection> injections = const []}) =>
    planReminderNotifications(r, now, injections: injections);

void main() {
  group('interval mode', () {
    test('ten one-shots, ids base+0..9, one interval apart from the next occurrence', () {
      final plan = _plan(_interval(), _now);
      expect(plan.map((p) => p.id), [for (var i = 0; i < 10; i++) _seed + i]);
      expect(plan.first.when, DateTime(2026, 5, 18, 8, 0));
      for (var i = 0; i < plan.length; i++) {
        expect(plan[i].when, DateTime(2026, 5, 18, 8, 0).add(const Duration(hours: 84) * i));
        expect(plan[i].repeatsWeekly, isFalse);
        expect(plan[i].slotTime, isNull, reason: 'fires at the instant, not a wall-clock time');
      }
      expect(plan.map((p) => p.when), intervalOccurrences(_interval(), _now, 10));
    });

    test('an overdue anchor rolls forward to the next future occurrence', () {
      final r = _interval(days: 7, anchor: DateTime(2026, 5, 4, 8, 0));
      final plan = _plan(r, _now);
      expect(plan.first.when, DateTime(2026, 5, 18, 8, 0));
      expect(plan.first.id, _seed);
    });

    test('ids fall back to id.hashCode for a reminder without a seed', () {
      final plan = _plan(_interval(seed: null), _now);
      expect(plan.first.id, 'iv'.hashCode);
    });

    test('title, payload and body with the last matching dose', () {
      final injections = [
        Injection(id: 'a', compoundId: 'test_e', date: DateTime(2026, 5, 10), dosage: 125, snapshot: _testE),
        Injection(id: 'b', compoundId: 'test_e', date: DateTime(2026, 5, 14), dosage: 150, snapshot: _testE),
      ];
      final plan = _plan(_interval(), _now, injections: injections);
      for (final p in plan) {
        expect(p.title, 'ProtoLog Reminder');
        expect(p.payload, 'iv');
        expect(p.body, 'Time to administer Testosterone Enanthate · last dose 150 mg');
      }
    });

    test('a corrupt interval plans nothing instead of throwing', () {
      for (final days in [0.0, -1.0, double.nan, double.infinity, 1000.0]) {
        expect(_plan(_interval(days: days), _now), isEmpty, reason: 'interval $days');
      }
    });
  });

  group('custom mode', () {
    test('one weekly-repeating notification per slot, ids base+1+slotIndex', () {
      final plan = _plan(_custom(_mwf), _sun);
      expect(plan.map((p) => p.id), [_seed + 1, _seed + 2, _seed + 3]);
      expect(plan.map((p) => p.when), [
        DateTime(2026, 5, 18, 8, 0),
        DateTime(2026, 5, 20, 8, 0),
        DateTime(2026, 5, 22, 8, 0),
      ]);
      for (final p in plan) {
        expect(p.repeatsWeekly, isTrue);
        expect(p.slotTime, (hour: 8, minute: 0));
        expect(p.payload, 'cu');
        expect(p.body, 'Time to administer BPC-157');
      }
    });

    test('an acknowledged slot gets eight weekly one-shots (A3)', () {
      // Skip on Sunday acknowledges Monday's 08:00 dose.
      final skipped = advanceAfterSkip(_custom(_mwf), now: _sun);
      final plan = _plan(skipped, _sun);

      final monday = plan.where((p) => !p.repeatsWeekly).toList();
      expect(monday.map((p) => p.id), [for (var w = 0; w < 8; w++) _seed + 8 + w]);
      expect(monday.map((p) => p.when),
          [for (var w = 0; w < 8; w++) DateTime(2026, 5, 25 + 7 * w, 8, 0)]);
      expect(monday.every((p) => p.slotTime == (hour: 8, minute: 0)), isTrue);

      final repeating = plan.where((p) => p.repeatsWeekly).toList();
      expect(repeating.map((p) => p.id), [_seed + 2, _seed + 3]);
    });

    test("one-shot ids follow the slot's index", () {
      // Acknowledged through Wednesday 08:00: Mon has passed (unacked next
      // week is the regular repeat), Wed is acknowledged.
      final r = _custom(_mwf, ack: DateTime(2026, 5, 20, 8, 0));
      final plan = _plan(r, DateTime(2026, 5, 19, 12, 0));
      final wed = plan.where((p) => !p.repeatsWeekly).map((p) => p.id).toList();
      expect(wed, [for (var w = 0; w < 8; w++) _seed + 1 + 7 + 1 * 8 + w]);
    });

    test('every id stays inside the reminder\'s cancel range', () {
      final everyDay = [
        for (var d = 1; d <= 7; d++) ReminderSlot(weekday: d, hour: 9, minute: 30),
      ];
      // Acknowledge a week ahead: every slot's next occurrence is acked.
      final r = _custom(everyDay, ack: DateTime(2026, 5, 25, 9, 30));
      final plan = _plan(r, _now);
      expect(plan, hasLength(7 * 8));
      final offsets = plan.map((p) => p.id - _seed).toSet();
      expect(offsets, hasLength(plan.length), reason: 'no collisions');
      expect(offsets.every((o) => o >= 0 && o < kNotificationIdsPerReminder), isTrue);
      expect(offsets.any((o) => o < kIntervalNotificationCount && o >= 1 && o <= 7), isFalse,
          reason: 'one-shots never reuse the repeating ids');
    });

    test('corrupt slots are skipped; all-corrupt plans nothing', () {
      final r = _custom(const [
        ReminderSlot(weekday: 0, hour: 8, minute: 0),
        ReminderSlot(weekday: 3, hour: 25, minute: 0),
        ReminderSlot(weekday: 5, hour: 8, minute: 0),
      ]);
      final plan = _plan(r, _sun);
      expect(plan.single.id, _seed + 1 + 2);
      expect(plan.single.when, DateTime(2026, 5, 22, 8, 0));

      final allBad = _custom(const [ReminderSlot(weekday: 9, hour: 8, minute: 0)]);
      expect(_plan(allBad, _sun), isEmpty);
    });

    test('one-shots keep the slot time across a DST change', () {
      // Europe/Kyiv springs forward on Sun 2026-03-29 (meaningful under
      // TZ=Europe/Kyiv; trivially true under UTC).
      final r = _custom(const [ReminderSlot(weekday: 1, hour: 8, minute: 0)],
          ack: DateTime(2026, 3, 23, 8, 0));
      final plan = _plan(r, DateTime(2026, 3, 22, 9, 0));
      expect(plan, hasLength(8));
      expect(plan.every((p) => p.when.hour == 8 && p.when.minute == 0), isTrue);
      expect(plan.first.when, DateTime(2026, 3, 30, 8, 0));
    });
  });

  test('a disabled reminder plans nothing', () {
    expect(_plan(_interval(enabled: false), _now), isEmpty);
    expect(_plan(_custom(_mwf, enabled: false), _sun), isEmpty);
  });
}
