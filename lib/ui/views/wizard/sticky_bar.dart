import 'package:flutter/material.dart';
import '../../../models.dart';
import '../../../utils.dart';
import '../../../engine/dose_math.dart';
import '../../../engine/injection_draft.dart';
import '../../../engine/reminder_schedule.dart';
import '../../theme.dart';

/// Bottom bar of the details step: the linked-reminder banner (if any), a
/// "LOGGING 250 mg · glute R" summary and the Confirm button, which is inert
/// until [doseText] parses to a positive dose.
class WizardStickyBar extends StatelessWidget {
  final CompoundDefinition? compound;
  final String doseText;
  final Unit unit;
  final String site;
  final bool isEdit;

  /// The reminder this log can advance (null in edit mode).
  final Reminder? linkedReminder;
  final bool advanceReminder;
  final VoidCallback onToggleAdvance;
  final VoidCallback onSubmit;

  const WizardStickyBar({
    super.key,
    required this.compound,
    required this.doseText,
    required this.unit,
    required this.site,
    required this.isEdit,
    required this.linkedReminder,
    required this.advanceReminder,
    required this.onToggleAdvance,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final c = compound;
    final doseVal = parseFlexibleDouble(doseText) ?? 0;
    final hasDose = doseVal > 0;
    final isPillForm = c != null && isPillFormType(c.type);
    final showSite = c != null && !isPillForm;
    final siteShort = (showSite && site.isNotEmpty)
        ? ' · ${site.replaceFirst('Vent. ', '')}'
        : '';
    final matched = linkedReminder;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (matched != null)
          ReminderBanner(
            reminder: matched,
            advance: advanceReminder,
            onToggle: onToggleAdvance,
          ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isEdit ? 'EDITING' : 'LOGGING',
                      style: AppTheme.sans(size: 10, color: AppTheme.fgDim, letterSpacing: 0.6)),
                  const SizedBox(height: 2),
                  Text(
                    hasDose
                        ? '${formatAmount(doseVal)} ${unit.name}$siteShort'
                        : '—',
                    style: AppTheme.mono(size: 14, weight: FontWeight.w500, color: AppTheme.fg),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: hasDose ? onSubmit : null,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    color: hasDose ? AppTheme.accent : AppTheme.surface2,
                    child: Text(
                        isEdit
                            ? 'Save changes'
                            : (isPillForm ? 'Log administration' : 'Log injection'),
                        style: AppTheme.sans(
                            size: 13,
                            weight: FontWeight.w600,
                            color: hasDose ? AppTheme.bg : AppTheme.fgDim,
                            letterSpacing: 0.3)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Linked to your X reminder · Next due …" with the Advance checkbox.
class ReminderBanner extends StatelessWidget {
  final Reminder reminder;
  final bool advance;
  final VoidCallback onToggle;

  const ReminderBanner({
    super.key,
    required this.reminder,
    required this.advance,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final next = nextOccurrence(r, DateTime.now());
    final label = '${relativeDayLabel(next, DateTime.now())} '
        '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Linked to your ${r.compoundBase} reminder',
                    style: AppTheme.sans(size: 12, weight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('Next due $label', style: AppTheme.sans(size: 11, color: AppTheme.fgMute)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: advance ? AppTheme.accent : Colors.transparent,
                    border: Border.all(color: advance ? AppTheme.accent : AppTheme.border, width: 1),
                  ),
                  child: advance
                      ? const Icon(Icons.check, size: 13, color: AppTheme.bg)
                      : null,
                ),
                const SizedBox(width: 6),
                Text('Advance', style: AppTheme.sans(size: 11, color: AppTheme.fgMute)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
