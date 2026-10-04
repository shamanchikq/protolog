import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/theme.dart';
import 'package:protolog_tracker/ui/views/bloodwork_page.dart';
import 'package:protolog_tracker/ui/widgets/pk_chart_card.dart';
import 'package:protolog_tracker/ui/widgets/pk_graph_painter.dart';

import 'pk_chart_test_support.dart';
import 'real_fonts.dart';

// Painted chart labels follow the system text size (they ignored it), up to
// maxChartTextScale so axis labels can't blow past the plot insets.

const _size = Size(400, 240);

Widget _scaled(double scale, Widget child) => MaterialApp(
      home: Builder(
        builder: (ctx) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );

void main() {
  // Real glyph heights: the box test font is too short to overflow.
  setUpAll(loadAppFonts);

  final data = pkData(curves: [pkCurve('Testosterone', 300)], maxMg: 330);

  /// Widths of the five date labels, recovered from their centred positions.
  List<double> dateLabelWidths(List<RecordedInvocation> calls) {
    final offsets = paintedParagraphs(calls).toList();
    final dates = offsets.sublist(offsets.length - 5);
    const chartWidth = 400 - pkPaddingLeft - pkPaddingRight;
    return [
      for (var i = 0; i < 5; i++) 2 * (pkPaddingLeft + i / 4 * chartWidth - dates[i].dx),
    ];
  }

  /// Height of a tick label at [scale].
  double tickHeight(double scale) {
    final tp = TextPainter(
      text: TextSpan(text: '0', style: AppTheme.mono(color: AppTheme.fgDimText, size: 9)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(scale),
    )..layout();
    final h = tp.height;
    tp.dispose();
    return h;
  }

  test('PKGraphPainter scales its tick labels', () {
    final plain = dateLabelWidths(recordPaint(PKGraphPainter(graphData: data), _size));
    final large = dateLabelWidths(recordPaint(
      PKGraphPainter(graphData: data, textScaler: const TextScaler.linear(1.3)),
      _size,
    ));
    for (var i = 0; i < 5; i++) {
      expect(large[i], closeTo(plain[i] * 1.3, 0.5));
    }
  });

  test('at 1.0× the plot keeps its 20 px bottom inset', () {
    final calls = recordPaint(PKGraphPainter(graphData: data), _size);
    final dateLabels = paintedParagraphs(calls).where((o) => o.dy > _size.height - pkPaddingBottom);
    expect(dateLabels, hasLength(5));
    for (final o in dateLabels) {
      expect(o.dy, closeTo(_size.height - pkPaddingBottom + 6, 0.01));
    }
  });

  test('larger labels get a taller bottom inset instead of spilling out', () {
    final calls = recordPaint(
      PKGraphPainter(graphData: data, textScaler: const TextScaler.linear(1.3)),
      _size,
    );
    final dates = paintedParagraphs(calls).toList().reversed.take(5);
    for (final o in dates) {
      expect(o.dy + tickHeight(1.3), lessThanOrEqualTo(_size.height + 0.01));
    }
  });

  for (final (system, expected) in [(1.0, 1.0), (1.15, 1.15), (1.3, 1.3), (2.0, maxChartTextScale)]) {
    testWidgets('PKChartCard at system ${system}x paints at ${expected}x', (tester) async {
      await tester.pumpWidget(_scaled(
        system,
        PKChartCard(
          graphData: data,
          settings: pkSettings(),
          onRangeChanged: (_) {},
          onSettingsChanged: (_) {},
        ),
      ));
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<PKGraphPainter>()
          .single;
      expect(painter.textScaler.scale(10), closeTo(10 * expected, 1e-9));
    });
  }

  testWidgets('the bloodwork trend chart follows the text scale too', (tester) async {
    await tester.pumpWidget(_scaled(
      2.0,
      SizedBox(
        height: 1200,
        child: BloodworkPage(
          initialEntries: [
            BloodworkEntry(id: '1', date: DateTime(2026, 5, 1), marker: 'Total T', value: 30, unit: 'nmol/L'),
            BloodworkEntry(id: '2', date: DateTime(2026, 7, 1), marker: 'Total T', value: 38.5, unit: 'nmol/L'),
          ],
          onChanged: (_) {},
        ),
      ),
    ));
    final scalers = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .where((p) => p != null && p.runtimeType.toString() == '_TrendPainter')
        .map((p) => (p as dynamic).textScaler as TextScaler)
        .toList();
    expect(scalers, hasLength(1));
    expect(scalers.single.scale(10), closeTo(10 * maxChartTextScale, 1e-9));
  });
}
