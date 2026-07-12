import 'dart:math' as math;

import '../models.dart';
import 'compute_engine.dart';

/// Days a compound's dashboard stat card stays visible after its latest dose.
/// Floor of 30 days preserves "Nd ago" cards for short-lived/event compounds;
/// halfLife × 8 keeps long esters (e.g. Test Undecanoate, t½ 21d) visible
/// while still pharmacologically active.
double statRelevanceWindowDays(double halfLife) =>
    math.max(30.0, halfLife * 8);

/// One row of the LoadHero breakdown: an injectable base and its summed
/// active level at a point in time.
class ActiveLoadEntry {
  final String base;
  final CompoundType type;
  final double activeMg;
  const ActiveLoadEntry({
    required this.base,
    required this.type,
    required this.activeMg,
  });
}

/// Per-base active injectable load (steroid + oral only) at [now].
/// A base is included while its level is ≥ 0.05 mg, or unconditionally for
/// 48h after its latest dose so a fresh log shows up before the Bateman
/// curve has risen off the baseline.
List<ActiveLoadEntry> activeInjectableLoad({
  required List<Injection> injections,
  required DateTime now,
}) {
  final totals = <String, double>{};
  final latest = <String, Injection>{};

  for (final inj in injections) {
    if (inj.snapshot.type != CompoundType.steroid &&
        inj.snapshot.type != CompoundType.oral) {
      continue;
    }
    final diffDays = now.difference(inj.date).inSeconds / 86400.0;
    if (diffDays < 0) continue; // future injection

    final base = inj.snapshot.base;
    final prev = latest[base];
    if (prev == null || inj.date.isAfter(prev.date)) latest[base] = inj;

    final hl = inj.snapshot.halfLife > 0.05 ? inj.snapshot.halfLife : 1.0;
    if (diffDays > hl * 8) continue; // fully decayed
    totals[base] = (totals[base] ?? 0) +
        calculateActiveLevel(
          inj.dosage,
          diffDays,
          hl,
          inj.snapshot.timeToPeak,
          inj.snapshot.ratio,
          inj.snapshot.ester,
        );
  }

  final out = <ActiveLoadEntry>[];
  for (final entry in latest.entries) {
    final mg = totals[entry.key] ?? 0.0;
    final recentlyDosed =
        now.difference(entry.value.date) < const Duration(hours: 48);
    if (mg < 0.05 && !recentlyDosed) continue;
    out.add(ActiveLoadEntry(
      base: entry.key,
      type: entry.value.snapshot.type,
      activeMg: mg,
    ));
  }
  return out;
}

double averageActiveMgOverRange({
  required CompoundType type,
  required List<Injection> injections,
  required DateTime windowStart,
  required DateTime windowEnd,
  int samplesPerDay = 1,
}) {
  final filtered = injections.where((i) => i.snapshot.type == type).toList();
  if (filtered.isEmpty) return 0.0;

  final totalDays = windowEnd.difference(windowStart).inSeconds / 86400.0;
  if (totalDays <= 0) return 0.0;

  final totalSamples = (totalDays * samplesPerDay).round().clamp(1, 1000);
  double sum = 0.0;
  for (int i = 0; i <= totalSamples; i++) {
    final t = windowStart.add(Duration(milliseconds: (i * 86400000 / samplesPerDay).round()));
    double instant = 0.0;
    for (final inj in filtered) {
      final diffDays = t.difference(inj.date).inSeconds / 86400.0;
      if (diffDays < 0) continue;
      if (diffDays > inj.snapshot.halfLife * 8) continue;
      instant += calculateActiveLevel(
        inj.dosage,
        diffDays,
        inj.snapshot.halfLife,
        inj.snapshot.timeToPeak,
        inj.snapshot.ratio,
        inj.snapshot.ester,
      );
    }
    sum += instant;
  }
  return sum / (totalSamples + 1);
}

/// Current total active steroid mg (sum at exactly `now`).
double currentActiveMg({
  required CompoundType type,
  required List<Injection> injections,
  required DateTime now,
}) {
  double total = 0.0;
  for (final inj in injections) {
    if (inj.snapshot.type != type) continue;
    final diffDays = now.difference(inj.date).inSeconds / 86400.0;
    if (diffDays < 0) continue;
    if (diffDays > inj.snapshot.halfLife * 8) continue;
    total += calculateActiveLevel(
      inj.dosage,
      diffDays,
      inj.snapshot.halfLife,
      inj.snapshot.timeToPeak,
      inj.snapshot.ratio,
      inj.snapshot.ester,
    );
  }
  return total;
}

/// Trend: current steroid saturation vs the average across the prior week
/// (days 14 → 7 ago). Positive => trending up.
double deltaSteroidNowVsPrior7({
  required List<Injection> injections,
  required DateTime now,
}) {
  final current = currentActiveMg(
    type: CompoundType.steroid,
    injections: injections,
    now: now,
  );
  final prior7 = averageActiveMgOverRange(
    type: CompoundType.steroid,
    injections: injections,
    windowStart: now.subtract(const Duration(days: 14)),
    windowEnd: now.subtract(const Duration(days: 7)),
  );
  return current - prior7;
}

List<double> sampleLaneIntensity({
  required List<Injection> injections,
  required DateTime windowStart,
  required DateTime windowEnd,
  int sampleCount = 80,
}) {
  if (injections.isEmpty) return List.filled(sampleCount + 1, 0.0);
  final totalMs = windowEnd.difference(windowStart).inMilliseconds;
  final out = List<double>.filled(sampleCount + 1, 0.0);
  for (int i = 0; i <= sampleCount; i++) {
    final t = windowStart.add(Duration(milliseconds: (totalMs * i / sampleCount).round()));
    double v = 0.0;
    for (final inj in injections) {
      final diffDays = t.difference(inj.date).inSeconds / 86400.0;
      if (diffDays < 0) continue;
      if (diffDays > inj.snapshot.halfLife * 8) continue;
      v += calculateActiveLevel(
        inj.dosage,
        diffDays,
        inj.snapshot.halfLife,
        inj.snapshot.timeToPeak,
        inj.snapshot.ratio,
        inj.snapshot.ester,
      );
    }
    out[i] = v;
  }
  return out;
}
