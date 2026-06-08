import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/dashboard_stats.dart';

CompoundDefinition _testCyp() => const CompoundDefinition(
  id: 'test_cyp',
  base: 'Testosterone',
  ester: 'Cypionate',
  type: CompoundType.steroid,
  graphType: GraphType.curve,
  halfLife: 5.0,
  timeToPeak: 1.8,
  ratio: 0.69,
  unit: Unit.mg,
  colorValue: 0xFFA8C9E8,
);

Injection _inj(CompoundDefinition c, DateTime when, double mg) => Injection(
  id: when.toIso8601String(),
  compoundId: c.id,
  date: when,
  dosage: mg,
  snapshot: c,
);

void main() {
  group('averageActiveMgOverRange', () {
    test('returns 0 when no injections fall in window', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 19, 12);
      final injections = <Injection>[];
      final avg = averageActiveMgOverRange(
        type: CompoundType.steroid,
        injections: injections,
        windowStart: now.subtract(const Duration(days: 7)),
        windowEnd: now,
      );
      expect(avg, 0.0);
      expect(cyp.base, 'Testosterone');
    });

    test('produces a positive average after a recent injection', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 19, 12);
      final injections = [_inj(cyp, now.subtract(const Duration(days: 3)), 250)];
      final avg = averageActiveMgOverRange(
        type: CompoundType.steroid,
        injections: injections,
        windowStart: now.subtract(const Duration(days: 7)),
        windowEnd: now,
      );
      expect(avg, greaterThan(0));
    });
  });

  group('currentActiveMg', () {
    test('zero with no recent dosing', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 19, 12);
      expect(
        currentActiveMg(type: CompoundType.steroid, injections: const [], now: now),
        0.0,
      );
      expect(cyp.base, 'Testosterone');
    });

    test('positive within decay window', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 19, 12);
      final injections = [_inj(cyp, now.subtract(const Duration(days: 2)), 250)];
      final v = currentActiveMg(
        type: CompoundType.steroid, injections: injections, now: now,
      );
      expect(v, greaterThan(0));
    });
  });

  group('deltaSteroidNowVsPrior7', () {
    test('positive when current saturation exceeds prior-week avg', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 19, 12);
      final injections = [
        _inj(cyp, now.subtract(const Duration(days: 2)), 250),
        _inj(cyp, now.subtract(const Duration(days: 5)), 250),
      ];
      final delta = deltaSteroidNowVsPrior7(injections: injections, now: now);
      expect(delta, greaterThan(0));
    });

    test('small magnitude when injections at steady-state', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 19, 12);
      // 60 days of every-3-day dosing — well past steady-state for a t½ 5d compound.
      final injections = [
        for (int d = 60; d >= 0; d -= 3)
          _inj(cyp, now.subtract(Duration(days: d)), 250),
      ];
      final delta = deltaSteroidNowVsPrior7(injections: injections, now: now);
      expect(delta.abs(), lessThan(60.0));
    });
  });

  test('sampleLaneIntensity returns numeric array of correct length', () {
    final cyp = _testCyp();
    final now = DateTime(2026, 5, 19, 12);
    final injections = [
      _inj(cyp, now.subtract(const Duration(days: 7)), 250),
      _inj(cyp, now, 250),
    ];
    final samples = sampleLaneIntensity(
      injections: injections,
      windowStart: now.subtract(const Duration(days: 21)),
      windowEnd: now.add(const Duration(days: 7)),
      sampleCount: 80,
    );
    expect(samples.length, 81);
    expect(samples.any((v) => v > 0), isTrue);
  });
}
