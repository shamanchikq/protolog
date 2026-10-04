import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/engine/compute_engine.dart';
import 'package:protolog_tracker/engine/dashboard_stats.dart';
import 'package:protolog_tracker/engine/library_stats.dart';
import 'package:protolog_tracker/models.dart';

final _susp = BASE_LIBRARY['Testosterone Suspension']!.copyWith(id: 'test-susp');

Injection _inj(CompoundDefinition c, DateTime when, double mg) => Injection(
      id: '${c.id}-${when.toIso8601String()}',
      compoundId: c.id,
      date: when,
      dosage: mg,
      snapshot: c,
    );

const _zoom = GraphSettings(
  normalized: false,
  cumulative: false,
  showPeptides: true,
  timeRange: 'zoom',
);

/// Whole-second "now" so chart-grid diffs (ms) and stats diffs (seconds)
/// describe exactly the same instants.
DateTime _nowToSecond() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, n.hour, n.minute, n.second);
}

DateTime _pointTime(ComputedGraphData g, double pct) =>
    DateTime.fromMillisecondsSinceEpoch(
        g.startDate.millisecondsSinceEpoch + (pct * g.totalDurationMs).round());

double _heroTotal(List<Injection> injections, DateTime at) =>
    activeInjectableLoad(injections: injections, now: at)
        .fold<double>(0.0, (s, e) => s + e.activeMg);

void main() {
  group('one relevance rule across surfaces (A5)', () {
    test('Suspension doses 30 h and 10 h ago: chart, LoadHero, current, lanes agree', () async {
      final now = _nowToSecond();
      final injections = [
        _inj(_susp, now.subtract(const Duration(hours: 30)), 100),
        _inj(_susp, now.subtract(const Duration(hours: 10)), 100),
      ];

      final g = await calculateGraphData(IsolateInput(injections, _zoom));
      final curve = g.curves.singleWhere((c) => c.baseName == 'Testosterone');

      var checked = 0;
      for (final p in curve.points) {
        final at = _pointTime(g, p.dx);
        if (at.isAfter(now)) continue;
        final current = currentActiveMg(
            type: CompoundType.steroid, injections: injections, now: at);
        final lane = sampleLaneIntensity(
            injections: injections, windowStart: at, windowEnd: at, sampleCount: 1)[0];
        expect(p.dy, closeTo(current, 1e-9), reason: 'chart vs currentActiveMg at $at');
        expect(_heroTotal(injections, at), closeTo(current, 1e-9), reason: 'LoadHero at $at');
        expect(lane, closeTo(current, 1e-9), reason: 'lane sampler at $at');
        checked++;
      }
      expect(checked, greaterThan(10));

      // ≈0 now: a 10 h-old Suspension dose is past 8 × 1.2 h.
      expect(currentActiveMg(type: CompoundType.steroid, injections: injections, now: now), 0.0);
      expect(_heroTotal(injections, now), 0.0);
      expect(curve.points.where((p) => !_pointTime(g, p.dx).isBefore(now)).every((p) => p.dy == 0), isTrue);
    });

    test('the in-window part of a fresh Suspension dose shows on every surface', () async {
      final now = _nowToSecond();
      final dose = now.subtract(const Duration(hours: 2));
      final injections = [_inj(_susp, dose, 100)];
      final at = dose.add(const Duration(minutes: 30)); // ≈ tmax

      final current = currentActiveMg(type: CompoundType.steroid, injections: injections, now: at);
      expect(current, greaterThan(50));
      expect(_heroTotal(injections, at), closeTo(current, 1e-9));
      expect(
        sampleLaneIntensity(injections: injections, windowStart: at, windowEnd: at, sampleCount: 1)[0],
        closeTo(current, 1e-9),
      );
      expect(isInProtocol(compound: _susp, injections: injections, now: at), isTrue);
    });

    test('protocol membership ends where the PK contribution ends', () {
      final now = _nowToSecond();
      final dose = now.subtract(const Duration(days: 3));
      final injections = [_inj(_susp, dose, 100)];
      final window = relevanceWindowDays(_susp);
      final inside = dose.add(Duration(milliseconds: (window * 86400000).round() - 60000));
      final outside = dose.add(Duration(milliseconds: (window * 86400000).round() + 60000));

      expect(isInProtocol(compound: _susp, injections: injections, now: inside), isTrue);
      expect(currentActiveMg(type: CompoundType.steroid, injections: injections, now: inside),
          greaterThan(0));
      expect(isInProtocol(compound: _susp, injections: injections, now: outside), isFalse);
      expect(currentActiveMg(type: CompoundType.steroid, injections: injections, now: outside), 0.0);
    });

    test('Tri-Tren stays relevant for its longest component (Enanthate)', () {
      final triTren = BASE_LIBRARY['Tri-Tren']!.copyWith(id: 'tri');
      final now = DateTime(2026, 6, 1, 12);
      // 60 d ago: past the snapshot's 7 d × 8 = 56 d, inside 10.5 d × 8 = 84 d.
      final injections = [_inj(triTren, now.subtract(const Duration(days: 60)), 300)];
      final current = currentActiveMg(type: CompoundType.steroid, injections: injections, now: now);
      expect(current, greaterThan(0));
      expect(_heroTotal(injections, now), closeTo(current, 1e-9));
      expect(isInProtocol(compound: triTren, injections: injections, now: now), isTrue);
    });
  });

  group('non-finite legacy data is skipped, never thrown on (A6)', () {
    final cyp = BASE_LIBRARY['Testosterone Cypionate']!.copyWith(id: 'test-c');
    final hcg = BASE_LIBRARY['HCG']!.copyWith(id: 'hcg');
    final anavar = BASE_LIBRARY['Oxandrolone']!.copyWith(id: 'anavar');
    final bad = <String, Injection Function(DateTime)>{
      'oral dosage NaN': (d) => _inj(anavar, d, double.nan),
      'dosage NaN': (d) => _inj(cyp, d, double.nan),
      'dosage ∞': (d) => _inj(cyp, d, double.infinity),
      'half-life ∞': (d) => _inj(cyp.copyWith(halfLife: double.infinity), d, 250),
      'half-life NaN': (d) => _inj(cyp.copyWith(halfLife: double.nan), d, 250),
      'half-life 0': (d) => _inj(cyp.copyWith(halfLife: 0), d, 250),
      'tmax NaN': (d) => _inj(cyp.copyWith(timeToPeak: double.nan), d, 250),
      'tmax ∞': (d) => _inj(cyp.copyWith(timeToPeak: double.infinity), d, 250),
      'yield NaN': (d) => _inj(cyp.copyWith(ratio: double.nan), d, 250),
      'yield ∞': (d) => _inj(cyp.copyWith(ratio: double.infinity), d, 250),
      'peptide half-life ∞': (d) => _inj(hcg.copyWith(halfLife: double.infinity), d, 500),
      'peptide dosage NaN': (d) => _inj(hcg, d, double.nan),
    };

    test('isModelableInjection flags each bad record', () {
      final now = DateTime(2026, 6, 1);
      for (final e in bad.entries) {
        expect(isModelableInjection(e.value(now)), isFalse, reason: e.key);
      }
      expect(isModelableInjection(_inj(cyp, now, 250)), isTrue);
      expect(isModelableInjection(_inj(BASE_LIBRARY['Sustanon 250']!, now, 250)), isTrue);
    });

    for (final range in ['zoom', 'standard', 'cycle', 'year']) {
      test('calculateGraphData ($range) ignores bad records next to a good one', () async {
        final now = DateTime.now();
        final good = _inj(cyp, now.subtract(const Duration(days: 3)), 250);
        final injections = [
          good,
          for (final make in bad.values) ...[
            make(now.subtract(const Duration(days: 2))),
            make(now.subtract(const Duration(days: 400))), // before every range
          ],
        ];
        final settings = GraphSettings(
            normalized: false, cumulative: true, showPeptides: true, timeRange: range);
        final g = await calculateGraphData(IsolateInput(injections, settings));
        final clean = await calculateGraphData(IsolateInput([good], settings));

        expect(g.maxMg.isFinite, isTrue);
        expect(g.maxOralMg.isFinite, isTrue);
        for (final c in g.curves) {
          expect(c.points.every((p) => p.dx.isFinite && p.dy.isFinite), isTrue, reason: c.baseName);
        }
        // Bad records draw nothing: same curves, markers and lanes as the good dose alone.
        expect(g.curves.length, clean.curves.length);
        expect(g.injectionMarkers.length, clean.injectionMarkers.length);
        expect(g.injectionMarkers.every((m) => m.yLevel.isFinite), isTrue);
        expect(g.peptideLanes, isEmpty);
        expect(g.maxMg, closeTo(clean.maxMg, 1e-9));
      });
    }

    test('dashboard stats ignore bad records next to a good one', () {
      final now = DateTime(2026, 6, 1, 12);
      final good = _inj(cyp, now.subtract(const Duration(days: 3)), 250);
      final injections = [good, for (final make in bad.values) make(now.subtract(const Duration(hours: 6)))];

      final load = activeInjectableLoad(injections: injections, now: now);
      final cleanLoad = activeInjectableLoad(injections: [good], now: now);
      expect(load, hasLength(1));
      expect(load.single.activeMg, closeTo(cleanLoad.single.activeMg, 1e-9));

      final current = currentActiveMg(type: CompoundType.steroid, injections: injections, now: now);
      expect(current, closeTo(currentActiveMg(type: CompoundType.steroid, injections: [good], now: now), 1e-9));

      final delta = deltaSteroidNowVsPrior7(injections: injections, now: now);
      expect(delta.isFinite, isTrue);

      final avg = averageActiveMgOverRange(
        type: CompoundType.steroid,
        injections: injections,
        windowStart: now.subtract(const Duration(days: 7)),
        windowEnd: now,
      );
      expect(avg.isFinite, isTrue);

      final lanes = sampleLaneIntensity(
        injections: injections,
        windowStart: now.subtract(const Duration(days: 7)),
        windowEnd: now.add(const Duration(days: 7)),
      );
      expect(lanes.every((v) => v.isFinite && v >= 0), isTrue);
    });
  });
}
