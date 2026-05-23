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

  group('protocolCompounds', () {
    test('empty when no injections', () {
      final result = protocolCompounds(
        userCompounds: const [],
        injections: const [],
        now: DateTime(2026, 5, 23),
      );
      expect(result, isEmpty);
    });

    test('returns compounds sorted by last-used desc', () {
      final cyp = _testCyp();
      final mast = _mastE();
      final now = DateTime(2026, 5, 23);
      final injections = [
        _inj(cyp, now.subtract(const Duration(days: 5)), 125),
        _inj(mast, now.subtract(const Duration(days: 2)), 100),
      ];
      final result = protocolCompounds(
        userCompounds: [cyp, mast],
        injections: injections,
        now: now,
      );
      expect(result.map((c) => c.base).toList(), ['Masteron', 'Testosterone']);
    });

    test('excludes compounds outside their relevance window', () {
      final cyp = _testCyp(); // 40d window
      final now = DateTime(2026, 5, 23);
      final injections = [_inj(cyp, now.subtract(const Duration(days: 60)), 125)];
      final result = protocolCompounds(
        userCompounds: [cyp],
        injections: injections,
        now: now,
      );
      expect(result, isEmpty);
    });

    test('uses BASE_LIBRARY when no matching user compound exists', () {
      // Built-in Testosterone Cypionate exists in BASE_LIBRARY; user added none.
      final builtinCyp = _testCyp(); // simulate by passing through injections.snapshot
      final now = DateTime(2026, 5, 23);
      final injections = [_inj(builtinCyp, now.subtract(const Duration(days: 3)), 125)];
      final result = protocolCompounds(
        userCompounds: const [],
        injections: injections,
        now: now,
      );
      expect(result, isNotEmpty);
      expect(result.first.base, 'Testosterone');
      expect(result.first.ester, 'Cypionate');
    });
  });

  group('cataloguedCompounds', () {
    test('includes all BASE_LIBRARY entries when no customs', () {
      final result = cataloguedCompounds(userCompounds: const []);
      // BASE_LIBRARY has many entries — just sanity check it returns them.
      expect(result.length, greaterThan(10));
      // ids should be the map keys, not 'temp'
      expect(result.any((c) => c.id == 'Testosterone Cypionate'), isTrue);
      expect(result.any((c) => c.id == 'temp'), isFalse);
    });

    test('customs shadow built-ins with same (base, ester)', () {
      final customCyp = const CompoundDefinition(
        id: 'my_test_c',
        base: 'Testosterone',
        ester: 'Cypionate',
        type: CompoundType.steroid,
        graphType: GraphType.curve,
        halfLife: 4.2, // overridden
        timeToPeak: 1.5,
        ratio: 0.69,
        unit: Unit.mg,
        colorValue: 0xFF000000,
        isCustom: true,
      );
      final result = cataloguedCompounds(userCompounds: [customCyp]);
      final cypResults = result.where((c) =>
          c.base == 'Testosterone' && c.ester == 'Cypionate').toList();
      expect(cypResults.length, 1);
      expect(cypResults.first.id, 'my_test_c');
      expect(cypResults.first.halfLife, 4.2);
    });

    test('sorts by type (steroid, oral, peptide, ancillary) then base asc', () {
      final result = cataloguedCompounds(userCompounds: const []);
      final types = result.map((c) => c.type).toList();
      // first compound should be a steroid; ancillaries last (if present).
      expect(types.first, CompoundType.steroid);
      // verify no later type appears before an earlier one
      var lastTypeIndex = -1;
      const order = [
        CompoundType.steroid,
        CompoundType.oral,
        CompoundType.peptide,
        CompoundType.ancillary,
      ];
      for (final t in types) {
        final idx = order.indexOf(t);
        expect(idx, greaterThanOrEqualTo(lastTypeIndex));
        lastTypeIndex = idx;
      }
    });
  });
}
