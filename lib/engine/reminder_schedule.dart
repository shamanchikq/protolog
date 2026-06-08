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

/// Current UI state of a reminder row.
ReminderState reminderState(
  Reminder r,
  DateTime now, {
  Duration dueWindow = const Duration(hours: 12),
}) {
  if (!r.enabled) return ReminderState.paused;
  final dose = expectedDose(r, now);
  final dueEdge = now.add(dueWindow);
  if (r.scheduleMode == 'custom') {
    return dose.isAfter(dueEdge) ? ReminderState.on : ReminderState.due;
  }
  if (dose.isBefore(now)) return ReminderState.overdue;
  return dose.isAfter(dueEdge) ? ReminderState.on : ReminderState.due;
}

Reminder advanceAfterSkip(Reminder r, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (r.scheduleMode == 'custom') {
    return r.copyWith(acknowledgedUntil: _nextCustomSlot(r, n));
  }
  final next = expectedDose(r, n).add(_intervalDuration(r.intervalDays));
  return r.copyWith(anchorDate: next);
}

Reminder advanceAfterDose(Reminder r, DateTime takenAt) {
  if (r.scheduleMode == 'custom') {
    return r.copyWith(acknowledgedUntil: takenAt);
  }
  return r.copyWith(anchorDate: takenAt.add(_intervalDuration(r.intervalDays)));
}

const _wdShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _wdLetter = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _wdFull = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _hhmm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

String formatSchedule(Reminder r) {
  if (r.scheduleMode == 'interval') {
    final n = r.intervalDays;
    final numStr = n == n.roundToDouble() ? n.toInt().toString() : n.toString();
    final unit = n == 1.0 ? 'day' : 'days';
    final t = r.anchorDate != null
        ? _hhmm(r.anchorDate!.hour, r.anchorDate!.minute)
        : _hhmm(r.hour, r.minute);
    return 'Every $numStr $unit · $t';
  }
  final slots = [...r.customSlots]..sort((a, b) => a.weekday.compareTo(b.weekday));
  if (slots.isEmpty) return 'Custom';
  final t = _hhmm(slots.first.hour, slots.first.minute);
  final weekdays = slots.map((s) => s.weekday).toList();
  final set = weekdays.toSet();
  final sameTime =
      slots.every((s) => s.hour == slots.first.hour && s.minute == slots.first.minute);
  if (!sameTime) {
    return '${weekdays.map((w) => _wdShort[w - 1]).join(' / ')} · varies';
  }
  if (set.length == 5 && set.containsAll({1, 2, 3, 4, 5})) return 'Weekdays · $t';
  if (set.length == 1) return '${_wdFull[weekdays.first - 1]}s · $t';
  if (set.length == 2) return '${weekdays.map((w) => _wdShort[w - 1]).join(' / ')} · $t';
  return '${weekdays.map((w) => _wdLetter[w - 1]).join(' / ')} · $t';
}

String relativeDayLabel(DateTime d, DateTime now) {
  final dd = DateTime(d.year, d.month, d.day);
  final nn = DateTime(now.year, now.month, now.day);
  final diff = dd.difference(nn).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${_wdShort[d.weekday - 1]} ${_monShort[d.month - 1]} ${d.day}';
}

/// For each of the next [days] days starting today, the distinct compound
/// colors that have at least one occurrence that day. Disabled reminders are
/// skipped. Colors are de-duplicated per day.
List<List<Color>> weekAgenda(
  List<Reminder> reminders,
  DateTime now,
  int days,
  Color Function(Reminder) colorOf,
) {
  final result = List.generate(days, (_) => <Color>[]);
  final startDay = DateTime(now.year, now.month, now.day);
  final windowEnd = startDay.add(Duration(days: days));
  for (final r in reminders) {
    if (!r.enabled) continue;
    final col = colorOf(r);
    var occ = nextOccurrence(r, startDay);
    var guard = 0;
    while (occ.isBefore(windowEnd) && guard < 400) {
      final idx = DateTime(occ.year, occ.month, occ.day).difference(startDay).inDays;
      if (idx >= 0 && idx < days && !result[idx].contains(col)) {
        result[idx].add(col);
      }
      final next = nextOccurrence(r, occ.add(const Duration(seconds: 1)));
      if (!next.isAfter(occ)) break;
      occ = next;
      guard++;
    }
  }
  return result;
}
