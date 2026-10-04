import '../models.dart';
import 'reminder_schedule.dart';

/// Interval reminders pre-schedule this many one-shot notifications (ids
/// `notificationIdBase + 0 ..< this`) so they keep firing even when the app
/// isn't opened for several cycles.
const int kIntervalNotificationCount = 10;

const String kReminderNotificationTitle = 'ProtoLog Reminder';

/// A slot's clock time, which a custom-slot notification is pinned to.
typedef SlotClockTime = ({int hour, int minute});

/// One platform notification to schedule for a reminder. Pure data — the
/// notification service turns it into a plugin call.
class PlannedNotification {
  final int id;

  /// When it fires (device-local).
  final DateTime when;

  /// Custom slots only: the scheduler pins the notification to [when]'s
  /// date at this clock time in the platform's zone, so the slot keeps its
  /// wall-clock time across DST. Null for interval one-shots, which fire at
  /// the instant [when] (fractional intervals drift the time of day).
  final SlotClockTime? slotTime;

  /// Repeats every week on [when]'s weekday and time (custom slot);
  /// otherwise a one-shot.
  final bool repeatsWeekly;

  final String title;
  final String body;

  /// The reminder id — the tap handler routes on it.
  final String payload;

  const PlannedNotification({
    required this.id,
    required this.when,
    this.slotTime,
    this.repeatsWeekly = false,
    required this.title,
    required this.body,
    required this.payload,
  });

  @override
  String toString() =>
      'PlannedNotification($id @ $when${repeatsWeekly ? ' weekly' : ''})';
}

/// Everything to schedule for [r] at [now] (after cancelling its whole id
/// range). Empty for a disabled reminder and for corrupt data — never
/// throws, so one bad reminder can't stop the others being scheduled.
///
/// * Interval: [kIntervalNotificationCount] one-shots from the next
///   occurrence ([intervalOccurrences]), ids base + 0..9.
/// * Custom: per slot ([customSlotPlans]) one weekly-repeating notification
///   (id base + [customSlotIdOffset]), or — for a slot whose next
///   occurrence was acknowledged — [kAckedSlotOneShots] weekly one-shots
///   (A3).
///
/// The body carries the most recent matching log from [injections].
List<PlannedNotification> planReminderNotifications(
  Reminder r,
  DateTime now, {
  required List<Injection> injections,
}) {
  if (!r.enabled) return const [];
  final body = reminderNotificationBody(r, injections);
  final base = r.notificationIdBase;
  PlannedNotification note(int offset, DateTime when,
          {SlotClockTime? slotTime, bool weekly = false}) =>
      PlannedNotification(
        id: base + offset,
        when: when,
        slotTime: slotTime,
        repeatsWeekly: weekly,
        title: kReminderNotificationTitle,
        body: body,
        payload: r.id,
      );

  if (r.scheduleMode == 'custom') {
    return [
      for (final plan in customSlotPlans(r, now))
        if (plan.repeatsWeekly)
          note(customSlotIdOffset(plan.slotIndex), plan.fireTimes.first,
              slotTime: _clockOf(r.customSlots[plan.slotIndex]), weekly: true)
        else
          for (var w = 0; w < plan.fireTimes.length; w++)
            note(customSlotIdOffset(plan.slotIndex, oneShot: w), plan.fireTimes[w],
                slotTime: _clockOf(r.customSlots[plan.slotIndex])),
    ];
  }

  final times = intervalOccurrences(r, now, kIntervalNotificationCount);
  return [for (var i = 0; i < times.length; i++) note(i, times[i])];
}

SlotClockTime _clockOf(ReminderSlot s) => (hour: s.hour, minute: s.minute);
