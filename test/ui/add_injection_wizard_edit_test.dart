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

  testWidgets('N1: a 0.125 dose is prefilled exactly and re-saved unchanged', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = Injection(
      id: 'e2',
      compoundId: 'test_e',
      date: DateTime(2026, 7, 1, 17, 15),
      dosage: 0.125,
      snapshot: _testE,
    );
    Injection? edited;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddInjectionWizard(
          onAdd: (_, _) {},
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

    expect(find.widgetWithText(TextField, '0.125'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(edited!.dosage, 0.125); // was re-saved as 0.13
  });

  testWidgets('B28: the date picker opens for a log dated before 2020', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = Injection(
      id: 'e3',
      compoundId: 'test_e',
      date: DateTime(2015, 6, 1, 8),
      dosage: 250,
      snapshot: _testE,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddInjectionWizard(
          onAdd: (_, _) {},
          reminders: const [],
          onCancel: () {},
          onSuccess: () {},
          userCompounds: const [],
          addUserCompound: (_) {},
          injections: [original],
          editingInjection: original,
          onEdit: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jun 1, 2015'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // initialDate was below firstDate (2020)
    expect(find.byType(DatePickerDialog), findsOneWidget);
    final dialog = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(dialog.firstDate, DateTime(2000));
    expect(dialog.lastDate.isAfter(DateTime.now().add(const Duration(days: 364))), isTrue);
    // A past date shows no future hint.
    expect(find.textContaining('In the future'), findsNothing);
  });

  group('no step-1 flash: prefilled modes render the details step on the first frame', () {
    Widget wizard({CompoundDefinition? prefill, Injection? editing}) => MaterialApp(
          home: Scaffold(
            body: AddInjectionWizard(
              onAdd: (_, _) {},
              reminders: const [],
              onCancel: () {},
              onSuccess: () {},
              userCompounds: const [],
              addUserCompound: (_) {},
              injections: const [],
              prefillCompound: prefill,
              editingInjection: editing,
              onEdit: (_) {},
            ),
          ),
        );

    testWidgets('edit mode', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(wizard(
        editing: Injection(
            id: 'e1', compoundId: 'test_e', date: DateTime(2026, 7, 1, 17, 15),
            dosage: 250, snapshot: _testE),
      ));
      // One frame only — no pumpAndSettle.
      expect(find.text('Select compound'), findsNothing);
      expect(find.text('Edit dose'), findsOneWidget);
      expect(find.widgetWithText(TextField, '250'), findsOneWidget);
    });

    testWidgets('prefilled compound', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(wizard(prefill: _testE));
      expect(find.text('Select compound'), findsNothing);
      expect(find.text('Dose & time'), findsOneWidget);
    });
  });
}
