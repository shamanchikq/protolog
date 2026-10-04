import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/engine/calendar.dart';
import 'package:protolog_tracker/engine/compute_engine.dart';
import 'package:protolog_tracker/models.dart';

/// Time (days) of the curve's maximum, sampled finely over [0, horizon].
double _peakTime(double Function(double t) level, double horizon, {int steps = 4000}) {
  var bestT = 0.0;
  var best = -1.0;
  for (int i = 0; i <= steps; i++) {
    final t = horizon * i / steps;
    final v = level(t);
    if (v > best) {
      best = v;
      bestT = t;
    }
  }
  return bestT;
}

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

    test('non-finite half-lives contribute nothing (finite, zero)', () {
      for (final hl in [double.nan, double.infinity, double.negativeInfinity, 0.0, -3.0]) {
        for (final t in [0.0, 0.01, 0.5, 2.0, 30.0]) {
          final v = calculateActiveLevel(150, t, hl, 1.5, 0.72, 'Enanthate');
          expect(v.isFinite, isTrue, reason: 'hl=$hl t=$t');
          expect(v, 0.0, reason: 'hl=$hl t=$t');
        }
      }
    });

    test('non-finite dose / tmax / ratio / time never leak NaN or Infinity', () {
      final cases = <List<double>>[
        [double.nan, 2.0, 4.5, 1.5, 0.72],
        [double.infinity, 2.0, 4.5, 1.5, 0.72],
        [150, double.nan, 4.5, 1.5, 0.72],
        [150, double.infinity, 4.5, 1.5, 0.72],
        [150, 2.0, 4.5, double.nan, 0.72],
        [150, 2.0, 4.5, double.infinity, 0.72],
        [150, 2.0, 4.5, 1.5, double.nan],
        [150, 2.0, 4.5, 1.5, double.infinity],
      ];
      for (final c in cases) {
        final v = calculateActiveLevel(c[0], c[1], c[2], c[3], c[4], 'Enanthate');
        expect(v.isFinite, isTrue, reason: '$c');
        expect(v, greaterThanOrEqualTo(0), reason: '$c');
      }
    });

    test('extremely small valid half-lives stay finite', () {
      for (final hl in [1e-3, 1e-6, 1e-12, 1e-300]) {
        for (final t in [0.0, 1e-6, 0.001, 0.02, 1.0]) {
          final v = calculateActiveLevel(100, t, hl, 0.02, 1.0, 'Suspension');
          expect(v.isFinite, isTrue, reason: 'hl=$hl t=$t');
          expect(v, greaterThanOrEqualTo(0), reason: 'hl=$hl t=$t');
        }
      }
    });
  });

  group('Testosterone Suspension (t½ 0.05 d boundary, A5)', () {
    final susp = BASE_LIBRARY['Testosterone Suspension']!;
    double level(double t) => calculateActiveLevel(
        100, t, susp.halfLife, susp.timeToPeak, susp.ratio, susp.ester);

    test('library entry is the 0.05 d boundary case', () {
      expect(susp.halfLife, 0.05);
      expect(susp.timeToPeak, 0.02);
    });

    test('modelled with its own half-life: ≈0 one day after the dose', () {
      expect(level(1.0), lessThan(0.01));
      expect(level(2.0), lessThan(1e-6));
    });

    test('peaks near its time-to-peak with a sensible height', () {
      final tPeak = _peakTime(level, 0.2);
      expect(tPeak, closeTo(0.02, 0.003));
      final peak = level(tPeak);
      expect(peak, greaterThan(50));
      expect(peak, lessThan(100));
    });

    test('half-life just above and below the old 0.05 floor is honoured', () {
      // The old guard replaced any t½ ≤ 0.05 with 1.0, so 0.04 decayed far
      // slower than 0.06. Now the shorter half-life decays faster.
      final a = calculateActiveLevel(100, 0.3, 0.04, 0.02, 1.0, 'Suspension');
      final b = calculateActiveLevel(100, 0.3, 0.06, 0.02, 1.0, 'Suspension');
      expect(a, lessThan(b));
      expect(a, lessThan(1.0));
    });
  });

  group('_solveKa bracket for large elimination rates', () {
    test('ka above the old fixed 100/d bracket still reproduces tmax', () {
      // t½ 0.06 d, tmax 0.015 d needs ka ≈ 200/d; the old bracket capped ka
      // at 100/d, which moved the peak out to ≈0.024 d.
      double level(double t) => calculateActiveLevel(100, t, 0.06, 0.015, 1.0, 'X');
      final tPeak = _peakTime(level, 0.1);
      expect(tPeak, closeTo(0.015, 0.001));
      expect(level(tPeak), greaterThan(50));
    });

    test('ke above 100/d (t½ 0.005 d) gives a finite, fast-clearing curve', () {
      double level(double t) => calculateActiveLevel(100, t, 0.005, 0.02, 1.0, 'X');
      for (final t in [0.0, 0.001, 0.005, 0.02, 0.1]) {
        expect(level(t).isFinite, isTrue, reason: 't=$t');
        expect(level(t), greaterThanOrEqualTo(0), reason: 't=$t');
      }
      expect(level(0.005), greaterThan(0));
      expect(level(0.5), lessThan(1e-6));
    });

    test('tmax ≤ 0.01 still absorbs faster than a short half-life eliminates', () {
      // Instant-absorption shortcut must not hand back ka < ke, which would
      // turn the curve absorption-limited (flip-flop) and stretch its tail.
      double level(double t) => calculateActiveLevel(100, t, 0.001, 0.005, 1.0, 'X');
      expect(level(0.05), lessThan(1e-6));
      expect(level(0.0005).isFinite, isTrue);
    });
  });

  group('effectiveHalfLife / relevanceWindowDays', () {
    test('single esters use their own half-life × 8', () {
      expect(relevanceWindowDays(BASE_LIBRARY['Testosterone Suspension']!), closeTo(0.4, 1e-12));
      expect(relevanceWindowDays(BASE_LIBRARY['Testosterone Cypionate']!), 40.0);
      expect(relevanceWindowDays(BASE_LIBRARY['Oxandrolone']!), closeTo(3.2, 1e-12));
    });

    test('blends cover their longest component, not the snapshot t½', () {
      final sust = BASE_LIBRARY['Sustanon 250']!;
      final triTren = BASE_LIBRARY['Tri-Tren']!;
      final longestSust = SUSTANON_BLEND.map((c) => c['halfLife']!).reduce((a, b) => a > b ? a : b);
      final longestTren = TREN_BLEND.map((c) => c['halfLife']!).reduce((a, b) => a > b ? a : b);
      expect(effectiveHalfLife(sust), longestSust);
      expect(effectiveHalfLife(triTren), longestTren);
      expect(relevanceWindowDays(triTren), longestTren * 8); // 84 d, not 7×8
      // Blend math ignores the snapshot t½, so a corrupt one doesn't matter.
      expect(relevanceWindowDays(triTren.copyWith(halfLife: double.nan)), longestTren * 8);
    });

    test('invalid half-lives have no relevance window', () {
      final cyp = BASE_LIBRARY['Testosterone Cypionate']!;
      for (final hl in [0.0, -1.0, double.nan, double.infinity, double.negativeInfinity]) {
        expect(effectiveHalfLife(cyp.copyWith(halfLife: hl)), 0.0, reason: 'hl=$hl');
        expect(relevanceWindowDays(cyp.copyWith(halfLife: hl)), 0.0, reason: 'hl=$hl');
      }
    });
  });

  group('library ids (B7)', () {
    test('every BASE_LIBRARY entry carries its map key as id', () {
      for (final e in BASE_LIBRARY.entries) {
        expect(e.value.id, e.key);
      }
    });

    test('lookupLibraryDef returns the entry under its real key', () {
      final te = lookupLibraryDef('Testosterone', 'Enanthate')!;
      expect(te.id, 'Testosterone Enanthate');
      final sust = lookupLibraryDef('Testosterone', 'Sustanon (Mix)')!;
      expect(sust.id, 'Sustanon 250');
      final mast = lookupLibraryDef('Masteron', 'Propionate')!;
      expect(mast.id, 'Drostanolone Propionate');
      final mt2 = lookupLibraryDef('Melanotan II', 'None')!;
      expect(mt2.id, 'MT2');
    });

    test('base-name fallback also resolves to the real key', () {
      final anavar = lookupLibraryDef('Oxandrolone', 'Weird')!;
      expect(anavar.id, 'Oxandrolone');
      expect(lookupLibraryDef('Nonexistium', 'None'), isNull);
    });
  });

  group('graph range is whole calendar days (B27)', () {
    // Holds in every zone; catches the DST bug under TZ=Europe/Kyiv
    // (spring forward Mar 29 2026, fall back Oct 25 2026).
    const ranges = {
      'zoom': (back: 7, fwd: 7),
      'standard': (back: 28, fwd: 35),
      'cycle': (back: 90, fwd: 30),
      'year': (back: 365, fwd: 30),
    };
    final nows = [
      DateTime(2026, 4, 2, 15), // just after spring forward
      DateTime(2026, 10, 27, 9), // just after fall back
      DateTime(2026, 3, 30, 0, 30),
      DateTime(2026, 10, 3, 12),
    ];

    for (final r in ranges.entries) {
      test('${r.key}: starts at local midnight, ends 23:59, exact day counts', () async {
        for (final now in nows) {
          final g = await computeGraphData(
            IsolateInput(const [], GraphSettings(
                normalized: false, cumulative: false, showPeptides: true, timeRange: r.key)),
            now: now,
          );
          expect([g.startDate.hour, g.startDate.minute], [0, 0], reason: '$now ${g.startDate}');
          expect(calendarDaysBetween(g.startDate, now), r.value.back, reason: '$now');
          expect([g.endDate.hour, g.endDate.minute], [23, 59], reason: '$now ${g.endDate}');
          expect(calendarDaysBetween(now, g.endDate), r.value.fwd, reason: '$now');
          expect(g.totalDurationMs, g.endDate.difference(g.startDate).inMilliseconds);
        }
      });
    }

    test('standard range on Apr 2 2026 starts Mar 5 00:00, not Mar 4 23:00', () async {
      final g = await computeGraphData(
        IsolateInput(const [], const GraphSettings(
            normalized: false, cumulative: false, showPeptides: true, timeRange: 'standard')),
        now: DateTime(2026, 4, 2, 15),
      );
      expect(g.startDate, DateTime(2026, 3, 5));
      expect(g.endDate, DateTime(2026, 5, 7, 23, 59));
    });
  });
}
