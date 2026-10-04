import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/engine/calendar.dart';

// These tests are written against local time and hold in every time zone;
// they only *catch* the DST bugs when run in a zone with DST, e.g.
// `TZ=Europe/Kyiv flutter test` (Kyiv 2026: spring forward Sun Mar 29
// 03:00→04:00, fall back Sun Oct 25 04:00→03:00).

/// Calendar date of [d] as a comparable UTC midnight.
DateTime _date(DateTime d) => DateTime.utc(d.year, d.month, d.day);

void main() {
  group('dateOnly', () {
    test('strips the time of day, keeping the calendar date', () {
      final d = dateOnly(DateTime(2026, 3, 29, 23, 59, 59));
      expect(d, DateTime(2026, 3, 29));
      expect([d.hour, d.minute, d.second, d.millisecond], [0, 0, 0, 0]);
    });

    test('keeps UTC-ness', () {
      final d = dateOnly(DateTime.utc(2026, 10, 25, 12));
      expect(d.isUtc, isTrue);
      expect(d, DateTime.utc(2026, 10, 25));
    });
  });

  group('addCalendarDays', () {
    test('keeps the wall-clock time on every day of the year (DST-safe)', () {
      final start = DateTime(2026, 1, 1, 8, 30);
      for (var n = -400; n <= 400; n++) {
        final r = addCalendarDays(start, n);
        expect([r.hour, r.minute], [8, 30], reason: 'n=$n → $r');
        expect(_date(r), DateTime.utc(2026, 1, 1 + n), reason: 'n=$n');
      }
    });

    test('midnight steps never repeat or skip a date (week strip, Oct 22 2026)', () {
      final days = [for (var i = 0; i < 7; i++) addCalendarDays(DateTime(2026, 10, 22), i)];
      expect(days.map((d) => d.day), [22, 23, 24, 25, 26, 27, 28]);
      expect(days.every((d) => d.hour == 0), isTrue);
    });

    test('stepping back across spring-forward keeps midnight', () {
      final d = addCalendarDays(DateTime(2026, 4, 2), -28);
      expect(d, DateTime(2026, 3, 5));
      expect(d.hour, 0);
    });

    test('a wall-clock time skipped by spring-forward still lands on the right date', () {
      final r = addCalendarDays(DateTime(2026, 3, 28, 3, 30), 1);
      expect(_date(r), DateTime.utc(2026, 3, 29));
    });

    test('works on UTC values', () {
      final r = addCalendarDays(DateTime.utc(2026, 10, 24, 9), 2);
      expect(r, DateTime.utc(2026, 10, 26, 9));
      expect(r.isUtc, isTrue);
    });
  });

  group('calendarDaysBetween', () {
    test('counts calendar dates, not 24 h blocks', () {
      expect(calendarDaysBetween(DateTime(2026, 3, 28, 23), DateTime(2026, 3, 30, 0, 30)), 2);
      expect(calendarDaysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(calendarDaysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
      expect(calendarDaysBetween(DateTime(2026, 10, 25, 23, 59), DateTime(2026, 10, 26, 0, 1)), 1);
    });

    test('is 0 within a day and negative backwards', () {
      expect(calendarDaysBetween(DateTime(2026, 10, 25, 0, 1), DateTime(2026, 10, 25, 23, 59)), 0);
      expect(calendarDaysBetween(DateTime(2026, 3, 30), DateTime(2026, 3, 28)), -2);
    });

    test('round-trips addCalendarDays for every day of the year', () {
      final start = DateTime(2026, 1, 1, 0, 0);
      for (var n = -400; n <= 400; n++) {
        expect(calendarDaysBetween(start, addCalendarDays(start, n)), n, reason: 'n=$n');
      }
    });
  });

  group('isSameCalendarDay', () {
    test('true only for the same date', () {
      expect(isSameCalendarDay(DateTime(2026, 10, 25, 0, 1), DateTime(2026, 10, 25, 23, 59)), isTrue);
      expect(isSameCalendarDay(DateTime(2026, 10, 25, 23, 59), DateTime(2026, 10, 26)), isFalse);
    });
  });
}
