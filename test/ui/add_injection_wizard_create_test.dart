import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/theme.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the wizard hands back to its host.
class _Host {
  Injection? added;
  bool? advance;
  int successes = 0;
  int cancels = 0;
  final List<CompoundDefinition> upserted = [];
}

/// Pumps the wizard — on step 1 (the FAB path), or on the details step when
/// [prefillCompound] is given — on a tall surface so every details section is
/// laid out without scrolling. Width stays at the default 800 px: the test
/// font is much wider than Inter, so phone widths overflow in tests only.
Future<_Host> _pumpWizard(
  WidgetTester tester, {
  List<CompoundDefinition> userCompounds = const [],
  List<Injection> injections = const [],
  List<Reminder> reminders = const [],
  CompoundDefinition? prefillCompound,
  DateTime? prefillDate,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final host = _Host();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AddInjectionWizard(
        onAdd: (inj, advance) {
          host.added = inj;
          host.advance = advance;
        },
        reminders: reminders,
        onCancel: () => host.cancels++,
        onSuccess: () => host.successes++,
        userCompounds: userCompounds,
        addUserCompound: host.upserted.add,
        injections: injections,
        prefillCompound: prefillCompound,
        prefillDate: prefillDate,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return host;
}

/// The Amount field is the first TextField on the details step (Direct mode).
Finder get _amountField => find.byType(TextField).first;

/// Quick-time pills come after the Time field, which may show the same label.
Finder _quickTime(String label) => find.text(label).last;

void main() {
  final testE = BASE_LIBRARY['Testosterone Enanthate']!;

  testWidgets('steroid: base → ester drill-down, dose, confirm → onAdd gets the injection',
      (tester) async {
    final host = await _pumpWizard(tester, prefillDate: DateTime(2026, 5, 10));
    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.text('Select compound'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Recent'), findsNothing); // no history yet
    expect(find.text('6 esters'), findsOneWidget); // Testosterone row meta

    // Multi-ester base drills in; the header turns into the base name.
    await tester.tap(find.text('Testosterone'));
    await tester.pump();
    expect(find.text('Select compound'), findsNothing);
    expect(find.text('Testosterone'), findsOneWidget);
    expect(find.text('Injectable'), findsNothing); // filter pills hidden in drill-down
    expect(find.text('Enanthate · t½ 4.5d'), findsOneWidget);

    await tester.tap(find.text('Enanthate'));
    await tester.pump();
    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(find.text('Dose & time'), findsOneWidget);
    expect(find.text('t½ 4.5d · concentration unset'), findsOneWidget);
    expect(find.text('Today, May 10'), findsNothing); // prefillDate is not today
    expect(find.text('May 10'), findsOneWidget);
    expect(find.text('Log injection'), findsOneWidget);
    expect(find.text('—'), findsOneWidget); // sticky bar before a dose is typed

    await tester.enterText(_amountField, '250');
    await tester.pump();
    expect(find.text('250 mg · glute R'), findsOneWidget); // 'Vent. ' dropped
    await tester.tap(_quickTime('08:00'));
    await tester.pump();

    await tester.tap(find.text('Log injection'));
    await tester.pump();

    final added = host.added!;
    expect(added.dosage, 250);
    expect(added.date, DateTime(2026, 5, 10, 8, 0));
    expect(added.site, 'Vent. glute R');
    expect(added.notes, isNull);
    expect(added.snapshot.base, 'Testosterone');
    expect(added.snapshot.ester, 'Enanthate');
    expect(added.snapshot.unit, Unit.mg);
    expect(added.snapshot.halfLife, 4.5);
    expect(host.advance, isFalse); // no reminder to advance

    // First log of a built-in materializes a user copy carrying the library PK.
    final adopted = host.upserted.single;
    expect(added.compoundId, adopted.id);
    expect(adopted.id, 'Testosterone Enanthate'); // its library key (B6)
    expect(adopted.base, 'Testosterone');
    expect(adopted.ester, 'Enanthate');
    expect(adopted.isCustom, isFalse);
    expect(adopted.halfLife, 4.5);
    expect(adopted.unit, Unit.mg);
    expect(adopted.concentration, isNull);
    expect(host.successes, 1);
  });

  testWidgets('single-ester base goes straight to the details step', (tester) async {
    await _pumpWizard(tester);
    await tester.tap(find.text('Boldenone'));
    await tester.pump();
    expect(find.text('Dose & time'), findsOneWidget);
    // The selected-compound chip spells out base + ester.
    expect(find.text('Boldenone Undecylenate', findRichText: true), findsOneWidget);
    expect(find.text('t½ 14.0d · concentration unset'), findsOneWidget);
  });

  testWidgets('peptide: site, notes and the linked reminder flow into onAdd', (tester) async {
    final reminder = Reminder(
      id: 'r1',
      compoundBase: 'BPC-157',
      compoundEster: 'None',
      intervalDays: 1,
      hour: 8,
      minute: 0,
      enabled: true,
      anchorDate: DateTime.now().add(const Duration(days: 1)),
    );
    final host = await _pumpWizard(tester, reminders: [reminder]);
    await tester.tap(find.text('Peptide'));
    await tester.pump();
    expect(find.text('Testosterone'), findsNothing);
    expect(find.text('Peptide · event'), findsWidgets);

    await tester.tap(find.text('BPC-157'));
    await tester.pump();
    expect(find.text('Linked to your BPC-157 reminder'), findsOneWidget);
    expect(find.text('Advance'), findsOneWidget);
    expect(find.text('By volume'), findsOneWidget);
    // Sub-Q site list for peptides.
    expect(find.text('Abdominal L'), findsOneWidget);
    expect(find.text('Vent. glute R'), findsNothing);

    await tester.enterText(_amountField, '250');
    await tester.pump();
    expect(find.text('250 mcg · Abdominal R'), findsOneWidget); // default sub-Q site
    await tester.tap(find.text('Glute L'));
    await tester.pump();
    expect(find.text('250 mcg · Glute L'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Add a note…'), '  left side  ');
    await tester.pump();

    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added!.dosage, 250);
    expect(host.added!.snapshot.unit, Unit.mcg);
    expect(host.added!.site, 'Glute L');
    expect(host.added!.notes, 'left side'); // trimmed
    expect(host.advance, isTrue); // toggle defaults on for a linked reminder
  });

  testWidgets('unticking Advance logs without advancing; deselecting the site logs none',
      (tester) async {
    final reminder = Reminder(
      id: 'r1',
      compoundBase: 'Testosterone',
      compoundEster: 'Enanthate',
      intervalDays: 3.5,
      hour: 8,
      minute: 0,
      enabled: true,
      anchorDate: DateTime.now().add(const Duration(days: 1)),
    );
    final host = await _pumpWizard(tester, reminders: [reminder], prefillCompound: testE);
    await tester.tap(find.text('Advance'));
    await tester.pump();
    await tester.enterText(_amountField, '125');
    await tester.pump();
    // Tapping the active site clears it.
    await tester.tap(find.text('Vent. glute R'));
    await tester.pump();
    expect(find.text('125 mg'), findsOneWidget);

    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.advance, isFalse);
    expect(host.added!.site, isNull);
  });

  testWidgets('disabled reminders are not linked', (tester) async {
    final reminder = Reminder(
      id: 'r1',
      compoundBase: 'Testosterone',
      compoundEster: 'Enanthate',
      intervalDays: 3.5,
      hour: 8,
      minute: 0,
      enabled: false,
      anchorDate: DateTime.now().add(const Duration(days: 1)),
    );
    final host = await _pumpWizard(tester, reminders: [reminder], prefillCompound: testE);
    expect(find.textContaining('Linked to your'), findsNothing);
    await tester.enterText(_amountField, '100');
    await tester.pump();
    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.advance, isFalse);
  });

  testWidgets('oral: no site or mode toggle, logs an administration without a site',
      (tester) async {
    final host = await _pumpWizard(tester);
    await tester.tap(find.text('Oral'));
    await tester.pump();
    await tester.tap(find.text('Oxandrolone'));
    await tester.pump();
    expect(find.text('By volume'), findsNothing);
    expect(find.text('Site'), findsNothing);
    expect(find.text('Log administration'), findsOneWidget);

    await tester.enterText(_amountField, '20');
    await tester.pump();
    expect(find.text('20 mg'), findsOneWidget); // no site suffix
    await tester.tap(find.text('Log administration'));
    await tester.pump();
    expect(host.added!.site, isNull);
    expect(host.added!.snapshot.type, CompoundType.oral);
  });

  testWidgets('Confirm is inert until a positive dose is entered', (tester) async {
    final host = await _pumpWizard(tester, prefillCompound: testE);
    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added, isNull);
    await tester.enterText(_amountField, '0');
    await tester.pump();
    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added, isNull);
    expect(host.successes, 0);
  });

  testWidgets('Recent cards, search, and no-match state', (tester) async {
    final user = testE.copyWith(id: 'te');
    await _pumpWizard(
      tester,
      userCompounds: [user],
      injections: [
        Injection(
          id: 'i1',
          compoundId: 'te',
          date: DateTime.now().subtract(const Duration(days: 2, minutes: 5)),
          dosage: 250,
          snapshot: user,
        ),
      ],
    );
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('2d ago'), findsOneWidget);
    expect(find.text('6 esters'), findsNWidgets(2)); // Recent card + library row

    await tester.enterText(find.widgetWithText(TextField, 'Search compounds'), 'tren');
    await tester.pump();
    expect(find.text('Recent'), findsNothing); // hidden while searching
    expect(find.text('Trenbolone'), findsOneWidget);
    expect(find.text('Testosterone'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'tren'), 'zzz');
    await tester.pump();
    expect(find.text('No matches for "zzz"'), findsOneWidget);
  });

  testWidgets('Recent card of a multi-ester steroid drills into its base', (tester) async {
    final user = testE.copyWith(id: 'te');
    await _pumpWizard(
      tester,
      userCompounds: [user],
      injections: [
        Injection(
          id: 'i1',
          compoundId: 'te',
          date: DateTime.now().subtract(const Duration(hours: 3)),
          dosage: 250,
          snapshot: user,
        ),
      ],
    );
    expect(find.text('3h ago'), findsOneWidget);
    await tester.tap(find.text('3h ago'));
    await tester.pump();
    expect(find.text('Select compound'), findsNothing);
    expect(find.text('Enanthate · t½ 4.5d'), findsOneWidget);
    // ‹ leaves the drill-down.
    await tester.tap(find.text('‹'));
    await tester.pump();
    expect(find.text('Select compound'), findsOneWidget);
  });

  testWidgets('Back / Change return to step 1 keeping the filter and drill-down',
      (tester) async {
    final host = await _pumpWizard(tester);
    await tester.tap(find.text('Testosterone'));
    await tester.pump();
    await tester.tap(find.text('Cypionate'));
    await tester.pump();
    expect(find.text('Dose & time'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.text('Testosterone'), findsOneWidget); // still drilled in
    await tester.tap(find.text('‹'));
    await tester.pump();

    await tester.tap(find.text('Peptide'));
    await tester.pump();
    await tester.tap(find.text('HCG'));
    await tester.pump();
    await tester.tap(find.text('Change'));
    await tester.pump();
    expect(find.text('HCG'), findsOneWidget); // peptide filter kept

    await tester.tap(find.text('Cancel'));
    expect(host.cancels, 1);
    expect(host.added, isNull);
  });

  testWidgets('prior log prefills dose, unit, site and the "Last" line', (tester) async {
    final user = testE.copyWith(id: 'te', concentration: 250);
    final host = await _pumpWizard(
      tester,
      prefillCompound: testE,
      userCompounds: [user],
      injections: [
        Injection(
          id: 'i1',
          compoundId: 'te',
          date: DateTime.now().subtract(const Duration(days: 7, minutes: 1)),
          dosage: 125.5,
          snapshot: user,
          site: 'Delt L',
        ),
      ],
    );
    expect(find.widgetWithText(TextField, '125.5'), findsOneWidget);
    expect(find.text('Last: 125.5 mg · 7d ago'), findsOneWidget);
    expect(find.text('last: Delt L'), findsOneWidget);
    expect(find.text('t½ 4.5d · 250 mg/mL'), findsOneWidget);
    expect(find.text('≈ 0.50 mL'), findsOneWidget); // direct-mode volume hint
    expect(find.text('125.5 mg · Delt L'), findsOneWidget);

    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added!.compoundId, 'te');
    expect(host.added!.site, 'Delt L');
    expect(host.added!.snapshot.concentration, 250);
    expect(host.upserted, isEmpty); // nothing changed on the compound
  });

  testWidgets('steroid by volume: typed concentration is written back to the user copy',
      (tester) async {
    final user = testE.copyWith(id: 'te', concentration: 200);
    final host = await _pumpWizard(tester, prefillCompound: testE, userCompounds: [user]);
    await tester.tap(find.text('By volume'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '200'), '250');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '0.'), '0.5');
    await tester.pump();
    await tester.pump(); // post-frame dose sync
    expect(find.text('= 125 mg'), findsOneWidget);
    expect(find.text('125 mg · glute R'), findsOneWidget);

    // Back to Direct shows the computed dose.
    await tester.tap(find.text('Direct'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '125'), findsOneWidget);

    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added!.dosage, 125);
    expect(host.upserted.single.id, 'te');
    expect(host.upserted.single.concentration, 250);
    expect(host.added!.snapshot.concentration, 250);
  });

  testWidgets('custom sites: stored ones are offered, a new one persists under the same key',
      (tester) async {
    final host = await _pumpWizard(
      tester,
      prefillCompound: testE,
      prefs: {'customSitesIM': '["Lat L"]', 'customSitesSubQ': '["Love handle"]'},
    );
    expect(find.text('Lat L'), findsOneWidget);
    expect(find.text('Love handle'), findsNothing); // sub-Q list, not shown for IM

    await tester.tap(find.text('+ Add site'));
    await tester.pumpAndSettle();
    expect(find.text('Add site'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Lat L'), '  Pec R ');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Pec R'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('customSitesIM'), '["Lat L","Pec R"]');
    expect(prefs.getString('customSitesSubQ'), '["Love handle"]');

    await tester.enterText(_amountField, '250');
    await tester.pump();
    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added!.site, 'Pec R'); // the added site is selected
  });

  testWidgets('a corrupt stored site list is ignored, the other route still loads',
      (tester) async {
    await _pumpWizard(
      tester,
      prefillCompound: BASE_LIBRARY['BPC-157']!,
      prefs: {'customSitesIM': '{oops', 'customSitesSubQ': '["Love handle"]'},
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Love handle'), findsOneWidget);
  });

  testWidgets('date and time pickers open in the Lab Sheet theme', (tester) async {
    await _pumpWizard(tester, prefillCompound: testE, prefillDate: DateTime(2026, 5, 10));
    await tester.tap(find.text('May 10'));
    await tester.pumpAndSettle();
    final dateTheme = Theme.of(tester.element(find.byType(DatePickerDialog)));
    expect(dateTheme.colorScheme.primary, AppTheme.accent);
    expect(dateTheme.datePickerTheme.headerBackgroundColor, AppTheme.surface2);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('May 10'), findsOneWidget); // unchanged

    await tester.tap(find.text('TIME'));
    await tester.pumpAndSettle();
    final timeTheme = Theme.of(tester.element(find.byType(TimePickerDialog)));
    expect(timeTheme.timePickerTheme.dialHandColor, AppTheme.accent);
    expect(timeTheme.dialogTheme.backgroundColor, AppTheme.surface);
  });

  testWidgets('cancelling the add-site dialog changes nothing', (tester) async {
    await _pumpWizard(tester, prefillCompound: testE);
    await tester.tap(find.text('+ Add site'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Add site'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('customSitesIM'), isNull);
  });

  testWidgets('N1: a 0.125 mg last dose is prefilled and logged exactly', (tester) async {
    final user = testE.copyWith(id: 'te');
    final host = await _pumpWizard(
      tester,
      prefillCompound: testE,
      userCompounds: [user],
      injections: [
        Injection(
          id: 'i1',
          compoundId: 'te',
          date: DateTime.now().subtract(const Duration(days: 3, minutes: 1)),
          dosage: 0.125,
          snapshot: user,
        ),
      ],
    );
    expect(find.widgetWithText(TextField, '0.125'), findsOneWidget);
    expect(find.text('Last: 0.125 mg · 3d ago'), findsOneWidget);
    expect(find.text('0.125 mg · glute R'), findsOneWidget);
    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added!.dosage, 0.125);
  });

  testWidgets('B28: a date more than a day ahead shows a non-blocking hint', (tester) async {
    final host = await _pumpWizard(
      tester,
      prefillCompound: testE,
      prefillDate: DateTime.now().add(const Duration(days: 3)),
    );
    expect(find.text('In the future · 3 days ahead'), findsOneWidget);
    await tester.enterText(_amountField, '250');
    await tester.pump();
    await tester.tap(find.text('Log injection'));
    await tester.pump();
    expect(host.added, isNotNull); // planned doses are allowed
  });

  testWidgets('B28: no future hint for a log dated now', (tester) async {
    await _pumpWizard(tester, prefillCompound: testE);
    expect(find.textContaining('In the future'), findsNothing);
  });

  testWidgets('B28: the date picker spans 2000 to a year ahead', (tester) async {
    await _pumpWizard(tester, prefillCompound: testE, prefillDate: DateTime(2026, 5, 10));
    await tester.tap(find.text('May 10'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(dialog.firstDate, DateTime(2000));
    final now = DateTime.now();
    expect(dialog.lastDate, DateTime(now.year, now.month, now.day + 365));
  });

  testWidgets('B29: the search box still shows the query that filters after Back',
      (tester) async {
    await _pumpWizard(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Search compounds'), 'tren');
    await tester.pump();
    await tester.tap(find.text('Trenbolone'));
    await tester.pump();
    await tester.tap(find.text('Enanthate'));
    await tester.pump();
    expect(find.text('Dose & time'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.tap(find.text('‹'));
    await tester.pump();
    expect(find.text('Trenbolone'), findsOneWidget);
    expect(find.text('Testosterone'), findsNothing); // still filtered…
    expect(find.widgetWithText(TextField, 'tren'), findsOneWidget); // …and it shows

    // Clearing the box clears the filter.
    await tester.enterText(find.widgetWithText(TextField, 'tren'), '');
    await tester.pump();
    expect(find.text('Testosterone'), findsOneWidget);
  });

  testWidgets('adding a site that already exists (any case) selects it instead of duplicating',
      (tester) async {
    await _pumpWizard(tester, prefillCompound: testE, prefs: {'customSitesIM': '["Lat L"]'});
    await tester.enterText(_amountField, '250');
    await tester.pump();
    await tester.tap(find.text('+ Add site'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Lat L'), 'quad l');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Quad L'), findsOneWidget);
    expect(find.text('quad l'), findsNothing);
    expect(find.text('250 mg · Quad L'), findsOneWidget); // the built-in got selected

    await tester.tap(find.text('+ Add site'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Lat L'), 'LAT L');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Lat L'), findsOneWidget);
    expect(find.text('250 mg · Lat L'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('customSitesIM'), '["Lat L"]'); // nothing added
  });

  testWidgets('long-pressing a custom site asks, then removes it from storage', (tester) async {
    await _pumpWizard(
      tester,
      prefillCompound: testE,
      prefs: {'customSitesIM': '["Lat L","Pec R"]', 'customSitesSubQ': '["Love handle"]'},
    );
    await tester.enterText(_amountField, '250');
    await tester.pump();

    // Built-ins can't be removed.
    await tester.longPress(find.text('Quad L'));
    await tester.pumpAndSettle();
    expect(find.text('Remove site?'), findsNothing);

    // Cancel keeps it.
    await tester.longPress(find.text('Lat L'));
    await tester.pumpAndSettle();
    expect(find.text('Remove site?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Lat L'), findsOneWidget);

    // Removing the selected site falls back to the route default.
    await tester.tap(find.text('Pec R'));
    await tester.pump();
    expect(find.text('250 mg · Pec R'), findsOneWidget);
    await tester.longPress(find.text('Pec R'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Pec R'), findsNothing);
    expect(find.text('250 mg · glute R'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('customSitesIM'), '["Lat L"]');
    expect(prefs.getString('customSitesSubQ'), '["Love handle"]');
  });
}
