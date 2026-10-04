import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/record_validation.dart';

const _testE = CompoundDefinition(
  id: 'test_e', base: 'Testosterone', ester: 'Enanthate',
  type: CompoundType.steroid, graphType: GraphType.curve,
  halfLife: 4.5, timeToPeak: 1.5, ratio: 0.72,
  unit: Unit.mg, colorValue: 0xFF5DC59C,
);

const _interval = Reminder(
  id: 'i', compoundBase: 'Testosterone', compoundEster: 'Enanthate',
  intervalDays: 3.5, hour: 8, minute: 0, enabled: true, notificationSeed: 42,
);

// The editor stores intervalDays: 0 for custom reminders.
const _custom = Reminder(
  id: 'c', compoundBase: 'BPC-157', compoundEster: 'None',
  scheduleMode: 'custom', intervalDays: 0, hour: 8, minute: 0,
  customSlots: [ReminderSlot(weekday: 1, hour: 8, minute: 0)], enabled: true,
);

void main() {
  group('isValidReminder', () {
    test('accepts what the editor produces', () {
      expect(isValidReminder(_interval), isTrue);
      expect(isValidReminder(_custom), isTrue);
      expect(isValidReminder(_interval.copyWith(intervalDays: 0.5)), isTrue);
      expect(isValidReminder(_interval.copyWith(intervalDays: 90)), isTrue);
    });

    test('rejects intervals that are zero, negative, non-finite or absurd', () {
      for (final d in [0.0, -3.5, double.nan, double.infinity, 1e6]) {
        expect(isValidReminder(_interval.copyWith(intervalDays: d)), isFalse, reason: '$d');
      }
    });

    test('rejects out-of-range slots', () {
      for (final s in const [
        ReminderSlot(weekday: 0, hour: 8, minute: 0),
        ReminderSlot(weekday: 8, hour: 8, minute: 0),
        ReminderSlot(weekday: 3, hour: 24, minute: 0),
        ReminderSlot(weekday: 3, hour: -1, minute: 0),
        ReminderSlot(weekday: 3, hour: 8, minute: 60),
      ]) {
        expect(isValidReminder(_custom.copyWith(customSlots: [s])), isFalse,
            reason: '${s.toJson()}');
      }
    });

    test('rejects custom reminders with no slots or more than seven', () {
      expect(isValidReminder(_custom.copyWith(customSlots: [])), isFalse);
      final eight = [
        for (var i = 0; i < 8; i++) ReminderSlot(weekday: i % 7 + 1, hour: 8, minute: 0),
      ];
      expect(isValidReminder(_custom.copyWith(customSlots: eight)), isFalse);
    });

    test('rejects bad top-level time, unknown mode, 32-bit-overflowing seed', () {
      expect(isValidReminder(_interval.copyWith(hour: 24)), isFalse);
      expect(isValidReminder(_interval.copyWith(minute: -1)), isFalse);
      expect(isValidReminder(_interval.copyWith(scheduleMode: 'monthly')), isFalse);
      expect(isValidReminder(_interval.copyWith(notificationSeed: 0x7FFFFFFF)), isFalse);
      expect(isValidReminder(_interval.copyWith(notificationSeed: 1 << 40)), isFalse);
      expect(isValidReminder(_interval.copyWith(notificationSeed: -0x80000000)), isTrue);
    });
  });

  group('isValidCompound / isValidInjection / isValidBloodwork', () {
    test('accepts normal records and harmless edge values', () {
      expect(isValidCompound(_testE), isTrue);
      expect(isValidCompound(_testE.copyWith(timeToPeak: 0, ratio: 0)), isTrue);
      // Legacy pre-B1 records (t½ 0) and odd signs are harmless to the
      // engine and must survive load rather than vanish from the log.
      expect(isValidCompound(_testE.copyWith(halfLife: 0)), isTrue);
      expect(isValidCompound(_testE.copyWith(halfLife: -1, timeToPeak: -1)), isTrue);
      final inj = Injection(
        id: 'x', compoundId: 'test_e', date: DateTime(2026, 6, 1),
        dosage: 0, snapshot: _testE,
      );
      expect(isValidInjection(inj), isTrue);
      expect(
        isValidBloodwork(BloodworkEntry(
          id: 'b', date: DateTime(2026, 6, 1), marker: 'E2', value: 120, unit: 'pmol/L',
        )),
        isTrue,
      );
    });

    test('rejects non-finite PK parameters', () {
      for (final c in [
        _testE.copyWith(halfLife: double.nan),
        _testE.copyWith(halfLife: double.infinity),
        _testE.copyWith(timeToPeak: double.negativeInfinity),
        _testE.copyWith(ratio: double.infinity),
        _testE.copyWith(defaultHalfLife: double.nan),
        _testE.copyWith(concentration: double.infinity),
      ]) {
        expect(isValidCompound(c), isFalse, reason: '${c.toJson()}');
      }
    });

    test('rejects non-finite / negative doses and invalid snapshots', () {
      Injection inj(double mg, CompoundDefinition snap) => Injection(
            id: 'x', compoundId: 'test_e', date: DateTime(2026, 6, 1),
            dosage: mg, snapshot: snap,
          );
      expect(isValidInjection(inj(double.infinity, _testE)), isFalse);
      expect(isValidInjection(inj(double.nan, _testE)), isFalse);
      expect(isValidInjection(inj(-100, _testE)), isFalse);
      expect(isValidInjection(inj(100, _testE.copyWith(halfLife: double.nan))), isFalse);
    });

    test('rejects non-finite lab values', () {
      expect(
        isValidBloodwork(BloodworkEntry(
          id: 'b', date: DateTime(2026, 6, 1), marker: 'E2',
          value: double.infinity, unit: 'pmol/L',
        )),
        isFalse,
      );
    });
  });
}
