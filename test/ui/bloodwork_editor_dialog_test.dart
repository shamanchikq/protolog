import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/widgets/bloodwork_editor_dialog.dart';

void main() {
  Future<BloodworkDialogResult?> drive(
    WidgetTester tester, {
    BloodworkEntry? editing,
    required Future<void> Function() interact,
  }) async {
    BloodworkDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            result = await showDialog<BloodworkDialogResult>(
              context: ctx,
              builder: (_) => BloodworkEditorDialog(
                editing: editing,
                markerSuggestions: const {'Total T': 'nmol/L'},
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact();
    // Settle through the route's exit animation — this is where disposing
    // controllers too early used to trip the framework assertion.
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('chip prefill + save pops a complete entry without crashing', (tester) async {
    final result = await drive(tester, interact: () async {
      await tester.tap(find.text('Total T'));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Value').first, '38,5');
      await tester.pump();
      await tester.tap(find.text('Save'));
    });
    expect(result, isNotNull);
    expect(result!.delete, isFalse);
    expect(result.entry!.marker, 'Total T');
    expect(result.entry!.value, 38.5); // comma decimal accepted
    expect(result.entry!.unit, 'nmol/L'); // prefilled by the chip
  });

  testWidgets('save is disabled without marker and positive value', (tester) async {
    final result = await drive(tester, interact: () async {
      await tester.tap(find.text('Save')); // nothing filled in
      await tester.pump();
      // Dialog still open — dismiss via Cancel.
      await tester.tap(find.text('Cancel'));
    });
    expect(result, isNull);
  });

  testWidgets('delete pops a deletion result when editing', (tester) async {
    final existing = BloodworkEntry(
      id: 'b1', date: DateTime(2026, 7, 1), marker: 'E2',
      value: 120, unit: 'pmol/L',
    );
    final result = await drive(tester, editing: existing, interact: () async {
      await tester.tap(find.text('Delete'));
    });
    expect(result!.delete, isTrue);
  });
}
