import '../models.dart';
import 'reminder_schedule.dart';

/// Semantic checks for records read from storage or a backup (A7). fromJson
/// already rejects wrong types and missing fields; these reject values that
/// parse fine but can't be right and would hang, throw, or poison later
/// saves — a non-finite double (every later jsonEncode throws), a zero
/// interval (nextOccurrence divided by it), an out-of-range slot weekday
/// (the slot search never matched). Deliberately lenient beyond that: odd
/// but harmless values (a 0 % yield, a 0 mg log) are kept.

bool _finiteOrNull(double? v) => v == null || v.isFinite;

// PK values only need to be finite: the engine already treats a t½ ≤ 0 as
// "no contribution" (isUsableHalfLife), and the editor accepted t½ 0 before
// the B1 fix — dropping such records at load would hide real logs.
bool isValidCompound(CompoundDefinition c) =>
    c.halfLife.isFinite &&
    c.timeToPeak.isFinite &&
    c.ratio.isFinite &&
    _finiteOrNull(c.defaultHalfLife) &&
    _finiteOrNull(c.concentration);

bool isValidInjection(Injection i) =>
    i.dosage.isFinite && i.dosage >= 0 && isValidCompound(i.snapshot);

bool isValidBloodwork(BloodworkEntry b) => b.value.isFinite;

// Platform notification ids are 32-bit; a reminder uses
// seed + 0 ..< kNotificationIdsPerReminder.
const int _kMinSeed = -0x80000000;
const int _kMaxSeed = 0x7FFFFFFF - (kNotificationIdsPerReminder - 1);

bool isValidReminder(Reminder r) {
  if (r.hour < 0 || r.hour > 23 || r.minute < 0 || r.minute > 59) return false;
  final seed = r.notificationSeed;
  if (seed != null && (seed < _kMinSeed || seed > _kMaxSeed)) return false;
  switch (r.scheduleMode) {
    case 'interval':
      return isSchedulableInterval(r.intervalDays);
    case 'custom':
      // intervalDays is unused (the editor stores 0) but still serialized.
      return r.intervalDays.isFinite &&
          r.customSlots.isNotEmpty &&
          r.customSlots.length <= kMaxCustomSlots &&
          r.customSlots.every(isValidSlot);
    default:
      return false;
  }
}
