import 'package:flutter/material.dart';
import '../../../engine/injection_draft.dart';
import '../../../models.dart';
import '../../format.dart';
import '../../theme.dart';
import '../../widgets/lab_tap.dart';

// Small building blocks shared by both steps of the add-injection wizard.
//
// WizardField / WizardSegmented / WizardPill look like LabField /
// LabSegmented / LabPill (lab_primitives.dart) but are not identical — label
// and segment text are 10/12 px instead of 9.5/11.5 px, labels and hints
// ellipsize, pills are 12 px with 12 px padding — so the wizard keeps its own.

/// Display color of a compound in the wizard: [resolver] (MainScreen's live
/// base → color resolver, so a library recolor shows here too — B26) when
/// given, else the redesign palette for its base, else its stored color.
Color wizardCompoundColor(CompoundDefinition c, [Color Function(String base)? resolver]) =>
    resolver?.call(c.base) ?? AppTheme.compoundColor(c.base) ?? Color(c.colorValue);

/// Unit of a compound's vial concentration: IU/mL for IU-native compounds
/// (HCG, HGH), mg/mL for everything else (including mcg-dosed peptides).
String concentrationUnitLabel(CompoundDefinition c) => c.unit == Unit.iu ? 'IU/mL' : 'mg/mL';

/// Inline note under a concentration over [maxConcentrationPerMl] (N5),
/// e.g. "Above 100000 mg/mL — check the value". [unitLabel] is "mg/mL" or
/// "IU/mL".
String concentrationTooHighMessage(String unitLabel) =>
    'Above ${formatDose(maxConcentrationPerMl)} $unitLabel — check the value';

/// [concentrationTooHighMessage] in the wizard's warning style.
class ConcentrationTooHighNote extends StatelessWidget {
  final String unitLabel;
  const ConcentrationTooHighNote({super.key, required this.unitLabel});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(concentrationTooHighMessage(unitLabel),
            key: const Key('concentration-too-high'),
            style: AppTheme.sans(size: 11.5, color: AppTheme.warn)),
      );
}

/// "3d ago" / "5h ago" / "12m ago" / "just now" — the wizard's age label for
/// a previous log.
String relativeAgo(DateTime then, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(then);
  if (diff.inDays >= 1) return '${diff.inDays}d ago';
  if (diff.inHours >= 1) return '${diff.inHours}h ago';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
  return 'just now';
}

/// Section heading: muted title with an optional dim note on the right.
class WizardSectionTitle extends StatelessWidget {
  final String title;
  final String? meta;

  const WizardSectionTitle(this.title, {super.key, this.meta});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: AppTheme.sans(size: 11, weight: FontWeight.w500, color: AppTheme.fgMute, letterSpacing: 0.4)),
          if (meta != null)
            Text(meta!, style: AppTheme.sans(size: 11, color: AppTheme.fgDimText)),
        ],
      ),
    );
  }
}

/// Selectable pill — type filters on step 1, quick times on step 2.
class WizardPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const WizardPill({super.key, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LabTap(
      selected: active,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.fg : Colors.transparent,
          border: Border.all(color: active ? AppTheme.fg : AppTheme.border, width: 1),
        ),
        child: Text(
          label,
          style: AppTheme.sans(
            size: 12,
            weight: FontWeight.w500,
            color: active ? AppTheme.bg : AppTheme.fgMute,
          ),
        ),
      ),
    );
  }
}

/// A labeled input shell: surface bg + 1px border + uppercase label row + optional right-side hint.
class WizardField extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget child;
  final VoidCallback? onTap;

  const WizardField({
    super.key,
    required this.label,
    this.hint,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(label.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sans(size: 10, color: AppTheme.fgDimText, letterSpacing: 0.8)),
              ),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(hint!,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: AppTheme.mono(size: 10, color: AppTheme.fgDimText)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
    if (onTap == null) return body;
    return LabTap(onTap: onTap, child: body);
  }
}

/// A segmented control. `value` must be in `options`. `onChange` is called with the new value.
/// If `mono` is true, labels render in JetBrains Mono.
class WizardSegmented<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChange;
  final bool mono;

  const WizardSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChange,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
      child: Row(
        children: [
          for (int i = 0; i < options.length; i++) ...[
            if (i > 0) Container(width: 1, color: AppTheme.border),
            Expanded(
              child: LabTap(
                selected: options[i] == value,
                inMutuallyExclusiveGroup: true,
                onTap: () => onChange(options[i]),
                child: Container(
                  alignment: Alignment.center,
                  color: options[i] == value ? AppTheme.fg : Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Builder(
                    builder: (_) {
                      final style = mono
                          ? AppTheme.mono(
                              size: 12,
                              weight: options[i] == value ? FontWeight.w600 : FontWeight.w400,
                              color: options[i] == value ? AppTheme.bg : AppTheme.fgMute,
                              letterSpacing: 0.2,
                            )
                          : AppTheme.sans(
                              size: 12,
                              weight: options[i] == value ? FontWeight.w600 : FontWeight.w400,
                              color: options[i] == value ? AppTheme.bg : AppTheme.fgMute,
                              letterSpacing: 0.2,
                            );
                      return Text(labelOf(options[i]), style: style);
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
