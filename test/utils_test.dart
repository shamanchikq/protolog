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
  });
}
