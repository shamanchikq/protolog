import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/widgets/pk_graph_painter.dart';

const _size = Size(400, 240);
// skipPeptides → no lane area; chart height = size.height − 20 px bottom pad.
const _chartHeight = 220.0;
const _paddingRight = 20.0;

GraphSettings _settings({bool normalized = false}) => GraphSettings(
      normalized: normalized,
      cumulative: false,
      showPeptides: false,
      timeRange: 'standard',
    );

ComputedGraphData _data({
  List<CurveData> curves = const [],
  List<InjectionMarkerData> markers = const [],
  double maxMg = 11,
  double maxOralMg = 6,
}) {
  final start = DateTime.now().subtract(const Duration(days: 28));
  final end = start.add(const Duration(days: 63));
  return ComputedGraphData(
    curves: curves,
    peptideLanes: const [],
    laneLabels: const [],
    maxMg: maxMg,
    maxOralMg: maxOralMg,
    startDate: start,
    endDate: end,
    totalDurationMs: end.difference(start).inMilliseconds,
    laneCount: 0,
    injectionMarkers: markers,
  );
}

CurveData _curve(String base, double peak, {bool oral = false}) => CurveData(
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

List<RecordedInvocation> _paint(ComputedGraphData data, GraphSettings s) {
  final canvas = TestRecordingCanvas();
  PKGraphPainter(graphData: data, settings: s, skipPeptides: true)
      .paint(canvas, _size);
  return canvas.invocations;
}

Iterable<Offset> _circles(List<RecordedInvocation> calls) => calls
    .where((c) => c.invocation.memberName == #drawCircle)
    .map((c) => c.invocation.positionalArguments[0] as Offset);

Iterable<Offset> _paragraphs(List<RecordedInvocation> calls) => calls
    .where((c) => c.invocation.memberName == #drawParagraph)
    .map((c) => c.invocation.positionalArguments[1] as Offset);

void main() {
  group('"% of peak" markers (B35)', () {
    test('sit on their curve, not on the baseline', () {
      final data = _data(
        curves: [_curve('Testosterone', 200)],
        markers: [InjectionMarkerData(0.3, 100, false, 0xFF5DC59C, 'Testosterone')],
        maxMg: 220,
      );
      final circles = _circles(_paint(data, _settings(normalized: true))).toList();
      expect(circles, hasLength(1));
      // 100 / curve peak 200 → half height.
      expect(circles.single.dy, closeTo(_chartHeight / 2, 0.01));
    });

    test('each marker normalizes against its own curve', () {
      final data = _data(
        curves: [
          _curve('Testosterone', 400),
          _curve('Oxandrolone', 40, oral: true),
        ],
        markers: [
          InjectionMarkerData(0.5, 400, false, 0xFF5DC59C, 'Testosterone'),
          InjectionMarkerData(0.3, 10, true, 0xFFC9B062, 'Oxandrolone'),
        ],
        maxMg: 440,
        maxOralMg: 48,
      );
      final circles = _circles(_paint(data, _settings(normalized: true))).toList();
      expect(circles[0].dy, closeTo(0, 0.01)); // at its own peak
      expect(circles[1].dy, closeTo(_chartHeight * 0.75, 0.01)); // 10 / 40
    });
  });

  group('oral axis (B36)', () {
    bool rightAxisDrawn(List<RecordedInvocation> calls) =>
        _paragraphs(calls).any((o) => o.dx > _size.width - _paddingRight);

    test('not drawn for a steroid-only chart (engine floors maxOralMg to 6)', () {
      final data = _data(curves: [_curve('Testosterone', 300)], maxMg: 330, maxOralMg: 6);
      expect(rightAxisDrawn(_paint(data, _settings())), isFalse);
    });

    test('drawn when an oral curve exists', () {
      final data = _data(
        curves: [_curve('Testosterone', 300), _curve('Oxandrolone', 4, oral: true)],
        maxMg: 330,
        maxOralMg: 6,
      );
      expect(rightAxisDrawn(_paint(data, _settings())), isTrue);
    });

    test('no y tick labels at all on an empty chart', () {
      final calls = _paint(_data(), _settings());
      // Only the five x-axis date labels, below the chart.
      final labels = _paragraphs(calls).toList();
      expect(labels, hasLength(5));
      expect(labels.every((o) => o.dy > _chartHeight), isTrue);
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
      final data = _data(
        curves: [_curve('Testosterone', 300)],
        markers: [InjectionMarkerData(0.3, 100, false, 0xFF5DC59C, 'Testosterone')],
        maxMg: 330, // → axis max 400
      );
      final circle = _circles(_paint(data, _settings())).single;
      expect(circle.dy, closeTo(_chartHeight * (1 - 100 / 400), 0.01));
    });
  });
}
