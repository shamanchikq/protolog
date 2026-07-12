import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/compound_editor_page.dart';

void main() {
  // Create mode, steroid type: TextField order is name(0), ester(1),
  // half-life(2), time-to-peak(3), yield(4).
  Future<void> pumpCreate(
    WidgetTester tester,
    void Function(CompoundDefinition) onCreate,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: CompoundEditorPage(
        onTabChanged: (_) {},
        onCreate: onCreate,
      ),
    ));
  }

  testWidgets('save is blocked while half-life is empty or zero', (tester) async {
    CompoundDefinition? created;
    await pumpCreate(tester, (c) => created = c);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Testium');
    await tester.enterText(fields.at(1), 'Enanthate');
    await tester.pump();

    // Half-life empty -> blocked.
    await tester.tap(find.text('Add to library'));
    await tester.pump();
    expect(created, isNull);

    // Half-life 0 -> still blocked.
    await tester.enterText(fields.at(2), '0');
    await tester.pump();
    await tester.tap(find.text('Add to library'));
    await tester.pump();
    expect(created, isNull);
  });

  testWidgets('saves once half-life is positive, accepting comma decimals', (tester) async {
    CompoundDefinition? created;
    await pumpCreate(tester, (c) => created = c);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Testium');
    await tester.enterText(fields.at(1), 'Enanthate');
    await tester.enterText(fields.at(2), '4,5'); // EU decimal comma
    await tester.pump();

    await tester.tap(find.text('Add to library'));
    await tester.pump();

    expect(created, isNotNull);
    expect(created!.halfLife, 4.5);
    expect(created!.base, 'Testium');
  });
}
