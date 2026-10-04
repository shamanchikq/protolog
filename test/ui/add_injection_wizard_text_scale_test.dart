import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/theme.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'real_fonts.dart';

/// C1: the wizard must not overflow at Android "Large" (1.15×) / "Largest"
/// (1.3×) text on a 360 dp phone. Measured with the bundled fonts — the test
/// font's square glyphs give false results.
const _scales = [1.0, 1.15, 1.3];

Future<void> _pumpWizard(
  WidgetTester tester, {
  required double scale,
  double width = 360,
  double height = 800,
  CompoundDefinition? prefill,
  List<CompoundDefinition> userCompounds = const [],
  List<Injection> injections = const [],
  List<Reminder> reminders = const [],
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        // As main.dart hosts it.
        child: Scaffold(
          backgroundColor: AppTheme.bg,
          body: SafeArea(
            child: AddInjectionWizard(
              onAdd: (_, _) {},
              reminders: reminders,
              onCancel: () {},
              onSuccess: () {},
              userCompounds: userCompounds,
              addUserCompound: (_) {},
              injections: injections,
              prefillCompound: prefill,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The Amount field is the first TextField on the details step (Direct mode).
Finder get _amountField => find.byType(TextField).first;

void main() {
  setUpAll(loadAppFonts);

  final testE = BASE_LIBRARY['Testosterone Enanthate']!;
  final bpc = BASE_LIBRARY['BPC-157']!;

  for (final scale in _scales) {
    group('text scale $scale on 360 dp', () {
      testWidgets('step 1: filter pills, Recent cards, library', (tester) async {
        final user = testE.copyWith(id: 'te');
        await _pumpWizard(
          tester,
          scale: scale,
          userCompounds: [user],
          injections: [
            Injection(
              id: 'i1',
              compoundId: 'te',
              date: DateTime.now().subtract(const Duration(days: 2)),
              dosage: 250,
              snapshot: user,
            ),
          ],
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Ancillary'), findsOneWidget);
        await tester.tap(find.text('Testosterone').last);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('step 2: steroid with a reminder, a long dose and site, and a warning',
          (tester) async {
        final user = testE.copyWith(id: 'te', concentration: 250);
        await _pumpWizard(
          tester,
          scale: scale,
          height: 1800, // lay out every details section, not just the first screen
          prefill: testE,
          userCompounds: [user],
          injections: [
            Injection(
              id: 'i1',
              compoundId: 'te',
              date: DateTime.now().subtract(const Duration(days: 7)),
              dosage: 0.125,
              snapshot: user,
              site: 'Lower lateral thigh R',
            ),
          ],
          reminders: [
            Reminder(
              id: 'r1',
              compoundBase: 'Testosterone',
              compoundEster: 'Enanthate',
              intervalDays: 3.5,
              hour: 8,
              minute: 0,
              enabled: true,
              anchorDate: DateTime.now().add(const Duration(days: 1)),
            ),
          ],
          prefs: {'customSitesIM': '["Lower lateral thigh R"]'},
        );
        await tester.enterText(_amountField, '1234.567891');
        await tester.pump();
        expect(find.textContaining('your last dose'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.text('Log injection'), findsOneWidget);
      });

      testWidgets('step 2: peptide by volume', (tester) async {
        await _pumpWizard(
          tester,
          scale: scale,
          height: 1800,
          prefill: bpc,
          userCompounds: [bpc.copyWith(id: 'bpc', concentration: 2.5)],
        );
        await tester.tap(find.text('By volume'));
        await tester.pump();
        await tester.enterText(find.widgetWithText(TextField, '0.'), '0.125');
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('step 2: oral', (tester) async {
        await _pumpWizard(tester, scale: scale, height: 1800, prefill: BASE_LIBRARY['Oxandrolone']!);
        await tester.enterText(_amountField, '20');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Log administration'), findsOneWidget);
      });
    });
  }

  testWidgets('a long drill-down title ellipsizes at 1.3×', (tester) async {
    CompoundDefinition custom(String ester) => testE.copyWith(
        id: 'c-$ester', base: 'Dihydroboldenone Experimental', ester: ester, isCustom: true);
    await _pumpWizard(tester, scale: 1.3, userCompounds: [custom('Cypionate'), custom('Acetate')]);
    await tester.tap(find.text('Dihydroboldenone Experimental'));
    await tester.pump();
    expect(find.text('Cypionate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('default text size keeps the original layout', () {
    testWidgets('filter pills share one line', (tester) async {
      await _pumpWizard(tester, scale: 1.0);
      final dy = tester.getTopLeft(find.text('Injectable')).dy;
      for (final label in ['Oral', 'Peptide', 'Ancillary']) {
        expect(tester.getTopLeft(find.text(label)).dy, dy, reason: label);
      }
    });

    testWidgets('sticky bar summary is shown in full; a long one ellipsizes at 1.3×',
        (tester) async {
      await _pumpWizard(tester, scale: 1.0, prefill: testE);
      await tester.enterText(_amountField, '250');
      await tester.pump();
      final summary = tester.renderObject<RenderParagraph>(find.text('250 mg · glute R'));
      expect(summary.didExceedMaxLines, isFalse);
      // The button still fills the rest of the bar.
      final buttonLeft = tester.getTopLeft(find.ancestor(
          of: find.text('Log injection'), matching: find.byType(Container)).first).dx;
      expect(buttonLeft, closeTo(tester.getTopRight(find.text('250 mg · glute R')).dx + 14, 0.5));
    });

    testWidgets('a long summary at 1.3× ellipsizes instead of overflowing', (tester) async {
      await _pumpWizard(tester, scale: 1.3, prefill: testE, prefs: {'customSitesIM': '["Lower lateral thigh R"]'});
      await tester.enterText(_amountField, '1234.567891');
      await tester.tap(find.text('Lower lateral thigh R'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final summary = tester.renderObject<RenderParagraph>(
          find.text('1234.567891 mg · Lower lateral thigh R'));
      expect(summary.didExceedMaxLines, isTrue);
    });
  });
}
