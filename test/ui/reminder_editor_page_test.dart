import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/reminder_editor_page.dart';

void main() {
  testWidgets('new reminder: picker visible, save disabled until compound chosen', (tester) async {
    Reminder? saved;
    await tester.pumpWidget(MaterialApp(
      home: ReminderEditorPage(
        userCompounds: const [],
        now: DateTime(2026, 5, 18, 8, 0),
        onSave: (r) => saved = r,
      ),
    ));
    expect(find.text('New reminder'), findsOneWidget);
    expect(find.text('Injectable'), findsWidgets);
    // tapping save without a compound does nothing
    await tester.tap(find.text('Save reminder'));
    await tester.pump();
    expect(saved, isNull);
  });

  testWidgets('editing an existing reminder shows Edit title + Delete', (tester) async {
    final r = Reminder(
      id: 'r', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
      scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
      enabled: true, anchorDate: DateTime(2026, 5, 18, 8, 0),
    );
    await tester.pumpWidget(MaterialApp(
      home: ReminderEditorPage(
        editing: r, userCompounds: const [], now: DateTime(2026, 5, 18, 8, 0),
        onSave: (_) {}, onDelete: () {},
      ),
    ));
    expect(find.text('Edit reminder'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Every 3.5 days · 08:00'), findsNothing); // formatSchedule not shown in editor; preview uses "Next dose"
    expect(find.text('NEXT DOSE'), findsOneWidget); // _label() upper-cases its text
  });
}
