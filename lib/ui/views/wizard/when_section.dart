import 'package:flutter/material.dart';
import '../../../engine/calendar.dart';
import '../../../engine/injection_draft.dart';
import '../../../utils.dart';
import '../../theme.dart';
import '../../widgets/lab_pickers.dart';
import 'wizard_widgets.dart';

/// "When" section of the details step: date + time fields (Material pickers
/// in the Lab Sheet theme), quick-time pills, and a non-blocking hint when the
/// log is dated more than a day ahead (planned doses are allowed).
class WhenSection extends StatelessWidget {
  /// The log's day (its time-of-day is ignored).
  final DateTime date;
  final TimeOfDay time;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;

  /// Clock for "Today" labels and the future hint; null reads the real one.
  final DateTime? now;

  const WhenSection({
    super.key,
    required this.date,
    required this.time,
    required this.onDateChanged,
    required this.onTimeChanged,
    this.now,
  });

  /// Quick-time pills, as (hour, minute).
  static const quickTimes = <(int, int)>[(6, 0), (8, 0), (20, 0), (22, 0)];

  @override
  Widget build(BuildContext context) {
    final n = now ?? DateTime.now();
    final daysAhead = futureDaysAhead(
      logDateTime(date, hour: time.hour, minute: time.minute),
      now: n,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WizardSectionTitle('When'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: WizardField(
                label: 'Date',
                onTap: () => _pickDate(context),
                child: Text(formatRelativeDate(date, now: n),
                    style: AppTheme.sans(size: 15, weight: FontWeight.w500, color: AppTheme.fg)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: WizardField(
                label: 'Time',
                onTap: () => _pickTime(context),
                child: Text(formatClock(time),
                    style: AppTheme.mono(size: 15, weight: FontWeight.w500, color: AppTheme.fg)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildQuickTimes(),
        if (daysAhead != null) ...[
          const SizedBox(height: 8),
          Text(
            'In the future · $daysAhead ${daysAhead == 1 ? 'day' : 'days'} ahead',
            style: AppTheme.sans(size: 11, color: AppTheme.warm),
          ),
        ],
      ],
    );
  }

  Widget _buildQuickTimes() {
    const slots = quickTimes;
    return Row(
      children: [
        for (int i = 0; i < slots.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: WizardPill(
              label: formatClock(TimeOfDay(hour: slots[i].$1, minute: slots[i].$2)),
              active: time.hour == slots[i].$1 && time.minute == slots[i].$2,
              onTap: () => onTimeChanged(TimeOfDay(hour: slots[i].$1, minute: slots[i].$2)),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final range = logDatePickerRange(current: date, now: now ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: range.first,
      lastDate: range.last,
      initialDate: dateOnly(date),
      builder: (ctx, child) => labPickerTheme(child!),
    );
    // The wizard may have closed while the picker was open.
    if (picked != null && context.mounted) onDateChanged(picked);
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: time,
      builder: (ctx, child) => labPickerTheme(child!),
    );
    if (picked != null && context.mounted) onTimeChanged(picked);
  }
}

/// "Today, May 10" / "Yesterday, …" / "Tomorrow, …" / "May 10" (this year) /
/// "May 10, 2025".
String formatRelativeDate(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  // Calendar days, not Duration.inDays: a DST day is 23 or 25 h long (B27).
  final diff = calendarDaysBetween(d, n);
  final monthDay = formatDate(d, 'MMM d');
  if (diff == 0) return 'Today, $monthDay';
  if (diff == 1) return 'Yesterday, $monthDay';
  if (diff == -1) return 'Tomorrow, $monthDay';
  if (d.year == n.year) return monthDay;
  return '${formatDate(d, 'MMM d')}, ${d.year}';
}

/// 24-hour "HH:mm".
String formatClock(TimeOfDay t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}
