import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/utils.dart';

void main() {
  group('parseFlexibleDouble', () {
    test('parses dot decimals', () {
      expect(parseFlexibleDouble('3.5'), 3.5);
    });

    test('parses comma decimals (EU keyboards)', () {
      expect(parseFlexibleDouble('3,5'), 3.5);
    });

    test('parses plain integers and trims whitespace', () {
      expect(parseFlexibleDouble(' 250 '), 250.0);
    });

    test('returns null for garbage', () {
      expect(parseFlexibleDouble('abc'), isNull);
    });

    test('returns null for empty', () {
      expect(parseFlexibleDouble(''), isNull);
    });

    test('rejects non-finite values (would break jsonEncode on save)', () {
      expect(parseFlexibleDouble('Infinity'), isNull);
      expect(parseFlexibleDouble('-Infinity'), isNull);
      expect(parseFlexibleDouble('1e999'), isNull);
      expect(parseFlexibleDouble('-1e999'), isNull);
      expect(parseFlexibleDouble('NaN'), isNull);
    });

    test('still accepts padded comma decimals and exponents', () {
      expect(parseFlexibleDouble(' 3,5 '), 3.5);
      expect(parseFlexibleDouble('1e3'), 1000.0);
    });

    test('EU decimal commas keep working (B13)', () {
      expect(parseFlexibleDouble('3,5'), 3.5);
      expect(parseFlexibleDouble('0,250'), 0.25);
      expect(parseFlexibleDouble('12,5'), 12.5);
      expect(parseFlexibleDouble('-0,250'), -0.25);
      expect(parseFlexibleDouble('1,50'), 1.5);
      expect(parseFlexibleDouble('1,5000'), 1.5);
      expect(parseFlexibleDouble(',5'), 0.5);
    });

    test('a comma that reads as a thousands separator is rejected (B13)', () {
      // "5,000" IU HCG must not be logged as 5 IU.
      expect(parseFlexibleDouble('5,000'), isNull);
      expect(parseFlexibleDouble('1,500'), isNull);
      expect(parseFlexibleDouble('12,345'), isNull);
      expect(parseFlexibleDouble('100,250'), isNull);
      expect(parseFlexibleDouble('1,000,000'), isNull);
      expect(parseFlexibleDouble('1,5,0'), isNull);
    });

    test('mixed separators are rejected (B13)', () {
      expect(parseFlexibleDouble('1.000,5'), isNull);
      expect(parseFlexibleDouble('1,000.5'), isNull);
    });

    test('a dot is always the decimal point', () {
      // Prefills and Dart's own toString use '.', so "1.500" means 1.5.
      expect(parseFlexibleDouble('1.500'), 1.5);
      expect(parseFlexibleDouble('0.125'), 0.125);
    });
  });

  group('formatDate', () {
    final d = DateTime(2026, 6, 2, 15, 7); // a Tuesday

    test('the patterns the app uses', () {
      expect(formatDate(d, 'yyyy-MM-dd'), '2026-06-02');
      expect(formatDate(d, 'MMM d'), 'Jun 2');
      expect(formatDate(d, 'EEE ha'), 'Tue 3PM');
      expect(formatDate(DateTime(2026, 6, 1, 0, 30), 'EEE ha'), 'Mon 12AM');
      expect(formatDate(DateTime(2026, 6, 1, 12), 'EEE ha'), 'Mon 12PM');
    });

    test('an unknown pattern falls back to toString (no dd/MM mislabel)', () {
      expect(formatDate(d, 'MM/dd HH:mm'), d.toString());
    });
  });
}
