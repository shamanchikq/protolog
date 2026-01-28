import 'models.dart';

const Map<String, CompoundDefinition> BASE_LIBRARY = {
  // Injectables
  'Testosterone': CompoundDefinition(id: 'temp', base: 'Testosterone', ester: '', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 0, timeToPeak: 0, ratio: 1, unit: Unit.mg, colorValue: 0xFF10B981),
  'Nandrolone': CompoundDefinition(id: 'temp', base: 'Nandrolone', ester: '', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 0, timeToPeak: 0, ratio: 1, unit: Unit.mg, colorValue: 0xFF3B82F6),
  'Trenbolone': CompoundDefinition(id: 'temp', base: 'Trenbolone', ester: '', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 0, timeToPeak: 0, ratio: 1, unit: Unit.mg, colorValue: 0xFFEF4444),
  'Masteron': CompoundDefinition(id: 'temp', base: 'Masteron', ester: '', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 0, timeToPeak: 0, ratio: 1, unit: Unit.mg, colorValue: 0xFFF59E0B),
  'Primobolan': CompoundDefinition(id: 'temp', base: 'Primobolan', ester: '', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 0, timeToPeak: 0, ratio: 1, unit: Unit.mg, colorValue: 0xFF8B5CF6),
  'Boldenone': CompoundDefinition(id: 'temp', base: 'Boldenone', ester: '', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 0, timeToPeak: 0, ratio: 1, unit: Unit.mg, colorValue: 0xFF6366F1),

  // Orals
  'Oxandrolone': CompoundDefinition(id: 'temp', base: 'Oxandrolone', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.4, defaultHalfLife: 0.4, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFD946EF),
  'Methandienone': CompoundDefinition(id: 'temp', base: 'Methandienone', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.2, defaultHalfLife: 0.2, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFEC4899),
  'Methasterone': CompoundDefinition(id: 'temp', base: 'Methasterone', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.35, defaultHalfLife: 0.35, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFF43F5E),
  'Oxymetholone': CompoundDefinition(id: 'temp', base: 'Oxymetholone', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.35, defaultHalfLife: 0.35, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFBE123C),
  'Stanozolol': CompoundDefinition(id: 'temp', base: 'Stanozolol', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.4, defaultHalfLife: 0.4, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFF59E0B),

  // Peptides
  'HGH': CompoundDefinition(id: 'temp', base: 'HGH', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.15, defaultHalfLife: 0.15, timeToPeak: 0.1, ratio: 1, unit: Unit.iu, colorValue: 0xFF0EA5E9),
  'Semaglutide': CompoundDefinition(id: 'temp', base: 'Semaglutide', ester: 'None', type: CompoundType.peptide, graphType: GraphType.activeWindow, halfLife: 7.0, defaultHalfLife: 7.0, timeToPeak: 2.0, ratio: 1, unit: Unit.mcg, colorValue: 0xFF06B6D4),
  'Tirzepatide': CompoundDefinition(id: 'temp', base: 'Tirzepatide', ester: 'None', type: CompoundType.peptide, graphType: GraphType.activeWindow, halfLife: 5.0, defaultHalfLife: 5.0, timeToPeak: 2.0, ratio: 1, unit: Unit.mg, colorValue: 0xFF8B5CF6),
  'Retatrutide': CompoundDefinition(id: 'temp', base: 'Retatrutide', ester: 'None', type: CompoundType.peptide, graphType: GraphType.activeWindow, halfLife: 6.0, defaultHalfLife: 6.0, timeToPeak: 2.0, ratio: 1, unit: Unit.mg, colorValue: 0xFF818CF8),
  'BPC-157': CompoundDefinition(id: 'temp', base: 'BPC-157', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.25, defaultHalfLife: 0.25, timeToPeak: 0.1, ratio: 1, unit: Unit.mcg, colorValue: 0xFF14B8A6),
  'TB-500': CompoundDefinition(id: 'temp', base: 'TB-500', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 1.5, defaultHalfLife: 1.5, timeToPeak: 0.1, ratio: 1, unit: Unit.mcg, colorValue: 0xFF2DD4BF),
  'MT2': CompoundDefinition(id: 'temp', base: 'Melanotan II', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.1, defaultHalfLife: 0.1, timeToPeak: 0.1, ratio: 1, unit: Unit.mcg, colorValue: 0xFFA855F7),
  'CJC-1295': CompoundDefinition(id: 'temp', base: 'CJC-1295', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.1, defaultHalfLife: 7.0, timeToPeak: 0.1, ratio: 1, unit: Unit.mcg, colorValue: 0xFF34D399),
  'Ipamorelin': CompoundDefinition(id: 'temp', base: 'Ipamorelin', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.1, defaultHalfLife: 0.1, timeToPeak: 0.1, ratio: 1, unit: Unit.mcg, colorValue: 0xFF6EE7B7),
  'GHK-Cu': CompoundDefinition(id: 'temp', base: 'GHK-Cu', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.1, defaultHalfLife: 0.1, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFF3B82F6),

  // Ancillaries
  'HCG': CompoundDefinition(id: 'temp', base: 'HCG', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.activeWindow, halfLife: 1.5, defaultHalfLife: 1.5, timeToPeak: 0.25, ratio: 1, unit: Unit.iu, colorValue: 0xFFEC4899),
  'Anastrazole': CompoundDefinition(id: 'temp', base: 'Anastrazole', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.activeWindow, halfLife: 2.1, defaultHalfLife: 2.1, timeToPeak: 0.5, ratio: 1, unit: Unit.mg, colorValue: 0xFF94A3B8),
  'Tamoxifen': CompoundDefinition(id: 'temp', base: 'Tamoxifen', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.event, halfLife: 6.0, defaultHalfLife: 6.0, timeToPeak: 0.5, ratio: 1, unit: Unit.mg, colorValue: 0xFF94A3B8),
  'Finasteride': CompoundDefinition(id: 'temp', base: 'Finasteride', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.activeWindow, halfLife: 0.25, defaultHalfLife: 0.25, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFF94A3B8),
  'Dutasteride': CompoundDefinition(id: 'temp', base: 'Dutasteride', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.activeWindow, halfLife: 35.0, defaultHalfLife: 35.0, timeToPeak: 0.5, ratio: 1, unit: Unit.mg, colorValue: 0xFF94A3B8),
};

const Map<String, Ester> ESTER_LIBRARY = {
  'Suspension': Ester(name: 'Suspension', halfLife: 0.1, timeToPeak: 0.04, molecularWeightRatio: 1.0),
  'Acetate': Ester(name: 'Acetate', halfLife: 1.0, timeToPeak: 0.3, molecularWeightRatio: 0.83),
  'Propionate': Ester(name: 'Propionate', halfLife: 0.8, timeToPeak: 0.4, molecularWeightRatio: 0.80),
  'Phenylpropionate': Ester(name: 'Phenylpropionate', halfLife: 2.5, timeToPeak: 1.0, molecularWeightRatio: 0.66),
  'Enanthate': Ester(name: 'Enanthate', halfLife: 4.5, timeToPeak: 1.5, molecularWeightRatio: 0.70),
  'Cypionate': Ester(name: 'Cypionate', halfLife: 5.0, timeToPeak: 1.8, molecularWeightRatio: 0.69),
  'Decanoate': Ester(name: 'Decanoate', halfLife: 7.0, timeToPeak: 2.5, molecularWeightRatio: 0.62),
  'Undecanoate': Ester(name: 'Undecanoate', halfLife: 20.9, timeToPeak: 6.0, molecularWeightRatio: 0.61),
  'Sustanon': Ester(name: 'Sustanon (Mix)', halfLife: 15.0, timeToPeak: 1.0, molecularWeightRatio: 0.71),
  'None': Ester(name: 'None', halfLife: 0.15, timeToPeak: 0.1, molecularWeightRatio: 1.0),
};

// Initial data for first time app load
final List<CompoundDefinition> INITIAL_COMPOUNDS = [
  BASE_LIBRARY['Testosterone']!.copyWith(id: 'test-c', ester: 'Cypionate', halfLife: 5.0, timeToPeak: 1.8, ratio: 0.69),
  BASE_LIBRARY['Oxandrolone']!.copyWith(id: 'anavar'),
];

extension CopyWith on CompoundDefinition {
  CompoundDefinition copyWith({String? id, String? ester, double? halfLife, double? timeToPeak, double? ratio}) {
    return CompoundDefinition(
      id: id ?? this.id,
      base: base,
      ester: ester ?? this.ester,
      type: type,
      graphType: graphType,
      halfLife: halfLife ?? this.halfLife,
      defaultHalfLife: defaultHalfLife,
      timeToPeak: timeToPeak ?? this.timeToPeak,
      ratio: ratio ?? this.ratio,
      unit: unit,
      colorValue: colorValue,
      isCustom: isCustom,
    );
  }
}