import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/widgets/bloodwork_editor_dialog.dart';

void main() {
  Future<BloodworkDialogResult?> drive(
    WidgetTester tester, {
    BloodworkEntry? editing,
    Map<String, String> suggestions = const {'Total T': 'nmol/L'},
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
                markerSuggestions: suggestions,
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
          find.byKey(const Key('bloodwork-value')), '38,5');
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

  group('switching marker chips (B33)', () {
    const suggestions = {'Total T': 'nmol/L', 'E2': 'pmol/L'};

    String unitText(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(const Key('bloodwork-unit')))
        .controller!
        .text;

    testWidgets('replaces the previous chip\'s suggested unit', (tester) async {
      final result = await drive(tester, suggestions: suggestions,
          interact: () async {
        await tester.tap(find.text('Total T'));
        await tester.pump();
        expect(unitText(tester), 'nmol/L');
        await tester.tap(find.text('E2'));
        await tester.pump();
        expect(unitText(tester), 'pmol/L');
        await tester.enterText(find.byKey(const Key('bloodwork-value')), '95');
        await tester.pump();
        await tester.tap(find.text('Save'));
      });
      expect(result!.entry!.marker, 'E2');
      expect(result.entry!.unit, 'pmol/L');
    });

    testWidgets('keeps a unit the user typed', (tester) async {
      await drive(tester, suggestions: suggestions, interact: () async {
        await tester.tap(find.text('Total T'));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('bloodwork-unit')), 'ng/dL');
        await tester.pump();
        await tester.tap(find.text('E2'));
        await tester.pump();
        expect(unitText(tester), 'ng/dL');
        await tester.tap(find.text('Cancel'));
      });
    });

    testWidgets('editing: switching away from the entry\'s suggested unit updates it',
        (tester) async {
      final existing = BloodworkEntry(
        id: 'b1', date: DateTime(2026, 7, 1), marker: 'E2',
        value: 120, unit: 'pmol/L',
      );
      await drive(tester, editing: existing, suggestions: suggestions,
          interact: () async {
        await tester.tap(find.text('Total T'));
        await tester.pump();
        expect(unitText(tester), 'nmol/L');
        await tester.tap(find.text('Cancel'));
      });
    });
  });

  group('date range and zero values (B28)', () {
    Future<void> openPicker(WidgetTester tester, DateTime date) async {
      final existing = BloodworkEntry(
        id: 'old', date: date, marker: 'E2', value: 120, unit: 'pmol/L',
      );
      await drive(tester, editing: existing, interact: () async {
        await tester.tap(find.text('tap to change'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('Cancel').last); // picker
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel')); // dialog
      });
    }

    testWidgets('a pre-2020 entry opens the date picker', (tester) async {
      await openPicker(tester, DateTime(2015, 3, 1));
    });

    testWidgets('a pre-1990 (imported) entry opens the date picker', (tester) async {
      await openPicker(tester, DateTime(1985, 6, 15));
    });

    testWidgets('a future-dated (imported) entry opens the date picker', (tester) async {
      await openPicker(tester, DateTime.now().add(const Duration(days: 400)));
    });

    testWidgets('value 0 (undetectable) can be saved', (tester) async {
      final result = await drive(tester, interact: () async {
        await tester.tap(find.text('Total T'));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('bloodwork-value')), '0');
        await tester.pump();
        await tester.tap(find.text('Save'));
      });
      expect(result, isNotNull);
      expect(result!.entry!.value, 0);
    });

    testWidgets('negative values cannot be saved', (tester) async {
      final result = await drive(tester, interact: () async {
        await tester.tap(find.text('Total T'));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('bloodwork-value')), '-1');
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.tap(find.text('Cancel'));
      });
      expect(result, isNull);
    });
  });
}
