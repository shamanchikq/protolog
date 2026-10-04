import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/ui/widgets/lab_tap.dart';
import 'package:protolog_tracker/ui/widgets/tap_target.dart';

/// A 30 × 20 control at [at], recording its taps.
Widget _small(String id, List<String> taps, {Key? key}) => LabTap(
      key: key,
      onTap: () => taps.add(id),
      child: SizedBox(width: 30, height: 20, child: Center(child: Text(id))),
    );

Future<void> _pump(WidgetTester tester, Widget body, {bool scoped = true}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 400);
  addTearDown(tester.view.reset);
  final content = Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(children: [body]),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: scoped ? TapTargetScope(child: content) : content),
  ));
}

void main() {
  group('TapTarget', () {
    testWidgets('lays out and paints exactly like its child', (tester) async {
      await _pump(
        tester,
        const Positioned(
          left: 100,
          top: 100,
          child: TapTarget(child: SizedBox(key: Key('box'), width: 30, height: 20)),
        ),
      );
      expect(tester.getRect(find.byKey(const Key('box'))),
          const Rect.fromLTWH(100, 100, 30, 20));
      expect(tester.getSize(find.byType(TapTarget)), const Size(30, 20));
    });

    testWidgets('a near miss inside a scope reaches the control', (tester) async {
      final taps = <String>[];
      await _pump(tester, Positioned(left: 100, top: 100, child: _small('a', taps)));
      // The 30 × 20 box grows to 48 × 48 around its centre (115, 110):
      // x 91..139, y 86..134.
      await tester.tapAt(const Offset(115, 88)); // 12 px above
      await tester.tapAt(const Offset(93, 110)); // 7 px left
      await tester.tapAt(const Offset(137, 132)); // below right
      expect(taps, ['a', 'a', 'a']);
      await tester.tapAt(const Offset(115, 84)); // outside 48 × 48
      await tester.tapAt(const Offset(141, 110));
      expect(taps, hasLength(3));
    });

    testWidgets('without a scope only the box is touchable', (tester) async {
      final taps = <String>[];
      await _pump(tester, Positioned(left: 100, top: 100, child: _small('a', taps)),
          scoped: false);
      await tester.tapAt(const Offset(115, 88));
      expect(taps, isEmpty);
      await tester.tapAt(const Offset(115, 110));
      expect(taps, ['a']);
    });

    testWidgets('the closest of two near targets wins; a direct hit stays put', (tester) async {
      final taps = <String>[];
      await _pump(
        tester,
        Positioned(
          left: 100,
          top: 100,
          child: Row(children: [
            _small('a', taps),
            const SizedBox(width: 4),
            _small('b', taps),
          ]),
        ),
      );
      // a: x 100..130, b: x 134..164; the gap is 130..134.
      await tester.tapAt(const Offset(131, 110));
      await tester.tapAt(const Offset(133, 110));
      // Inside b's box but within a's grown area: b keeps it.
      await tester.tapAt(const Offset(136, 110));
      expect(taps, ['a', 'b', 'b']);
    });

    testWidgets('a near miss on a button inside a tappable row opens the button', (tester) async {
      final taps = <String>[];
      await _pump(
        tester,
        Positioned(
          left: 0,
          top: 100,
          width: 400,
          child: LabTap(
            mergeSemantics: false,
            onTap: () => taps.add('row'),
            child: SizedBox(
              height: 44,
              child: Row(children: [
                const Expanded(child: Text('row')),
                _small('icon', taps),
                const SizedBox(width: 40),
              ]),
            ),
          ),
        ),
      );
      // icon: x 330..360, y 112..132 → grown 321..369 × 98..146.
      await tester.tapAt(const Offset(325, 122));
      await tester.tapAt(const Offset(345, 141)); // below the icon, still in the row
      expect(taps, ['icon', 'icon']);
      await tester.tapAt(const Offset(100, 122));
      await tester.tapAt(const Offset(375, 122)); // right of the icon's area
      expect(taps, ['icon', 'icon', 'row', 'row']);
    });

    testWidgets('a target scrolled out of view does not catch touches', (tester) async {
      final taps = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        Positioned(
          left: 0,
          top: 100,
          width: 400,
          height: 100,
          child: ListView(
            controller: controller,
            children: [
              const SizedBox(height: 105),
              Row(children: [const SizedBox(width: 100), _small('a', taps)]),
              const SizedBox(height: 400),
            ],
          ),
        ),
      );
      // The control sits at y 205..225, just below the viewport (100..200);
      // its grown area (191..239) reaches into it but it is clipped away.
      await tester.tapAt(const Offset(115, 196));
      expect(taps, isEmpty);
      controller.jumpTo(30);
      await tester.pump();
      await tester.tapAt(const Offset(115, 167)); // 8 px above, now visible
      expect(taps, ['a']);
    });

    testWidgets('a drag starting in the grown area still scrolls', (tester) async {
      final taps = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        Positioned.fill(
          child: ListView(
            controller: controller,
            children: [
              const SizedBox(height: 100),
              Row(children: [const SizedBox(width: 100), _small('a', taps)]),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      );
      await tester.dragFrom(const Offset(115, 90), const Offset(0, -60));
      await tester.pump();
      expect(controller.offset, greaterThan(0));
      expect(taps, isEmpty);
    });

    testWidgets('semantics report the 48 × 48 area inside a scope', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, Positioned(left: 100, top: 100, child: _small('a', [])));
      final node = tester.getSemantics(find.byType(TapTargetBox));
      expect(node.rect.size, const Size(48, 48));
      expect(node.label, 'a');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('…and the child box without one', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, Positioned(left: 100, top: 100, child: _small('a', [])),
          scoped: false);
      expect(tester.getSemantics(find.byType(TapTargetBox)).rect.size, const Size(30, 20));
      handle.dispose();
    });
  });

  group('LabTap semantics', () {
    testWidgets('button with state; a label replaces glyph text', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Positioned(
          left: 100,
          top: 100,
          child: Row(children: [
            LabTap(onTap: () {}, selected: true, inMutuallyExclusiveGroup: true, child: const Text('7d')),
            LabTap(onTap: () {}, label: 'Next month', child: const Text('›')),
            LabTap(onTap: () {}, toggled: false, label: 'Reminder on', child: const SizedBox(width: 34, height: 19)),
            const LabTap(onTap: null, child: Text('Save')),
          ]),
        ),
      );
      expect(
        tester.getSemantics(find.ancestor(of: find.text('7d'), matching: find.byType(TapTargetBox))),
        matchesSemantics(
          label: '7d',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.ancestor(of: find.text('›'), matching: find.byType(TapTargetBox))),
        matchesSemantics(
          label: 'Next month',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.ancestor(of: find.text('Save'), matching: find.byType(TapTargetBox))),
        matchesSemantics(label: 'Save', isButton: true, hasEnabledState: true),
      );
      handle.dispose();
    });
  });
}
