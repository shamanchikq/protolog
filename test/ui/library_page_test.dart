import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/library_page.dart';
import 'package:protolog_tracker/ui/widgets/library_row.dart';

import '../support/finders.dart';

void main() {
  testWidgets('"used ago" is measured from the same now as protocol membership', (tester) async {
    // A fixed now well past the real clock: the dose is a day old for the
    // page, but would be "planned" (future) against DateTime.now().
    final now = DateTime(2030, 1, 1, 12);
    final te = BASE_LIBRARY['Testosterone Enanthate']!;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 4000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibraryPage(
          userCompounds: const [],
          injections: [
            Injection(
              id: 'i1', compoundId: te.id, date: DateTime(2029, 12, 31, 12),
              dosage: 125, snapshot: te,
            ),
          ],
          now: now,
          onExport: () {}, onImport: () {}, onBackup: (_) {}, onRestore: () {},
          onOpenDetail: (_) {}, onOpenCreate: () {},
        ),
      ),
    ));

    expect(find.text('Testosterone Enanthate'), findsNWidgets(2)); // protocol + catalogue
    expect(find.text('1d ago'), findsOneWidget);
  });

  group('row stripes (B26)', () {
    Future<void> pump(WidgetTester tester, {Color Function(String base)? resolver}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 4000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibraryPage(
            userCompounds: const [],
            injections: const [],
            now: DateTime(2030, 1, 1, 12),
            onExport: () {}, onImport: () {}, onBackup: (_) {}, onRestore: () {},
            onOpenDetail: (_) {}, onOpenCreate: () {},
            colorResolver: resolver,
          ),
        ),
      ));
    }

    LibraryRow row(WidgetTester tester, String name) =>
        tester.widget<LibraryRow>(find.widgetWithText(LibraryRow, name));

    testWidgets('use the live resolver, so a recolor shows here too', (tester) async {
      final asked = <String>{};
      await pump(tester, resolver: (base) {
        asked.add(base);
        return base == 'Testosterone' ? userColor : Colors.grey;
      });
      expect(row(tester, 'Testosterone Enanthate').stripeColor, userColor);
      expect(row(tester, 'Nandrolone Decanoate').stripeColor, Colors.grey);
      expect(asked, containsAll(['Testosterone', 'Nandrolone']));
    });

    testWidgets('without a resolver: palette, then the stored color', (tester) async {
      await pump(tester);
      expect(row(tester, 'Testosterone Enanthate').stripeColor, const Color(0xFF5DC59C));
      expect(row(tester, 'GHK-Cu').stripeColor,
          Color(BASE_LIBRARY['GHK-Cu']!.colorValue));
    });
  });

  testWidgets('backup hands over the menu button\'s rect to anchor the share sheet (D4)',
      (tester) async {
    final origins = <Rect?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibraryPage(
          userCompounds: const [],
          injections: const [],
          onExport: () {}, onImport: () {}, onBackup: origins.add, onRestore: () {},
          onOpenDetail: (_) {}, onOpenCreate: () {},
        ),
      ),
    ));
    final button = tester.getRect(find.byType(PopupMenuButton<String>));
    await tester.tap(find.text('Import / export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back up everything to file…'));
    await tester.pumpAndSettle();

    expect(origins, [button]);
    expect(button.width, lessThan(tester.view.physicalSize.width / tester.view.devicePixelRatio),
        reason: 'the button, not the whole screen');
  });
}
