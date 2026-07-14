import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  testWidgets('edit mode opens on details, prefilled, and saves in place', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = Injection(
      id: 'e1',
      compoundId: 'test_e',
      date: DateTime(2026, 7, 1, 17, 15),
      dosage: 250,
      snapshot: _testE,
      site: 'Vent. glute R',
      notes: 'first shot of the vial',
    );

    Injection? edited;
    Injection? added;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddInjectionWizard(
          onAdd: (inj, _) => added = inj,
          reminders: const [],
          onCancel: () {},
          onSuccess: () {},
          userCompounds: const [],
          addUserCompound: (_) {},
          injections: [original],
          editingInjection: original,
          onEdit: (inj) => edited = inj,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Lands directly on the details step in edit dress.
    expect(find.text('Edit dose'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    // No compound switching or reminder advancing while editing.
    expect(find.text('Change'), findsNothing);

    // Dose prefilled from the injection; change it using a decimal comma.
    expect(find.widgetWithText(TextField, '250'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '250'), '300,5');
    await tester.pump();

    await tester.tap(find.text('Save changes'));
    await tester.pump();

    expect(added, isNull); // must not create a new log
    expect(edited, isNotNull);
    expect(edited!.id, 'e1');
    expect(edited!.compoundId, 'test_e');
    expect(edited!.dosage, 300.5);
    expect(edited!.date, DateTime(2026, 7, 1, 17, 15)); // untouched
    expect(edited!.site, 'Vent. glute R');
    expect(edited!.notes, 'first shot of the vial');
    expect(edited!.snapshot.halfLife, 4.5); // frozen PK stays frozen
  });
}
