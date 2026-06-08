import 'package:flutter/material.dart';
import '../../models.dart';
import '../theme.dart';
import '../../engine/reminder_schedule.dart';
import '../../engine/library_stats.dart';

class RemindersPage extends StatelessWidget {
  final List<Reminder> reminders;
  final List<CompoundDefinition> userCompounds;
  final DateTime now;
  final void Function(Reminder? editing) onEditReminder;
  final void Function(Reminder) onToggleEnabled;
  final void Function(Reminder) onLogNow;
  final void Function(Reminder) onSkip;

  RemindersPage({
    super.key,
    required this.reminders,
    required this.userCompounds,
    required this.onEditReminder,
    required this.onToggleEnabled,
    required this.onLogNow,
    required this.onSkip,
    DateTime? now,
  }) : now = now ?? DateTime.now();

  Color _colorFor(Reminder r) {
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? meta;
  const _SectionHeader({required this.title, this.meta});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title.toUpperCase(), style: AppTheme.sans(size: 10, color: AppTheme.fgDim, letterSpacing: 1.1)),
        if (meta != null) Text(meta!, style: AppTheme.sans(size: 10, color: AppTheme.fgDim, letterSpacing: 0.4)),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final List<Reminder> reminders;
  final DateTime now;
  final Color Function(Reminder) colorOf;
  const _WeekStrip({required this.reminders, required this.now, required this.colorOf});

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final agenda = weekAgenda(reminders, now, 7, colorOf);
    final startDay = DateTime(now.year, now.month, now.day);
    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: _dayCell(startDay.add(Duration(days: i)), i == 0, agenda[i])),
        ],
      ],
    );
  }

  Widget _dayCell(DateTime d, bool today, List<Color> colors) {
    final fg = today ? AppTheme.paperInk : AppTheme.fg;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: today ? AppTheme.paper : Colors.transparent,
        border: Border.all(color: today ? AppTheme.paperInk : AppTheme.borderSoft, width: 1),
      ),
      child: Column(
        children: [
          Text(_wd[d.weekday - 1], style: AppTheme.sans(size: 10, color: today ? AppTheme.paperInk : AppTheme.fgDim)),
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
        ReminderState.paused => (AppTheme.fgDim, 'Paused'),
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
    final nextLabel = '${relativeDayLabel(dose, now)} ${dose.hour.toString().padLeft(2, '0')}:${dose.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: paused ? 0.55 : 1,
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
                  Container(width: 3, height: 32, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_name, style: AppTheme.sans(size: 13, weight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(formatSchedule(reminder), style: AppTheme.sans(size: 11, color: AppTheme.fgMute)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(stateLabel, style: AppTheme.sans(size: 11, weight: FontWeight.w600, color: stateColor)),
                      const SizedBox(height: 2),
                      Text(nextLabel, style: AppTheme.sans(size: 11, color: AppTheme.fgMute)),
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
                    _PauseToggle(paused: paused, onTap: onToggle),
                  ],
                ),
              ),
            ],
          ),
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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

class _PauseToggle extends StatelessWidget {
  final bool paused;
  final VoidCallback onTap;
  const _PauseToggle({required this.paused, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
          GestureDetector(
            onTap: onCreate,
            behavior: HitTestBehavior.opaque,
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
