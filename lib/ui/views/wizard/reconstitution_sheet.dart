import 'package:flutter/material.dart';
import '../../../models.dart';
import '../../../utils.dart';
import '../../../engine/dose_math.dart';
import '../../../engine/injection_draft.dart';
import '../../theme.dart';
import 'wizard_widgets.dart';

/// Opens the reconstitution calculator (amount per vial + diluent volume →
/// concentration). Resolves to the concentration (per mL, in
/// [massUnitLabel]) when the user taps "Use this", else null.
Future<double?> showReconstitutionSheet(
  BuildContext context, {
  required bool isPeptide,
  required Unit doseUnit,
  required String massUnitLabel,
}) {
  return showModalBottomSheet<double>(
    context: context,
    backgroundColor: AppTheme.bg,
    isScrollControlled: true,
    builder: (ctx) => ReconstitutionSheet(
      initialMgPerVial: null,
      initialVolume: null,
      isPeptide: isPeptide,
      doseUnit: doseUnit,
      massUnitLabel: massUnitLabel,
    ),
  );
}

class ReconstitutionSheet extends StatefulWidget {
  final double? initialMgPerVial;
  final double? initialVolume;
  final bool isPeptide;
  final Unit doseUnit; // the wizard's selected dose unit
  final String massUnitLabel; // 'mg' for mass-dosed, 'IU' for IU-native
  const ReconstitutionSheet({
    super.key,
    required this.initialMgPerVial,
    required this.initialVolume,
    required this.isPeptide,
    required this.doseUnit,
    this.massUnitLabel = 'mg',
  });

  @override
  State<ReconstitutionSheet> createState() => _ReconstitutionSheetState();
}

class _ReconstitutionSheetState extends State<ReconstitutionSheet> {
  late final TextEditingController _mg = TextEditingController(
      text: widget.initialMgPerVial?.toString() ?? '');
  late final TextEditingController _vol = TextEditingController(
      text: widget.initialVolume?.toString() ?? '');
  String _volUnit = 'mL'; // 'mL' or 'IU'

  @override
  void dispose() {
    _mg.dispose();
    _vol.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mg = parseFlexibleDouble(_mg.text) ?? 0;
    final volRaw = parseFlexibleDouble(_vol.text) ?? 0;
    // At U100, 100 IU = 1 mL.
    final volMl = _volUnit == 'IU' ? mlFromSyringeUnits(volRaw) : volRaw;
    final conc = (mg > 0 && volMl > 0) ? (mg / volMl) : 0.0;
    // N5: a result over the limit is shown but can't be used.
    final tooHigh = isConcentrationTooHigh(conc);
    final usable = conc > 0 && !tooHigh;
    // The "X per 10 IU" line is the syringe-reading hint, only useful when
    // the dose unit is mass (mcg). IU-native compounds dose in IU directly.
    // Expressed in the dose unit so it reads the same as the Amount field.
    final per10 = (usable && widget.isPeptide && widget.massUnitLabel == 'mg')
        ? doseForVolume(
            volumeMl: mlFromSyringeUnits(10),
            concentration: conc,
            unit: widget.doseUnit,
            iuConcentration: false,
          )
        : null;
    final iuLine = per10 != null
        ? '≈ ${per10.toStringAsFixed(widget.doseUnit == Unit.mcg ? 0 : 2)} '
            '${widget.doseUnit.name} per 10 IU'
        : null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.bg,
            border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Reconstitute vial',
                        style: AppTheme.serif(
                            size: 18, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.3)),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text('×', style: AppTheme.sans(size: 18, color: AppTheme.fgMute)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _sheetField('${widget.massUnitLabel} per vial', _mg)),
                    const SizedBox(width: 8),
                    Expanded(child: _volField()),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conc > 0
                          ? '${conc.toStringAsFixed(2)} ${widget.massUnitLabel}/mL'
                          : '— ${widget.massUnitLabel}/mL',
                      style: AppTheme.mono(size: 22, weight: FontWeight.w500, color: AppTheme.fg),
                    ),
                    if (iuLine != null) ...[
                      const SizedBox(height: 4),
                      Text(iuLine, style: AppTheme.sans(size: 11, color: AppTheme.fgMute)),
                    ],
                    if (tooHigh) ConcentrationTooHighNote(unitLabel: '${widget.massUnitLabel}/mL'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: usable ? () => Navigator.of(context).pop(conc) : null,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: usable ? AppTheme.accent : AppTheme.surface2,
                  child: Text('Use this',
                      style: AppTheme.sans(
                          size: 13,
                          weight: FontWeight.w600,
                          color: usable ? AppTheme.bg : AppTheme.fgDim,
                          letterSpacing: 0.3)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _volField() {
    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text('RECONSTITUTION',
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sans(size: 10, color: AppTheme.fgDim, letterSpacing: 0.8)),
              ),
              const SizedBox(width: 6),
              // Compact mL/IU toggle.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _volUnit = _volUnit == 'mL' ? 'IU' : 'mL'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
                  child: Text(_volUnit,
                      style: AppTheme.mono(size: 10, weight: FontWeight.w600, color: AppTheme.fg)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _vol,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            cursorColor: AppTheme.accent,
            style: AppTheme.serif(
                size: 22, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.4, height: 1.1),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: '0',
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetField(String label, TextEditingController ctl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: AppTheme.sans(size: 10, color: AppTheme.fgDim, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          TextField(
            controller: ctl,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            cursorColor: AppTheme.accent,
            style: AppTheme.serif(
                size: 22, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.4, height: 1.1),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: '0',
            ),
          ),
        ],
      ),
    );
  }
}
