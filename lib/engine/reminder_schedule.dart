import 'dart:convert';
import 'dart:ui' show Color;
import '../models.dart';
import '../format.dart';
import 'calendar.dart';

const _msPerDay = 86400000;

/// A whole number of days (float noise from arithmetic or a foreign backup
/// tolerated). Such intervals step by calendar day so a dose keeps its
/// wall-clock time across DST (B17); fractional ones step absolute time and
/// drift the time of day by design.
bool isWholeDayInterval(double days) =>
    days.isFinite && (days - days.roundToDouble()).abs() < 1e-9;

/// Occurrence [k] (k >= 0) of the rhythm starting at [anchor] and repeating
/// every [days]: `anchor + k × days`, in calendar days for a whole-day
/// interval. Always computed from the anchor, so a wall-clock time that one
/// DST date normalizes doesn't shift the rest.
DateTime _rhythmAt(DateTime anchor, double days, int k) => isWholeDayInterval(days)
    ? addCalendarDays(anchor, k * days.round())
    : anchor.add(Duration(milliseconds: (k * (days * _msPerDay)).round()));

/// Index of the first occurrence of [anchor]'s rhythm at/after [t] (strictly
/// after with [strict]); 0 when the anchor itself qualifies. [days] must be
/// schedulable.
int _firstIndexFrom(DateTime anchor, double days, DateTime t, {bool strict = false}) {
  bool reached(DateTime d) => strict ? d.isAfter(t) : !d.isBefore(t);
  if (reached(anchor)) return 0;
  // Estimate from absolute time — calendar stepping is at most a DST hour
  // off it — then settle on the exact index in a step or two.
  final stepMs = days * _msPerDay;
  var k = (t.difference(anchor).inMilliseconds / stepMs).floor();
  if (k < 1) k = 1;
  for (var guard = 0; guard < 4 && k > 1 && reached(_rhythmAt(anchor, days, k - 1)); guard++) {
    k--;
  }
  for (var guard = 0; guard < 4 && !reached(_rhythmAt(anchor, days, k)); guard++) {
    k++;
  }
  return k;
}

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
  return _rhythmAt(anchor, r.intervalDays, _firstIndexFrom(anchor, r.intervalDays, now));
}

/// The next [count] interval-mode fire times, from [nextOccurrence] on.
/// Empty for a corrupt interval, so the scheduler can never throw on one.
List<DateTime> intervalOccurrences(Reminder r, DateTime now, int count) {
  final days = r.intervalDays;
  if (!isSchedulableInterval(days)) return const [];
  final anchor = expectedDose(r, now);
  final first = _firstIndexFrom(anchor, days, now);
  return [for (var i = 0; i < count; i++) _rhythmAt(anchor, days, first + i)];
}

/// How far ahead a dose shows as Due (and, for a custom slot, how early a
/// logged dose still counts for it).
const Duration kReminderDueWindow = Duration(hours: 12);

/// Current UI state of a reminder row.
ReminderState reminderState(
  Reminder r,
  DateTime now, {
  Duration dueWindow = kReminderDueWindow,
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

/// Skip pressed in the app. Custom: acknowledges the row's next slot.
/// Interval: moves the anchor to the first occurrence after both the
/// current dose and [now] — one interval for a dose not yet due; for an
/// overdue one, past every missed dose to the next future occurrence, so it
/// doesn't stay Overdue (B14).
Reminder advanceAfterSkip(Reminder r, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (r.scheduleMode == 'custom') {
    return r.copyWith(acknowledgedUntil: _nextCustomSlot(r, n));
  }
  return _skipIntervalThrough(r, expectedDose(r, n), n);
}

/// Interval [r] with its anchor moved to the first occurrence of [anchor]'s
/// rhythm strictly after both [through] and [now].
Reminder _skipIntervalThrough(Reminder r, DateTime through, DateTime now, {DateTime? anchor}) {
  final days = r.intervalDays;
  if (!isSchedulableInterval(days)) return r;
  final origin = anchor ?? expectedDose(r, now);
  final past = now.isAfter(through) ? now : through;
  return r.copyWith(anchorDate: _rhythmAt(origin, days, _firstIndexFrom(origin, days, past, strict: true)));
}

/// Skip pressed on a notification that announced [occurrence] (null for a
/// weekly-repeating notification or one scheduled by an older release — see
/// [ReminderPayload]). Returns [r] itself when nothing changes, so a
/// repeated delivery of the same tap is harmless.
///
/// * Interval: skips that occurrence and every one before [now] — unless the
///   anchor is already past it (a stale notification, or the same Skip
///   delivered twice). Without an occurrence it skips like the in-app Skip.
/// * Custom: slots never go overdue, so a fired occurrence is already behind
///   us and there's nothing to acknowledge; [advanceAfterSkip] would
///   acknowledge the *next* slot and — since notifications honour
///   acknowledgedUntil (A3) — silence a dose the user never skipped. Only an
///   announced occurrence that is still owed (delivered early) is
///   acknowledged.
Reminder advanceAfterNotificationSkip(Reminder r, {DateTime? occurrence, DateTime? now}) {
  final n = now ?? DateTime.now();
  if (r.scheduleMode == 'custom') {
    if (occurrence == null || !occurrence.isAfter(_slotThreshold(r, n))) return r;
    return r.copyWith(acknowledgedUntil: occurrence);
  }
  if (occurrence == null) return advanceAfterSkip(r, now: n);
  // A reminder without an anchor floats at "today, hh:mm"; the announced
  // occurrence is the better rhythm origin.
  final anchor = r.anchorDate ?? occurrence;
  if (occurrence.isBefore(anchor)) return r;
  return _skipIntervalThrough(r, occurrence, n, anchor: anchor);
}

/// How far ahead of a custom slot a logged dose still counts as taken early
/// for it. Deliberately much tighter than [kReminderDueWindow]: a late dose
/// (missed 08:00, logged at 21:00) must not silence tomorrow's 08:00 — an
/// extra notification is cheaper than a missed one.
const Duration kEarlyDoseWindow = Duration(hours: 4);

/// The upcoming slot occurrence a custom dose taken at [takenAt] counts for
/// (B14): the first slot after it, when that is within [kEarlyDoseWindow]
/// and nearer than the slot occurrence before it — a dose an hour after
/// Tuesday 20:00 is Tuesday's, not an early one for Wednesday 06:00. Null
/// when the dose isn't early for any slot.
DateTime? _slotCoveredByEarlyDose(Reminder r, DateTime takenAt) {
  DateTime? next;
  DateTime? prev;
  final weekBefore = addCalendarDays(takenAt, -7);
  for (final s in r.customSlots.take(kMaxCustomSlots)) {
    final after = nextSlotAfter(s, takenAt);
    if (after != null && (next == null || after.isBefore(next))) next = after;
    // The one occurrence in (takenAt - 7 days, takenAt].
    final before = nextSlotAfter(s, weekBefore);
    if (before != null && !before.isAfter(takenAt) && (prev == null || before.isAfter(prev))) {
      prev = before;
    }
  }
  if (next == null) return null;
  final ahead = next.difference(takenAt);
  if (ahead > kEarlyDoseWindow) return null;
  if (prev != null && takenAt.difference(prev) <= ahead) return null;
  return next;
}

/// Moves the schedule past a logged dose — forward only (A4). Interval: the
/// anchor becomes `takenAt + interval` unless that's no later than the
/// current expected dose, so a back-dated log can't rewind the rhythm into
/// the past (Overdue right after a dose); an early-but-recent dose still
/// re-anchors, since its next dose lands after the old anchor. Custom:
/// acknowledges through `takenAt` — or through the slot the dose was taken
/// early for ([_slotCoveredByEarlyDose]) — and `acknowledgedUntil` only ever
/// grows. Returns [r] itself when nothing moves.
Reminder advanceAfterDose(Reminder r, DateTime takenAt, {DateTime? now}) {
  if (r.scheduleMode == 'custom') {
    final through = _slotCoveredByEarlyDose(r, takenAt) ?? takenAt;
    final ack = r.acknowledgedUntil;
    if (ack != null && !through.isAfter(ack)) return r;
    return r.copyWith(acknowledgedUntil: through);
  }
  if (!isSchedulableInterval(r.intervalDays)) return r;
  final next = _rhythmAt(takenAt, r.intervalDays, 1);
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

/// What a reminder notification hands back to the tap handler: which
/// reminder, and — for a one-shot — the occurrence it announced, so Skip
/// acts on that dose and a repeated or stale tap changes nothing (B14).
///
/// Encoded as a JSON object, `{"reminder": id, "at": µs since epoch}`.
/// Notifications scheduled by earlier releases carry the bare reminder id;
/// [parse] reads those as a payload without an occurrence.
class ReminderPayload {
  final String reminderId;

  /// The occurrence announced; null for a weekly-repeating notification
  /// (its date changes every week) and for an old bare-id payload.
  final DateTime? occurrence;

  const ReminderPayload(this.reminderId, {this.occurrence});

  String encode() => jsonEncode({
        'reminder': reminderId,
        if (occurrence != null) 'at': occurrence!.microsecondsSinceEpoch,
      });

  /// Null for a missing payload. Never throws: anything that isn't the JSON
  /// object above is taken as a bare reminder id.
  static ReminderPayload? parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload.startsWith('{')) {
      Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        decoded = null;
      }
      if (decoded is Map && decoded.containsKey('reminder')) {
        final id = decoded['reminder'];
        if (id is! String || id.isEmpty) return null;
        return ReminderPayload(id, occurrence: _instant(decoded['at']));
      }
    }
    return ReminderPayload(payload);
  }

  static DateTime? _instant(Object? micros) {
    if (micros is! int) return null;
    try {
      return DateTime.fromMicrosecondsSinceEpoch(micros);
    } on ArgumentError {
      return null; // out of DateTime's range
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderPayload && other.reminderId == reminderId && other.occurrence == occurrence;

  @override
  int get hashCode => Object.hash(reminderId, occurrence);

  @override
  String toString() => 'ReminderPayload($reminderId @ $occurrence)';
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

/// 24-hour "HH:mm" — the app shows clock times this way everywhere,
/// whatever the locale's 12/24 h preference.
String formatHourMinute(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// "M", "T", … for [weekday] (1 = Monday).
String weekdayLetter(int weekday) => weekdaysShort[weekday - 1].substring(0, 1);

String formatSchedule(Reminder r) {
  if (r.scheduleMode == 'interval') {
    final n = r.intervalDays;
    final numStr = n.isFinite && n == n.roundToDouble() ? n.toInt().toString() : n.toString();
    final unit = n == 1.0 ? 'day' : 'days';
    final t = r.anchorDate != null
        ? formatHourMinute(r.anchorDate!.hour, r.anchorDate!.minute)
        : formatHourMinute(r.hour, r.minute);
    return 'Every $numStr $unit · $t';
  }
  final slots = r.customSlots.where(isValidSlot).toList()
    ..sort((a, b) => a.weekday.compareTo(b.weekday));
  if (slots.isEmpty) return 'Custom';
  final t = formatHourMinute(slots.first.hour, slots.first.minute);
  final weekdays = slots.map((s) => s.weekday).toList();
  final set = weekdays.toSet();
  final sameTime =
      slots.every((s) => s.hour == slots.first.hour && s.minute == slots.first.minute);
  if (!sameTime) {
    return '${weekdays.map((w) => weekdaysShort[w - 1]).join(' / ')} · varies';
  }
  if (set.length == 5 && set.containsAll({1, 2, 3, 4, 5})) return 'Weekdays · $t';
  if (set.length == 1) return '${weekdaysLong[weekdays.first - 1]}s · $t';
  if (set.length == 2) return '${weekdays.map((w) => weekdaysShort[w - 1]).join(' / ')} · $t';
  return '${weekdays.map((w) => weekdayLetter(w)).join(' / ')} · $t';
}

/// "Today" / "Tomorrow" / "Yesterday" / "Thu May 21" for [d] relative to
/// [now], counted in calendar days (a 23 h or 25 h DST day is still one).
String relativeDayLabel(DateTime d, DateTime now) {
  final diff = calendarDaysBetween(now, d);
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${weekdaysShort[d.weekday - 1]} ${monthsShort[d.month - 1]} ${d.day}';
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
  // Calendar days, not 24 h steps: across DST those land on the wrong date.
  final startDay = dateOnly(now);
  final windowEnd = addCalendarDays(startDay, days);
  for (final r in reminders) {
    if (!r.enabled) continue;
    if (r.scheduleMode != 'custom' && !isSchedulableInterval(r.intervalDays)) continue;
    final col = colorOf(r);
    var occ = nextOccurrence(r, startDay);
    var guard = 0;
    while (occ.isBefore(windowEnd) && guard < 400) {
      final idx = calendarDaysBetween(startDay, occ);
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
