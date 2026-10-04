import 'package:flutter/material.dart';
import '../../../models.dart';
import '../../format.dart';
import '../../theme.dart';
import 'wizard_widgets.dart';

/// Header of the details step: "Step 2 of 2 / Dose & time" with Back, or
/// "Editing logged dose / Edit dose" with Cancel in edit mode.
class DetailsHeader extends StatelessWidget {
  final bool isEdit;

  /// Back to step 1 — or, in edit mode (no step 1), close the wizard.
  final VoidCallback onBack;

  const DetailsHeader({super.key, required this.isEdit, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Editing logged dose' : 'Step 2 of 2',
                  style: AppTheme.sans(size: 11, color: AppTheme.fgDim)),
              const SizedBox(height: 4),
              Text(isEdit ? 'Edit dose' : 'Dose & time',
                  style: AppTheme.serif(
                      size: 22, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.4)),
            ],
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onBack,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
            child: Text(isEdit ? 'Cancel' : 'Back',
                style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
        ),
      ],
    );
  }
}

/// The compound being logged: name (+ ester for steroids), t½ and the vial
/// concentration draft, with a "Change" link back to step 1 when [onChange]
/// is given.
class SelectedCompoundChip extends StatelessWidget {
  final CompoundDefinition compound;
  final double? concentration;
  final VoidCallback? onChange;

  /// Live base → color resolver (see [wizardCompoundColor]).
  final Color Function(String base)? colorResolver;

  const SelectedCompoundChip({
    super.key,
    required this.compound,
    required this.concentration,
    required this.onChange,
    this.colorResolver,
  });

  @override
  Widget build(BuildContext context) {
    final c = compound;
    final color = wizardCompoundColor(c, colorResolver);
    final esterPart = (c.type == CompoundType.steroid &&
            c.ester.isNotEmpty &&
            c.ester.toLowerCase() != 'none')
        ? ' ${c.ester}'
        : '';
    final concPart = concentration != null
        ? '${formatDose(concentration!)} ${concentrationUnitLabel(c)}'
        : 'concentration unset';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: color, width: 2),
          left: BorderSide(color: AppTheme.border, width: 1),
          right: BorderSide(color: AppTheme.border, width: 1),
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: c.base,
                        style: AppTheme.sans(size: 14, weight: FontWeight.w600, color: AppTheme.fg, letterSpacing: -0.2),
                      ),
                      TextSpan(
                        text: esterPart,
                        style: AppTheme.sans(size: 14, weight: FontWeight.w400, color: AppTheme.fgMute, letterSpacing: -0.2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text('t½ ${c.halfLife.toStringAsFixed(1)}d · $concPart',
                    style: AppTheme.sans(size: 11, color: AppTheme.fgDim)),
              ],
            ),
          ),
          if (onChange != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onChange,
              child: Text('Change',
                  style: AppTheme.sans(size: 11, color: AppTheme.accent)),
            ),
        ],
      ),
    );
  }
}

/// "Last: 250 mg · 7d ago" under the chip.
class LastLogLine extends StatelessWidget {
  final Injection last;

  const LastLogLine({super.key, required this.last});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Last: ${formatDose(last.dosage)} ${last.snapshot.unit.name} · ${relativeAgo(last.date)}',
      style: AppTheme.sans(size: 11, color: AppTheme.accent),
    );
  }
}

/// Optional free-text notes for the log.
class NotesSection extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const NotesSection({super.key, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WizardSectionTitle('Notes', meta: 'optional'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            minLines: 1,
            maxLines: 3,
            cursorColor: AppTheme.accent,
            style: AppTheme.sans(size: 13, color: AppTheme.fg),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: 'Add a note…',
              hintStyle: AppTheme.sans(size: 13, color: AppTheme.fgDim),
            ),
          ),
        ),
      ],
    );
  }
}
