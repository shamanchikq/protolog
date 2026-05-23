import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/library_stats.dart';

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

CompoundDefinition _mastE() => const CompoundDefinition(
  id: 'mast_e',
  base: 'Masteron',
  ester: 'Enanthate',
  type: CompoundType.steroid,
  graphType: GraphType.curve,
  halfLife: 5.0,
  timeToPeak: 1.5,
  ratio: 0.70,
  unit: Unit.mg,
  colorValue: 0xFFE0B870,
);

Injection _inj(CompoundDefinition c, DateTime when, double mg) => Injection(
  id: when.toIso8601String(),
  compoundId: c.id,
  date: when,
  dosage: mg,
  snapshot: c,
);

void main() {
  group('lastInjectionFor', () {
    test('returns null when no injection matches', () {
      final result = lastInjectionFor(
        base: 'Testosterone',
        ester: 'Cypionate',
        injections: const [],
      );
      expect(result, isNull);
    });

    test('returns the most recent matching injection date', () {
      final cyp = _testCyp();
      final inj1 = _inj(cyp, DateTime(2026, 5, 10), 125);
      final inj2 = _inj(cyp, DateTime(2026, 5, 20), 125);
      final inj3 = _inj(cyp, DateTime(2026, 5, 15), 125);
      final result = lastInjectionFor(
        base: 'Testosterone',
        ester: 'Cypionate',
        injections: [inj1, inj2, inj3],
      );
      expect(result, DateTime(2026, 5, 20));
    });

    test('ignores injections of a different (base, ester)', () {
      final cyp = _testCyp();
      final mast = _mastE();
      final injCyp = _inj(cyp, DateTime(2026, 5, 10), 125);
      final injMast = _inj(mast, DateTime(2026, 5, 20), 100);
      final result = lastInjectionFor(
        base: 'Testosterone',
        ester: 'Cypionate',
        injections: [injCyp, injMast],
      );
      expect(result, DateTime(2026, 5, 10));
    });
  });

  group('formatUsedAgo', () {
    final now = DateTime(2026, 5, 23, 12, 0);

    test('returns em-dash for null', () {
      expect(formatUsedAgo(null, now: now), '—');
    });

    test('returns hours when less than 24h ago', () {
      expect(formatUsedAgo(now.subtract(const Duration(hours: 4)), now: now), '4h ago');
    });

    test('returns "1d ago" at exactly 24h', () {
      expect(formatUsedAgo(now.subtract(const Duration(hours: 24)), now: now), '1d ago');
    });

    test('returns days for older timestamps', () {
      expect(formatUsedAgo(now.subtract(const Duration(days: 12)), now: now), '12d ago');
    });

    test('floors partial hours and partial days', () {
      expect(formatUsedAgo(now.subtract(const Duration(hours: 3, minutes: 45)), now: now), '3h ago');
      expect(formatUsedAgo(now.subtract(const Duration(days: 2, hours: 5)), now: now), '2d ago');
    });
  });

  group('isInProtocol', () {
    test('false when no injection ever', () {
      final cyp = _testCyp();
      expect(
        isInProtocol(compound: cyp, injections: const [], now: DateTime(2026, 5, 23)),
        isFalse,
      );
    });

    test('true when last injection within halfLife * 8 days', () {
      final cyp = _testCyp(); // halfLife 5d → window 40d
      final now = DateTime(2026, 5, 23);
      final injections = [_inj(cyp, now.subtract(const Duration(days: 20)), 125)];
      expect(isInProtocol(compound: cyp, injections: injections, now: now), isTrue);
    });

    test('false when last injection outside halfLife * 8 days', () {
      final cyp = _testCyp(); // halfLife 5d → window 40d
      final now = DateTime(2026, 5, 23);
      final injections = [_inj(cyp, now.subtract(const Duration(days: 50)), 125)];
      expect(isInProtocol(compound: cyp, injections: injections, now: now), isFalse);
    });

    test('falls back to 7-day window when halfLife is 0', () {
      final event = const CompoundDefinition(
        id: 'bpc',
        base: 'BPC-157',
        ester: 'None',
        type: CompoundType.peptide,
        graphType: GraphType.event,
        halfLife: 0,
        timeToPeak: 0,
        ratio: 1.0,
        unit: Unit.mcg,
        colorValue: 0xFF8FC5A8,
      );
      final now = DateTime(2026, 5, 23);
      final within = [_inj(event, now.subtract(const Duration(days: 3)), 250)];
      final outside = [_inj(event, now.subtract(const Duration(days: 10)), 250)];
      expect(isInProtocol(compound: event, injections: within, now: now), isTrue);
      expect(isInProtocol(compound: event, injections: outside, now: now), isFalse);
    });
  });
}
