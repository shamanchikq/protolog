import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/library_stats.dart';
import 'package:protolog_tracker/data.dart';

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

    test('planned (future-dated) doses are not "last used"', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 23, 12);
      final injections = [
        _inj(cyp, now.subtract(const Duration(days: 5)), 125),
        _inj(cyp, now.add(const Duration(days: 2)), 125),
      ];
      expect(
        lastInjectionFor(base: 'Testosterone', ester: 'Cypionate', injections: injections, now: now),
        now.subtract(const Duration(days: 5)),
      );
      expect(
        lastInjectionFor(
            base: 'Testosterone', ester: 'Cypionate', injections: [injections[1]], now: now),
        isNull,
      );
    });

    test('defaults to the real clock for "now"', () {
      final cyp = _testCyp();
      final real = DateTime.now();
      final past = real.subtract(const Duration(days: 1));
      final result = lastInjectionFor(
        base: 'Testosterone',
        ester: 'Cypionate',
        injections: [_inj(cyp, past, 125), _inj(cyp, real.add(const Duration(days: 30)), 125)],
      );
      expect(result, past);
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

    test('future dates read "in …", never negative', () {
      expect(formatUsedAgo(now.add(const Duration(hours: 30)), now: now), 'in 1d');
      expect(formatUsedAgo(now.add(const Duration(days: 2, hours: 5)), now: now), 'in 2d');
      expect(formatUsedAgo(now.add(const Duration(hours: 5)), now: now), 'in 5h');
      expect(formatUsedAgo(now.add(const Duration(minutes: 10)), now: now), 'in 1h');
    });

    // Hold in every zone; only discriminate under a DST zone such as
    // TZ=Europe/Kyiv (spring forward Mar 29 2026, fall back Oct 25 2026),
    // where elapsed `.inDays` was off by one.
    group('counts days on the wall clock across DST', () {
      test('across spring forward (a 23 h day)', () {
        // 08:00 → 08:00 three dates later: 71 h elapsed in Kyiv.
        expect(formatUsedAgo(DateTime(2026, 3, 28, 8), now: DateTime(2026, 3, 31, 8)), '3d ago');
        expect(formatUsedAgo(DateTime(2026, 3, 31, 8), now: DateTime(2026, 3, 28, 8)), 'in 3d');
      });

      test('across fall back (a 25 h day)', () {
        // 08:00 → 07:30 three dates later: 72.5 h elapsed in Kyiv, but the
        // clock hasn't reached 08:00 on the third day yet.
        expect(formatUsedAgo(DateTime(2026, 10, 24, 8), now: DateTime(2026, 10, 27, 7, 30)), '2d ago');
        expect(formatUsedAgo(DateTime(2026, 10, 27, 7, 30), now: DateTime(2026, 10, 24, 8)), 'in 2d');
      });

      test('24 h+ elapsed on a 25 h day is never "0d ago"', () {
        final when = DateTime(2026, 10, 24, 8);
        final n = DateTime(2026, 10, 25, 7, 30); // 24.5 h later in Kyiv, 23.5 h in UTC
        final expected = n.difference(when).inHours >= 24 ? '1d ago' : '23h ago';
        expect(formatUsedAgo(when, now: n), expected);
      });
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

    test('a planned (future) dose still counts as on protocol', () {
      final cyp = _testCyp();
      final now = DateTime(2026, 5, 23);
      final planned = [_inj(cyp, now.add(const Duration(days: 2)), 125)];
      expect(isInProtocol(compound: cyp, injections: planned, now: now), isTrue);
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

    test('ranks by last real use, not by planned doses', () {
      final cyp = _testCyp();
      final mast = _mastE();
      final now = DateTime(2026, 5, 23);
      final injections = [
        _inj(cyp, now.subtract(const Duration(days: 5)), 125),
        _inj(cyp, now.add(const Duration(days: 1)), 125), // planned
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

  group('recentInjectionsFor', () {
    test('returns empty when no matches', () {
      final result = recentInjectionsFor(
        base: 'Testosterone',
        ester: 'Cypionate',
        injections: const [],
      );
      expect(result, isEmpty);
    });

    test('returns most recent first, honors limit', () {
      final cyp = _testCyp();
      final injections = [
        _inj(cyp, DateTime(2026, 5, 10), 125),
        _inj(cyp, DateTime(2026, 5, 20), 125),
        _inj(cyp, DateTime(2026, 5, 15), 125),
        _inj(cyp, DateTime(2026, 5, 5), 125),
      ];
      final result = recentInjectionsFor(
        base: 'Testosterone',
        ester: 'Cypionate',
        injections: injections,
        limit: 2,
      );
      expect(result.length, 2);
      expect(result[0].date, DateTime(2026, 5, 20));
      expect(result[1].date, DateTime(2026, 5, 15));
    });

    test('excludes other (base, ester) injections', () {
      final cyp = _testCyp();
      final mast = _mastE();
      final injections = [
        _inj(cyp, DateTime(2026, 5, 10), 125),
        _inj(mast, DateTime(2026, 5, 20), 100),
      ];
      final result = recentInjectionsFor(
        base: 'Testosterone',
        ester: 'Cypionate',
        injections: injections,
      );
      expect(result.length, 1);
      expect(result.first.snapshot.base, 'Testosterone');
    });
  });

  group('injectionCountFor', () {
    test('returns 0 when no matches', () {
      expect(
        injectionCountFor(base: 'X', ester: 'Y', injections: const []),
        0,
      );
    });

    test('counts only matching (base, ester)', () {
      final cyp = _testCyp();
      final mast = _mastE();
      final injections = [
        _inj(cyp, DateTime(2026, 5, 10), 125),
        _inj(cyp, DateTime(2026, 5, 15), 125),
        _inj(mast, DateTime(2026, 5, 20), 100),
      ];
      expect(
        injectionCountFor(
            base: 'Testosterone', ester: 'Cypionate', injections: injections),
        2,
      );
    });
  });

  group('displayName', () {
    test('returns BASE_LIBRARY map key when id matches', () {
      final sust = BASE_LIBRARY['Sustanon 250']!.copyWith(id: 'Sustanon 250');
      expect(displayName(sust), 'Sustanon 250');
    });

    test('returns base alone when ester is None', () {
      const c = CompoundDefinition(
        id: 'x', base: 'BPC-157', ester: 'None',
        type: CompoundType.peptide, graphType: GraphType.event,
        halfLife: 0, timeToPeak: 0, ratio: 1.0, unit: Unit.mcg,
        colorValue: 0xFF000000,
      );
      expect(displayName(c), 'BPC-157');
    });

    test('joins base + ester otherwise', () {
      expect(displayName(_testCyp()), 'Testosterone Cypionate');
    });

    test('built-ins adopted under a timestamp id keep their library name (B8)', () {
      // The wizard adopts a built-in into userCompounds with a timestamp id on
      // first log; the label must not change from the catalogue's.
      for (final key in [
        'Sustanon 250',
        'Tri-Tren',
        'Drostanolone Propionate',
        'Methenolone Enanthate',
        'Dihydroboldenone Cypionate',
        'MT2',
      ]) {
        final adopted = BASE_LIBRARY[key]!.copyWith(id: '1727000000000');
        expect(displayName(adopted), key, reason: key);
        expect(displayName(BASE_LIBRARY[key]!), key, reason: key);
      }
    });

    test('a true custom keeps its own base + ester label', () {
      final custom = BASE_LIBRARY['Drostanolone Propionate']!
          .copyWith(id: 'c1', isCustom: true);
      expect(displayName(custom), 'Masteron Propionate');
    });
  });

  group('metaLineFor', () {
    test('steroid curve compound uses t½', () {
      expect(metaLineFor(_testCyp()), 'Steroid · t½ 5.0d');
    });

    test('blend compound shows ester count', () {
      final sust = BASE_LIBRARY['Sustanon 250']!.copyWith(id: 'Sustanon 250');
      expect(metaLineFor(sust), 'Steroid · 4-ester');
      final tri = BASE_LIBRARY['Tri-Tren']!.copyWith(id: 'Tri-Tren');
      expect(metaLineFor(tri), 'Steroid · 3-ester');
    });

    test('blend meta survives adoption under a timestamp id (B8)', () {
      final sust = BASE_LIBRARY['Sustanon 250']!.copyWith(id: '1727000000000');
      expect(metaLineFor(sust), 'Steroid · 4-ester');
      final tri = BASE_LIBRARY['Tri-Tren']!.copyWith(id: '1727000000001');
      expect(metaLineFor(tri), 'Steroid · 3-ester');
    });

    test('peptide event compound shows "event"', () {
      const c = CompoundDefinition(
        id: 'x', base: 'BPC-157', ester: 'None',
        type: CompoundType.peptide, graphType: GraphType.event,
        halfLife: 0, timeToPeak: 0, ratio: 1.0, unit: Unit.mcg,
        colorValue: 0xFF000000,
      );
      expect(metaLineFor(c), 'Peptide · event');
    });

    test('peptide window compound shows "window"', () {
      const c = CompoundDefinition(
        id: 'x', base: 'Semaglutide', ester: 'None',
        type: CompoundType.peptide, graphType: GraphType.activeWindow,
        halfLife: 7, timeToPeak: 2, ratio: 1.0, unit: Unit.mg,
        colorValue: 0xFF000000,
      );
      expect(metaLineFor(c), 'Peptide · window');
    });
  });

  group('defaultDefFor', () {
    test('returns the BASE_LIBRARY default matched by base+ester', () {
      final c = _testCyp(); // Testosterone Cypionate
      final def = defaultDefFor(c);
      expect(def, isNotNull);
      expect(def!.halfLife, 5.0); // BASE_LIBRARY Testosterone Cypionate
      expect(def.timeToPeak, 1.8);
      expect(def.id, 'Testosterone Cypionate'); // id resolved to the map key
    });

    test('returns null when no library counterpart exists', () {
      const c = CompoundDefinition(
        id: 'x', base: 'MyOwnPeptide', ester: 'None',
        type: CompoundType.peptide, graphType: GraphType.event,
        halfLife: 1, timeToPeak: 0.1, ratio: 1.0, unit: Unit.mcg,
        colorValue: 0xFF000000, isCustom: true,
      );
      expect(defaultDefFor(c), isNull);
    });
  });

  group('colorCandidatesForBase', () {
    test('unedited built-in: userSet null, any is the live default color', () {
      final r = colorCandidatesForBase('Testosterone', userCompounds: const []);
      expect(r.userSet, isNull);
      expect(r.any, isNotNull); // some Testosterone built-in color
    });

    test('user-edited built-in color wins as userSet', () {
      // Shadow the built-in Testosterone Cypionate with a recolored override.
      final recolored =
          defaultDefFor(_testCyp())!.copyWith(colorValue: 0xFF123456);
      final r = colorCandidatesForBase('Testosterone',
          userCompounds: [recolored]);
      expect(r.userSet, 0xFF123456);
    });

    test('custom compound color is reported as userSet', () {
      const custom = CompoundDefinition(
        id: 'mine', base: 'MyPeptide', ester: 'None',
        type: CompoundType.peptide, graphType: GraphType.event,
        halfLife: 0, timeToPeak: 0, ratio: 1.0, unit: Unit.mcg,
        colorValue: 0xFFABCDEF, isCustom: true,
      );
      final r = colorCandidatesForBase('MyPeptide', userCompounds: const [custom]);
      expect(r.userSet, 0xFFABCDEF);
      expect(r.any, 0xFFABCDEF);
    });

    test('does not read injection snapshots (resolves from live catalogue)', () {
      // Even with a logged injection carrying an OLD snapshot color, the
      // candidate color comes from the current catalogue override.
      final recolored =
          defaultDefFor(_testCyp())!.copyWith(colorValue: 0xFF00FF00);
      final r = colorCandidatesForBase('Testosterone',
          userCompounds: [recolored]);
      expect(r.userSet, 0xFF00FF00);
    });

    test('unknown base returns nulls', () {
      final r = colorCandidatesForBase('Nonexistent', userCompounds: const []);
      expect(r.userSet, isNull);
      expect(r.any, isNull);
    });

    test('matches base case-insensitively', () {
      final r = colorCandidatesForBase('testosterone', userCompounds: const []);
      expect(r.any, isNotNull);
    });
  });

  group('isEditedFromDefault', () {
    test('false when values equal the BASE_LIBRARY default', () {
      // A seed-style row that matches the default exactly.
      final def = defaultDefFor(_testCyp())!;
      final seed = def.copyWith(id: 'test-c');
      expect(isEditedFromDefault(seed), isFalse);
    });

    test('true when a PK param differs from default', () {
      final def = defaultDefFor(_testCyp())!;
      final edited = def.copyWith(id: 'test-c', halfLife: 9.9);
      expect(isEditedFromDefault(edited), isTrue);
    });

    test('true when lane color differs from default', () {
      final def = defaultDefFor(_testCyp())!;
      final recolored = def.copyWith(id: 'test-c', colorValue: 0xFF123456);
      expect(isEditedFromDefault(recolored), isTrue);
    });

    test('false for custom compounds (no default to compare)', () {
      final custom = _testCyp().copyWith(isCustom: true, halfLife: 99);
      expect(isEditedFromDefault(custom), isFalse);
    });
  });

  group('compoundKey (B6)', () {
    test('joins base and ester exactly', () {
      expect(compoundKey('Testosterone', 'Enanthate'), 'Testosterone|Enanthate');
      expect(compoundKey('HCG', 'None'), 'HCG|None');
      expect(compoundKey('Testosterone', 'Enanthate'),
          isNot(compoundKey('Testosterone', 'Cypionate')));
    });

    test('keyOf reads a compound', () {
      expect(keyOf(_testCyp()), 'Testosterone|Cypionate');
    });
  });

  group('dedupeUserCompounds (B6)', () {
    final te = BASE_LIBRARY['Testosterone Enanthate']!;
    final adoptedHere = te.copyWith(id: '1700000000001'); // wizard, new phone
    final fromBackup =
        te.copyWith(id: '1600000000000', colorValue: 0xFF112233, concentration: 250);
    final anavar = BASE_LIBRARY['Oxandrolone']!.copyWith(id: 'anavar');

    test('no duplicates: same entries, empty remap, injections untouched', () {
      final inj = _inj(adoptedHere, DateTime(2026, 5, 1), 250);
      final r = dedupeUserCompounds([adoptedHere, anavar], injections: [inj]);
      expect(r.compounds, [adoptedHere, anavar]);
      expect(r.idRemap, isEmpty);
      expect(identical(r.injections.single, inj), isTrue);
    });

    test('keeps one entry per base+ester — the later one — at the first slot', () {
      final r = dedupeUserCompounds([adoptedHere, anavar, fromBackup]);
      expect(r.compounds.map((c) => c.id), ['1600000000000', 'anavar']);
      expect(r.compounds.first.colorValue, 0xFF112233);
      expect(r.idRemap, {'1700000000001': '1600000000000'});
    });

    test('order of the input decides, not which one has more logs', () {
      final r = dedupeUserCompounds([fromBackup, adoptedHere]);
      expect(r.compounds.single.id, '1700000000001');
    });

    test('remaps Injection.compoundId of dropped duplicates, snapshot untouched', () {
      final mine = _inj(adoptedHere, DateTime(2026, 5, 1), 250);
      final theirs = _inj(fromBackup, DateTime(2026, 4, 1), 250);
      final other = _inj(anavar, DateTime(2026, 5, 2), 20);
      final r = dedupeUserCompounds([adoptedHere, anavar, fromBackup],
          injections: [mine, theirs, other]);
      expect(r.injections.map((i) => i.compoundId),
          ['1600000000000', '1600000000000', 'anavar']);
      final relinked = r.injections.first;
      expect(relinked.id, mine.id);
      expect(relinked.date, mine.date);
      expect(relinked.dosage, mine.dosage);
      expect(identical(relinked.snapshot, mine.snapshot), isTrue);
      expect(identical(r.injections[1], theirs), isTrue);
      expect(identical(r.injections[2], other), isTrue);
    });

    test('a vial strength only the dropped duplicate knew is carried over', () {
      final withConc = adoptedHere.copyWith(concentration: 200);
      final noConc = te.copyWith(id: 'later');
      final r = dedupeUserCompounds([withConc, noConc]);
      expect(r.compounds.single.id, 'later');
      expect(r.compounds.single.concentration, 200);
      // The winner's own strength is never overwritten.
      final r2 = dedupeUserCompounds([withConc, fromBackup]);
      expect(r2.compounds.single.concentration, 250);
    });

    test('exact duplicates (same id) collapse without a remap', () {
      final r = dedupeUserCompounds([adoptedHere, adoptedHere]);
      expect(r.compounds, hasLength(1));
      expect(r.idRemap, isEmpty);
    });

    test('a dropped id still used by another compound is relinked per key only', () {
      // Legacy 'temp' ids (B7) could be shared by different compounds.
      final tempTe = te.copyWith(id: 'temp');
      final tempAnavar = anavar.copyWith(id: 'temp');
      final keptTe = te.copyWith(id: 'te');
      final teLog = _inj(tempTe, DateTime(2026, 5, 1), 250);
      final anavarLog = _inj(tempAnavar, DateTime(2026, 5, 1), 20);
      final r = dedupeUserCompounds([tempTe, tempAnavar, keptTe],
          injections: [teLog, anavarLog]);
      expect(r.compounds.map((c) => c.id), ['te', 'temp']);
      expect(r.idRemap, isEmpty); // 'temp' is ambiguous: still Oxandrolone's id
      expect(r.injections[0].compoundId, 'te');
      expect(identical(r.injections[1], anavarLog), isTrue);
    });
  });

  group('duplicates in catalogue / protocol follow the dedupe winner (B6)', () {
    final te = BASE_LIBRARY['Testosterone Enanthate']!;
    final first = te.copyWith(id: 'first', colorValue: 0xFF000001);
    final second = te.copyWith(id: 'second', colorValue: 0xFF000002);

    test('cataloguedCompounds lists one row: the later duplicate', () {
      final rows = cataloguedCompounds(userCompounds: [first, second])
          .where((c) => keyOf(c) == keyOf(te))
          .toList();
      expect(rows.map((c) => c.id), ['second']);
    });

    test('protocolCompounds lists one row: the later duplicate', () {
      final now = DateTime(2026, 5, 23);
      final rows = protocolCompounds(
        userCompounds: [first, second],
        injections: [_inj(first, now.subtract(const Duration(days: 2)), 250)],
        now: now,
      );
      expect(rows.map((c) => c.id), ['second']);
    });

    test('cataloguedCompounds order does not depend on input order', () {
      CompoundDefinition custom(String id, String ester) => CompoundDefinition(
            id: id, base: 'Zeta', ester: ester,
            type: CompoundType.steroid, graphType: GraphType.curve,
            halfLife: 5, timeToPeak: 1, ratio: 1, unit: Unit.mg,
            colorValue: 0xFF000000, isCustom: true,
          );
      final a = custom('a', 'Alpha');
      final b = custom('b', 'Beta');
      final c = custom('c', 'Gamma');
      List<String> ids(List<CompoundDefinition> u) =>
          cataloguedCompounds(userCompounds: u).map((x) => x.id).toList();
      expect(ids([c, a, b]), ids([a, b, c]));
      expect(ids([b, c, a]), ids([a, b, c]));
    });
  });
}
