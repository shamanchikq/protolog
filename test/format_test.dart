import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/format.dart';

void main() {
  group('stripTrailingZeros', () {
    test('drops trailing zeros and a dangling point', () {
      expect(stripTrailingZeros('1.500'), '1.5');
      expect(stripTrailingZeros('2.000'), '2');
      expect(stripTrailingZeros('120'), '120');
      expect(stripTrailingZeros('100.0'), '100');
      expect(stripTrailingZeros('0.010'), '0.01');
    });
    test('negative zero reads as zero', () {
      expect(stripTrailingZeros('-0.000'), '0');
      expect(stripTrailingZeros('-0'), '0');
    });
  });

  group('decimalsOf', () {
    test('fewest decimals that reproduce the value', () {
      expect(decimalsOf(120), 0);
      expect(decimalsOf(38.5), 1);
      expect(decimalsOf(0.125), 3);
      expect(decimalsOf(-4.25), 2);
    });
    test('float noise is capped', () {
      expect(decimalsOf(0.1 + 0.2), 6);
      expect(decimalsOf(0.1 + 0.2, maxDecimals: 3), 3);
    });
    test('non-finite is 0', () {
      expect(decimalsOf(double.nan), 0);
      expect(decimalsOf(double.infinity), 0);
    });
  });

  group('formatLabValue', () {
    test('prints values as typed', () {
      expect(formatLabValue(120), '120');
      expect(formatLabValue(38.5), '38.5');
      expect(formatLabValue(0.05), '0.05');
      expect(formatLabValue(0), '0');
    });
    test('hides float noise', () {
      expect(formatLabValue(0.1 + 0.2), '0.3');
      expect(formatLabValue(5.799999999999997), '5.8');
    });
    test('non-finite reads as a dash', () {
      expect(formatLabValue(double.nan), '—');
      expect(formatLabValue(double.infinity), '—');
    });
  });

  group('labDelta / formatLabDelta (B32)', () {
    test('rounds to the precision the draws were recorded with', () {
      // 37.9 − 32.1 is 5.799999999999997 in floating point.
      expect(37.9 - 32.1, isNot(5.8));
      expect(labDelta(37.9, 32.1), 5.8);
      expect(labDelta(32.1, 37.9), -5.8);
      expect(labDelta(38.5, 30), 8.5);
      expect(labDelta(1.25, 1.2), 0.05);
    });
    test('arrow + magnitude without noise', () {
      expect(formatLabDelta(32.1, 37.9), '↓ 5.8');
      expect(formatLabDelta(37.9, 32.1), '↑ 5.8');
      expect(formatLabDelta(38.5, 30), '↑ 8.5');
      expect(formatLabDelta(120, 95), '↑ 25');
    });
    test('no visible change gives an empty string', () {
      expect(formatLabDelta(30, 30), '');
      expect(formatLabDelta(0.3, 0.1 + 0.2), '');
    });
    test('non-finite gives an empty string', () {
      expect(formatLabDelta(double.nan, 1), '');
    });
  });

  group('formatDose', () {
    test('whole doses have no decimals', () {
      expect(formatDose(250), '250');
      expect(formatDose(0), '0');
    });
    test('keeps up to three decimals, no 2-decimal truncation', () {
      expect(formatDose(0.125), '0.125');
      expect(formatDose(2.5), '2.5');
      expect(formatDose(1 / 3), '0.333');
      expect(formatDose(1234.5678), '1234.568');
    });
    test('small doses keep three significant digits', () {
      expect(formatDose(0.0625), '0.0625');
      expect(formatDose(0.00125), '0.00125');
    });
    test('hides float noise', () {
      expect(formatDose(0.1 + 0.2), '0.3');
    });
    test('non-finite reads as a dash', () {
      expect(formatDose(double.nan), '—');
    });
  });

  group('date names', () {
    test('month and weekday arrays line up with DateTime', () {
      expect(monthsShort, hasLength(12));
      expect(monthsLong, hasLength(12));
      expect(weekdaysShort, hasLength(7));
      expect(weekdaysLong, hasLength(7));
      expect(monthsShort[DateTime.june - 1], 'Jun');
      expect(monthsLong[DateTime.december - 1], 'December');
      expect(weekdaysShort[DateTime.monday - 1], 'Mon');
      expect(weekdaysLong[DateTime.sunday - 1], 'Sunday');
    });
    test('formatMonthDay', () {
      expect(formatMonthDay(DateTime(2026, 6, 2)), 'Jun 2');
      expect(formatMonthDay(DateTime(2026, 12, 31, 23, 59)), 'Dec 31');
    });
  });
}
