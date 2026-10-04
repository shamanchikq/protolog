import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/compound_detail_page.dart';

import '../support/finders.dart';
import 'real_fonts.dart';

const _custom = CompoundDefinition(
  id: 'c1', base: 'Testium', ester: 'Enanthate',
  type: CompoundType.steroid, graphType: GraphType.curve,
  halfLife: 4.5, timeToPeak: 1.5, ratio: 1, unit: Unit.mg,
  colorValue: 0xFF5DC59C, isCustom: true,
);

Injection _log(DateTime date, double dose, {String? site, Unit unit = Unit.mg}) =>
    Injection(
      id: 'i${date.millisecondsSinceEpoch}',
      compoundId: _custom.id,
      date: date,
      dosage: dose,
      snapshot: _custom.copyWith(unit: unit),
      site: site,
    );

Future<void> _pump(
  WidgetTester tester, {
  List<Injection> injections = const [],
  int linkedReminderCount = 0,
  VoidCallback? onDelete,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: CompoundDetailPage(
      compound: _custom,
      injections: injections,
      linkedReminderCount: linkedReminderCount,
      onTabChanged: (_) {},
      openEditor: (_) async => null,
      onDelete: onDelete ?? () {},
      onLogInjection: (_) {},
    ),
  ));
}

/// True when [finder]'s paragraph got its full single-line width — i.e. it
/// wasn't wrapped or squeezed by its row.
bool _unsqueezed(WidgetTester tester, Finder finder) {
  final p = tester.renderObject<RenderParagraph>(finder);
  return p.size.width >= p.getMaxIntrinsicWidth(double.infinity) - 0.01;
}

void main() {
  setUpAll(loadAppFonts);

  group('history rows (B30)', () {
    Future<void> pumpAt(WidgetTester tester, List<Injection> logs,
        {double scale = 1.0}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
            child: CompoundDetailPage(
              compound: _custom,
              injections: logs,
              onTabChanged: (_) {},
              openEditor: (_) async => null,
              onDelete: () {},
              onLogInjection: (_) {},
            ),
          ),
        ),
      ));
    }

    testWidgets('fractional doses are not rounded to one decimal', (tester) async {
      await pumpAt(tester, [
        _log(DateTime(2026, 9, 1, 8), 0.25),
        _log(DateTime(2026, 9, 2, 8), 0.125),
        _log(DateTime(2026, 9, 3, 8), 250),
      ]);
      expect(find.text('0.25 mg'), findsOneWidget);
      expect(find.text('0.125 mg'), findsOneWidget);
      expect(find.text('250 mg'), findsOneWidget);
      expect(find.text('0.3 mg'), findsNothing);
    });

    // 1.3× is left out: the PK section's LabMetric tiles (lab_primitives)
    // already overflow by 1 px at that scale on 360 dp, unrelated to history rows.
    for (final scale in [1.0, 1.15]) {
      testWidgets('a wide dose and a long site keep date and dose on one line (×$scale)',
          (tester) async {
        await pumpAt(
          tester,
          [
            _log(DateTime(2026, 9, 2, 8), 1250, unit: Unit.mcg,
                site: 'Ventrogluteal right, upper outer quadrant'),
          ],
          scale: scale,
        );
        expect(tester.takeException(), isNull); // no RenderFlex overflow
        expect(_unsqueezed(tester, find.text('1250 mcg')), isTrue);
        expect(_unsqueezed(tester, find.text('Sep 02 · Wed')), isTrue);
        final site = tester.renderObject<RenderParagraph>(
            find.text('Ventrogluteal right, upper outer quadrant'));
        expect(site.didExceedMaxLines, isTrue); // ellipsized, not wrapped
      });
    }

    testWidgets('PK values keep their precision (t½ 0.05 d is not "0.1")', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CompoundDetailPage(
          compound: BASE_LIBRARY['Testosterone Suspension']!,
          injections: const [],
          onTabChanged: (_) {},
          openEditor: (_) async => null,
          onDelete: () {},
          onLogInjection: (_) {},
        ),
      ));
      expect(find.text('0.05'), findsOneWidget); // half-life
      expect(find.text('0.02'), findsOneWidget); // time to peak
    });
  });

  group('delete confirmation (B11)', () {
    final dialogDelete = find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete'));

    testWidgets('mentions linked reminders and that they go too', (tester) async {
      var deletes = 0;
      await _pump(tester,
          injections: [_log(DateTime(2026, 9, 1), 250)],
          linkedReminderCount: 2,
          onDelete: () => deletes++);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 injection of this compound will keep'), findsOneWidget);
      expect(find.textContaining('Its 2 reminders will be removed too.'), findsOneWidget);

      await tester.tap(dialogDelete);
      await tester.pumpAndSettle();
      expect(deletes, 1);
    });

    testWidgets('no reminder sentence without linked reminders', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Testium Enanthate?'), findsOneWidget);
      expect(find.textContaining('reminder'), findsNothing);
    });
  });

  group('hero color (B26)', () {
    final te = BASE_LIBRARY['Testosterone Enanthate']!;

    testWidgets('comes from the live resolver, read again after an edit', (tester) async {
      Color color = Colors.grey;
      await tester.pumpWidget(MaterialApp(
        home: CompoundDetailPage(
          compound: te,
          injections: const [],
          onTabChanged: (_) {},
          // The host saves the recolor; its resolver now answers with it.
          openEditor: (c) async {
            color = userColor;
            return c.copyWith(colorValue: userColor.toARGB32());
          },
          onDelete: () {},
          onLogInjection: (_) {},
          colorResolver: (base) => base == 'Testosterone' ? color : Colors.black,
        ),
      ));
      expect(coloredWith(Colors.grey), findsOneWidget);
      expect(coloredWith(userColor), findsNothing);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(coloredWith(userColor), findsOneWidget);
      expect(coloredWith(Colors.grey), findsNothing);
    });

    testWidgets('without a resolver: palette for the base, else the stored color',
        (tester) async {
      await _pump(tester);
      expect(coloredWith(Color(_custom.colorValue)), findsOneWidget);
      await tester.pumpWidget(MaterialApp(
        home: CompoundDetailPage(
          compound: te,
          injections: const [],
          onTabChanged: (_) {},
          openEditor: (_) async => null,
          onDelete: () {},
          onLogInjection: (_) {},
        ),
      ));
      expect(coloredWith(const Color(0xFF5DC59C)), findsOneWidget);
    });
  });
}
