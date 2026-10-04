import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/wizard/compound_catalog.dart';

/// Pins what the wizard's compound picker lists (wizard/compound_catalog.dart),
/// including where it deliberately differs from `cataloguedCompounds`.
void main() {
  final testE = BASE_LIBRARY['Testosterone Enanthate']!;
  final hcg = BASE_LIBRARY['HCG']!;
  const customSteroid = CompoundDefinition(
    id: 'x', base: 'Zeta', ester: 'Acetate', type: CompoundType.steroid,
    graphType: GraphType.curve, halfLife: 1, timeToPeak: 0.5, ratio: 1,
    unit: Unit.mg, colorValue: 0xFF000000, isCustom: true,
  );
  const customPeptide = CompoundDefinition(
    id: 'k', base: 'Kisspeptin', ester: 'None', type: CompoundType.peptide,
    graphType: GraphType.event, halfLife: 0.2, timeToPeak: 0.05, ratio: 1,
    unit: Unit.mcg, colorValue: 0xFF000000, isCustom: true,
  );

  test('typeForFilter maps filter keys, defaulting to steroid', () {
    expect(typeForFilter('steroid'), CompoundType.steroid);
    expect(typeForFilter('oral'), CompoundType.oral);
    expect(typeForFilter('peptide'), CompoundType.peptide);
    expect(typeForFilter('ancillary'), CompoundType.ancillary);
    expect(typeForFilter('bogus'), CompoundType.steroid);
  });

  test('matchesCompoundSearch: case-insensitive on base or ester, blank matches all', () {
    expect(matchesCompoundSearch(testE, ''), isTrue);
    expect(matchesCompoundSearch(testE, '   '), isTrue);
    expect(matchesCompoundSearch(testE, 'TESTO'), isTrue);
    expect(matchesCompoundSearch(testE, 'enan'), isTrue);
    expect(matchesCompoundSearch(testE, 'tren'), isFalse);
  });

  test('esterCountForBase unions user and library steroid esters', () {
    expect(esterCountForBase('Testosterone', const []), 6);
    expect(esterCountForBase('Boldenone', const []), 1);
    expect(esterCountForBase('Zeta', const [customSteroid]), 1);
    final extra = testE.copyWith(id: 'b', ester: 'Besylate');
    expect(esterCountForBase('Testosterone', [extra, testE.copyWith(id: 'te')]), 7);
  });

  test('steroid bases: user compounds first, then BASE_LIBRARY order', () {
    final bases = pickerCompounds(
      type: CompoundType.steroid, drillBase: null, query: '', userCompounds: const [customSteroid],
    ).map((c) => c.base).toList();
    expect(bases, ['Zeta', 'Testosterone', 'Nandrolone', 'Trenbolone', 'Boldenone', 'Masteron', 'Primobolan', 'DHB']);
  });

  test('drilled into a base: one row per ester, user copy first', () {
    final copy = testE.copyWith(id: 'te', halfLife: 9);
    final rows = pickerCompounds(
      type: CompoundType.steroid, drillBase: 'Testosterone', query: '', userCompounds: [copy],
    );
    expect(rows.map((c) => c.ester).toList(),
        ['Enanthate', 'Suspension', 'Propionate', 'Cypionate', 'Undecanoate', 'Sustanon (Mix)']);
    expect(rows.first.halfLife, 9);
  });

  test('drilled in with duplicate user copies: the last one is listed (B6)', () {
    final rows = pickerCompounds(
      type: CompoundType.steroid,
      drillBase: 'Testosterone',
      query: '',
      userCompounds: [testE.copyWith(id: 'a', halfLife: 5), testE.copyWith(id: 'b', halfLife: 6)],
    );
    expect(rows.first.ester, 'Enanthate');
    expect(rows.first.id, 'b');
    expect(rows.where((c) => c.ester == 'Enanthate'), hasLength(1));
  });

  test('non-steroids: library row stands for a user copy; true customs listed under their type', () {
    final staleCopy = hcg.copyWith(id: 'h', type: CompoundType.ancillary, halfLife: 3);
    final peptides = pickerCompounds(
      type: CompoundType.peptide, drillBase: null, query: '', userCompounds: [staleCopy, customPeptide],
    );
    final hcgRow = peptides.singleWhere((c) => c.base == 'HCG');
    expect(hcgRow.halfLife, 1.2); // the library entry, not the copy
    expect(peptides.last.base, 'Kisspeptin');
    final ancillaries = pickerCompounds(
      type: CompoundType.ancillary, drillBase: null, query: '', userCompounds: [staleCopy],
    );
    expect(ancillaries.any((c) => c.base == 'HCG'), isFalse);
  });

  test('query filters the list', () {
    final rows = pickerCompounds(
      type: CompoundType.steroid, drillBase: null, query: 'tren', userCompounds: const [],
    );
    expect(rows.map((c) => c.base), ['Trenbolone']);
  });

  test('catalogCompoundFor prefers the user copy (the last of duplicates, B6), then the library', () {
    final a = testE.copyWith(id: 'a');
    final b = testE.copyWith(id: 'b');
    expect(catalogCompoundFor('Testosterone', 'Enanthate', [a, b])!.id, 'b');
    expect(catalogCompoundFor('Testosterone', 'Enanthate', const [])!.halfLife, 4.5);
    expect(catalogCompoundFor('Nope', 'None', const []), isNull);
  });

  test('recentCompounds: newest first, one per base, max 3, re-resolved to the catalog', () {
    final now = DateTime(2026, 5, 18);
    Injection log(CompoundDefinition snap, int daysAgo) => Injection(
        id: '$daysAgo', compoundId: snap.id, date: now.subtract(Duration(days: daysAgo)),
        dosage: 1, snapshot: snap);
    final cyp = BASE_LIBRARY['Testosterone Cypionate']!;
    final tren = BASE_LIBRARY['Trenbolone Acetate']!;
    final npp = BASE_LIBRARY['Nandrolone Phenylpropionate']!;
    final bold = BASE_LIBRARY['Boldenone Undecylenate']!;
    final copy = testE.copyWith(id: 'te', halfLife: 9);
    final recent = recentCompounds(
      type: CompoundType.steroid,
      userCompounds: [copy],
      injections: [log(cyp, 5), log(testE, 1), log(tren, 2), log(hcg, 0), log(npp, 3), log(bold, 4)],
    );
    expect(recent.map((r) => r.compound.base), ['Testosterone', 'Trenbolone', 'Nandrolone']);
    expect(recent.first.compound.halfLife, 9); // the user's copy, not the snapshot
    expect(recent.first.lastDate, now.subtract(const Duration(days: 1)));
  });
}
