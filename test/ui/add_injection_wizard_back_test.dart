import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B25: Android back (system back button / gesture) inside the wizard steps
/// back through it instead of closing the whole route.

/// Pumps a host page with an "open" button that pushes the wizard the way
/// main.dart does (a full-screen MaterialPageRoute whose Cancel pops it).
Future<void> _openWizard(
  WidgetTester tester, {
  CompoundDefinition? prefillCompound,
  Injection? editing,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (routeContext) => Scaffold(
                body: AddInjectionWizard(
                  onAdd: (_, _) {},
                  reminders: const [],
                  onCancel: () => Navigator.of(routeContext).pop(),
                  onSuccess: () => Navigator.of(routeContext).pop(),
                  userCompounds: const [],
                  addUserCompound: (_) {},
                  injections: editing != null ? [editing] : const [],
                  prefillCompound: prefillCompound,
                  editingInjection: editing,
                  onEdit: (_) {},
                ),
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Simulates the Android system back button.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

bool _wizardOpen() => find.byType(AddInjectionWizard).evaluate().isNotEmpty;

void main() {
  testWidgets('step 1 root: back closes the wizard', (tester) async {
    await _openWizard(tester);
    expect(find.text('Select compound'), findsOneWidget);
    await _systemBack(tester);
    expect(_wizardOpen(), isFalse);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('ester drill-down: back returns to the base list, then closes', (tester) async {
    await _openWizard(tester);
    await tester.tap(find.text('Testosterone'));
    await tester.pump();
    expect(find.text('Enanthate'), findsOneWidget);

    await _systemBack(tester);
    expect(_wizardOpen(), isTrue);
    expect(find.text('Select compound'), findsOneWidget);
    expect(find.text('Injectable'), findsOneWidget); // filter pills are back

    await _systemBack(tester);
    expect(_wizardOpen(), isFalse);
  });

  testWidgets('step 2: back goes to step 1 (keeping the drill-down), not out', (tester) async {
    await _openWizard(tester);
    await tester.tap(find.text('Testosterone'));
    await tester.pump();
    await tester.tap(find.text('Cypionate'));
    await tester.pump();
    expect(find.text('Dose & time'), findsOneWidget);

    await _systemBack(tester);
    expect(_wizardOpen(), isTrue);
    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.text('Cypionate'), findsOneWidget); // still drilled into Testosterone

    await _systemBack(tester);
    expect(find.text('Select compound'), findsOneWidget);
    await _systemBack(tester);
    expect(_wizardOpen(), isFalse);
  });

  testWidgets('opened on step 2 (prefilled): back goes to step 1', (tester) async {
    await _openWizard(tester, prefillCompound: BASE_LIBRARY['Testosterone Enanthate']!);
    expect(find.text('Dose & time'), findsOneWidget);
    await _systemBack(tester);
    expect(_wizardOpen(), isTrue);
    expect(find.text('Step 1 of 2'), findsOneWidget);
  });

  testWidgets('edit mode has no step 1: back closes the wizard', (tester) async {
    final testE = BASE_LIBRARY['Testosterone Enanthate']!.copyWith(id: 'te');
    await _openWizard(
      tester,
      editing: Injection(
        id: 'e1',
        compoundId: 'te',
        date: DateTime(2026, 7, 1, 17, 15),
        dosage: 250,
        snapshot: testE,
      ),
    );
    expect(find.text('Edit dose'), findsOneWidget);
    await _systemBack(tester);
    expect(_wizardOpen(), isFalse);
  });
}
