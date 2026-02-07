import 'models.dart';

const Map<String, CompoundDefinition> BASE_LIBRARY = {
  // Testosterone
  'Testosterone Suspension': CompoundDefinition(id: 'temp', base: 'Testosterone', ester: 'Suspension', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 0.05, defaultHalfLife: 0.05, timeToPeak: 0.02, ratio: 1.0, unit: Unit.mg, colorValue: 0xFF10B981),
  'Testosterone Propionate': CompoundDefinition(id: 'temp', base: 'Testosterone', ester: 'Propionate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 0.8, defaultHalfLife: 0.8, timeToPeak: 0.4, ratio: 0.83, unit: Unit.mg, colorValue: 0xFF10B981),
  'Testosterone Enanthate': CompoundDefinition(id: 'temp', base: 'Testosterone', ester: 'Enanthate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 4.5, defaultHalfLife: 4.5, timeToPeak: 1.5, ratio: 0.72, unit: Unit.mg, colorValue: 0xFF10B981),
  'Testosterone Cypionate': CompoundDefinition(id: 'temp', base: 'Testosterone', ester: 'Cypionate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 5.0, defaultHalfLife: 5.0, timeToPeak: 1.8, ratio: 0.69, unit: Unit.mg, colorValue: 0xFF10B981),
  'Testosterone Undecanoate': CompoundDefinition(id: 'temp', base: 'Testosterone', ester: 'Undecanoate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 21.0, defaultHalfLife: 21.0, timeToPeak: 7.0, ratio: 0.63, unit: Unit.mg, colorValue: 0xFF10B981),
  'Sustanon 250': CompoundDefinition(id: 'temp', base: 'Testosterone', ester: 'Sustanon (Mix)', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 15.0, defaultHalfLife: 15.0, timeToPeak: 1.5, ratio: 0.70, unit: Unit.mg, colorValue: 0xFF10B981),

  // Nandrolone
  'Nandrolone Phenylpropionate': CompoundDefinition(id: 'temp', base: 'Nandrolone', ester: 'Phenylpropionate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 2.5, defaultHalfLife: 2.5, timeToPeak: 1.0, ratio: 0.67, unit: Unit.mg, colorValue: 0xFF3B82F6),
  'Nandrolone Decanoate': CompoundDefinition(id: 'temp', base: 'Nandrolone', ester: 'Decanoate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 7.5, defaultHalfLife: 7.5, timeToPeak: 2.5, ratio: 0.64, unit: Unit.mg, colorValue: 0xFF3B82F6),

  // Trenbolone
  'Trenbolone Acetate': CompoundDefinition(id: 'temp', base: 'Trenbolone', ester: 'Acetate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 1.5, defaultHalfLife: 1.5, timeToPeak: 0.8, ratio: 0.83, unit: Unit.mg, colorValue: 0xFFEF4444),
  'Trenbolone Enanthate': CompoundDefinition(id: 'temp', base: 'Trenbolone', ester: 'Enanthate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 10.5, defaultHalfLife: 10.5, timeToPeak: 2.5, ratio: 0.70, unit: Unit.mg, colorValue: 0xFFEF4444),
  'Trenbolone Hexahydrobenzylcarbonate': CompoundDefinition(id: 'temp', base: 'Trenbolone', ester: 'Hexahydrobenzylcarbonate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 8.0, defaultHalfLife: 8.0, timeToPeak: 2.0, ratio: 0.68, unit: Unit.mg, colorValue: 0xFFEF4444),
  'Tri-Tren': CompoundDefinition(id: 'temp', base: 'Trenbolone', ester: 'Tri-Tren (Mix)', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 7.0, defaultHalfLife: 7.0, timeToPeak: 1.7, ratio: 0.72, unit: Unit.mg, colorValue: 0xFFEF4444),

  // Boldenone
  'Boldenone Undecylenate': CompoundDefinition(id: 'temp', base: 'Boldenone', ester: 'Undecylenate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 14.0, defaultHalfLife: 14.0, timeToPeak: 4.0, ratio: 0.61, unit: Unit.mg, colorValue: 0xFF6366F1),

  // Masteron (Drostanolone)
  'Drostanolone Propionate': CompoundDefinition(id: 'temp', base: 'Masteron', ester: 'Propionate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 1.5, defaultHalfLife: 1.5, timeToPeak: 0.5, ratio: 0.84, unit: Unit.mg, colorValue: 0xFFF59E0B),
  'Drostanolone Enanthate': CompoundDefinition(id: 'temp', base: 'Masteron', ester: 'Enanthate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 5.0, defaultHalfLife: 5.0, timeToPeak: 1.5, ratio: 0.70, unit: Unit.mg, colorValue: 0xFFF59E0B),

  // Primobolan (Methenolone)
  'Methenolone Enanthate': CompoundDefinition(id: 'temp', base: 'Primobolan', ester: 'Enanthate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 10.5, defaultHalfLife: 10.5, timeToPeak: 3.0, ratio: 0.70, unit: Unit.mg, colorValue: 0xFF8B5CF6),

  // DHB (Dihydroboldenone)
  'Dihydroboldenone Cypionate': CompoundDefinition(id: 'temp', base: 'DHB', ester: 'Cypionate', type: CompoundType.steroid, graphType: GraphType.curve, halfLife: 5.0, defaultHalfLife: 5.0, timeToPeak: 1.8, ratio: 0.69, unit: Unit.mg, colorValue: 0xFF6366F1),

  // Orals
  'Oxandrolone': CompoundDefinition(id: 'temp', base: 'Oxandrolone', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.4, defaultHalfLife: 0.4, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFD946EF),
  'Methandienone': CompoundDefinition(id: 'temp', base: 'Methandienone', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.2, defaultHalfLife: 0.2, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFEC4899),
  'Methasterone': CompoundDefinition(id: 'temp', base: 'Methasterone', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.35, defaultHalfLife: 0.35, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFF43F5E),
  'Oxymetholone': CompoundDefinition(id: 'temp', base: 'Oxymetholone', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.35, defaultHalfLife: 0.35, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFBE123C),
  'Stanozolol': CompoundDefinition(id: 'temp', base: 'Stanozolol', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.4, defaultHalfLife: 0.4, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFF59E0B),
  'Turinabol': CompoundDefinition(id: 'temp', base: 'Turinabol', ester: 'None', type: CompoundType.oral, graphType: GraphType.curve, halfLife: 0.35, defaultHalfLife: 0.35, timeToPeak: 0.1, ratio: 1.0, unit: Unit.mg, colorValue: 0xFFD946EF),

  // Peptides
  'HGH': CompoundDefinition(id: 'temp', base: 'HGH', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.15, defaultHalfLife: 0.15, timeToPeak: 0.1, ratio: 1, unit: Unit.iu, colorValue: 0xFF0EA5E9),
  'Semaglutide': CompoundDefinition(id: 'temp', base: 'Semaglutide', ester: 'None', type: CompoundType.peptide, graphType: GraphType.activeWindow, halfLife: 7.0, defaultHalfLife: 7.0, timeToPeak: 2.0, ratio: 1, unit: Unit.mcg, colorValue: 0xFF06B6D4),
  'Tirzepatide': CompoundDefinition(id: 'temp', base: 'Tirzepatide', ester: 'None', type: CompoundType.peptide, graphType: GraphType.activeWindow, halfLife: 5.0, defaultHalfLife: 5.0, timeToPeak: 2.0, ratio: 1, unit: Unit.mg, colorValue: 0xFF8B5CF6),
  'Retatrutide': CompoundDefinition(id: 'temp', base: 'Retatrutide', ester: 'None', type: CompoundType.peptide, graphType: GraphType.activeWindow, halfLife: 6.0, defaultHalfLife: 6.0, timeToPeak: 2.0, ratio: 1, unit: Unit.mg, colorValue: 0xFF818CF8),
  'BPC-157': CompoundDefinition(id: 'temp', base: 'BPC-157', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.25, defaultHalfLife: 0.25, timeToPeak: 0.1, ratio: 1, unit: Unit.mcg, colorValue: 0xFF14B8A6),
  'TB-500': CompoundDefinition(id: 'temp', base: 'TB-500', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 1.5, defaultHalfLife: 1.5, timeToPeak: 0.1, ratio: 1, unit: Unit.mcg, colorValue: 0xFF2DD4BF),
  'MT2': CompoundDefinition(id: 'temp', base: 'Melanotan II', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.1, defaultHalfLife: 0.1, timeToPeak: 0.1, ratio: 1, unit: Unit.mcg, colorValue: 0xFFA855F7),
  'CJC-1295 no DAC': CompoundDefinition(id: 'temp', base: 'CJC-1295', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.1, defaultHalfLife: 0.1, timeToPeak: 0.1, ratio: 1, unit: Unit.mcg, colorValue: 0xFF34D399),
  'Ipamorelin': CompoundDefinition(id: 'temp', base: 'Ipamorelin', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.1, defaultHalfLife: 0.1, timeToPeak: 0.1, ratio: 1, unit: Unit.mcg, colorValue: 0xFF6EE7B7),
  'GHK-Cu': CompoundDefinition(id: 'temp', base: 'GHK-Cu', ester: 'None', type: CompoundType.peptide, graphType: GraphType.event, halfLife: 0.1, defaultHalfLife: 0.1, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFF3B82F6),

  // Ancillaries
  'HCG': CompoundDefinition(id: 'temp', base: 'HCG', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.activeWindow, halfLife: 1.2, defaultHalfLife: 1.2, timeToPeak: 0.25, ratio: 1, unit: Unit.iu, colorValue: 0xFFEC4899),
  'Anastrazole': CompoundDefinition(id: 'temp', base: 'Anastrazole', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.activeWindow, halfLife: 2.1, defaultHalfLife: 2.1, timeToPeak: 0.5, ratio: 1, unit: Unit.mg, colorValue: 0xFF94A3B8),
  'Tamoxifen': CompoundDefinition(id: 'temp', base: 'Tamoxifen', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.activeWindow, halfLife: 6.0, defaultHalfLife: 6.0, timeToPeak: 0.5, ratio: 1, unit: Unit.mg, colorValue: 0xFF94A3B8),
  'Finasteride': CompoundDefinition(id: 'temp', base: 'Finasteride', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.event, halfLife: 0.25, defaultHalfLife: 0.25, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFF94A3B8),
  'Dutasteride': CompoundDefinition(id: 'temp', base: 'Dutasteride', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.activeWindow, halfLife: 35.0, defaultHalfLife: 35.0, timeToPeak: 0.5, ratio: 1, unit: Unit.mg, colorValue: 0xFF94A3B8),
  'Clomiphene': CompoundDefinition(id: 'temp', base: 'Clomiphene', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.event, halfLife: 5.0, defaultHalfLife: 5.0, timeToPeak: 0.5, ratio: 1.0, unit: Unit.mg, colorValue: 0xFF94A3B8),
  'Enclomiphene': CompoundDefinition(id: 'temp', base: 'Enclomiphene', ester: 'None', type: CompoundType.ancillary, graphType: GraphType.event, halfLife: 0.5, defaultHalfLife: 0.5, timeToPeak: 0.15, ratio: 1.0, unit: Unit.mg, colorValue: 0xFF94A3B8),
};

const Map<String, Ester> ESTER_LIBRARY = {
  'Suspension': Ester(name: 'Suspension', halfLife: 0.05, timeToPeak: 0.02, molecularWeightRatio: 1.0),
  'Acetate': Ester(name: 'Acetate', halfLife: 1.0, timeToPeak: 0.3, molecularWeightRatio: 0.83),
  'Propionate': Ester(name: 'Propionate', halfLife: 0.8, timeToPeak: 0.4, molecularWeightRatio: 0.80),
  'Phenylpropionate': Ester(name: 'Phenylpropionate', halfLife: 2.5, timeToPeak: 1.0, molecularWeightRatio: 0.66),
  'Enanthate': Ester(name: 'Enanthate', halfLife: 4.5, timeToPeak: 1.5, molecularWeightRatio: 0.70),
  'Cypionate': Ester(name: 'Cypionate', halfLife: 5.0, timeToPeak: 1.8, molecularWeightRatio: 0.69),
  'Decanoate': Ester(name: 'Decanoate', halfLife: 7.0, timeToPeak: 2.5, molecularWeightRatio: 0.62),
  'Undecanoate': Ester(name: 'Undecanoate', halfLife: 20.9, timeToPeak: 6.0, molecularWeightRatio: 0.61),
  'Hexahydrobenzylcarbonate': Ester(name: 'Hexahydrobenzylcarbonate', halfLife: 8.0, timeToPeak: 2.0, molecularWeightRatio: 0.68),
  'Sustanon': Ester(name: 'Sustanon (Mix)', halfLife: 15.0, timeToPeak: 1.0, molecularWeightRatio: 0.71),
  'Tri-Tren': Ester(name: 'Tri-Tren (Mix)', halfLife: 7.0, timeToPeak: 1.7, molecularWeightRatio: 0.72),
  'None': Ester(name: 'None', halfLife: 0.05, timeToPeak: 0.02, molecularWeightRatio: 1.0),
};

const List<Map<String, double>> SUSTANON_BLEND = [
  {'fraction': 0.12, 'halfLife': 0.8, 'timeToPeak': 0.4, 'ratio': 0.83},   // Propionate 30mg
  {'fraction': 0.24, 'halfLife': 2.5, 'timeToPeak': 1.0, 'ratio': 0.66},   // Phenylpropionate 60mg
  {'fraction': 0.24, 'halfLife': 4.0, 'timeToPeak': 1.5, 'ratio': 0.72},   // Isocaproate 60mg
  {'fraction': 0.40, 'halfLife': 15.0, 'timeToPeak': 2.0, 'ratio': 0.65},   // Decanoate 100mg
];

const List<Map<String, double>> TREN_BLEND = [
  {'fraction': 0.20, 'halfLife': 1.5, 'timeToPeak': 0.8, 'ratio': 0.83},   // Acetate
  {'fraction': 0.50, 'halfLife': 10.5, 'timeToPeak': 2.5, 'ratio': 0.70},   // Enanthate
  {'fraction': 0.30, 'halfLife': 8.0, 'timeToPeak': 2.0, 'ratio': 0.68},   // Hexahydrobenzylcarbonate
];

// Initial data for first time app load
final List<CompoundDefinition> INITIAL_COMPOUNDS = [
  BASE_LIBRARY['Testosterone Cypionate']!.copyWith(id: 'test-c'),
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