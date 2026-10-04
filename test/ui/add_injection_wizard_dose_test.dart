import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/engine/library_stats.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the wizard hands back to its host.
class _Host {
  Injection? added;
  final List<CompoundDefinition> upserted = [];
}

/// Pumps the wizard straight onto the details step for [compound] (the same
/// path the Library "Log" action and reminder taps use).
Future<_Host> _pumpWizard(
  WidgetTester tester, {
  required CompoundDefinition compound,
  List<CompoundDefinition> userCompounds = const [],
  List<Injection> injections = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final host = _Host();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AddInjectionWizard(
        onAdd: (inj, _) => host.added = inj,
        reminders: const [],
        onCancel: () {},
        onSuccess: () {},
        userCompounds: userCompounds,
        addUserCompound: host.upserted.add,
        injections: injections,
        prefillCompound: compound,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return host;
}

/// The Amount field is the first TextField on the details step (Direct mode).
Finder get _amountField => find.byType(TextField).first;

void main() {
  final bpc = BASE_LIBRARY['BPC-157']!;
  final hcg = BASE_LIBRARY['HCG']!;
  final sema = BASE_LIBRARY['Semaglutide']!; // library unit: mcg

  Injection logOf(CompoundDefinition snapshot, double dosage, {int daysAgo = 7}) => Injection(
        id: 'last',
        compoundId: snapshot.id,
        date: DateTime.now().subtract(Duration(days: daysAgo)),
        dosage: dosage,
        snapshot: snapshot,
      );

  group('A1 — dose ↔ volume conversion is unit-aware', () {
    testWidgets('BPC-157 (mcg) at 2.5 mg/mL: direct hint, by-volume dose, logged dose',
        (tester) async {
      final host = await _pumpWizard(
        tester,
        compound: bpc,
        userCompounds: [bpc.copyWith(id: 'bpc', concentration: 2.5)],
      );
      expect(find.text('Dose & time'), findsOneWidget);

      // Direct: 250 mcg at 2.5 mg/mL is 0.10 mL = 10 units on a U-100 syringe.
      await tester.enterText(_amountField, '250');
      await tester.pump();
      expect(find.text('≈ 0.10 mL · 10.0 IU'), findsOneWidget);

      // By volume: 0.1 mL → 250 mcg (was 0.25 mcg).
      await tester.tap(find.text('By volume'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '0.'), '0.1');
      await tester.pump(); // rebuild with the new volume
      await tester.pump(); // post-frame dose sync
      expect(find.text('= 250 mcg ≈ 10.0 IU'), findsOneWidget);
      expect(find.text('250 mcg · Abdominal R'), findsOneWidget); // sticky bar

      // Volume entered as syringe units: 10 units = 0.1 mL = 250 mcg.
      await tester.tap(find.text('IU'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '0.1'), '10');
      await tester.pump();
      await tester.pump();
      expect(find.text('= 250 mcg · 0.1 mL'), findsOneWidget);

      await tester.tap(find.text('Log injection'));
      await tester.pump();
      expect(host.added, isNotNull);
      expect(host.added!.dosage, closeTo(250, 1e-9));
      expect(host.added!.snapshot.unit, Unit.mcg);
    });

    testWidgets('BPC-157 via reconstitution sheet: 5 mg + 2 mL → 0.1 mL logs 250 mcg',
        (tester) async {
      final host = await _pumpWizard(tester, compound: bpc);
      await tester.tap(find.text('By volume'));
      await tester.pump();

      await tester.tap(find.text('tap to calculate'));
      await tester.pumpAndSettle();
      final sheetFields = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(sheetFields.at(0), '5'); // mg per vial
      await tester.enterText(sheetFields.at(1), '2'); // mL bac water
      await tester.pump();
      expect(find.text('2.50 mg/mL'), findsOneWidget);
      expect(find.text('≈ 250 mcg per 10 IU'), findsOneWidget);
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '0.'), '0.1');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Log injection'));
      await tester.pump();
      expect(host.added!.dosage, closeTo(250, 1e-9));
      expect(host.added!.snapshot.unit, Unit.mcg);
      expect(host.added!.snapshot.concentration, 2.5); // persisted as mg/mL
    });

    testWidgets('BPC-157 switched to mg: 0.1 mL at 2.5 mg/mL logs 0.25 mg', (tester) async {
      final host = await _pumpWizard(
        tester,
        compound: bpc,
        userCompounds: [bpc.copyWith(id: 'bpc', concentration: 2.5)],
      );
      await tester.tap(find.text('mg'));
      await tester.pump();
      await tester.tap(find.text('By volume'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '0.'), '0.1');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Log injection'));
      await tester.pump();
      expect(host.added!.dosage, closeTo(0.25, 1e-9));
      expect(host.added!.snapshot.unit, Unit.mg);
    });

    testWidgets('HCG (IU-native) at 1000 IU/mL: direct hint and by-volume dose', (tester) async {
      final host = await _pumpWizard(
        tester,
        compound: hcg,
        userCompounds: [hcg.copyWith(id: 'hcg', concentration: 1000)],
      );
      await tester.enterText(_amountField, '250');
      await tester.pump();
      expect(find.text('≈ 0.25 mL'), findsOneWidget);

      await tester.tap(find.text('By volume'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '0.'), '0.25');
      await tester.pump();
      await tester.pump();
      expect(find.text('= 250 iu'), findsOneWidget);
      await tester.tap(find.text('Log injection'));
      await tester.pump();
      expect(host.added!.dosage, closeTo(250, 1e-9));
      expect(host.added!.snapshot.unit, Unit.iu);
    });
  });

  group('A2 — prefilled dose and unit come from the same source', () {
    testWidgets('Semaglutide last logged as 0.25 mg prefills 0.25 mg, not 0.25 mcg',
        (tester) async {
      final override = sema.copyWith(id: 'sema'); // stored unit = library mcg
      final host = await _pumpWizard(
        tester,
        compound: sema,
        userCompounds: [override],
        injections: [logOf(override.copyWith(unit: Unit.mg), 0.25)],
      );
      expect(find.widgetWithText(TextField, '0.25'), findsOneWidget);
      expect(find.text('0.25 mg · Abdominal R'), findsOneWidget); // sticky bar

      await tester.tap(find.text('Log injection'));
      await tester.pump();
      expect(host.added!.dosage, 0.25);
      expect(host.added!.snapshot.unit, Unit.mg);
      // Nothing about the compound changed, so nothing is written back.
      expect(host.upserted, isEmpty);
    });

    testWidgets('logging a built-in in another unit does not mark it edited', (tester) async {
      // First-ever log: the wizard materializes the built-in as a user copy.
      final host = await _pumpWizard(tester, compound: sema);
      await tester.tap(find.text('mg'));
      await tester.pump();
      await tester.enterText(_amountField, '0.5');
      await tester.pump();
      await tester.tap(find.text('Log injection'));
      await tester.pump();

      expect(host.added!.snapshot.unit, Unit.mg); // the log keeps its unit…
      expect(host.upserted, hasLength(1));
      expect(host.upserted.single.unit, Unit.mcg); // …the compound keeps its own
      expect(isEditedFromDefault(host.upserted.single), isFalse);
      expect(host.added!.compoundId, host.upserted.single.id);
    });

    testWidgets('existing user copy: logging in another unit does not rewrite its unit',
        (tester) async {
      final override = sema.copyWith(id: 'sema');
      final host = await _pumpWizard(tester, compound: sema, userCompounds: [override]);
      await tester.tap(find.text('mg'));
      await tester.pump();
      await tester.enterText(_amountField, '0.5');
      await tester.pump();
      await tester.tap(find.text('Log injection'));
      await tester.pump();

      expect(host.added!.snapshot.unit, Unit.mg);
      expect(host.added!.compoundId, 'sema');
      expect(host.upserted, isEmpty);
    });

    testWidgets('concentration edits are still persisted to the user copy', (tester) async {
      final override = sema.copyWith(id: 'sema');
      final host = await _pumpWizard(tester, compound: sema, userCompounds: [override]);
      await tester.tap(find.text('By volume'));
      await tester.pump();
      await tester.tap(find.text('tap to calculate'));
      await tester.pumpAndSettle();
      final sheetFields = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(sheetFields.at(0), '5');
      await tester.enterText(sheetFields.at(1), '2');
      await tester.pump();
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '0.'), '0.1');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Log injection'));
      await tester.pump();

      expect(host.upserted, hasLength(1));
      expect(host.upserted.single.concentration, 2.5);
      expect(host.upserted.single.unit, Unit.mcg);
      expect(isEditedFromDefault(host.upserted.single), isFalse);
      expect(host.added!.dosage, closeTo(250, 1e-9)); // 0.1 mL × 2.5 mg/mL
      expect(host.added!.snapshot.unit, Unit.mcg);
    });

    testWidgets('no prior log: the Compound Editor unit and PK are what the wizard shows',
        (tester) async {
      final override = sema.copyWith(id: 'sema', unit: Unit.mg, halfLife: 6.5);
      final host = await _pumpWizard(tester, compound: sema, userCompounds: [override]);
      // The chip shows the user's edited half-life (it is what gets frozen).
      expect(find.text('t½ 6.5d · concentration unset'), findsOneWidget);
      expect(tester.widget<TextField>(_amountField).controller!.text, isEmpty);

      await tester.enterText(_amountField, '1');
      await tester.pump();
      expect(find.text('1 mg · Abdominal R'), findsOneWidget);
      await tester.tap(find.text('Log injection'));
      await tester.pump();
      expect(host.added!.snapshot.unit, Unit.mg);
      expect(host.added!.snapshot.halfLife, 6.5);
      expect(host.upserted, isEmpty);
    });

    testWidgets('IU-native compounds only offer IU, even over a legacy mg log / copy',
        (tester) async {
      // Older versions let a dose be logged (and the copy stored) in any unit.
      final legacyCopy = hcg.copyWith(id: 'hcg', unit: Unit.mg);
      final host = await _pumpWizard(
        tester,
        compound: hcg,
        userCompounds: [legacyCopy],
        injections: [logOf(legacyCopy, 500)],
      );
      // A "500 mg" amount must not be re-offered as 500 IU.
      expect(find.widgetWithText(TextField, '500'), findsNothing);
      expect(find.text('mg'), findsNothing);
      expect(find.text('mcg'), findsNothing);

      await tester.enterText(_amountField, '250');
      await tester.pump();
      expect(find.text('250 iu · Abdominal R'), findsOneWidget);
      await tester.tap(find.text('Log injection'));
      await tester.pump();
      expect(host.added!.snapshot.unit, Unit.iu);
    });
  });
}
