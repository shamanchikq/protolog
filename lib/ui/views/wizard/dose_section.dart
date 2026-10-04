import 'package:flutter/material.dart';
import '../../../models.dart';
import '../../../utils.dart';
import '../../../engine/dose_math.dart';
import '../../../engine/injection_draft.dart';
import '../../format.dart';
import '../../theme.dart';
import 'wizard_widgets.dart';
import '../../widgets/lab_tap.dart';

/// "Dose" section of the details step: Direct amount + unit, or By volume
/// (concentration × volume, U-100 syringe readings for peptides). Pill-form
/// compounds only get Direct.
///
/// The wizard owns the text controllers and draft values; this widget only
/// renders them and reports edits. In By-volume mode the computed dose is
/// handed back through [onVolumeDoseComputed] after the frame, so the sticky
/// bar and Confirm read one dose text in both modes.
class DoseSection extends StatelessWidget {
  final CompoundDefinition compound;

  /// 'direct' | 'volume'.
  final String mode;
  final Unit unit;
  final String doseText;
  final String volumeText;

  /// 'mL' | 'IU' (U-100 syringe units) — only offered for peptides.
  final String volumeInputUnit;
  final double? concentration;
  final TextEditingController doseController;
  final TextEditingController volumeController;
  final TextEditingController concController;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onDoseChanged;
  final ValueChanged<Unit> onUnitChanged;
  final ValueChanged<String> onVolumeChanged;
  final ValueChanged<String> onVolumeInputUnitChanged;

  /// A typed concentration: the positive value, or null when unusable.
  final ValueChanged<double?> onConcentrationChanged;

  /// Peptides set their concentration through the reconstitution sheet.
  final VoidCallback onOpenReconstitution;

  /// Called after the frame with the By-volume dose text when it differs
  /// from [doseText].
  final ValueChanged<String> onVolumeDoseComputed;

  const DoseSection({
    super.key,
    required this.compound,
    required this.mode,
    required this.unit,
    required this.doseText,
    required this.volumeText,
    required this.volumeInputUnit,
    required this.concentration,
    required this.doseController,
    required this.volumeController,
    required this.concController,
    required this.onModeChanged,
    required this.onDoseChanged,
    required this.onUnitChanged,
    required this.onVolumeChanged,
    required this.onVolumeInputUnitChanged,
    required this.onConcentrationChanged,
    required this.onOpenReconstitution,
    required this.onVolumeDoseComputed,
  });

  bool get _isPeptide => compound.type == CompoundType.peptide;
  bool get _isPillForm => isPillFormType(compound.type);
  // "IU-native" compounds (HCG, HGH, etc.) — their stored unit is iu and
  // their vial concentration is IU/mL rather than mg/mL. Every other compound
  // stores mg/mL, even when dosed in mcg — conversions go through
  // engine/dose_math.dart, which applies the mg↔mcg factor.
  bool get _isIuNative => compound.unit == Unit.iu;
  String get _concentrationUnit => concentrationUnitLabel(compound);

  /// [concentration] when it can be used for a conversion: one over
  /// [maxConcentrationPerMl] is flagged in By-volume mode and never used
  /// (N5).
  double? get _usableConcentration =>
      isConcentrationTooHigh(concentration) ? null : concentration;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WizardSectionTitle('Dose'),
        if (!_isPillForm) ...[
          WizardSegmented<String>(
            value: mode,
            options: const ['direct', 'volume'],
            labelOf: (s) => s == 'direct' ? 'Direct' : 'By volume',
            onChange: onModeChanged,
          ),
          const SizedBox(height: 8),
        ],
        if (mode == 'direct' || _isPillForm) _buildDoseDirect() else _buildDoseByVolume(),
      ],
    );
  }

  Widget _buildDoseDirect() {
    final dose = parseFlexibleDouble(doseText) ?? 0;
    final ml = dose > 0
        ? volumeForDose(
            dose: dose,
            concentration: _usableConcentration,
            unit: unit,
            iuConcentration: _isIuNative,
          )
        : null;
    String? hint;
    if (ml != null) {
      // U100 syringe-reading hint only adds value for mass-dosed peptides;
      // IU-native compounds are already dosed in IU so the equivalent is the
      // dose itself.
      if (unit == Unit.mcg) {
        final iu = syringeUnitsFromMl(ml);
        hint = '≈ ${ml.toStringAsFixed(2)} mL · ${iu.toStringAsFixed(1)} IU';
      } else {
        hint = '≈ ${ml.toStringAsFixed(2)} mL';
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: WizardField(
            label: 'Amount',
            hint: hint,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: LabTextFieldTarget(
                    label: 'Amount',
                    child: TextField(
                      controller: doseController,
                      onChanged: onDoseChanged,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      cursorColor: AppTheme.accent,
                      style: AppTheme.serif(
                          size: 32, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.8, height: 1.1),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: '0',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(unit.name, style: AppTheme.sans(size: 13, color: AppTheme.fgMute)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: WizardField(
            label: 'Unit',
            child: WizardSegmented<Unit>(
              value: unit,
              options: doseUnitOptions(compound.unit),
              labelOf: (u) => u.name,
              onChange: onUnitChanged,
              mono: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDoseByVolume() {
    final conc = _usableConcentration;
    final tooHigh = isConcentrationTooHigh(concentration);
    final volumeRaw = parseFlexibleDouble(volumeText) ?? 0;
    // Convert the user-entered volume to mL using the U100 standard
    // (100 IU = 1 mL) when they're inputting in IU.
    final volumeMl = (_isPeptide && volumeInputUnit == 'IU')
        ? mlFromSyringeUnits(volumeRaw)
        : volumeRaw;
    // Null when the concentration is unset (or can't express unit).
    final dose = doseForVolume(
      volumeMl: volumeMl,
      concentration: conc,
      unit: unit,
      iuConcentration: _isIuNative,
    );
    final computedDose = dose ?? 0.0;
    String volumeHint = '';
    if (dose != null && volumeRaw > 0) {
      if (unit == Unit.mcg) {
        // Mass-dosed peptide: show the syringe-reading IU equivalent.
        final mlPart = formatDose(volumeMl);
        final iuPart = syringeUnitsFromMl(volumeMl).toStringAsFixed(1);
        if (volumeInputUnit == 'IU') {
          volumeHint = '= ${formatDose(computedDose)} ${unit.name} · $mlPart mL';
        } else {
          volumeHint = '= ${formatDose(computedDose)} ${unit.name} ≈ $iuPart IU';
        }
      } else if (_isPeptide && volumeInputUnit == 'IU') {
        // IU-native peptide and user entered IU volume: just show the dose
        // and the mL equivalent of the volume.
        final mlPart = formatDose(volumeMl);
        volumeHint = '= ${formatDose(computedDose)} ${unit.name} · $mlPart mL';
      } else {
        volumeHint = '= ${formatDose(computedDose)} ${unit.name}';
      }
    }
    // Keep the wizard's dose text in sync so the sticky bar / confirm logic stays simple.
    final computedDoseText = computedDose > 0 ? formatAmount(computedDose) : '';
    if (doseText != computedDoseText) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onVolumeDoseComputed(computedDoseText));
    }
    final shown = concentration;
    final concDisplay = (shown != null) ? formatDose(shown) : '—';
    // Peptides get a tap → reconstitution sheet (mg + bac → mg/mL).
    // Steroids/anything else: edit the concentration directly as a number.
    final Widget concField = _isPeptide
        ? WizardField(
            label: 'Concentration',
            hint: (shown == null) ? 'tap to calculate' : 'from vial',
            onTap: onOpenReconstitution,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(concDisplay,
                    style: AppTheme.serif(
                        size: 28, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.6, height: 1.1)),
                const SizedBox(width: 6),
                Text(_concentrationUnit, style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
              ],
            ),
          )
        : WizardField(
            label: 'Concentration',
            hint: 'from vial',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: LabTextFieldTarget(
                    label: 'Concentration',
                    child: TextField(
                      controller: concController,
                      onChanged: (v) {
                        final parsed = parseFlexibleDouble(v);
                        onConcentrationChanged((parsed != null && parsed > 0) ? parsed : null);
                      },
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      cursorColor: AppTheme.accent,
                      style: AppTheme.serif(
                          size: 28, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.6, height: 1.1),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: '0',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(_concentrationUnit, style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
              ],
            ),
          );
    final fields = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: concField),
          const SizedBox(width: 8),
          Expanded(
            child: WizardField(
              label: 'Volume',
              hint: volumeHint.isEmpty ? null : volumeHint,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: LabTextFieldTarget(
                      label: 'Volume',
                      child: TextField(
                        controller: volumeController,
                        enabled: conc != null && conc > 0,
                        onChanged: onVolumeChanged,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        cursorColor: AppTheme.accent,
                        style: AppTheme.serif(
                            size: 28,
                            weight: FontWeight.w500,
                            color: (conc != null && conc > 0) ? AppTheme.fg : AppTheme.fgDim,
                            letterSpacing: -0.6,
                            height: 1.1),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          hintText: '0',
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                if (_isPeptide)
                  SizedBox(
                    width: 84,
                    child: WizardSegmented<String>(
                      value: volumeInputUnit,
                      options: const ['mL', 'IU'],
                      labelOf: (s) => s,
                      onChange: onVolumeInputUnitChanged,
                      mono: true,
                    ),
                  )
                else
                  Text('mL', style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (!tooHigh) return fields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [fields, ConcentrationTooHighNote(unitLabel: _concentrationUnit)],
    );
  }
}
