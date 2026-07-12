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

  group('activeInjectableLoad', () {
    const anavar = CompoundDefinition(
      id: 'anavar', base: 'Oxandrolone', ester: 'None',
      type: CompoundType.oral, graphType: GraphType.curve,
      halfLife: 0.4, timeToPeak: 0.06, ratio: 1.0,
      unit: Unit.mg, colorValue: 0xFFC9B062,
    );
    const hcg = CompoundDefinition(
      id: 'hcg', base: 'HCG', ester: 'None',
      type: CompoundType.peptide, graphType: GraphType.activeWindow,
      halfLife: 1.5, timeToPeak: 0.25, ratio: 1.0,
      unit: Unit.iu, colorValue: 0xFF8FC5A8,
    );

    test('groups doses by base and sums their active levels', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 19, 12);
      final entries = activeInjectableLoad(injections: [
        _inj(cyp, now.subtract(const Duration(days: 2)), 250),
        _inj(cyp, now.subtract(const Duration(days: 5)), 250),
      ], now: now);
      expect(entries, hasLength(1));
      expect(entries.first.base, 'Testosterone');
      expect(entries.first.type, CompoundType.steroid);
      final single = activeInjectableLoad(injections: [
        _inj(cyp, now.subtract(const Duration(days: 2)), 250),
      ], now: now);
      expect(entries.first.activeMg, greaterThan(single.first.activeMg));
    });

    test('separates bases and includes orals, excludes peptides', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 19, 12);
      final entries = activeInjectableLoad(injections: [
        _inj(cyp, now.subtract(const Duration(days: 2)), 250),
        _inj(anavar, now.subtract(const Duration(hours: 3)), 20),
        _inj(hcg, now.subtract(const Duration(hours: 3)), 500),
      ], now: now);
      expect(entries.map((e) => e.base).toSet(), {'Testosterone', 'Oxandrolone'});
    });

    test('ignores future injections', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 19, 12);
      final entries = activeInjectableLoad(injections: [
        _inj(cyp, now.add(const Duration(days: 1)), 250),
      ], now: now);
      expect(entries, isEmpty);
    });

    test('keeps a just-dosed base even while its level is still ~0', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 19, 12);
      final entries = activeInjectableLoad(injections: [
        _inj(cyp, now.subtract(const Duration(minutes: 1)), 0.1),
      ], now: now);
      expect(entries, hasLength(1));
    });

    test('drops a base whose only dose is fully decayed', () {
      final cyp = _testCyp(); // t½ 5d → relevance window 40d
      final now = DateTime(2026, 5, 19, 12);
      final entries = activeInjectableLoad(injections: [
        _inj(cyp, now.subtract(const Duration(days: 60)), 250),
      ], now: now);
      expect(entries, isEmpty);
    });
  });

  group('statRelevanceWindowDays', () {
    test('floors at 30 days for short half-lives and event compounds', () {
      expect(statRelevanceWindowDays(0.1), 30.0);
      expect(statRelevanceWindowDays(3.0), 30.0); // 3*8=24 < 30
    });

    test('uses halfLife*8 for long esters', () {
      expect(statRelevanceWindowDays(5.0), 40.0);
      expect(statRelevanceWindowDays(21.0), 168.0); // Test Undecanoate
    });
  });
}
