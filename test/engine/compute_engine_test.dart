import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/engine/compute_engine.dart';

void main() {
  group('calculateActiveLevel half-life guards', () {
    test('normal case returns a finite positive level', () {
      final v = calculateActiveLevel(150, 2.0, 4.5, 1.5, 0.72, 'Enanthate');
      expect(v.isFinite, isTrue);
      expect(v, greaterThan(0));
    });

    test('half-life 0 never produces NaN or Infinity', () {
      final v = calculateActiveLevel(150, 2.0, 0, 1.5, 0.72, 'Enanthate');
      expect(v.isFinite, isTrue);
      expect(v, greaterThanOrEqualTo(0));
    });

    test('negative half-life never produces NaN or Infinity', () {
      final v = calculateActiveLevel(150, 2.0, -3, 1.5, 0.72, 'Enanthate');
      expect(v.isFinite, isTrue);
      expect(v, greaterThanOrEqualTo(0));
    });
  });
}
