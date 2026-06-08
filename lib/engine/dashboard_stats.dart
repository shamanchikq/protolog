import '../models.dart';
import 'compute_engine.dart';

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
