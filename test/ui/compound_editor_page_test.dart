import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/compound_editor_page.dart';
import 'package:protolog_tracker/ui/widgets/protolog_shell.dart';

// Editor text fields, by key.
final _name = find.byKey(const ValueKey('compound-editor-name'));
final _ester = find.byKey(const ValueKey('compound-editor-ester'));
final _halfLife = find.byKey(const ValueKey('compound-editor-half-life'));
final _timeToPeak = find.byKey(const ValueKey('compound-editor-time-to-peak'));

/// Taps the lane-color swatch [argb] (swatches sit in the color section's Wrap).
Future<void> tapSwatch(WidgetTester tester, int argb) async {
  final swatch = find.descendant(
    of: find.byType(Wrap),
    matching: find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == Color(argb)),
  );
  await tester.ensureVisible(swatch);
  await tester.tap(swatch);
  await tester.pump();
}
final _yield = find.byKey(const ValueKey('compound-editor-yield'));

void main() {
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

  /// Fills a valid new steroid ("Testium Enanthate", t½ 4.5 d).
  Future<void> fillValidSteroid(WidgetTester tester) async {
    await tester.enterText(_name, 'Testium');
    await tester.enterText(_ester, 'Enanthate');
    await tester.enterText(_halfLife, '4.5');
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Add to library'));
    await tester.pump();
  }

  testWidgets('save is blocked while half-life is empty or zero', (tester) async {
    CompoundDefinition? created;
    await pumpCreate(tester, (c) => created = c);

    await tester.enterText(_name, 'Testium');
    await tester.enterText(_ester, 'Enanthate');
    await tester.pump();

    // Half-life empty -> blocked.
    await tapSave(tester);
    expect(created, isNull);

    // Half-life 0 -> still blocked.
    await tester.enterText(_halfLife, '0');
    await tester.pump();
    await tapSave(tester);
    expect(created, isNull);
  });

  testWidgets('saves once half-life is positive, accepting comma decimals', (tester) async {
    CompoundDefinition? created;
    await pumpCreate(tester, (c) => created = c);

    await tester.enterText(_name, 'Testium');
    await tester.enterText(_ester, 'Enanthate');
    await tester.enterText(_halfLife, '4,5'); // EU decimal comma
    await tester.pump();

    await tapSave(tester);

    expect(created, isNotNull);
    expect(created!.halfLife, 4.5);
    expect(created!.base, 'Testium');
  });

  group('yield (B12)', () {
    for (final bad in ['0', '-5', '150', '100.5', '', 'abc']) {
      testWidgets('yield "$bad" blocks save', (tester) async {
        CompoundDefinition? created;
        await pumpCreate(tester, (c) => created = c);
        await fillValidSteroid(tester);
        await tester.enterText(_yield, bad);
        await tester.pump();

        await tapSave(tester);
        expect(created, isNull);
      });
    }

    testWidgets('an out-of-range yield explains the allowed range', (tester) async {
      await pumpCreate(tester, (_) {});
      await fillValidSteroid(tester);
      await tester.enterText(_yield, '150');
      await tester.pump();

      expect(find.textContaining('Yield must be'), findsOneWidget);
    });

    testWidgets('an untouched yield keeps the stored ratio exactly', (tester) async {
      // 0.835 displays as "83.5"; re-parsing must not nudge it (a changed
      // ratio would trigger a spurious "apply to past logs" offer).
      const c = CompoundDefinition(
        id: 'c1', base: 'Testium', ester: 'Enanthate',
        type: CompoundType.steroid, graphType: GraphType.curve,
        halfLife: 4.5, timeToPeak: 1.5, ratio: 0.835, unit: Unit.mg,
        colorValue: 0xFF5DC59C, isCustom: true,
      );
      CompoundDefinition? updated;
      await tester.pumpWidget(MaterialApp(
        home: CompoundEditorPage(
          editing: c,
          onTabChanged: (_) {},
          onUpdate: (u) => updated = u,
        ),
      ));
      expect(find.text('83.5'), findsOneWidget);

      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(updated, isNotNull);
      expect(updated!.ratio, 0.835);
    });

    for (final (text, ratio) in [('100', 1.0), ('0,5', 0.005), ('72', 0.72)]) {
      testWidgets('yield "$text" saves as ratio $ratio', (tester) async {
        CompoundDefinition? created;
        await pumpCreate(tester, (c) => created = c);
        await fillValidSteroid(tester);
        await tester.enterText(_yield, text);
        await tester.pump();

        await tapSave(tester);
        expect(created, isNotNull);
        expect(created!.ratio, closeTo(ratio, 1e-12));
      });
    }
  });

  group('PK validation', () {
    Future<CompoundDefinition?> trySave(
      WidgetTester tester, {
      required String halfLife,
      required String timeToPeak,
    }) async {
      CompoundDefinition? created;
      await pumpCreate(tester, (c) => created = c);
      await tester.enterText(_name, 'Testium');
      await tester.enterText(_ester, 'Enanthate');
      await tester.enterText(_halfLife, halfLife);
      await tester.enterText(_timeToPeak, timeToPeak);
      await tester.pump();
      await tapSave(tester);
      return created;
    }

    // The Bateman ka solver can only reach tmax < t½ / ln 2 (ka → ke);
    // for t½ 4.5 d that limit is 6.492 d.
    testWidgets('time to peak at or past t½/ln2 blocks save with a reason', (tester) async {
      final created = await trySave(tester, halfLife: '4.5', timeToPeak: '6.5');
      expect(created, isNull);
      expect(find.textContaining('Time to peak must be under 6.492 d'), findsOneWidget);
    });

    testWidgets('time to peak just under t½/ln2 saves', (tester) async {
      final created = await trySave(tester, halfLife: '4,5', timeToPeak: '6,49');
      expect(created, isNotNull);
      expect(created!.timeToPeak, 6.49);
    });

    testWidgets('an empty time to peak still saves as 0 (instant absorption)', (tester) async {
      final created = await trySave(tester, halfLife: '4.5', timeToPeak: '');
      expect(created, isNotNull);
      expect(created!.timeToPeak, 0);
    });

    for (final (hl, tp) in [
      ('366', '1'), // t½ over 365 d
      ('1e308', '1'), // huge finite input (N5)
      ('365', '61'), // tmax over 60 d
      ('4.5', '-1'), // negative tmax
      ('4.5', 'abc'), // unparseable tmax
    ]) {
      testWidgets('t½ "$hl" / tmax "$tp" is rejected with a message', (tester) async {
        final created = await trySave(tester, halfLife: hl, timeToPeak: tp);
        expect(created, isNull);
        expect(
          find.textContaining(RegExp(r'^(Half-life|Time to peak) must be')),
          findsOneWidget,
        );
      });
    }

    testWidgets('upper bounds are inclusive: t½ 365 d, tmax 60 d', (tester) async {
      final created = await trySave(tester, halfLife: '365', timeToPeak: '60');
      expect(created, isNotNull);
    });

    testWidgets('a legacy compound with an unreachable tmax must be fixed before saving', (tester) async {
      const legacy = CompoundDefinition(
        id: 'c1', base: 'Testium', ester: 'Enanthate',
        type: CompoundType.steroid, graphType: GraphType.curve,
        halfLife: 1, timeToPeak: 2, ratio: 1, unit: Unit.mg,
        colorValue: 0xFF5DC59C, isCustom: true,
      );
      CompoundDefinition? updated;
      await tester.pumpWidget(MaterialApp(
        home: CompoundEditorPage(
          editing: legacy, onTabChanged: (_) {}, onUpdate: (u) => updated = u,
        ),
      ));
      expect(find.textContaining('Time to peak must be under 1.442 d'), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(updated, isNull);
    });

    testWidgets('every built-in opens with values the editor accepts', (tester) async {
      for (final entry in BASE_LIBRARY.entries) {
        CompoundDefinition? updated;
        // Fresh navigator per entry: Save pops the editor route.
        await tester.pumpWidget(MaterialApp(
          key: ValueKey(entry.key),
          home: CompoundEditorPage(
            editing: entry.value,
            onTabChanged: (_) {},
            onUpdate: (u) => updated = u,
          ),
        ));
        await tester.tap(find.text('Save changes'));
        await tester.pump();
        expect(updated, isNotNull, reason: '${entry.key} should be saveable');
      }
    });
  });

  group('blends (B9)', () {
    // The engine models Sustanon / Tri-Tren from SUSTANON_BLEND / TREN_BLEND
    // and ignores the compound's own t½ / tmax / yield.
    for (final key in ['Sustanon 250', 'Tri-Tren']) {
      testWidgets('$key: PK fields are read-only with a note', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: CompoundEditorPage(
            editing: BASE_LIBRARY[key]!.copyWith(id: key),
            onTabChanged: (_) {},
          ),
        ));
        expect(_halfLife, findsNothing);
        expect(_timeToPeak, findsNothing);
        expect(_yield, findsNothing);
        expect(find.textContaining('Modelled from its'), findsOneWidget);
      });

      testWidgets('$key: saving never changes its PK values', (tester) async {
        // Even a legacy override whose t½ was edited before the lock.
        final stored = BASE_LIBRARY[key]!.copyWith(id: key, halfLife: 20, timeToPeak: 3, ratio: 0.5);
        CompoundDefinition? updated;
        await tester.pumpWidget(MaterialApp(
          home: CompoundEditorPage(
            editing: stored,
            onTabChanged: (_) {},
            onUpdate: (u) => updated = u,
          ),
        ));
        // A non-PK edit: pick another lane color.
        await tapSwatch(tester, 0xFF7DD3D0);
        await tester.tap(find.text('Save changes'));
        await tester.pump();

        expect(updated, isNotNull);
        expect(updated!.colorValue, 0xFF7DD3D0);
        expect(updated!.halfLife, 20);
        expect(updated!.timeToPeak, 3);
        expect(updated!.ratio, 0.5);
      });
    }

    testWidgets('Reset to default still restores a legacy-edited blend', (tester) async {
      final stored = BASE_LIBRARY['Sustanon 250']!
          .copyWith(id: 'Sustanon 250', halfLife: 20, timeToPeak: 3, ratio: 0.5);
      CompoundDefinition? updated;
      await tester.pumpWidget(MaterialApp(
        home: CompoundEditorPage(
          editing: stored, onTabChanged: (_) {}, onUpdate: (u) => updated = u,
        ),
      ));
      expect(find.text('20'), findsOneWidget);
      await tester.tap(find.text('Reset to default'));
      await tester.pump();
      expect(find.text('20'), findsNothing);
      await tester.tap(find.text('Save changes'));
      await tester.pump();

      final def = BASE_LIBRARY['Sustanon 250']!;
      expect(updated!.halfLife, def.halfLife);
      expect(updated!.timeToPeak, def.timeToPeak);
      expect(updated!.ratio, def.ratio);
    });

    testWidgets('a custom typed with a blend ester gets read-only PK too (create)', (tester) async {
      CompoundDefinition? created;
      await pumpCreate(tester, (c) => created = c);
      await tester.enterText(_name, 'Testium');
      await tester.enterText(_ester, 'Sustanon (Mix)');
      await tester.pump();

      expect(_halfLife, findsNothing);
      expect(find.textContaining('Modelled from its'), findsOneWidget);
      await tapSave(tester);
      // Stored values are display-only; they come from the longest-lasting
      // component so the record stays well-formed.
      expect(created, isNotNull);
      expect(created!.halfLife, 15.0);
      expect(created!.timeToPeak, 2.0);
      expect(created!.ratio, 0.65);
    });
  });

  group('custom compounds: identity (B10) + delete (B11)', () {
    const custom = CompoundDefinition(
      id: 'c1', base: 'Testium', ester: 'Enanthate',
      type: CompoundType.steroid, graphType: GraphType.curve,
      halfLife: 4.5, timeToPeak: 1.5, ratio: 1, unit: Unit.mg,
      colorValue: 0xFF5DC59C, isCustom: true,
    );

    Future<void> pumpEdit(
      WidgetTester tester, {
      CompoundDefinition editing = custom,
      int logCount = 0,
      int linkedReminderCount = 0,
      List<CompoundDefinition> userCompounds = const [custom],
      void Function(CompoundDefinition)? onUpdate,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: CompoundEditorPage(
          editing: editing,
          logCount: logCount,
          linkedReminderCount: linkedReminderCount,
          userCompounds: userCompounds,
          onTabChanged: (_) {},
          onUpdate: onUpdate,
          onDelete: () {},
        ),
      ));
    }

    testWidgets('a custom with logs has a locked name, ester and type', (tester) async {
      CompoundDefinition? updated;
      await pumpEdit(tester, logCount: 3, onUpdate: (u) => updated = u);

      expect(_name, findsNothing);
      expect(_ester, findsNothing);
      expect(find.text('Peptide'), findsNothing); // no type selector
      expect(find.textContaining('3 logs refer to this compound'), findsOneWidget);

      await tapSwatch(tester, 0xFFB5A8E0);
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(updated!.base, 'Testium');
      expect(updated!.ester, 'Enanthate');
      expect(updated!.type, CompoundType.steroid);
      expect(updated!.colorValue, 0xFFB5A8E0);
    });

    testWidgets('linked reminders lock the identity too', (tester) async {
      await pumpEdit(tester, linkedReminderCount: 1);
      expect(_name, findsNothing);
      expect(find.textContaining('1 reminder refers to this compound'), findsOneWidget);
    });

    testWidgets('logs and reminders are both named in the lock reason', (tester) async {
      await pumpEdit(tester, logCount: 1, linkedReminderCount: 2);
      expect(find.textContaining('1 log and 2 reminders refer to this compound'), findsOneWidget);
    });

    testWidgets('an unused custom can still be renamed', (tester) async {
      CompoundDefinition? updated;
      await pumpEdit(tester, onUpdate: (u) => updated = u);
      expect(_name, findsOneWidget);
      await tester.enterText(_name, 'Testium II');
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(updated!.base, 'Testium II');
    });

    testWidgets('keeping its own name (or changing only its case) is no clash', (tester) async {
      CompoundDefinition? updated;
      await pumpEdit(tester, onUpdate: (u) => updated = u);
      await tester.enterText(_name, 'TESTIUM');
      await tester.pump();
      expect(find.textContaining('already in the library'), findsNothing);
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(updated!.base, 'TESTIUM');
    });

    testWidgets('renaming onto another custom is blocked', (tester) async {
      const other = CompoundDefinition(
        id: 'c2', base: 'Otherium', ester: 'Enanthate',
        type: CompoundType.steroid, graphType: GraphType.curve,
        halfLife: 4.5, timeToPeak: 1.5, ratio: 1, unit: Unit.mg,
        colorValue: 0xFF5DC59C, isCustom: true,
      );
      CompoundDefinition? updated;
      await pumpEdit(tester,
          userCompounds: const [custom, other], onUpdate: (u) => updated = u);
      await tester.enterText(_name, 'Otherium');
      await tester.pump();
      expect(find.textContaining('Otherium Enanthate is already in the library'), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(updated, isNull);
    });

    for (final (base, ester, label) in [
      ('Testosterone', 'Enanthate', 'Testosterone Enanthate'), // built-in
      ('testosterone ', ' enanthate', 'Testosterone Enanthate'), // case/space
    ]) {
      testWidgets('creating "$base|$ester" clashes with built-in $label', (tester) async {
        CompoundDefinition? created;
        await pumpCreate(tester, (c) => created = c);
        await tester.enterText(_name, base);
        await tester.enterText(_ester, ester);
        await tester.enterText(_halfLife, '4.5');
        await tester.pump();
        expect(find.textContaining('$label is already in the library'), findsOneWidget);
        await tapSave(tester);
        expect(created, isNull);
      });
    }

    group('delete (B11)', () {
      final dialogDelete = find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete'));

      Future<int> pumpWithDelete(
        WidgetTester tester, {
        int logCount = 0,
        int linkedReminderCount = 0,
      }) async {
        var deletes = 0;
        await tester.pumpWidget(MaterialApp(
          home: CompoundEditorPage(
            editing: custom,
            logCount: logCount,
            linkedReminderCount: linkedReminderCount,
            onTabChanged: (_) {},
            onDelete: () => deletes++,
          ),
        ));
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        return deletes;
      }

      testWidgets('asks before deleting; Cancel keeps the compound', (tester) async {
        var deletes = 0;
        await tester.pumpWidget(MaterialApp(
          home: CompoundEditorPage(
            editing: custom, onTabChanged: (_) {}, onDelete: () => deletes++,
          ),
        ));
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Delete compound'), findsOneWidget);
        expect(find.text('Delete Testium Enanthate?'), findsOneWidget);
        expect(deletes, 0);

        await tester.tap(find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Cancel')));
        await tester.pumpAndSettle();
        expect(deletes, 0);

        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(dialogDelete);
        await tester.pumpAndSettle();
        expect(deletes, 1);
      });

      testWidgets('names the logs and linked reminders that go with it', (tester) async {
        await pumpWithDelete(tester, logCount: 3, linkedReminderCount: 2);
        final body = find.descendant(
            of: find.byType(AlertDialog), matching: find.textContaining('Delete Testium'));
        final text = tester.widget<Text>(body).data!;
        expect(text, contains('3 injections of this compound will keep their logged data'));
        expect(text, contains('Its 2 reminders will be removed too.'));
      });

      testWidgets('a single reminder reads naturally', (tester) async {
        await pumpWithDelete(tester, linkedReminderCount: 1);
        expect(find.textContaining('Its reminder will be removed too.'), findsOneWidget);
      });

      testWidgets('no reminder sentence without reminders', (tester) async {
        await pumpWithDelete(tester, logCount: 1);
        expect(find.textContaining('reminder'), findsNothing);
      });
    });

    testWidgets('a non-steroid clashes on base alone (ester None)', (tester) async {
      CompoundDefinition? created;
      await pumpCreate(tester, (c) => created = c);
      await tester.tap(find.text('Peptide'));
      await tester.pump();
      await tester.enterText(_name, 'BPC-157');
      await tester.enterText(_halfLife, '0.25');
      await tester.pump();
      expect(find.textContaining('BPC-157 is already in the library'), findsOneWidget);
      await tapSave(tester);
      expect(created, isNull);
    });
  });

  group('dose unit choices (N3)', () {
    // Same rule as the wizard (doseUnitOptions of the native unit): IU-native
    // compounds dose only in IU, everything else in mg or mcg.
    List<String> unitLabels(WidgetTester tester) => [
          for (final label in ['mg', 'mcg', 'IU'])
            if (find.text(label).evaluate().isNotEmpty) label,
        ];

    Future<void> pumpEditing(WidgetTester tester, CompoundDefinition c,
        {void Function(CompoundDefinition)? onUpdate}) async {
      await tester.pumpWidget(MaterialApp(
        home: CompoundEditorPage(
          editing: c, onTabChanged: (_) {}, onUpdate: onUpdate,
        ),
      ));
    }

    testWidgets('IU-native built-in (HCG) offers IU only', (tester) async {
      await pumpEditing(tester, BASE_LIBRARY['HCG']!);
      expect(unitLabels(tester), ['IU']);
    });

    testWidgets('mass-dosed built-in (Semaglutide) offers mg and mcg', (tester) async {
      await pumpEditing(tester, BASE_LIBRARY['Semaglutide']!);
      expect(unitLabels(tester), ['mg', 'mcg']);
    });

    testWidgets('a legacy override in a unit no longer offered falls back to native', (tester) async {
      // Older versions stored HCG with whatever unit its first log used.
      CompoundDefinition? updated;
      await pumpEditing(tester, BASE_LIBRARY['HCG']!.copyWith(id: 'h', unit: Unit.mg),
          onUpdate: (u) => updated = u);
      expect(unitLabels(tester), ['IU']);
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(updated!.unit, Unit.iu);
    });

    testWidgets('a custom keeps its own unit family', (tester) async {
      const iuCustom = CompoundDefinition(
        id: 'c', base: 'Gonadium', ester: 'None',
        type: CompoundType.peptide, graphType: GraphType.activeWindow,
        halfLife: 1, timeToPeak: 0.2, ratio: 1, unit: Unit.iu,
        colorValue: 0xFF8FC5A8, isCustom: true,
      );
      await pumpEditing(tester, iuCustom);
      expect(unitLabels(tester), ['IU']);

      await pumpEditing(tester, iuCustom.copyWith(id: 'd', unit: Unit.mcg));
      expect(unitLabels(tester), ['mg', 'mcg']);
    });

    testWidgets('a new compound may pick any unit', (tester) async {
      await pumpCreate(tester, (_) {});
      expect(unitLabels(tester), ['mg', 'mcg', 'IU']);
    });
  });

  group('leaving with unsaved edits (B25)', () {
    const custom = CompoundDefinition(
      id: 'c1', base: 'Testium', ester: 'Enanthate',
      type: CompoundType.steroid, graphType: GraphType.curve,
      halfLife: 4.5, timeToPeak: 1.5, ratio: 1, unit: Unit.mg,
      colorValue: 0xFF5DC59C, isCustom: true,
    );
    final discardPrompt = find.text('Discard changes?');
    bool editorOpen() => find.byType(CompoundEditorPage).evaluate().isNotEmpty;

    /// Pushes the editor over a home route, as the app does.
    Future<void> pumpPushed(
      WidgetTester tester, {
      CompoundDefinition? editing,
      void Function(ShellTab)? onTabChanged,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CompoundEditorPage(
                    editing: editing,
                    onTabChanged: onTabChanged ?? (_) {},
                  ),
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(editorOpen(), isTrue);
    }

    Future<void> systemBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    testWidgets('just tapping a field is not an edit', (tester) async {
      await pumpPushed(tester);
      await tester.tap(_name);
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(discardPrompt, findsNothing);
      expect(editorOpen(), isFalse);
    });

    testWidgets('an edit that is undone again is not an edit', (tester) async {
      await pumpPushed(tester, editing: custom);
      await tester.enterText(_halfLife, '9');
      await tester.enterText(_halfLife, '4,5'); // same value, comma spelling
      await tapSwatch(tester, 0xFFB5A8E0);
      await tapSwatch(tester, 0xFF5DC59C); // back to the original color
      await systemBack(tester);
      expect(discardPrompt, findsNothing);
      expect(editorOpen(), isFalse);
    });

    testWidgets('system back with edits asks first', (tester) async {
      await pumpPushed(tester);
      await tester.enterText(_name, 'Testium');
      await tester.pump();

      await systemBack(tester);
      expect(discardPrompt, findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(editorOpen(), isTrue);
      expect(find.text('Testium'), findsOneWidget);

      await systemBack(tester);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(editorOpen(), isFalse);
    });

    testWidgets('Save still leaves while there are edits', (tester) async {
      await pumpPushed(tester);
      await fillValidSteroid(tester);
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(discardPrompt, findsNothing);
      expect(editorOpen(), isFalse);
    });

    testWidgets('system back without edits just leaves', (tester) async {
      await pumpPushed(tester, editing: custom);
      await systemBack(tester);
      expect(discardPrompt, findsNothing);
      expect(editorOpen(), isFalse);
    });

    testWidgets('a shell tab tap with edits asks first', (tester) async {
      final tabs = <ShellTab>[];
      await pumpPushed(tester, editing: custom, onTabChanged: tabs.add);
      await tapSwatch(tester, 0xFFB5A8E0);

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(discardPrompt, findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(tabs, isEmpty);
      expect(editorOpen(), isTrue);

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(tabs, [ShellTab.today]);
      expect(editorOpen(), isFalse);
    });

    testWidgets('a shell tab tap without edits switches straight away', (tester) async {
      final tabs = <ShellTab>[];
      await pumpPushed(tester, editing: custom, onTabChanged: tabs.add);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(discardPrompt, findsNothing);
      expect(tabs, [ShellTab.today]);
      expect(editorOpen(), isFalse);
    });
  });
}
