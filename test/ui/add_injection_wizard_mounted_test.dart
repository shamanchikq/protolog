import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wizard awaits dialogs, sheets and pickers. If its route goes away
/// while one is open (e.g. another flow removes it), the await must not
/// resume into setState on a disposed State.

/// Pushes the wizard (prefilled on [compound]) on its own route and returns
/// that route so a test can remove it from under an open dialog.
Future<Route<void>> _openWizard(WidgetTester tester, CompoundDefinition compound) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final route = MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      body: AddInjectionWizard(
        onAdd: (_, _) {},
        reminders: const [],
        onCancel: () {},
        onSuccess: () {},
        userCompounds: const [],
        addUserCompound: (_) {},
        injections: const [],
        prefillCompound: compound,
      ),
    ),
  );
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(route),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return route;
}

/// Removes the wizard's route while whatever it opened stays on top.
Future<void> _removeWizard(WidgetTester tester, Route<void> route) async {
  route.navigator!.removeRoute(route);
  await tester.pump();
  expect(find.byType(AddInjectionWizard), findsNothing);
}

void main() {
  final testE = BASE_LIBRARY['Testosterone Enanthate']!;
  final bpc = BASE_LIBRARY['BPC-157']!;

  testWidgets('add-site dialog resolving after the wizard is gone', (tester) async {
    final route = await _openWizard(tester, testE);
    await tester.tap(find.text('+ Add site'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Lat L'), 'Pec R');
    await _removeWizard(tester, route);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reconstitution sheet resolving after the wizard is gone', (tester) async {
    final route = await _openWizard(tester, bpc);
    await tester.tap(find.text('By volume'));
    await tester.pump();
    await tester.tap(find.text('tap to calculate'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(BottomSheet), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '5');
    await tester.enterText(fields.at(1), '2');
    await tester.pump();
    await _removeWizard(tester, route);
    await tester.tap(find.text('Use this'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('date picker resolving after the wizard is gone', (tester) async {
    final route = await _openWizard(tester, testE);
    await tester.tap(find.text('DATE'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await _removeWizard(tester, route);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('time picker resolving after the wizard is gone', (tester) async {
    final route = await _openWizard(tester, testE);
    await tester.tap(find.text('TIME'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await _removeWizard(tester, route);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
