import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/library_page.dart';

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
          onExport: () {}, onImport: () {}, onBackup: () {}, onRestore: () {},
          onOpenDetail: (_) {}, onOpenCreate: () {},
        ),
      ),
    ));

    expect(find.text('Testosterone Enanthate'), findsNWidgets(2)); // protocol + catalogue
    expect(find.text('1d ago'), findsOneWidget);
  });
}
