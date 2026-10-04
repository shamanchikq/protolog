import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import '../data.dart';

double _solveKa(double ke, double tmax) {
  // The ka that reproduces tmax can sit far above a fixed 100/d when the
  // half-life is short (Suspension: ke ≈ 13.9/d → ka ≈ 123/d; t½ < 0.007 d
  // puts ke itself above 100), so the upper bracket scales with ke. The
  // "instant absorption" shortcut uses the same floor so ka never drops
  // below ke (which would turn the curve absorption-limited).
  final double high0 = math.max(100.0, 50.0 * ke);
  if (tmax <= 0.01) return high0;
  double low = ke + 0.001;
  double high = high0;
  double mid = 0.0;
  for (int i = 0; i < 20; i++) {
    mid = (low + high) / 2;
    double calculatedTmax = (math.log(mid) - math.log(ke)) / (mid - ke);
    if (calculatedTmax > tmax) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return mid;
}

double _calculateBatemanValue(double dose, double t, double halfLife, double tmax, double ratio) {
  if (!(t >= 0) || t.isInfinite) return 0.0; // also rejects NaN
  // Only genuinely unusable input is rejected: a non-finite or non-positive
  // half-life has no elimination rate, so the dose contributes nothing rather
  // than an invented curve. Short but valid half-lives (Testosterone
  // Suspension, t½ 0.05 d) are modelled as given.
  if (!isUsableHalfLife(halfLife)) return 0.0;
  // Legacy non-finite dose / tmax / yield: no contribution (a NaN tmax would
  // otherwise bisect to a meaningless but finite ka).
  if (!dose.isFinite || !tmax.isFinite || !ratio.isFinite) return 0.0;
  double effectiveDose = dose * ratio;
  double ke = math.log(2) / halfLife;
  double ka = _solveKa(ke, tmax);
  double term1 = (effectiveDose * ka) / (ka - ke);
  double term2 = math.exp(-ke * t) - math.exp(-ka * t);
  final value = term1 * term2;
  // ka ≈ ke or absurd magnitudes can still overflow; math.max keeps NaN.
  if (!value.isFinite) return 0.0;
  return math.max(0.0, value);
}

double calculateActiveLevel(double dosage, double diffDays, double halfLife, double timeToPeak, double ratio, String esterName) {
  final blend = blendComponentsFor(esterName);
  if (blend != null) {
    double level = 0;
    for (var comp in blend) {
      level += _calculateBatemanValue(
        dosage * comp['fraction']!,
        diffDays,
        comp['halfLife']!,
        comp['timeToPeak']!,
        comp['ratio']!,
      );
    }
    return level;
  }
  return _calculateBatemanValue(dosage, diffDays, halfLife, timeToPeak, ratio);
}

/// Blend components for a blend ester ("Sustanon (Mix)", "Tri-Tren (Mix)"),
/// or null for a single ester. Same match as [calculateActiveLevel].
List<Map<String, double>>? blendComponentsFor(String esterName) {
  if (esterName.contains('Sustanon')) return SUSTANON_BLEND;
  if (esterName.contains('Tri-Tren')) return TREN_BLEND;
  return null;
}

/// True when [halfLife] can drive the Bateman model: finite and > 0.
bool isUsableHalfLife(double halfLife) => halfLife.isFinite && halfLife > 0;

/// Half-lives after which a dose counts as fully decayed (≈0.4 % left).
const double relevanceHalfLives = 8.0;

/// The half-life (days) that actually governs how long a dose of [c] stays
/// active. Blends are modelled from their components (the snapshot t½ is
/// ignored by [calculateActiveLevel]), so they use the longest component.
/// 0 when the half-life is unusable — such doses contribute nothing.
double effectiveHalfLife(CompoundDefinition c) {
  final blend = blendComponentsFor(c.ester);
  if (blend != null) {
    return blend.map((comp) => comp['halfLife']!).reduce(math.max);
  }
  return isUsableHalfLife(c.halfLife) ? c.halfLife : 0.0;
}

/// Days after a dose of [c] during which it still contributes:
/// [effectiveHalfLife] × [relevanceHalfLives]. The single relevance rule for
/// the chart, LoadHero, trend delta, lanes and protocol membership.
double relevanceWindowDays(CompoundDefinition c) =>
    effectiveHalfLife(c) * relevanceHalfLives;

/// False for a logged dose whose numbers can't be modelled — non-finite
/// dosage / time-to-peak / yield, or an unusable half-life (legacy or
/// corrupt data from before input validation). Such doses are skipped by the
/// chart and dashboard stats instead of crashing or drawing flat lines.
bool isModelableInjection(Injection inj) =>
    inj.dosage.isFinite &&
    inj.snapshot.timeToPeak.isFinite &&
    inj.snapshot.ratio.isFinite &&
    effectiveHalfLife(inj.snapshot) > 0;

/// Active level of one logged dose [diffDays] after it was taken, under the
/// single relevance rule: 0 before the dose and once past
/// [relevanceWindowDays]. Every surface (chart, LoadHero, trend, lanes)
/// samples through this so they agree on when a dose stops counting.
double injectionLevelAt(Injection inj, double diffDays) {
  if (!(diffDays >= 0)) return 0.0;
  if (!isModelableInjection(inj)) return 0.0;
  if (diffDays > relevanceWindowDays(inj.snapshot)) return 0.0;
  return calculateActiveLevel(
    inj.dosage,
    diffDays,
    inj.snapshot.halfLife,
    inj.snapshot.timeToPeak,
    inj.snapshot.ratio,
    inj.snapshot.ester,
  );
}

CompoundDefinition? lookupLibraryDef(String base, String ester) {
  for (var entry in BASE_LIBRARY.values) {
    if (entry.base == base && entry.ester == ester) return entry;
  }
  return BASE_LIBRARY[base]; // fallback for orals/peptides/ancillaries keyed by base name
}

// --- HEAVY COMPUTATION ---
Future<ComputedGraphData> calculateGraphData(IsolateInput input) async {
  final injections = input.injections;
  final settings = input.settings;

  int daysBack = 28;
  int daysFwd = 35;
  if (settings.timeRange == 'zoom') { daysBack = 7; daysFwd = 7; }
  if (settings.timeRange == 'cycle') { daysBack = 90; daysFwd = 30; }
  if (settings.timeRange == 'year') { daysBack = 365; daysFwd = 30; }

  final now = DateTime.now();
  final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysBack));
  final endDate = DateTime(now.year, now.month, now.day).add(Duration(days: daysFwd)).add(const Duration(hours: 23, minutes: 59));
  final totalDurationMs = endDate.difference(startDate).inMilliseconds;
  final startMs = startDate.millisecondsSinceEpoch;

  // Non-modelable legacy records (non-finite numbers) are skipped entirely:
  // no flat curve, marker or lane, and nothing that can throw in the isolate.
  final relevantInjections = injections.where((i) {
    if (!isModelableInjection(i)) return false;
    final injTime = i.date.millisecondsSinceEpoch;
    if (injTime > endDate.millisecondsSinceEpoch) return false;
    if (injTime >= startMs) return true;
    return (startMs - injTime) / 86400000.0 <= relevanceWindowDays(i.snapshot);
  }).toList();

  final curveInjections = relevantInjections.where((i) => i.snapshot.type == CompoundType.steroid || i.snapshot.type == CompoundType.oral).toList();
  final peptideInjections = relevantInjections.where((i) => i.snapshot.type == CompoundType.peptide || i.snapshot.type == CompoundType.ancillary).toList();

  final uniquePeptideBases = peptideInjections.map((i) => i.snapshot.base).toSet().toList()..sort();
  final laneMap = {for (var e in uniquePeptideBases) e: uniquePeptideBases.indexOf(e)};
  final List<PeptideLaneData> lanes = [];

  for (var inj in peptideInjections) {
    // Read PK from the injection's frozen snapshot — same as steroid/oral
    // curves. This keeps past lanes stable when a compound's library entry is
    // edited; retroactive changes are applied explicitly via rewriteSnapshots.
    final graphType = inj.snapshot.graphType;
    final halfLife = effectiveHalfLife(inj.snapshot);

    final msSinceStart = inj.date.millisecondsSinceEpoch - startMs;
    final startPct = msSinceStart / totalDurationMs;
    final fadeDurationMs = (halfLife * 4) * 86400000;
    final durationPct = fadeDurationMs / totalDurationMs;

    if (startPct + durationPct > 0 && startPct < 1.0) {
      lanes.add(PeptideLaneData(
          inj.snapshot.base,
          inj.snapshot.colorValue,
          laneMap[inj.snapshot.base] ?? 0,
          startPct,
          durationPct,
          graphType
      ));
    }
  }

  final uniqueCurveBases = curveInjections.map((i) => i.snapshot.base).toSet();
  double maxMg = 10.0;
  double maxOralMg = 5.0;
  final List<CurveData> curves = [];

  final stepsPerDay = settings.timeRange == 'zoom' ? 12 : (settings.timeRange == 'standard' ? 4 : 2);
  final stepSizeMs = 86400000 ~/ stepsPerDay;

  final Map<String, List<Injection>> injectionsByBase = {};
  for(var base in uniqueCurveBases) {
    injectionsByBase[base] = curveInjections.where((i) => i.snapshot.base == base).toList();
  }

  final Map<String, List<Offset>> tempPoints = {for (var base in uniqueCurveBases) base: []};

  for (int currentTime = startMs; currentTime <= endDate.millisecondsSinceEpoch; currentTime += stepSizeMs) {
    final timePct = (currentTime - startMs) / totalDurationMs;

    for (var base in uniqueCurveBases) {
      double level = 0.0;
      final baseInjections = injectionsByBase[base] ?? [];

      for (var inj in baseInjections) {
        final diffMs = currentTime - inj.date.millisecondsSinceEpoch;
        level += injectionLevelAt(inj, diffMs / 86400000.0);
      }
      tempPoints[base]!.add(Offset(timePct, level));

      final isOral = baseInjections.isNotEmpty && baseInjections.first.snapshot.type == CompoundType.oral;
      if (isOral) {
        maxOralMg = math.max(maxOralMg, level);
      } else {
        maxMg = math.max(maxMg, level);
      }
    }
  }

  final injectionMarkers = <InjectionMarkerData>[];
  for (var inj in curveInjections) {
    final ms = inj.date.millisecondsSinceEpoch - startMs;
    final pct = ms / totalDurationMs;
    if (pct >= 0 && pct <= 1.0) {
      final baseInjs = injectionsByBase[inj.snapshot.base] ?? [];
      double level = 0;
      for (var other in baseInjs) {
        final diffMs = inj.date.millisecondsSinceEpoch - other.date.millisecondsSinceEpoch;
        level += injectionLevelAt(other, diffMs / 86400000.0);
      }
      injectionMarkers.add(InjectionMarkerData(pct, level, inj.snapshot.type == CompoundType.oral, inj.snapshot.colorValue, inj.snapshot.base));
    }
  }

  if (settings.cumulative) {
    final List<Offset> totalPoints = [];
    double dailyMaxTotal = 0;
    for (int currentTime = startMs; currentTime <= endDate.millisecondsSinceEpoch; currentTime += stepSizeMs) {
      double totalLevel = 0.0;
      final timePct = (currentTime - startMs) / totalDurationMs;
      for(var inj in curveInjections.where((i) => i.snapshot.type == CompoundType.steroid)) {
        final diffMs = currentTime - inj.date.millisecondsSinceEpoch;
        totalLevel += injectionLevelAt(inj, diffMs / 86400000.0);
      }
      totalPoints.add(Offset(timePct, totalLevel));
      dailyMaxTotal = math.max(dailyMaxTotal, totalLevel);
    }
    curves.add(CurveData('Total Androgens', 0xFFFFFFFF, false, totalPoints));
    maxMg = math.max(maxMg, dailyMaxTotal);
  }

  for (var base in uniqueCurveBases) {
    final baseInjections = injectionsByBase[base];
    if (baseInjections == null || baseInjections.isEmpty) continue;
    final sample = baseInjections.first.snapshot;
    curves.add(CurveData(base, sample.colorValue, sample.type == CompoundType.oral, tempPoints[base]!));
  }

  return ComputedGraphData(
    curves: curves,
    peptideLanes: lanes,
    laneLabels: uniquePeptideBases,
    maxMg: maxMg * 1.1,
    maxOralMg: maxOralMg * 1.2,
    startDate: startDate,
    endDate: endDate,
    totalDurationMs: totalDurationMs,
    laneCount: uniquePeptideBases.length,
    injectionMarkers: injectionMarkers,
  );
}
