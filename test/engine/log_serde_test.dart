import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/log_serde.dart';

const _testE = CompoundDefinition(
  id: 'test_e',
  base: 'Testosterone',
  ester: 'Enanthate',
  type: CompoundType.steroid,
  graphType: GraphType.curve,
  halfLife: 4.5,
  timeToPeak: 1.5,
  ratio: 0.72,
  unit: Unit.mg,
  colorValue: 0xFF5DC59C,
);

Injection _inj({
  DateTime? date,
  double dosage = 150.0,
  String? site,
  String? notes,
}) {
  final d = date ?? DateTime(2026, 6, 1, 8, 30);
  return Injection(
    id: '${d.millisecondsSinceEpoch}_Testosterone',
    compoundId: 'test_e',
    date: d,
    dosage: dosage,
    snapshot: _testE,
    site: site,
    notes: notes,
  );
}

void main() {
  group('injectionsToMarkdown', () {
    test('emits 7-column header including Site and Notes', () {
      final md = injectionsToMarkdown([_inj()]);
      expect(md, contains('| Date | Compound | Ester | Dosage | Unit | Site | Notes |'));
    });

    test('writes site and notes cells', () {
      final md = injectionsToMarkdown([_inj(site: 'Delt L', notes: 'pip next day')]);
      expect(md, contains('| Delt L | pip next day |'));
    });

    test('sanitizes pipes and newlines in notes', () {
      final md = injectionsToMarkdown([_inj(notes: 'a|b\nc')]);
      expect(md, contains('a/b c'));
      expect(md, isNot(contains('a|b')));
    });
  });

  group('parseMarkdownLog', () {
    test('round-trips site and notes', () {
      final original = _inj(site: 'Vent. glute R', notes: 'smooth');
      final md = injectionsToMarkdown([original]);
      final parsed = parseMarkdownLog(md, userCompounds: [_testE], existing: []);
      expect(parsed, hasLength(1));
      expect(parsed.first.dosage, 150.0);
      expect(parsed.first.date, DateTime(2026, 6, 1, 8, 30));
      expect(parsed.first.site, 'Vent. glute R');
      expect(parsed.first.notes, 'smooth');
      expect(parsed.first.snapshot.base, 'Testosterone');
      expect(parsed.first.snapshot.ester, 'Enanthate');
    });

    test('parses legacy 5-column rows with null site/notes', () {
      const legacy = '''
| Date | Compound | Ester | Dosage | Unit |
|------|----------|-------|--------|------|
| 01/06/2026 08:30 | Testosterone | Enanthate | 150.0 | mg |
''';
      final parsed = parseMarkdownLog(legacy, userCompounds: [_testE], existing: []);
      expect(parsed, hasLength(1));
      expect(parsed.first.site, isNull);
      expect(parsed.first.notes, isNull);
    });

    test('skips rows that already exist (same compound, date, dosage)', () {
      final existing = _inj();
      final md = injectionsToMarkdown([existing]);
      final parsed =
          parseMarkdownLog(md, userCompounds: [_testE], existing: [existing]);
      expect(parsed, isEmpty);
    });

    test('same-minute rows with different doses get distinct ids', () {
      const md = '''
| Date | Compound | Ester | Dosage | Unit | Site | Notes |
|------|----------|-------|--------|------|------|-------|
| 01/06/2026 08:30 | Testosterone | Enanthate | 150.0 | mg |  |  |
| 01/06/2026 08:30 | Testosterone | Enanthate | 100.0 | mg |  |  |
''';
      final parsed = parseMarkdownLog(md, userCompounds: [_testE], existing: []);
      expect(parsed, hasLength(2));
      expect(parsed[0].id, isNot(parsed[1].id));
    });

    test('skips rows whose compound cannot be resolved', () {
      const unknown = '''
| Date | Compound | Ester | Dosage | Unit |
|------|----------|-------|--------|------|
| 01/06/2026 08:30 | Nonexistium | Enanthate | 150.0 | mg |
''';
      final parsed = parseMarkdownLog(unknown, userCompounds: [_testE], existing: []);
      expect(parsed, isEmpty);
    });

    test('built-in rows link to the library key, never a shared placeholder id (B7)', () {
      const md = '''
| Date | Compound | Ester | Dosage | Unit | Site | Notes |
|------|----------|-------|--------|------|------|-------|
| 01/06/2026 08:30 | Testosterone | Cypionate | 125.0 | mg |  |  |
| 02/06/2026 08:30 | Oxandrolone |  | 20.0 | mg |  |  |
''';
      final parsed = parseMarkdownLog(md, userCompounds: const [], existing: const []);
      expect(parsed, hasLength(2));
      expect(parsed[0].compoundId, 'Testosterone Cypionate');
      expect(parsed[0].snapshot.id, 'Testosterone Cypionate');
      expect(parsed[1].compoundId, 'Oxandrolone');
      expect(parsed[1].snapshot.id, 'Oxandrolone');
    });
  });

  group('import ids are unique across imports (B21)', () {
    const testC = CompoundDefinition(
      id: 'test_c', base: 'Testosterone', ester: 'Cypionate',
      type: CompoundType.steroid, graphType: GraphType.curve,
      halfLife: 5.0, timeToPeak: 1.8, ratio: 0.69,
      unit: Unit.mg, colorValue: 0xFF5DC59C,
    );

    test('a later import never reuses an id already in the log', () {
      // First import gave the Enanthate row "<ms>_Testosterone_0".
      final first = parseMarkdownLog('''
| Date | Compound | Ester | Dosage | Unit | Site | Notes |
|------|----------|-------|--------|------|------|-------|
| 01/06/2026 08:30 | Testosterone | Enanthate | 150.0 | mg |  |  |
''', userCompounds: [_testE], existing: const []);
      expect(first, hasLength(1));

      // Re-import after adding the missing Cypionate: same minute, same base.
      final second = parseMarkdownLog('''
| Date | Compound | Ester | Dosage | Unit | Site | Notes |
|------|----------|-------|--------|------|------|-------|
| 01/06/2026 08:30 | Testosterone | Enanthate | 150.0 | mg |  |  |
| 01/06/2026 08:30 | Testosterone | Cypionate | 100.0 | mg |  |  |
''', userCompounds: [_testE, testC], existing: first);
      expect(second, hasLength(1));
      expect(second.single.snapshot.ester, 'Cypionate');
      expect(second.single.id, isNot(first.single.id));
    });

    test('ids stay distinct from every existing id and from each other', () {
      final d = DateTime(2026, 6, 1, 8, 30);
      final existing = [
        for (var n = 0; n < 3; n++)
          Injection(
            id: '${d.millisecondsSinceEpoch}_Testosterone_$n',
            compoundId: 'x',
            date: d,
            dosage: 10.0 + n,
            snapshot: _testE,
          ),
      ];
      final parsed = parseMarkdownLog('''
| Date | Compound | Ester | Dosage | Unit | Site | Notes |
|------|----------|-------|--------|------|------|-------|
| 01/06/2026 08:30 | Testosterone | Enanthate | 150.0 | mg |  |  |
| 01/06/2026 08:30 | Testosterone | Enanthate | 100.0 | mg |  |  |
''', userCompounds: [_testE], existing: existing);
      expect(parsed, hasLength(2));
      final ids = {...existing.map((i) => i.id), ...parsed.map((i) => i.id)};
      expect(ids, hasLength(5));
    });
  });

  group('table parsing (B22)', () {
    test('a row whose note contains --- is imported, not taken for the separator', () {
      final parsed = parseMarkdownLog('''
| Date | Compound | Ester | Dosage | Unit | Site | Notes |
|------|----------|-------|--------|------|------|-------|
| 01/06/2026 08:30 | Testosterone | Enanthate | 150.0 | mg | Delt L | pain --- none |
''', userCompounds: [_testE], existing: const []);
      expect(parsed, hasLength(1));
      expect(parsed.single.notes, 'pain --- none');
    });

    test('aligned separator rows (:---:) are still skipped', () {
      final parsed = parseMarkdownLog('''
| Date | Compound | Ester | Dosage | Unit |
|:-----|:--------:|-------|-------:|------|
| 01/06/2026 08:30 | Testosterone | Enanthate | 150.0 | mg |
''', userCompounds: [_testE], existing: const []);
      expect(parsed, hasLength(1));
    });

    test('duplicate rows within one paste are imported once', () {
      final parsed = parseMarkdownLog('''
| Date | Compound | Ester | Dosage | Unit | Site | Notes |
|------|----------|-------|--------|------|------|-------|
| 01/06/2026 08:30 | Testosterone | Enanthate | 150.0 | mg |  |  |
| 01/06/2026 08:30 | Testosterone | Enanthate | 150.0 | mg |  |  |
''', userCompounds: [_testE], existing: const []);
      expect(parsed, hasLength(1));
    });

    test('a paste without the header row keeps its first data row', () {
      final parsed = parseMarkdownLog('''
| 01/06/2026 08:30 | Testosterone | Enanthate | 150.0 | mg |  |  |
| 02/06/2026 08:30 | Testosterone | Enanthate | 100.0 | mg |  |  |
''', userCompounds: [_testE], existing: const []);
      expect(parsed, hasLength(2));
    });
  });
}
