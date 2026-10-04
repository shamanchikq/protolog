import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:protolog_tracker/ui/views/wizard/wizard_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/finders.dart';

/// B26: the wizard's compound cards, library rows and the selected-compound
/// chip show the live resolver's color, so a library recolor shows here too.
void main() {
  final te = BASE_LIBRARY['Testosterone Enanthate']!;
  Color resolver(String base) => base == 'Testosterone' ? userColor : Colors.grey;

  Future<void> pump(WidgetTester tester,
      {CompoundDefinition? prefill, List<Injection> injections = const []}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddInjectionWizard(
          onAdd: (_, _) {},
          reminders: const [],
          onCancel: () {},
          onSuccess: () {},
          userCompounds: const [],
          addUserCompound: (_) {},
          injections: injections,
          prefillCompound: prefill,
          colorResolver: resolver,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('step 1: recent card and library row', (tester) async {
    await pump(tester, injections: [
      Injection(
        id: 'i1', compoundId: te.id, date: DateTime.now().subtract(const Duration(days: 2)),
        dosage: 250, snapshot: te,
      ),
    ]);
    expect(find.text('Recent'), findsOneWidget);
    // The recent card's top rule and the library row's swatch.
    expect(coloredWith(userColor), findsNWidgets(2));
    expect(coloredWith(const Color(0xFF5DC59C)), findsNothing, reason: 'no palette fallback');
  });

  testWidgets('step 2: the selected-compound chip', (tester) async {
    await pump(tester, prefill: te);
    expect(find.text('Dose & time'), findsOneWidget);
    expect(coloredWith(userColor), findsOneWidget);
  });

  test('wizardCompoundColor: resolver, else palette, else the stored color', () {
    final ghk = BASE_LIBRARY['GHK-Cu']!;
    expect(wizardCompoundColor(te, resolver), userColor);
    expect(wizardCompoundColor(ghk, resolver), Colors.grey);
    expect(wizardCompoundColor(te), const Color(0xFF5DC59C));
    expect(wizardCompoundColor(ghk), Color(ghk.colorValue));
  });
}
