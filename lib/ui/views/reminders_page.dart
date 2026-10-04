import 'package:flutter/material.dart';
import '../../models.dart';
import '../format.dart';
import '../theme.dart';
import '../../engine/calendar.dart';
import '../../engine/reminder_schedule.dart';
import '../../engine/library_stats.dart';
import '../widgets/lab_tap.dart';

class RemindersPage extends StatelessWidget {
  final List<Reminder> reminders;
  final List<CompoundDefinition> userCompounds;
  final DateTime now;
  final void Function(Reminder? editing) onEditReminder;
  final void Function(Reminder) onToggleEnabled;
  final void Function(Reminder) onLogNow;
  final void Function(Reminder) onSkip;

  /// Notification permission is denied (B20): a banner says reminders won't
  /// alert, with an Allow action when [onRequestNotificationPermission] is
  /// given.
  final bool notificationsDisabled;
  final VoidCallback? onRequestNotificationPermission;

  /// Live base → display color (MainScreen's resolver), so a library recolor
  /// shows on the rows and week strip too (B26). Without one, the static
  /// palette, then the catalogue entry's stored color.
  final Color Function(String base)? colorResolver;

  RemindersPage({
    super.key,
    required this.reminders,
    required this.userCompounds,
    required this.onEditReminder,
    required this.onToggleEnabled,
    required this.onLogNow,
    required this.onSkip,
    DateTime? now,
    this.notificationsDisabled = false,
    this.onRequestNotificationPermission,
    this.colorResolver,
  }) : now = now ?? DateTime.now();

  Color _colorFor(Reminder r) {
    final live = colorResolver;
    if (live != null) return live(r.compoundBase);
    final override = AppTheme.compoundColor(r.compoundBase);
    if (override != null) return override;
    for (final c in cataloguedCompounds(userCompounds: userCompounds)) {
      if (c.base == r.compoundBase && c.ester == r.compoundEster) {
        return Color(c.colorValue);
      }
    }
    return AppTheme.fgMute;
  }

  @override
  Widget build(BuildContext context) {
    final dueCount = reminders
        .where((r) {
          final s = reminderState(r, now);
          return s == ReminderState.overdue || s == ReminderState.due;
        })
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 90),
      children: [
        Text('Reminders', style: AppTheme.serif(size: 22, weight: FontWeight.w500, letterSpacing: -0.4)),
        const SizedBox(height: 4),
        Text(
          reminders.isEmpty ? 'Nothing scheduled yet' : '$dueCount due today · ${reminders.length} scheduled',
          style: AppTheme.sans(size: 12, color: AppTheme.fgMute),
        ),
        const SizedBox(height: 22),
        if (notificationsDisabled) ...[
          _NotificationsOffBanner(onAllow: onRequestNotificationPermission),
          const SizedBox(height: 18),
        ],
        if (reminders.isEmpty)
          _EmptyState(onCreate: () => onEditReminder(null))
        else ...[
          _SectionHeader(title: 'Next 7 days'),
          const SizedBox(height: 10),
          _WeekStrip(reminders: reminders, now: now, colorOf: _colorFor),
          const SizedBox(height: 22),
          _SectionHeader(title: 'Schedules', meta: 'tap to edit'),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: AppTheme.surface, border: Border.all(color: AppTheme.border, width: 1)),
            child: Column(
              children: [
                for (var i = 0; i < reminders.length; i++)
                  _ReminderRow(
                    reminder: reminders[i],
                    now: now,
                    color: _colorFor(reminders[i]),
                    topBorder: i > 0,
                    onTap: () => onEditReminder(reminders[i]),
                    onToggle: () => onToggleEnabled(reminders[i]),
                    onLogNow: () => onLogNow(reminders[i]),
                    onSkip: () => onSkip(reminders[i]),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Lab Sheet notice: notification permission is off, so reminders are
/// silent. "Allow" re-asks; once Android stops showing the prompt (denied
/// twice) only Settings can turn it back on, so the hint says where.
class _NotificationsOffBanner extends StatelessWidget {
  final VoidCallback? onAllow;
  const _NotificationsOffBanner({required this.onAllow});

  @override
  Widget build(BuildContext context) {
    final allow = onAllow;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          left: BorderSide(color: AppTheme.warn, width: 3),
          top: BorderSide(color: AppTheme.border, width: 1),
          right: BorderSide(color: AppTheme.border, width: 1),
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Notifications are off — reminders won't alert you",
                    style: AppTheme.sans(size: 12.5, weight: FontWeight.w600, height: 1.3)),
                const SizedBox(height: 4),
                Text(
                  allow != null
                      ? 'If no prompt appears, turn them on in Android Settings › Apps › ProtoLog › Notifications.'
                      : 'Turn them on in Android Settings › Apps › ProtoLog › Notifications.',
                  style: AppTheme.sans(size: 11, color: AppTheme.fgMute, height: 1.4),
                ),
              ],
            ),
          ),
          if (allow != null) ...[
            const SizedBox(width: 12),
            _ActionButton(label: 'Allow', filled: true, onTap: allow),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? meta;
  const _SectionHeader({required this.title, this.meta});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Semantics(
          header: true,
          child: Text(title.toUpperCase(), style: AppTheme.sans(size: 10, color: AppTheme.fgDimText, letterSpacing: 1.1)),
        ),
        if (meta != null) Text(meta!, style: AppTheme.sans(size: 10, color: AppTheme.fgDimText, letterSpacing: 0.4)),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final List<Reminder> reminders;
  final DateTime now;
  final Color Function(Reminder) colorOf;
  const _WeekStrip({required this.reminders, required this.now, required this.colorOf});

  @override
  Widget build(BuildContext context) {
    final agenda = weekAgenda(reminders, now, 7, colorOf);
    final startDay = dateOnly(now);
    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: _dayCell(addCalendarDays(startDay, i), i == 0, agenda[i])),
        ],
      ],
    );
  }

  Widget _dayCell(DateTime d, bool today, List<Color> colors) {
    // "Saturday 3, today, doses due" rather than "Sat", "3" and silent dots
    // (one dot per compound color, so no count).
    return Semantics(
      label: '${weekdaysLong[d.weekday - 1]} ${d.day}${today ? ', today' : ''}'
          '${colors.isEmpty ? '' : ', doses due'}',
      child: ExcludeSemantics(child: _dayCellBox(d, today, colors)),
    );
  }

  Widget _dayCellBox(DateTime d, bool today, List<Color> colors) {
    final fg = today ? AppTheme.paperInk : AppTheme.fg;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: today ? AppTheme.paper : Colors.transparent,
        border: Border.all(color: today ? AppTheme.paperInk : AppTheme.borderSoft, width: 1),
      ),
      child: Column(
        children: [
          Text(weekdaysShort[d.weekday - 1], style: AppTheme.sans(size: 10, color: today ? AppTheme.paperInk : AppTheme.fgDimText)),
          const SizedBox(height: 2),
          Text('${d.day}', style: AppTheme.sans(size: 17, weight: today ? FontWeight.w700 : FontWeight.w500, color: fg, height: 1.2)),
          const SizedBox(height: 8),
          SizedBox(
            height: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var j = 0; j < colors.length; j++) ...[
                  if (j > 0) const SizedBox(width: 2),
                  Container(width: 4, height: 3, color: colors[j]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  final Reminder reminder;
  final DateTime now;
  final Color color;
  final bool topBorder;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onLogNow;
  final VoidCallback onSkip;
  const _ReminderRow({
    required this.reminder,
    required this.now,
    required this.color,
    required this.topBorder,
    required this.onTap,
    required this.onToggle,
    required this.onLogNow,
    required this.onSkip,
  });

  (Color, String) _stateMeta(ReminderState s) => switch (s) {
        ReminderState.overdue => (AppTheme.warn, 'Overdue'),
        ReminderState.due => (AppTheme.warm, 'Due'),
        ReminderState.on => (AppTheme.accent, 'On'),
        ReminderState.paused => (AppTheme.fgDimText, 'Paused'),
      };

  String get _name => reminder.compoundEster.isEmpty || reminder.compoundEster.toLowerCase() == 'none'
      ? reminder.compoundBase
      : '${reminder.compoundBase} ${reminder.compoundEster}';

  @override
  Widget build(BuildContext context) {
    final state = reminderState(reminder, now);
    final (stateColor, stateLabel) = _stateMeta(state);
    final paused = state == ReminderState.paused;
    final actionable = state == ReminderState.overdue || state == ReminderState.due;
    final dose = expectedDose(reminder, now);
    final nextLabel = '${relativeDayLabel(dose, now)} ${formatHourMinute(dose.hour, dose.minute)}';

    // A paused row is dimmed, but its text stays readable (C3): the stripe
    // and the switch fade; the text steps down one tone instead of fading
    // below 4.5:1.
    final nameColor = paused ? AppTheme.fgMute : AppTheme.fg;
    final metaColor = paused ? AppTheme.fgDimText : AppTheme.fgMute;
    return LabTap(
      mergeSemantics: false,
      hint: 'Edit reminder',
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          border: topBorder ? const Border(top: BorderSide(color: AppTheme.borderSoft, width: 1)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(width: 3, height: 32, color: paused ? color.withValues(alpha: 0.55) : color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_name, style: AppTheme.sans(size: 13, weight: FontWeight.w500, color: nameColor)),
                      const SizedBox(height: 2),
                      Text(formatSchedule(reminder), style: AppTheme.sans(size: 11, color: metaColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(stateLabel, style: AppTheme.sans(size: 11, weight: FontWeight.w600, color: stateColor)),
                    const SizedBox(height: 2),
                    Text(nextLabel, style: AppTheme.sans(size: 11, color: metaColor)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 11),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: Row(
                children: [
                  if (actionable) ...[
                    _ActionButton(label: 'Log now', filled: true, onTap: onLogNow),
                    const SizedBox(width: 8),
                    _ActionButton(label: 'Skip', filled: false, onTap: onSkip),
                  ],
                  const Spacer(),
                  Opacity(
                    opacity: paused ? 0.55 : 1,
                    child: _PauseToggle(
                        key: ValueKey('reminder-toggle-${reminder.id}'),
                        paused: paused,
                        label: '$_name reminder',
                        onTap: onToggle),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.filled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return LabTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? AppTheme.accent : Colors.transparent,
          border: filled ? null : Border.all(color: AppTheme.border, width: 1),
        ),
        child: Text(label, style: AppTheme.sans(size: 11.5, weight: filled ? FontWeight.w600 : FontWeight.w500, color: filled ? AppTheme.bg : AppTheme.fgMute, letterSpacing: 0.2)),
      ),
    );
  }
}

/// On/off switch for one reminder; spoken as "Testosterone Enanthate
/// reminder, switch, on".
class _PauseToggle extends StatelessWidget {
  final bool paused;
  final String label;
  final VoidCallback onTap;
  const _PauseToggle({super.key, required this.paused, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return LabTap(
      toggled: !paused,
      label: label,
      onTap: onTap,
      child: Container(
        width: 34,
        height: 19,
        decoration: BoxDecoration(
          color: paused ? AppTheme.surface2 : AppTheme.accentDeep,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Align(
          alignment: paused ? Alignment.centerLeft : Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Container(width: 15, height: 15, decoration: BoxDecoration(shape: BoxShape.circle, color: paused ? AppTheme.fgDim : AppTheme.accent)),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 40, 22, 34),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Icon(Icons.water_drop_outlined, size: 40, color: AppTheme.fgMute.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('No reminders yet', style: AppTheme.serif(size: 18, weight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            'Set a schedule and ProtoLog will tell you when each compound is due — so nothing slips.',
            textAlign: TextAlign.center,
            style: AppTheme.sans(size: 12, color: AppTheme.fgMute, height: 1.5),
          ),
          const SizedBox(height: 18),
          LabTap(
            onTap: onCreate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              color: AppTheme.accent,
              child: Text('+ New reminder', style: AppTheme.sans(size: 12.5, weight: FontWeight.w600, color: AppTheme.bg, letterSpacing: 0.3)),
            ),
          ),
        ],
      ),
    );
  }
}
