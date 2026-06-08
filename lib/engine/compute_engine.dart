import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import '../data.dart';

double _solveKa(double ke, double tmax) {
  if (tmax <= 0.01) return 100.0;
  double low = ke + 0.001;
  double high = 100.0;
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
  if (t < 0) return 0.0;
  double effectiveDose = dose * ratio;
  double ke = math.log(2) / halfLife;
  double ka = _solveKa(ke, tmax);
  double term1 = (effectiveDose * ka) / (ka - ke);
  double term2 = math.exp(-ke * t) - math.exp(-ka * t);
  return math.max(0.0, term1 * term2);
}

double calculateActiveLevel(double dosage, double diffDays, double halfLife, double timeToPeak, double ratio, String esterName) {
  if (esterName.contains('Sustanon')) {
    double level = 0;
    for (var comp in SUSTANON_BLEND) {
      level += _calculateBatemanValue(
        dosage * comp['fraction']!,
        diffDays,
        comp['halfLife']!,
        comp['timeToPeak']!,
        comp['ratio']!,
      );
    }
    return level;
  } else if (esterName.contains('Tri-Tren')) {
    double level = 0;
    for (var comp in TREN_BLEND) {
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

  final relevantInjections = injections.where((i) {
    final injTime = i.date.millisecondsSinceEpoch;
    final windowMs = (i.snapshot.halfLife * 8 * 86400000).toInt();
    return injTime <= endDate.millisecondsSinceEpoch && (injTime >= startMs || (startMs - injTime) < windowMs);
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
    final halfLife = inj.snapshot.halfLife;

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
        if (diffMs >= 0) {
          final diffDays = diffMs / 86400000.0;
          level += calculateActiveLevel(
              inj.dosage, diffDays, inj.snapshot.halfLife, inj.snapshot.timeToPeak, inj.snapshot.ratio, inj.snapshot.ester
          );
        }
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
        if (diffMs >= 0) {
          level += calculateActiveLevel(other.dosage, diffMs / 86400000.0,
              other.snapshot.halfLife, other.snapshot.timeToPeak, other.snapshot.ratio, other.snapshot.ester);
        }
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
        if (diffMs >= 0) {
          totalLevel += calculateActiveLevel(inj.dosage, diffMs/86400000.0, inj.snapshot.halfLife, inj.snapshot.timeToPeak, inj.snapshot.ratio, inj.snapshot.ester);
        }
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
