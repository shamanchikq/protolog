import 'dart:math' as math;

import '../models.dart';
import 'dashboard_stats.dart';

/// Distinct marker names, ordered by most recent draw first — drives the
/// chip order on the bloodwork page and card.
List<String> distinctMarkers(List<BloodworkEntry> entries) {
  final latest = <String, DateTime>{};
  for (final e in entries) {
    final cur = latest[e.marker];
    if (cur == null || e.date.isAfter(cur)) latest[e.marker] = e.date;
  }
  final markers = latest.keys.toList()
    ..sort((a, b) => latest[b]!.compareTo(latest[a]!));
  return markers;
}

/// Units compare trimmed and case-insensitively ("nmol/L" == " nmol/l").
String unitKey(String unit) => unit.trim().toLowerCase();

final _digits = RegExp(r'^\d+$');

/// Chronological draw order with a deterministic tie-break for same-day
/// draws: by date, then by id (numerically when both are digit strings —
/// created ids are millisecond timestamps, so that's entry order).
int compareDraws(BloodworkEntry a, BloodworkEntry b) {
  final byDate = a.date.compareTo(b.date);
  if (byDate != 0) return byDate;
  if (_digits.hasMatch(a.id) && _digits.hasMatch(b.id)) {
    final byLength = a.id.length.compareTo(b.id.length);
    if (byLength != 0) return byLength;
  }
  return a.id.compareTo(b.id);
}

/// All draws of one marker, oldest first (chart order). With [unit], only
/// the draws recorded in that unit (see [unitKey]).
List<BloodworkEntry> historyFor(
  String marker,
  List<BloodworkEntry> entries, {
  String? unit,
}) {
  final key = unit == null ? null : unitKey(unit);
  final h =
      entries
          .where(
            (e) => e.marker == marker && (key == null || unitKey(e.unit) == key),
          )
          .toList()
        ..sort(compareDraws);
  return h;
}

/// The units [marker] was recorded in, most recently used first. Units that
/// differ only in case/whitespace count once (spelled as most recently
/// entered).
List<String> unitsFor(String marker, List<BloodworkEntry> entries) {
  final seen = <String>{};
  final out = <String>[];
  for (final e in historyFor(marker, entries).reversed) {
    if (seen.add(unitKey(e.unit))) out.add(e.unit.trim());
  }
  return out;
}

/// The draw [entry] is compared against: the latest earlier draw of the
/// same marker **in the same unit** (comparing nmol/L against ng/dL is
/// meaningless), or null for the first such draw. Same-day draws are
/// ordered by [compareDraws], so they never use each other as "previous".
BloodworkEntry? previousDraw(
  BloodworkEntry entry,
  List<BloodworkEntry> entries,
) {
  final key = unitKey(entry.unit);
  BloodworkEntry? prev;
  for (final e in entries) {
    if (e.marker != entry.marker || e.id == entry.id) continue;
    if (unitKey(e.unit) != key) continue;
    if (compareDraws(e, entry) >= 0) continue;
    if (prev == null || compareDraws(e, prev) > 0) prev = e;
  }
  return prev;
}

/// Raw change vs [previousDraw], or null when there is none. Display code
/// formats through `formatLabDelta` (ui/format.dart), which strips the
/// float noise this subtraction carries.
double? deltaVsPrevious(BloodworkEntry entry, List<BloodworkEntry> entries) {
  final prev = previousDraw(entry, entries);
  if (prev == null) return null;
  return entry.value - prev.value;
}

/// Most points the PK overlay hands to the trend painter — about one per
/// device pixel of the chart.
const int overlayMaxPoints = 400;

/// How many intervals to sample the PK overlay at across [start]..[end]:
/// [samplesPerDay] per day so daily peaks aren't skipped, at least [min],
/// at most [max] (cost is samples × doses).
int overlaySampleCount(
  DateTime start,
  DateTime end, {
  int samplesPerDay = 6,
  int min = 80,
  int max = 3000,
}) {
  final days = end.difference(start).inMinutes / (24 * 60);
  if (!(days > 0)) return min;
  return (days * samplesPerDay).ceil().clamp(min, max);
}

/// Peak-preserving decimation: splits [samples] into at most [maxPoints]
/// consecutive buckets and keeps each bucket's max, so a short peak that
/// falls between output points still shows. Shorter input is returned as is.
List<double> decimatePeaks(List<double> samples, int maxPoints) {
  final n = samples.length;
  if (n <= maxPoints || maxPoints < 2) return List.of(samples);
  final out = List<double>.filled(maxPoints, 0);
  for (var j = 0; j < maxPoints; j++) {
    final from = (j * n / maxPoints).floor();
    final to = math.max(from + 1, ((j + 1) * n / maxPoints).floor());
    var m = samples[from];
    for (var i = from + 1; i < to; i++) {
      if (samples[i] > m) m = samples[i];
    }
    out[j] = m;
  }
  return out;
}

/// Modeled activity of [injections] across [windowStart]..[windowEnd] for
/// the bloodwork PK overlay: sampled densely (see [overlaySampleCount]) and
/// peak-decimated to [overlayMaxPoints], instead of a fixed 81-point grid
/// that aliases daily/weekly peaks over long spans.
List<double> sampleOverlay({
  required List<Injection> injections,
  required DateTime windowStart,
  required DateTime windowEnd,
}) {
  final raw = sampleLaneIntensity(
    injections: injections,
    windowStart: windowStart,
    windowEnd: windowEnd,
    sampleCount: overlaySampleCount(windowStart, windowEnd),
  );
  return decimatePeaks(raw, overlayMaxPoints);
}
