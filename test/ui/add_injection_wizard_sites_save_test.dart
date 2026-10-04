import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/services/custom_sites_store.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';

import '../support/fakes.dart';

/// A refused custom-site write is reported like any failed save, instead of
/// being dropped silently.
void main() {
  const failure =
      "Couldn't save your injection sites — the change may be lost when the app closes.";

  Future<FlakyPrefs> pump(WidgetTester tester, {Set<String> refuse = const {}}) async {
    final prefs = await FlakyPrefs.withValues({'customSitesIM': '["Lat L"]'}, refuse: refuse);
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddInjectionWizard(
          onAdd: (_, _) {},
          reminders: const [],
          onCancel: () {},
          onSuccess: () {},
          userCompounds: const [],
          addUserCompound: (_) {},
          injections: const [],
          prefillCompound: BASE_LIBRARY['Testosterone Enanthate']!,
          sitesStore: CustomSitesStore(prefs: () async => prefs),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return prefs;
  }

  Future<void> addSite(WidgetTester tester, String name) async {
    await tester.tap(find.text('+ Add site'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Lat L'), name);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  testWidgets("adding a site that can't be saved says so, and keeps it offered", (tester) async {
    final prefs = await pump(tester, refuse: {'customSites'});
    expect(find.text('Lat L'), findsOneWidget, reason: 'loaded through the injected store');
    await addSite(tester, 'Pec R');
    expect(find.text(failure), findsOneWidget);
    expect(find.text('Pec R'), findsOneWidget);
    expect(prefs.getString('customSitesIM'), '["Lat L"]');
  });

  testWidgets("removing a site that can't be saved says so", (tester) async {
    await pump(tester, refuse: {'customSites'});
    await tester.longPress(find.text('Lat L'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text(failure), findsOneWidget);
  });

  testWidgets('a saved site says nothing', (tester) async {
    final prefs = await pump(tester);
    await addSite(tester, 'Pec R');
    expect(find.text(failure), findsNothing);
    expect(prefs.getString('customSitesIM'), '["Lat L","Pec R"]');
  });
}
