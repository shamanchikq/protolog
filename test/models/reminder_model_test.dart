import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';

void main() {
  group('Reminder serde', () {
    test('round-trips new fields including fractional interval', () {
      final r = Reminder(
        id: 'r1',
        compoundBase: 'Testosterone',
        compoundEster: 'Cypionate',
        scheduleMode: 'interval',
        intervalDays: 3.5,
        hour: 8,
        minute: 0,
        enabled: true,
        anchorDate: DateTime(2026, 5, 18, 8, 0),
        acknowledgedUntil: DateTime(2026, 5, 17, 9, 0),
      );
      final back = Reminder.fromJson(r.toJson());
      expect(back.intervalDays, 3.5);
      expect(back.anchorDate, DateTime(2026, 5, 18, 8, 0));
      expect(back.acknowledgedUntil, DateTime(2026, 5, 17, 9, 0));
    });

    test('migrates legacy JSON: int interval + lastScheduledDate, no anchorDate', () {
      final legacy = {
        'id': 'old',
        'compoundBase': 'Masteron',
        'compoundEster': 'Enanthate',
        'scheduleMode': 'interval',
        'intervalDays': 4, // int in old data
        'hour': 8,
        'minute': 0,
        'customSlots': <dynamic>[],
        'enabled': true,
        'lastScheduledDate': '2026-05-15T08:00:00.000',
      };
      final r = Reminder.fromJson(legacy);
      expect(r.intervalDays, 4.0);
      expect(r.intervalDays, isA<double>());
      // anchorDate falls back to lastScheduledDate when absent
      expect(r.anchorDate, DateTime(2026, 5, 15, 8, 0));
      expect(r.acknowledgedUntil, isNull);
    });

    test('copyWith updates anchorDate without touching identity', () {
      final r = Reminder(
        id: 'r2', compoundBase: 'HCG', compoundEster: 'None',
        intervalDays: 3.5, hour: 9, minute: 0, enabled: true,
        anchorDate: DateTime(2026, 5, 18, 9, 0),
      );
      final r2 = r.copyWith(anchorDate: DateTime(2026, 5, 21, 9, 0));
      expect(r2.id, 'r2');
      expect(r2.anchorDate, DateTime(2026, 5, 21, 9, 0));
      expect(r2.intervalDays, 3.5);
    });
  });

  group('Reminder notification seed', () {
    test('round-trips an explicit notificationSeed', () {
      final r = Reminder(
        id: 'r1', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
        intervalDays: 3.5, hour: 8, minute: 0, enabled: true,
        notificationSeed: 12345,
      );
      final back = Reminder.fromJson(r.toJson());
      expect(back.notificationSeed, 12345);
      expect(back.notificationIdBase, 12345);
    });

    test('legacy JSON without seed falls back to id.hashCode and freezes it on save', () {
      final legacy = {
        'id': 'old',
        'compoundBase': 'Masteron',
        'compoundEster': 'Enanthate',
        'intervalDays': 4,
        'hour': 8,
        'minute': 0,
        'enabled': true,
      };
      final r = Reminder.fromJson(legacy);
      expect(r.notificationIdBase, 'old'.hashCode);
      // toJson persists the fallback so the seed survives future Dart
      // versions even if String.hashCode changes.
      expect(r.toJson()['notificationSeed'], 'old'.hashCode);
    });

    test('unsaved reminder falls back to id.hashCode via notificationIdBase', () {
      final r = Reminder(
        id: 'fresh', compoundBase: 'HCG', compoundEster: 'None',
        intervalDays: 3.5, hour: 9, minute: 0, enabled: true,
      );
      expect(r.notificationSeed, isNull);
      expect(r.notificationIdBase, 'fresh'.hashCode);
    });

    test('copyWith preserves notificationSeed', () {
      final r = Reminder(
        id: 'r3', compoundBase: 'HCG', compoundEster: 'None',
        intervalDays: 3.5, hour: 9, minute: 0, enabled: true,
        notificationSeed: 777,
      );
      final r2 = r.copyWith(anchorDate: DateTime(2026, 7, 1, 9, 0));
      expect(r2.notificationSeed, 777);
    });
  });

  test('ReminderState enum has four states', () {
    expect(ReminderState.values.length, 4);
  });
}
