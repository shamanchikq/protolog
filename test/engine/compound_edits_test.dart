import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/compound_edits.dart';

CompoundDefinition _def({
  String base = 'Testosterone',
  String ester = 'Enanthate',
  CompoundType type = CompoundType.steroid,
  GraphType graphType = GraphType.curve,
  double halfLife = 4.5,
  double timeToPeak = 1.5,
  double ratio = 0.72,
  Unit unit = Unit.mg,
  int colorValue = 0xFF10B981,
}) =>
    CompoundDefinition(
      id: 'x',
      base: base,
      ester: ester,
      type: type,
      graphType: graphType,
      halfLife: halfLife,
      timeToPeak: timeToPeak,
      ratio: ratio,
      unit: unit,
      colorValue: colorValue,
    );

Injection _inj(CompoundDefinition snap, {String id = 'i', double mg = 100}) =>
    Injection(
      id: id,
      compoundId: snap.id,
      date: DateTime(2026, 1, 1),
      dosage: mg,
      snapshot: snap,
      site: 'Quad L',
      notes: 'n',
    );

void main() {
  group('rewriteSnapshots', () {
    test('updates curve params on matching injections', () {
      final inj = _inj(_def(halfLife: 4.5, timeToPeak: 1.5, ratio: 0.72));
      final out = rewriteSnapshots(
        injections: [inj],
        base: 'Testosterone',
        ester: 'Enanthate',
        halfLife: 6.0,
        timeToPeak: 2.0,
        ratio: 0.6,
        graphType: GraphType.curve,
      );
      expect(out.single.snapshot.halfLife, 6.0);
      expect(out.single.snapshot.timeToPeak, 2.0);
      expect(out.single.snapshot.ratio, 0.6);
    });

    test('leaves non-matching injections untouched (same instance)', () {
      final other = _inj(_def(base: 'Trenbolone', ester: 'Acetate'), id: 'o');
      final out = rewriteSnapshots(
        injections: [other],
        base: 'Testosterone',
        ester: 'Enanthate',
        halfLife: 6.0,
        timeToPeak: 2.0,
        ratio: 0.6,
        graphType: GraphType.curve,
      );
      expect(identical(out.single, other), isTrue);
    });

    test('preserves dosage, unit, color, identity, site, notes', () {
      final inj = _inj(_def(unit: Unit.mg, colorValue: 0xFF10B981), mg: 250);
      final out = rewriteSnapshots(
        injections: [inj],
        base: 'Testosterone',
        ester: 'Enanthate',
        halfLife: 6.0,
        timeToPeak: 2.0,
        ratio: 0.6,
        graphType: GraphType.curve,
      );
      final s = out.single;
      expect(s.dosage, 250);
      expect(s.snapshot.unit, Unit.mg);
      expect(s.snapshot.colorValue, 0xFF10B981);
      expect(s.snapshot.base, 'Testosterone');
      expect(s.snapshot.ester, 'Enanthate');
      expect(s.site, 'Quad L');
      expect(s.notes, 'n');
    });

    test('updates graphType on matching peptide (window -> event)', () {
      final inj = _inj(_def(
        base: 'Semaglutide',
        ester: 'None',
        type: CompoundType.peptide,
        graphType: GraphType.activeWindow,
      ));
      final out = rewriteSnapshots(
        injections: [inj],
        base: 'Semaglutide',
        ester: 'None',
        halfLife: 7.0,
        timeToPeak: 2.0,
        ratio: 1.0,
        graphType: GraphType.event,
      );
      expect(out.single.snapshot.graphType, GraphType.event);
    });

    test('does not mutate the original injection snapshot', () {
      final inj = _inj(_def(halfLife: 4.5));
      rewriteSnapshots(
        injections: [inj],
        base: 'Testosterone',
        ester: 'Enanthate',
        halfLife: 6.0,
        timeToPeak: 2.0,
        ratio: 0.6,
        graphType: GraphType.curve,
      );
      expect(inj.snapshot.halfLife, 4.5);
    });

    test('only rewrites matching rows in a mixed list', () {
      final test = _inj(_def(), id: 't');
      final tren = _inj(_def(base: 'Trenbolone', ester: 'Acetate'), id: 'tr');
      final out = rewriteSnapshots(
        injections: [test, tren],
        base: 'Testosterone',
        ester: 'Enanthate',
        halfLife: 6.0,
        timeToPeak: 2.0,
        ratio: 0.6,
        graphType: GraphType.curve,
      );
      expect(out[0].snapshot.halfLife, 6.0);
      expect(out[1].snapshot.halfLife, 4.5); // tren default, untouched
    });
  });
}
