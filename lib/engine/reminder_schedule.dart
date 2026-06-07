import 'dart:ui' show Color;
import '../models.dart';

const _msPerDay = 86400000;

Duration _intervalDuration(double days) =>
    Duration(milliseconds: (days * _msPerDay).round());

/// Next custom weekday+time slot strictly after the suppression threshold
/// (max of `now` and `acknowledgedUntil`). Custom reminders never go overdue.
DateTime _nextCustomSlot(Reminder r, DateTime now) {
  final ack = r.acknowledgedUntil;
  final threshold = (ack != null && ack.isAfter(now))
      ? ack
      : now.subtract(const Duration(seconds: 1));
  if (r.customSlots.isEmpty) return threshold.add(const Duration(seconds: 1));
  DateTime? best;
  for (final s in r.customSlots) {
    var d = DateTime(threshold.year, threshold.month, threshold.day, s.hour, s.minute);
    while (d.weekday != s.weekday || !d.isAfter(threshold)) {
      d = d.add(const Duration(days: 1));
    }
    if (best == null || d.isBefore(best)) best = d;
  }
  return best!;
}

/// The dose the row label and state refer to.
/// Interval: the anchor (may be in the past -> overdue). Custom: next slot.
DateTime expectedDose(Reminder r, DateTime now) {
  if (r.scheduleMode == 'custom') return _nextCustomSlot(r, now);
  return r.anchorDate ??
      DateTime(now.year, now.month, now.day, r.hour, r.minute);
}

/// The next FUTURE dose (>= now) — for the week strip and the scheduler.
DateTime nextOccurrence(Reminder r, DateTime now) {
  if (r.scheduleMode == 'custom') return _nextCustomSlot(r, now);
  final anchor = expectedDose(r, now);
  if (!anchor.isBefore(now)) return anchor;
  final stepMs = r.intervalDays * _msPerDay;
  final diffMs = now.difference(anchor).inMilliseconds;
  final k = (diffMs / stepMs).ceil();
  return anchor.add(Duration(milliseconds: (k * stepMs).round()));
}
