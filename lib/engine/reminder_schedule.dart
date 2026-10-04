import 'dart:ui' show Color;
import '../models.dart';

const _msPerDay = 86400000;

Duration _intervalDuration(double days) =>
    Duration(milliseconds: (days * _msPerDay).round());

/// Sanity bounds for an interval reminder's spacing. The editor offers
/// 0.5–90 days; anything outside these came from corrupt data or a foreign
/// backup, and would divide by ~zero or overflow the interval arithmetic.
const double kMinReminderIntervalDays = 1 / 24; // one hour
const double kMaxReminderIntervalDays = 366;

bool isSchedulableInterval(double days) =>
    days.isFinite &&
    days >= kMinReminderIntervalDays &&
    days <= kMaxReminderIntervalDays;

/// A custom reminder holds at most one slot per weekday (the editor keys
/// slots by weekday). Slots past this are ignored by the scheduler.
const int kMaxCustomSlots = 7;

/// Weekly one-shots scheduled in place of the repeating notification for an
/// acknowledged custom slot — see [customSlotPlans].
const int kAckedSlotOneShots = 8;

/// Notification ids per reminder: `notificationIdBase + 0 ..< this`. The
/// scheduler's cancel sweep covers exactly this range.
const int kNotificationIdsPerReminder = 64;

/// Id offset (from the reminder's notification id base) for custom slot
/// [slotIndex]: 1..7 for its weekly-repeating notification, 8..63 for the
/// one-shots of an acknowledged slot. Interval mode uses 0..9.
int customSlotIdOffset(int slotIndex, {int? oneShot}) => oneShot == null
    ? 1 + slotIndex
    : 1 + kMaxCustomSlots + slotIndex * kAckedSlotOneShots + oneShot;

bool isValidSlot(ReminderSlot s) =>
    s.weekday >= 1 && s.weekday <= 7 &&
    s.hour >= 0 && s.hour <= 23 &&
    s.minute >= 0 && s.minute <= 59;

/// First occurrence of [slot] strictly after [after]. Steps by calendar day
/// (`DateTime(y, m, d + n, h, min)`, not 24 h) so the slot keeps its
/// wall-clock time across DST. Null for a corrupt slot; the search is
/// bounded either way, so bad data can never hang the caller.
DateTime? nextSlotAfter(ReminderSlot slot, DateTime after) {
  if (!isValidSlot(slot)) return null;
  final a = after.toLocal();
  // 8 days cover "later this week" through "today, but already past"; the
  // spare steps absorb a slot time that falls in a DST gap.
  for (var n = 0; n < 15; n++) {
    final d = DateTime(a.year, a.month, a.day + n, slot.hour, slot.minute);
    if (d.weekday == slot.weekday && d.isAfter(a)) return d;
  }
  return null;
}

/// Occurrences at/before this are handled: the later of `now` and the
/// reminder's acknowledgement (a Skip or a logged dose). `now - 1 s` so a
/// slot falling exactly on `now` still counts as upcoming.
DateTime _slotThreshold(Reminder r, DateTime now) {
  final ack = r.acknowledgedUntil;
  return (ack != null && ack.isAfter(now))
      ? ack
      : now.subtract(const Duration(seconds: 1));
}

/// Per custom slot (in `customSlots` order) the first occurrence still owed:
/// at/after [now] and strictly after `acknowledgedUntil`. Null for a corrupt
/// slot. One rule for the Reminders tab ([expectedDose]) and the scheduler
/// ([customSlotPlans]), so the two can't disagree (A3).
List<DateTime?> customSlotOccurrences(Reminder r, DateTime now) {
  final threshold = _slotThreshold(r, now);
  return [for (final s in r.customSlots) nextSlotAfter(s, threshold)];
}

/// Earliest owed custom slot. Custom reminders never go overdue.
DateTime _nextCustomSlot(Reminder r, DateTime now) {
  DateTime? best;
  for (final d in customSlotOccurrences(r, now)) {
    if (d != null && (best == null || d.isBefore(best))) best = d;
  }
  return best ?? _slotThreshold(r, now).add(const Duration(seconds: 1));
}

/// How one custom slot's notifications go out.
class CustomSlotPlan {
  final int slotIndex;

  /// Earliest first. A weekly-repeating plan has a single entry.
  final List<DateTime> fireTimes;
  final bool repeatsWeekly;

  const CustomSlotPlan(this.slotIndex, this.fireTimes, {required this.repeatsWeekly});
}

/// Notification plan per custom slot (corrupt slots and slots past
/// [kMaxCustomSlots] are left out).
///
/// Normally a slot gets one weekly-repeating notification. But a repeating
/// platform trigger always starts at the next match from *now* (Android's
/// plugin re-derives the first fire date; iOS uses a calendar trigger), so it
/// can't skip an acknowledged occurrence. A slot whose next occurrence is
/// acknowledged gets [kAckedSlotOneShots] weekly one-shots from its first
/// owed occurrence instead; the first reschedule after the acknowledgement
/// has passed turns it back into a repeating one (A3).
List<CustomSlotPlan> customSlotPlans(Reminder r, DateTime now) {
  final owed = customSlotOccurrences(r, now);
  final unacked = now.subtract(const Duration(seconds: 1));
  final plans = <CustomSlotPlan>[];
  for (var i = 0; i < r.customSlots.length && i < kMaxCustomSlots; i++) {
    final first = owed[i];
    if (first == null) continue;
    final s = r.customSlots[i];
    if (first == nextSlotAfter(s, unacked)) {
      plans.add(CustomSlotPlan(i, [first], repeatsWeekly: true));
    } else {
      plans.add(CustomSlotPlan(i, [
        for (var w = 0; w < kAckedSlotOneShots; w++)
          DateTime(first.year, first.month, first.day + 7 * w, s.hour, s.minute),
      ], repeatsWeekly: false));
    }
  }
  return plans;
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
  // Corrupt interval (zero, NaN, absurd): no rhythm to roll forward on —
  // dividing by it below would throw.
  if (!isSchedulableInterval(r.intervalDays)) return now;
  final stepMs = r.intervalDays * _msPerDay;
  final diffMs = now.difference(anchor).inMilliseconds;
  final k = (diffMs / stepMs).ceil();
  return anchor.add(Duration(milliseconds: (k * stepMs).round()));
}

/// The next [count] interval-mode fire times, from [nextOccurrence] on.
/// Empty for a corrupt interval, so the scheduler can never throw on one.
List<DateTime> intervalOccurrences(Reminder r, DateTime now, int count) {
  if (!isSchedulableInterval(r.intervalDays)) return const [];
  final step = _intervalDuration(r.intervalDays);
  final first = nextOccurrence(r, now);
  return [for (var i = 0; i < count; i++) first.add(step * i)];
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
  if (!isSchedulableInterval(r.intervalDays)) return r;
  final next = expectedDose(r, n).add(_intervalDuration(r.intervalDays));
  return r.copyWith(anchorDate: next);
}

/// Skip pressed on a notification — after the occurrence it announced has
/// fired. Interval: that occurrence is the anchor, so the regular skip moves
/// past it. Custom: slots never go overdue, so the fired occurrence is
/// already behind us and there's nothing to acknowledge; [advanceAfterSkip]
/// would acknowledge the *next* slot and — since notifications honour
/// acknowledgedUntil (A3) — silence a dose the user never skipped.
/// Returns [r] itself when nothing changes.
Reminder advanceAfterNotificationSkip(Reminder r, {DateTime? now}) =>
    r.scheduleMode == 'custom' ? r : advanceAfterSkip(r, now: now);

/// Moves the schedule past a logged dose — forward only (A4). Interval: the
/// anchor becomes `takenAt + interval` unless that's no later than the
/// current expected dose, so a back-dated log can't rewind the rhythm into
/// the past (Overdue right after a dose); an early-but-recent dose still
/// re-anchors, since its next dose lands after the old anchor. Custom:
/// `acknowledgedUntil` only ever grows. Returns [r] itself when nothing moves.
Reminder advanceAfterDose(Reminder r, DateTime takenAt, {DateTime? now}) {
  if (r.scheduleMode == 'custom') {
    final ack = r.acknowledgedUntil;
    if (ack != null && !takenAt.isAfter(ack)) return r;
    return r.copyWith(acknowledgedUntil: takenAt);
  }
  if (!isSchedulableInterval(r.intervalDays)) return r;
  final next = takenAt.add(_intervalDuration(r.intervalDays));
  // A legacy reminder without an anchor floats at "today, hh:mm".
  if (!next.isAfter(expectedDose(r, now ?? DateTime.now()))) return r;
  return r.copyWith(anchorDate: next);
}

/// The enabled reminders for the logged dose's compound ([base] + [ester])
/// that [advanceAfterDose] actually moves, keyed by their index in
/// [reminders]. A back-dated dose moves nothing (A4).
Map<int, Reminder> remindersAdvancedByDose(
  List<Reminder> reminders, {
  required String base,
  required String ester,
  required DateTime takenAt,
  DateTime? now,
}) {
  final out = <int, Reminder>{};
  for (var i = 0; i < reminders.length; i++) {
    final r = reminders[i];
    if (!r.enabled || r.compoundBase != base || r.compoundEster != ester) continue;
    final updated = advanceAfterDose(r, takenAt, now: now);
    if (!identical(updated, r)) out[i] = updated;
  }
  return out;
}

/// Notification body for a due reminder. Reminders don't store a dose, so
/// the most recent matching log supplies the "last dose" context.
String reminderNotificationBody(Reminder r, List<Injection> injections) {
  final ester = r.compoundEster;
  final showEster = ester.isNotEmpty && ester.toLowerCase() != 'none';
  final label = showEster ? '${r.compoundBase} $ester' : r.compoundBase;

  Injection? last;
  for (final i in injections) {
    if (i.snapshot.base != r.compoundBase) continue;
    if (i.snapshot.ester != r.compoundEster) continue;
    if (last == null || i.date.isAfter(last.date)) last = i;
  }
  if (last == null) return 'Time to administer $label';

  final d = last.dosage;
  final doseStr = d == d.roundToDouble()
      ? d.toStringAsFixed(0)
      : d.toString();
  return 'Time to administer $label · last dose $doseStr ${last.snapshot.unit.name}';
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
    final numStr = n.isFinite && n == n.roundToDouble() ? n.toInt().toString() : n.toString();
    final unit = n == 1.0 ? 'day' : 'days';
    final t = r.anchorDate != null
        ? _hhmm(r.anchorDate!.hour, r.anchorDate!.minute)
        : _hhmm(r.hour, r.minute);
    return 'Every $numStr $unit · $t';
  }
  final slots = r.customSlots.where(isValidSlot).toList()
    ..sort((a, b) => a.weekday.compareTo(b.weekday));
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
    if (r.scheduleMode != 'custom' && !isSchedulableInterval(r.intervalDays)) continue;
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
