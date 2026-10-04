import 'package:flutter/material.dart';
import '../../../models.dart';
import '../../../utils.dart';
import '../../../engine/dose_math.dart';
import '../../../engine/injection_draft.dart';
import '../../../engine/reminder_schedule.dart';
import '../../format.dart';
import '../../theme.dart';

/// "That's 10× your last dose (250 mcg)" / "That's 10× less than your last
/// dose (250 mcg)" for a [ratio] from [unusualDoseRatio] against [last].
String unusualDoseMessage(double ratio, Injection last) {
  final lastText = '${formatDose(last.dosage)} ${last.snapshot.unit.name}';
  return ratio >= 1
      ? "That's ${_factor(ratio)}× your last dose ($lastText)"
      : "That's ${_factor(1 / ratio)}× less than your last dose ($lastText)";
}

/// 3.2 → "3.2", 4.0 → "4", 12.4 → "12", 1000 → "1000".
String _factor(double f) =>
    f >= 10 ? f.round().toString() : stripTrailingZeros(f.toStringAsFixed(1));

/// Bottom bar of the details step: the linked-reminder banner (if any), a
/// "LOGGING 250 mg · glute R" summary and the Confirm button, which is inert
/// until [doseText] parses to a positive dose. A soft [doseWarning] (G5)
/// sits above the summary; it never blocks Confirm.
class WizardStickyBar extends StatelessWidget {
  final CompoundDefinition? compound;
  final String doseText;
  final Unit unit;
  final String site;
  final bool isEdit;

  /// Shown above the summary when the dose looks unusual, e.g. "That's 10×
  /// your last dose (250 mcg)" (see [unusualDoseMessage]).
  final String? doseWarning;

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
    this.doseWarning,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (doseWarning != null) ...[
                Text(doseWarning!, style: AppTheme.sans(size: 11.5, color: AppTheme.warn)),
                const SizedBox(height: 8),
              ],
              _buildSummaryRow(hasDose: hasDose, doseVal: doseVal, siteShort: siteShort, isPillForm: isPillForm),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow({
    required bool hasDose,
    required double doseVal,
    required String siteShort,
    required bool isPillForm,
  }) {
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isEdit ? 'EDITING' : 'LOGGING',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.sans(size: 10, color: AppTheme.fgDim, letterSpacing: 0.6)),
        const SizedBox(height: 2),
        Text(
          hasDose
              ? '${formatAmount(doseVal)} ${unit.name}$siteShort'
              : '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.mono(size: 14, weight: FontWeight.w500, color: AppTheme.fg),
        ),
      ],
    );
    final button = GestureDetector(
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
    );
    // The summary keeps its natural width (the button fills the rest) up to
    // half the bar, then ellipsizes: a long dose or site, or large text,
    // overflowed the row (C1).
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: (box.maxWidth - 14) / 2),
            child: summary,
          ),
          const SizedBox(width: 14),
          Expanded(child: button),
        ],
      ),
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
