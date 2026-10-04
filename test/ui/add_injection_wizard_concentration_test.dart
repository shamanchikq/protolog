import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// N5: the wizard flags a vial concentration over 100000 per mL — typed or
/// calculated — and holds Confirm while it would feed the dose.
class _Host {
  Injection? added;
  final List<CompoundDefinition> upserted = [];
}

Future<_Host> _pump(WidgetTester tester,
    {required CompoundDefinition compound, List<CompoundDefinition> userCompounds = const []}) async {
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
        injections: const [],
        prefillCompound: compound,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return host;
}

final _note = find.byKey(const Key('concentration-too-high'));

void main() {
  final te = BASE_LIBRARY['Testosterone Enanthate']!;
  final bpc = BASE_LIBRARY['BPC-157']!;

  Finder volumeField() => find.byType(TextField).at(1); // after the concentration

  testWidgets('a typed concentration over the limit is flagged and holds Confirm',
      (tester) async {
    final host = await _pump(tester,
        compound: te, userCompounds: [te.copyWith(id: 'te', concentration: 250)]);
    await tester.tap(find.text('By volume'));
    await tester.pump();
    await tester.enterText(volumeField(), '1');
    await tester.pump();
    await tester.pump(); // post-frame dose sync
    expect(find.text('= 250 mg'), findsOneWidget);
    expect(_note, findsNothing);

    await tester.enterText(find.widgetWithText(TextField, '250'), '200000');
    await tester.pump();
    await tester.pump();
    expect(find.text('Above 100000 mg/mL — check the value'), findsOneWidget);
    expect(tester.widget<TextField>(volumeField()).enabled, isFalse);
    expect(find.text('= 200000000 mg'), findsNothing, reason: 'never multiplied into a dose');
    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added, isNull);

    // The limit itself is fine.
    await tester.enterText(find.widgetWithText(TextField, '200000'), '100000');
    await tester.pump();
    await tester.pump();
    expect(_note, findsNothing);
    expect(find.text('= 100000 mg'), findsOneWidget);
  });

  testWidgets('a direct dose logs, and the flagged concentration is not stored', (tester) async {
    final host = await _pump(tester,
        compound: te, userCompounds: [te.copyWith(id: 'te', concentration: 250)]);
    await tester.tap(find.text('By volume'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '250'), '1e9');
    await tester.pump();
    expect(_note, findsOneWidget);

    await tester.tap(find.text('Direct'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '250');
    await tester.pump();
    expect(find.textContaining('≈'), findsNothing, reason: 'no volume hint from it either');
    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added!.dosage, 250);
    expect(host.added!.snapshot.concentration, 250);
    expect(host.upserted, isEmpty, reason: 'the stored 250 mg/mL stays');
  });

  testWidgets('a stored concentration over the limit is flagged in By volume', (tester) async {
    final host = await _pump(tester,
        compound: te, userCompounds: [te.copyWith(id: 'te', concentration: 5e6)]);
    await tester.tap(find.text('By volume'));
    await tester.pump();
    expect(_note, findsOneWidget);
    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added, isNull);
  });

  testWidgets('the reconstitution sheet flags a result over the limit and won\'t use it',
      (tester) async {
    await _pump(tester, compound: bpc);
    await tester.tap(find.text('By volume'));
    await tester.pump();
    await tester.tap(find.text('tap to calculate'));
    await tester.pumpAndSettle();
    final sheetFields =
        find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
    await tester.enterText(sheetFields.at(0), '500000'); // mg per vial
    await tester.enterText(sheetFields.at(1), '2'); // mL
    await tester.pump();
    expect(find.text('Above 100000 mg/mL — check the value'), findsOneWidget);
    expect(find.textContaining('per 10 IU'), findsNothing);

    await tester.tap(find.text('Use this'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'still open');

    await tester.enterText(sheetFields.at(0), '5');
    await tester.pump();
    expect(_note, findsNothing);
    await tester.tap(find.text('Use this'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('2.5'), findsOneWidget); // the concentration field
  });
}
