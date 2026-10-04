import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/engine/compute_engine.dart';
import 'package:protolog_tracker/models.dart';

/// Brute-force reference for the curve, marker and Σ math of
/// [computeGraphData]: every sample sums every dose of its base through
/// [injectionLevelAt], markers sum every same-base dose, Σ re-sums every
/// steroid dose. The optimized engine (E1: windowed sweep, memoized ka, Σ
/// built during the per-base pass) must reproduce it.
({
  Map<String, List<double>> curves,
  List<double> total,
  List<double> markers,
  double maxMg,
  double maxOralMg,
}) _reference(List<Injection> injections, ComputedGraphData g, int stepsPerDay) {
  final startMs = g.startDate.millisecondsSinceEpoch;
  final endMs = g.endDate.millisecondsSinceEpoch;
  final relevant = injections.where((i) {
    if (!isModelableInjection(i)) return false;
    final t = i.date.millisecondsSinceEpoch;
    if (t > endMs) return false;
    if (t >= startMs) return true;
    return (startMs - t) / 86400000.0 <= relevanceWindowDays(i.snapshot);
  }).toList();
  final curveInj = relevant
      .where((i) =>
          i.snapshot.type == CompoundType.steroid || i.snapshot.type == CompoundType.oral)
      .toList();
  final bases = curveInj.map((i) => i.snapshot.base).toSet();
  final step = 86400000 ~/ stepsPerDay;

  final curves = <String, List<double>>{for (final b in bases) b: []};
  final total = <double>[];
  var maxMg = 10.0;
  var maxOralMg = 5.0;
  for (var t = startMs; t <= endMs; t += step) {
    var sum = 0.0;
    for (final i in curveInj.where((i) => i.snapshot.type == CompoundType.steroid)) {
      sum += injectionLevelAt(i, (t - i.date.millisecondsSinceEpoch) / 86400000.0);
    }
    total.add(sum);
    for (final b in bases) {
      final ofBase = curveInj.where((i) => i.snapshot.base == b).toList();
      var level = 0.0;
      for (final i in ofBase) {
        level += injectionLevelAt(i, (t - i.date.millisecondsSinceEpoch) / 86400000.0);
      }
      curves[b]!.add(level);
      if (ofBase.first.snapshot.type == CompoundType.oral) {
        maxOralMg = math.max(maxOralMg, level);
      } else {
        maxMg = math.max(maxMg, level);
      }
    }
  }
  final markers = <double>[];
  for (final inj in curveInj) {
    final pct = (inj.date.millisecondsSinceEpoch - startMs) / g.totalDurationMs;
    if (pct < 0 || pct > 1) continue;
    var level = 0.0;
    for (final o in curveInj.where((o) => o.snapshot.base == inj.snapshot.base)) {
      level += injectionLevelAt(
          o, (inj.date.millisecondsSinceEpoch - o.date.millisecondsSinceEpoch) / 86400000.0);
    }
    markers.add(level);
  }
  return (curves: curves, total: total, markers: markers, maxMg: maxMg, maxOralMg: maxOralMg);
}

Injection _inj(CompoundDefinition c, DateTime d, double mg, [String tag = '']) => Injection(
    id: '${c.id}-${d.toIso8601String()}$tag', compoundId: c.id, date: d, dosage: mg, snapshot: c);

/// A messy log: several bases and esters, blends, same-timestamp doses, a
/// base logged both as an injectable and an oral, future doses, doses long
/// before every range, and doses whose window ends inside the range.
List<Injection> _log(DateTime now) {
  final out = <Injection>[];
  void every(String key, double stepDays, double mg, int count, {double offsetDays = 0}) {
    final c = BASE_LIBRARY[key]!;
    for (var i = 0; i < count; i++) {
      final d = now.subtract(
          Duration(minutes: ((offsetDays + i * stepDays) * 1440).round() + 17));
      out.add(_inj(c, d, mg));
    }
  }

  every('Testosterone Cypionate', 3.5, 125, 60);
  every('Testosterone Propionate', 2, 50, 20, offsetDays: 150);
  every('Sustanon 250', 7, 250, 10, offsetDays: 40);
  every('Tri-Tren', 5, 200, 12);
  every('Trenbolone Acetate', 2, 50, 40, offsetDays: 60);
  every('Drostanolone Propionate', 2, 100, 30);
  every('Oxandrolone', 1, 20, 90);
  every('Methandienone', 0.5, 10, 40, offsetDays: 20);
  every('HCG', 3, 500, 30);
  every('Testosterone Undecanoate', 30, 750, 6, offsetDays: 200); // before most ranges

  // A custom oral sharing the Testosterone base with the injectables.
  const oralTu = CompoundDefinition(
    id: 'oral-tu', base: 'Testosterone', ester: 'Undecanoate (oral)',
    type: CompoundType.oral, graphType: GraphType.curve,
    halfLife: 0.3, timeToPeak: 0.2, ratio: 0.63, unit: Unit.mg, colorValue: 0xFF10B981,
  );
  for (var i = 0; i < 20; i++) {
    out.add(_inj(oralTu, now.subtract(Duration(hours: 12 * i + 5)), 80));
  }
  // Same-timestamp doses and future (planned) doses.
  final cyp = BASE_LIBRARY['Testosterone Cypionate']!;
  final same = now.subtract(const Duration(days: 4, hours: 3));
  out.add(_inj(cyp, same, 100, 'a'));
  out.add(_inj(cyp, same, 100, 'b'));
  out.add(_inj(cyp, now.add(const Duration(days: 2)), 125));
  out.add(_inj(BASE_LIBRARY['Oxandrolone']!, now.add(const Duration(hours: 30)), 20));
  // Shuffle deterministically so nothing relies on input order.
  out.shuffle(math.Random(7));
  return out;
}

void main() {
  final now = DateTime(2026, 10, 3, 12, 34, 56);
  final log = _log(now);
  const steps = {'zoom': 12, 'standard': 4, 'cycle': 2, 'year': 2};

  for (final range in steps.keys) {
    for (final cumulative in [false, true]) {
      test('$range (Σ $cumulative): optimized graph == brute-force reference (E1)', () async {
        final settings = GraphSettings(
            normalized: false, cumulative: cumulative, showPeptides: true, timeRange: range);
        final g = await computeGraphData(IsolateInput(log, settings), now: now);
        final ref = _reference(log, g, steps[range]!);

        final byBase = {for (final c in g.curves) c.baseName: c};
        for (final e in ref.curves.entries) {
          final pts = byBase[e.key]!.points;
          expect(pts.length, e.value.length, reason: e.key);
          for (var i = 0; i < pts.length; i++) {
            expect(pts[i].dy, closeTo(e.value[i], 1e-9 * (1 + e.value[i])),
                reason: '${e.key} #$i');
          }
        }
        if (cumulative) {
          final total = byBase['Total Androgens']!.points;
          expect(total.length, ref.total.length);
          for (var i = 0; i < total.length; i++) {
            expect(total[i].dy, closeTo(ref.total[i], 1e-9 * (1 + ref.total[i])), reason: 'Σ #$i');
          }
          expect(g.curves.length, ref.curves.length + 1);
        } else {
          expect(g.curves.length, ref.curves.length);
        }
        final refMax = cumulative ? math.max(ref.maxMg, ref.total.reduce(math.max)) : ref.maxMg;
        expect(g.maxMg, closeTo(refMax * 1.1, 1e-9 * refMax));
        expect(g.maxOralMg, closeTo(ref.maxOralMg * 1.2, 1e-9 * ref.maxOralMg));

        expect(g.injectionMarkers.length, ref.markers.length);
        for (var i = 0; i < ref.markers.length; i++) {
          expect(g.injectionMarkers[i].yLevel,
              closeTo(ref.markers[i], 1e-9 * (1 + ref.markers[i])), reason: 'marker #$i');
        }
      });
    }
  }
}
