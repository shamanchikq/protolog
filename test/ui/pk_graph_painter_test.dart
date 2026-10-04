import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/widgets/pk_graph_painter.dart';

import 'pk_chart_test_support.dart';

const _size = Size(400, 240);
// No lane area; chart height = size.height − 20 px bottom pad.
const _chartHeight = 220.0;

List<RecordedInvocation> _paint(ComputedGraphData data) =>
    recordPaint(PKGraphPainter(graphData: data), _size);

void main() {
  group('"% of peak" markers (B35)', () {
    test('sit on their curve, not on the baseline', () {
      final data = pkData(
        curves: [pkCurve('Testosterone', 200)],
        markers: [InjectionMarkerData(0.3, 100, false, 0xFF5DC59C, 'Testosterone')],
        maxMg: 220,
        settings: pkSettings(normalized: true),
      );
      final circles = paintedCircles(_paint(data)).toList();
      expect(circles, hasLength(1));
      // 100 / curve peak 200 → half height.
      expect(circles.single.dy, closeTo(_chartHeight / 2, 0.01));
    });

    test('each marker normalizes against its own curve', () {
      final data = pkData(
        curves: [
          pkCurve('Testosterone', 400),
          pkCurve('Oxandrolone', 40, oral: true),
        ],
        markers: [
          InjectionMarkerData(0.5, 400, false, 0xFF5DC59C, 'Testosterone'),
          InjectionMarkerData(0.3, 10, true, 0xFFC9B062, 'Oxandrolone'),
        ],
        maxMg: 440,
        maxOralMg: 48,
        settings: pkSettings(normalized: true),
      );
      final circles = paintedCircles(_paint(data)).toList();
      expect(circles[0].dy, closeTo(0, 0.01)); // at its own peak
      expect(circles[1].dy, closeTo(_chartHeight * 0.75, 0.01)); // 10 / 40
    });
  });

  group('oral axis (B36)', () {
    bool rightAxisDrawn(List<RecordedInvocation> calls) =>
        paintedParagraphs(calls).any((o) => o.dx > _size.width - pkPaddingRight);

    test('not drawn for a steroid-only chart (engine floors maxOralMg to 6)', () {
      final data = pkData(curves: [pkCurve('Testosterone', 300)], maxMg: 330, maxOralMg: 6);
      expect(rightAxisDrawn(_paint(data)), isFalse);
    });

    test('drawn when an oral curve exists', () {
      final data = pkData(
        curves: [pkCurve('Testosterone', 300), pkCurve('Oxandrolone', 4, oral: true)],
        maxMg: 330,
        maxOralMg: 6,
      );
      expect(rightAxisDrawn(_paint(data)), isTrue);
    });

    test('no y tick labels at all on an empty chart', () {
      final calls = _paint(pkData());
      // Only the five x-axis date labels, below the chart.
      final labels = paintedParagraphs(calls).toList();
      expect(labels, hasLength(5));
      expect(labels.every((o) => o.dy > _chartHeight), isTrue);
    });
  });

  group('draws with the settings the data was computed with (B40)', () {
    test('x labels follow graphData.settings.timeRange', () {
      final standard = pkData(curves: [pkCurve('Testosterone', 300)], maxMg: 330);
      final zoom = pkData(
        curves: [pkCurve('Testosterone', 300)],
        maxMg: 330,
        settings: pkSettings(timeRange: 'zoom'),
      );
      // The two label formats really differ in width, so the check below
      // tells them apart.
      expect(expectedXLabelWidths(standard, 'MMM d'),
          isNot(expectedXLabelWidths(standard, 'EEE ha')));
      expectWidths(xLabelWidths(_paint(standard), _size), expectedXLabelWidths(standard, 'MMM d'));
      expectWidths(xLabelWidths(_paint(zoom), _size), expectedXLabelWidths(zoom, 'EEE ha'));
    });

    test('the Σ total fill follows graphData.settings.cumulative', () {
      final total = pkCurve('Total Androgens', 300);
      final withSigma = pkData(
        curves: [total, pkCurve('Testosterone', 300)],
        maxMg: 330,
        settings: pkSettings(cumulative: true),
      );
      expect(paintedCumulativeFill(_paint(withSigma)), isTrue);
      final withoutSigma = pkData(curves: [total, pkCurve('Testosterone', 300)], maxMg: 330);
      expect(paintedCumulativeFill(_paint(withoutSigma)), isFalse);
    });

    test('"% of peak" follows graphData.settings.normalized', () {
      final marker = [InjectionMarkerData(0.3, 150, false, 0xFF5DC59C, 'Testosterone')];
      final absolute = pkData(curves: [pkCurve('Testosterone', 300)], markers: marker, maxMg: 330);
      final normalized = pkData(
        curves: [pkCurve('Testosterone', 300)],
        markers: marker,
        maxMg: 330,
        settings: pkSettings(normalized: true),
      );

      final absCalls = _paint(absolute);
      expectWidths(leftYLabelWidths(absCalls, _size), [for (final t in ['0', '100', '200', '300', '400']) tickTextWidth(t)]);
      expect(paintedCircles(absCalls).single.dy, closeTo(_chartHeight * (1 - 150 / 400), 0.01));

      final normCalls = _paint(normalized);
      expectWidths(leftYLabelWidths(normCalls, _size), [for (final t in ['0%', '25%', '50%', '75%', '100%']) tickTextWidth(t)]);
      expect(paintedCircles(normCalls).single.dy, closeTo(_chartHeight / 2, 0.01)); // 150 / own peak 300
    });
  });

  group('nice y axis', () {
    test('rounds the axis max up to 4 even, readable steps', () {
      expect(niceAxisMax(11), 12); // 0 3 6 9 12
      expect(niceAxisMax(6), 6); // 0 1.5 3 4.5 6
      expect(niceAxisMax(330), 400);
      expect(niceAxisMax(300), 320);
      expect(niceAxisMax(1000), 1000);
      expect(niceAxisMax(0), 1);
      expect(niceAxisMax(double.nan), 1);
    });

    test('markers and curves scale against the nice max', () {
      final data = pkData(
        curves: [pkCurve('Testosterone', 300)],
        markers: [InjectionMarkerData(0.3, 100, false, 0xFF5DC59C, 'Testosterone')],
        maxMg: 330, // → axis max 400
      );
      final circle = paintedCircles(_paint(data)).single;
      expect(circle.dy, closeTo(_chartHeight * (1 - 100 / 400), 0.01));
    });
  });
}
