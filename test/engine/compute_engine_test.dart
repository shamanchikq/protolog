import 'dart:math' as math;

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

/// The Bateman closed form C(t) = D·r·ka/(ka−ke)·(e^(−ke·t) − e^(−ka·t)).
double _bateman(double dose, double ratio, double ka, double ke, double t) =>
    dose * ratio * ka / (ka - ke) * (math.exp(-ke * t) - math.exp(-ka * t));

/// The time to peak the closed form has for (ka, ke): ln(ka/ke)/(ka−ke).
double _tmaxFor(double ka, double ke) => math.log(ka / ke) / (ka - ke);

/// ∫ level dt over [0, horizon] by the trapezoid rule.
double _area(double Function(double t) level, double horizon, {int steps = 40000}) {
  final dt = horizon / steps;
  var sum = (level(0) + level(horizon)) / 2;
  for (var i = 1; i < steps; i++) {
    sum += level(i * dt);
  }
  return sum * dt;
}

void _expectRel(double actual, double expected, double rel, {String? reason}) =>
    expect(actual, closeTo(expected, expected.abs() * rel), reason: reason);

void main() {
  group('Bateman closed form (known values)', () {
    test('reproduces C(t) for a known ka (ke = 1/d, ka = 2/d)', () {
      // t½ = ln 2 → ke = 1; ka = 2 gives tmax = ln 2. The engine has to
      // recover ka from tmax (_solveKa) to match the closed form.
      const ke = 1.0, ka = 2.0;
      final tmax = _tmaxFor(ka, ke);
      expect(tmax, closeTo(math.ln2, 1e-15));
      for (final t in [0.05, 0.25, tmax, 1.0, 2.0, 5.0, 10.0]) {
        final v = calculateActiveLevel(100, t, math.ln2 / ke, tmax, 1.0, 'X');
        _expectRel(v, _bateman(100, 1.0, ka, ke, t), 1e-3, reason: 't=$t');
      }
      // 200·(e⁻¹ − e⁻²) at t = 1 d.
      _expectRel(calculateActiveLevel(100, 1.0, math.ln2, tmax, 1.0, 'X'), 46.5088, 1e-4);
    });

    test('reproduces C(t) for a slow ester (ke = 0.1/d, ka = 1/d)', () {
      const ke = 0.1, ka = 1.0;
      final tmax = _tmaxFor(ka, ke); // ≈ 2.558 d
      for (final t in [0.5, tmax, 7.0, 21.0, 60.0]) {
        final v = calculateActiveLevel(250, t, math.ln2 / ke, tmax, 0.7, 'X');
        _expectRel(v, _bateman(250, 0.7, ka, ke, t), 1e-3, reason: 't=$t');
      }
    });

    test('peak height is D·r·2^(−tmax/t½) — Testosterone Enanthate 250 mg', () {
      // At tmax, ka·e^(−ka·tmax) = ke·e^(−ke·tmax), so C(tmax) = D·r·e^(−ke·tmax).
      final te = BASE_LIBRARY['Testosterone Enanthate']!;
      double level(double t) =>
          calculateActiveLevel(250, t, te.halfLife, te.timeToPeak, te.ratio, te.ester);
      final expectedPeak = 250 * te.ratio * math.pow(2, -te.timeToPeak / te.halfLife);
      expect(expectedPeak, closeTo(142.87, 0.01)); // 180 · 2^(−1/3)
      _expectRel(level(te.timeToPeak), expectedPeak, 1e-4);
      final tPeak = _peakTime(level, 6.0);
      expect(tPeak, closeTo(te.timeToPeak, 0.01));
      _expectRel(level(tPeak), expectedPeak, 1e-4);
    });

    test('the terminal phase halves every half-life', () {
      final te = BASE_LIBRARY['Testosterone Enanthate']!;
      double level(double t) =>
          calculateActiveLevel(250, t, te.halfLife, te.timeToPeak, te.ratio, te.ester);
      for (final t in [30.0, 40.0, 60.0]) {
        expect(level(t + te.halfLife) / level(t), closeTo(0.5, 1e-6), reason: 't=$t');
      }
    });

    test('total exposure (AUC) is D·r·t½/ln 2, whatever ka is', () {
      final te = BASE_LIBRARY['Testosterone Enanthate']!;
      final auc = _area(
        (t) => calculateActiveLevel(250, t, te.halfLife, te.timeToPeak, te.ratio, te.ester),
        40 * te.halfLife,
      );
      _expectRel(auc, 250 * te.ratio * te.halfLife / math.ln2, 1e-3); // ≈ 1168.6 mg·d
    });

    test('linear in dose and in yield; zero at and before the dose', () {
      double level(double dose, double ratio, double t) =>
          calculateActiveLevel(dose, t, 4.5, 1.5, ratio, 'Enanthate');
      for (final t in [0.5, 1.5, 7.0]) {
        expect(level(500, 0.72, t), closeTo(2 * level(250, 0.72, t), 1e-9));
        expect(level(250, 0.36, t), closeTo(level(250, 0.72, t) / 2, 1e-9));
      }
      expect(level(250, 0.72, 0), 0.0);
      expect(level(250, 0.72, -1), 0.0);
    });
  });

  group('_solveKa reachability (via calculateActiveLevel)', () {
    // Every curve the app can draw must peak at its own time-to-peak with
    // the Bateman peak height; a tmax the ka bisection can't reach would
    // be silently clamped and move the peak.
    void expectPeaksAtTmax(String name, double halfLife, double tmax, double ratio) {
      double level(double t) => calculateActiveLevel(100, t, halfLife, tmax, ratio, 'X');
      final tPeak = _peakTime(level, tmax * 4);
      expect(tPeak, closeTo(tmax, tmax * 0.01), reason: '$name: t½ $halfLife, tmax $tmax');
      _expectRel(level(tPeak), 100 * ratio * math.pow(2, -tmax / halfLife), 1e-3, reason: name);
    }

    test('every single-ester library entry', () {
      var checked = 0;
      for (final e in BASE_LIBRARY.entries) {
        final c = e.value;
        if (blendComponentsFor(c.ester) != null) continue;
        expectPeaksAtTmax(e.key, c.halfLife, c.timeToPeak, c.ratio);
        checked++;
      }
      expect(checked, greaterThan(20));
    });

    test('every blend component', () {
      for (final (name, blend) in [('Sustanon', SUSTANON_BLEND), ('Tri-Tren', TREN_BLEND)]) {
        for (final c in blend) {
          expectPeaksAtTmax('$name t½ ${c['halfLife']}', c['halfLife']!, c['timeToPeak']!, c['ratio']!);
        }
      }
    });
  });

  group('blends', () {
    for (final (name, blend, ester) in [
      ('Sustanon', SUSTANON_BLEND, 'Sustanon (Mix)'),
      ('Tri-Tren', TREN_BLEND, 'Tri-Tren (Mix)'),
    ]) {
      test('$name: component fractions sum to 1, each component sane', () {
        final total = blend.fold<double>(0, (s, c) => s + c['fraction']!);
        expect(total, closeTo(1.0, 1e-12));
        for (final c in blend) {
          expect(c['fraction'], inExclusiveRange(0, 1));
          expect(c['halfLife'], greaterThan(0));
          expect(c['timeToPeak'], greaterThan(0));
          expect(c['ratio'], inInclusiveRange(0.5, 1.0));
        }
        expect(blendComponentsFor(ester), same(blend));
      });

      test('$name: a dose is the sum of its components (snapshot PK ignored)', () {
        for (final t in [0.25, 1.0, 3.0, 10.0, 30.0]) {
          final parts = blend.fold<double>(
            0,
            (s, c) => s +
                calculateActiveLevel(250 * c['fraction']!, t, c['halfLife']!, c['timeToPeak']!, c['ratio']!, 'X'),
          );
          expect(calculateActiveLevel(250, t, 7.0, 1.5, 0.7, ester), closeTo(parts, 1e-9), reason: 't=$t');
          // The snapshot's own t½ / tmax / yield play no part.
          expect(calculateActiveLevel(250, t, double.nan, double.nan, double.nan, ester),
              closeTo(parts, 1e-9), reason: 't=$t');
        }
      });

      test('$name: total exposure is Σ D·fraction·ratio·t½/ln 2', () {
        final longest = blend.map((c) => c['halfLife']!).reduce(math.max);
        final auc = _area((t) => calculateActiveLevel(250, t, 0, 0, 0, ester), 40 * longest, steps: 80000);
        final expected = blend.fold<double>(
            0, (s, c) => s + 250 * c['fraction']! * c['ratio']! * c['halfLife']! / math.ln2);
        _expectRel(auc, expected, 2e-3);
      });
    }
  });

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

  group('chart contents', () {
    final now = DateTime(2026, 10, 3, 12);
    const settings = GraphSettings(normalized: false, cumulative: true, timeRange: 'standard');
    Injection dose(String key, double mg, {int daysAgo = 2}) => Injection(
          id: '$key-$daysAgo',
          compoundId: key,
          date: now.subtract(Duration(days: daysAgo)),
          dosage: mg,
          snapshot: BASE_LIBRARY[key]!,
        );

    test('peptides and ancillaries are not charted (the swimlanes own them)', () async {
      final g = await computeGraphData(
        IsolateInput([dose('BPC-157', 0.25), dose('Anastrozole', 0.5)], settings),
        now: now,
      );
      expect(g.curves.where((c) => !c.isTotal), isEmpty);
      expect(g.injectionMarkers, isEmpty);
      expect(g.hasDoseCurves, isFalse);
      expect(g.hasOralCurve, isFalse);
    });

    test('hasDoseCurves / hasOralCurve reflect the curves, not the axis floors (B36)', () async {
      final steroidOnly = await computeGraphData(
        IsolateInput([dose('Testosterone Cypionate', 250)], settings),
        now: now,
      );
      expect(steroidOnly.hasDoseCurves, isTrue);
      expect(steroidOnly.hasOralCurve, isFalse);
      expect(steroidOnly.maxOralMg, greaterThan(0)); // floored all the same
      expect(steroidOnly.curves.where((c) => c.isTotal), hasLength(1));

      final withOral = await computeGraphData(
        IsolateInput([dose('Testosterone Cypionate', 250), dose('Oxandrolone', 20, daysAgo: 0)], settings),
        now: now,
      );
      expect(withOral.hasOralCurve, isTrue);
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
                normalized: false, cumulative: false, timeRange: r.key)),
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

    test('the result carries the settings it was computed with (B40)', () async {
      for (final r in ranges.keys) {
        for (final (normalized, cumulative) in [(false, false), (true, false), (false, true), (true, true)]) {
          final settings = GraphSettings(
              normalized: normalized, cumulative: cumulative, timeRange: r);
          final g = await computeGraphData(IsolateInput(const [], settings), now: nows.first);
          expect(g.settings, settings);
        }
      }
    });

    test('standard range on Apr 2 2026 starts Mar 5 00:00, not Mar 4 23:00', () async {
      final g = await computeGraphData(
        IsolateInput(const [], const GraphSettings(
            normalized: false, cumulative: false, timeRange: 'standard')),
        now: DateTime(2026, 4, 2, 15),
      );
      expect(g.startDate, DateTime(2026, 3, 5));
      expect(g.endDate, DateTime(2026, 5, 7, 23, 59));
    });
  });
}
