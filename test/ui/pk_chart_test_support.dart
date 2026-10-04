/// Shared fixtures and canvas-recording helpers for the PK chart tests
/// (`pk_graph_painter_test.dart`, `pk_chart_card_test.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/theme.dart';
import 'package:protolog_tracker/utils.dart';

// Plot insets used by PKGraphPainter.
const double pkPaddingLeft = 45.0;
const double pkPaddingRight = 20.0;
const double pkPaddingBottom = 20.0;

GraphSettings pkSettings({
  bool normalized = false,
  bool cumulative = false,
  String timeRange = 'standard',
}) =>
    GraphSettings(normalized: normalized, cumulative: cumulative, timeRange: timeRange);

/// A 63-day chart starting 28 days ago, computed with [settings]
/// (default: [pkSettings]).
ComputedGraphData pkData({
  List<CurveData> curves = const [],
  List<InjectionMarkerData> markers = const [],
  double maxMg = 11,
  double maxOralMg = 6,
  GraphSettings? settings,
}) {
  final start = DateTime.now().subtract(const Duration(days: 28));
  final end = start.add(const Duration(days: 63));
  return ComputedGraphData(
    settings: settings ?? pkSettings(),
    curves: curves,
    maxMg: maxMg,
    maxOralMg: maxOralMg,
    startDate: start,
    endDate: end,
    totalDurationMs: end.difference(start).inMilliseconds,
    injectionMarkers: markers,
  );
}

/// A curve rising to [peak] at x = 0.5.
CurveData pkCurve(String base, double peak, {bool oral = false}) => CurveData(
      base,
      0xFF5DC59C,
      oral,
      [
        const Offset(0, 0),
        Offset(0.3, peak / 2),
        Offset(0.5, peak),
        const Offset(1, 0),
      ],
    );

/// The canvas calls [painter] makes at [size].
List<RecordedInvocation> recordPaint(CustomPainter painter, Size size) {
  final canvas = TestRecordingCanvas();
  painter.paint(canvas, size);
  return canvas.invocations;
}

Iterable<Offset> paintedCircles(List<RecordedInvocation> calls) => calls
    .where((c) => c.invocation.memberName == #drawCircle)
    .map((c) => c.invocation.positionalArguments[0] as Offset);

Iterable<Offset> paintedParagraphs(List<RecordedInvocation> calls) => calls
    .where((c) => c.invocation.memberName == #drawParagraph)
    .map((c) => c.invocation.positionalArguments[1] as Offset);

/// True when the Σ total's gradient fill was drawn.
bool paintedCumulativeFill(List<RecordedInvocation> calls) => calls.any((c) =>
    c.invocation.memberName == #drawPath &&
    (c.invocation.positionalArguments[1] as Paint).shader != null);

/// Widths of the five x-axis date labels (drawn below the plot area),
/// recovered from their positions: label i is centred on its tick at
/// paddingLeft + i/4 × chart width. (The painter disposes its paragraphs,
/// so they can't be measured after the fact.)
List<double> xLabelWidths(List<RecordedInvocation> calls, Size size) {
  final chartWidth = size.width - pkPaddingLeft - pkPaddingRight;
  final offsets = paintedParagraphs(calls)
      .where((o) => o.dy > size.height - pkPaddingBottom)
      .toList();
  return [
    for (var i = 0; i < offsets.length; i++)
      2 * (pkPaddingLeft + i / 4 * chartWidth - offsets[i].dx),
  ];
}

/// Widths of the left y-axis labels, which end 6 px before the plot.
List<double> leftYLabelWidths(List<RecordedInvocation> calls, Size size) => [
      for (final o in paintedParagraphs(calls)
          .where((o) => o.dy <= size.height - pkPaddingBottom && o.dx < pkPaddingLeft))
        pkPaddingLeft - 6 - o.dx,
    ];

/// Width of [text] in the painter's tick style.
double tickTextWidth(String text) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: AppTheme.mono(color: AppTheme.fgDimText, size: 9, weight: FontWeight.w400),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// The widths of [d]'s five x-axis labels when formatted with [pattern]
/// ('MMM d' or the zoom range's 'EEE ha').
List<double> expectedXLabelWidths(ComputedGraphData d, String pattern) => [
      for (var i = 0; i <= 4; i++)
        tickTextWidth(formatDate(
          DateTime.fromMillisecondsSinceEpoch(
              d.startDate.millisecondsSinceEpoch + (i / 4.0 * d.totalDurationMs).toInt()),
          pattern,
        )),
    ];

void expectWidths(List<double> actual, List<double> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], closeTo(expected[i], 0.01), reason: 'label $i');
  }
}
