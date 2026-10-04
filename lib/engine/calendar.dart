/// Calendar-day arithmetic that stays correct across DST transitions.
///
/// `Duration(days: n)` is n × 24 h of absolute time. Across a DST switch that
/// lands an hour off the intended wall-clock time — and from midnight that
/// means the previous or the same date (a week strip reading 22, 23, 24, 25,
/// 25, 26 …). These helpers step and compare *calendar dates* instead; use
/// them wherever "N days later/earlier" or "how many days apart" is meant in
/// the calendar sense. Pure and isolate-safe.
library;

/// Midnight at the start of [d]'s calendar day (UTC if [d] is UTC).
DateTime dateOnly(DateTime d) =>
    d.isUtc ? DateTime.utc(d.year, d.month, d.day) : DateTime(d.year, d.month, d.day);

/// [d] moved by [days] calendar days (negative = earlier), keeping its
/// wall-clock time: 08:00 stays 08:00 across a DST switch.
///
/// If that wall-clock time doesn't exist on the target date (it falls in the
/// hour skipped by a spring-forward), `DateTime` normalizes it — typically an
/// hour later — but the date is still the intended one.
DateTime addCalendarDays(DateTime d, int days) => d.isUtc
    ? DateTime.utc(d.year, d.month, d.day + days, d.hour, d.minute, d.second,
        d.millisecond, d.microsecond)
    : DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second,
        d.millisecond, d.microsecond);

/// Whole calendar days from [a]'s date to [b]'s date (positive when [b] is a
/// later date), ignoring time of day. DST-safe: computed on UTC dates, so a
/// 23 h or 25 h day still counts as one.
int calendarDaysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

/// True when [a] and [b] fall on the same calendar date.
bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
