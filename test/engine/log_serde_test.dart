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

    test('skips rows whose compound cannot be resolved', () {
      const unknown = '''
| Date | Compound | Ester | Dosage | Unit |
|------|----------|-------|--------|------|
| 01/06/2026 08:30 | Nonexistium | Enanthate | 150.0 | mg |
''';
      final parsed = parseMarkdownLog(unknown, userCompounds: [_testE], existing: []);
      expect(parsed, isEmpty);
    });
  });
}
