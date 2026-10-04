import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../utils.dart';
import '../format.dart';
import '../theme.dart';

/// [max] rounded up so the axis splits into [ticks] even, readable steps
/// (1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8 × 10ⁿ): 11 → 12 (0 3 6 9 12),
/// 330 → 400. 1 for a non-positive or non-finite max.
double niceAxisMax(double max, {int ticks = 4}) {
  if (!max.isFinite || max <= 0) return 1;
  final raw = max / ticks;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  const steps = [1.0, 1.2, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0];
  final f = raw / magnitude;
  final step = steps.firstWhere((s) => f <= s * (1 + 1e-9), orElse: () => 10.0);
  return step * magnitude * ticks;
}

class PKGraphPainter extends CustomPainter {
  final ComputedGraphData graphData;
  final GraphSettings settings;
  final bool skipPeptides;
  final Color? Function(String baseName)? colorResolver;
  final double peptideLaneHeight = 24.0;
  final double leftLabelAreaWidth = 60.0;

  PKGraphPainter({
    required this.graphData,
    required this.settings,
    this.skipPeptides = false,
    this.colorResolver,
  });

  Color _curveColor(CurveData curve) {
    final override = colorResolver?.call(curve.baseName);
    return override ?? curve.color;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final laneCount = skipPeptides ? 0 : graphData.laneLabels.length;
    final topAreaHeight = skipPeptides ? 0.0 : math.max(40.0, (laneCount * peptideLaneHeight) + 20.0);
    final graphHeight = size.height - topAreaHeight;
    final paddingLeft = 45.0;
    final paddingRight = 20.0;
    final paddingBottom = 20.0;
    final chartWidth = size.width - paddingLeft - paddingRight;
    final chartHeight = graphHeight - paddingBottom;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Value curves (the cumulative "Total Androgens" fill only exists on top
    // of them). No curves → nothing to put on a y axis.
    final hasCurves = graphData.curves.any((c) => c.baseName != 'Total Androgens');
    // The engine floors maxOralMg to ≥ 6 even without orals, so the right
    // axis keys off an actual oral curve rather than that value.
    final hasOral = graphData.curves.any((c) => c.isOral);
    final leftMax = niceAxisMax(graphData.maxMg);
    final oralMax = niceAxisMax(graphData.maxOralMg);
    // "% of peak": every curve (and its markers) scales to its own max.
    final normMax = <String, double>{};
    if (settings.normalized) {
      for (final curve in graphData.curves) {
        var m = 0.0;
        for (final p in curve.points) {
          m = math.max(m, p.dy);
        }
        normMax[curve.baseName] = m > 0 ? m : 1.0;
      }
    }

    if (!skipPeptides) {
      final laneBgPaint = Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.5);
      final RRect laneRect = RRect.fromRectAndRadius(Rect.fromLTWH(paddingLeft, 0, chartWidth, topAreaHeight), const Radius.circular(4));
      canvas.drawRRect(laneRect, laneBgPaint);

      for (int i = 0; i < graphData.laneLabels.length; i++) {
        final name = graphData.laneLabels[i];
        final colorValue = graphData.peptideLanes.firstWhere((l) => l.baseName == name, orElse: () => PeptideLaneData(name, 0xFF999999, 0, 0, 0, GraphType.event)).colorValue;
        textPainter.text = TextSpan(text: name, style: TextStyle(color: Color(colorValue), fontSize: 9, fontWeight: FontWeight.bold));
        textPainter.layout();
        textPainter.paint(canvas, Offset(paddingLeft + 5, 5.0 + (i * peptideLaneHeight) + 2));
      }

      canvas.save();
      canvas.clipRRect(laneRect);

      for (var lane in graphData.peptideLanes) {
        final x = paddingLeft + (lane.startPct * chartWidth);
        final y = 5.0 + (lane.laneIndex * peptideLaneHeight);
        final w = lane.durationPct * chartWidth;

        if (x + w < paddingLeft || x > size.width) continue;

        if (lane.type == GraphType.activeWindow) {
          final rect = Rect.fromLTWH(x, y + 14, w, 6);
          final paint = Paint()..shader = LinearGradient(colors: [lane.color.withValues(alpha: 0.95), lane.color.withValues(alpha: 0.45), lane.color.withValues(alpha: 0.12), lane.color.withValues(alpha: 0.0)], stops: const [0.0, 0.25, 0.5, 1.0]).createShader(rect);
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
        } else {
          canvas.drawCircle(Offset(x, y + 17), 3, Paint()..color = lane.color);
        }
      }
      canvas.restore();
    }

    canvas.save();
    canvas.translate(0, topAreaHeight);

    // Horizontal grid: solid baseline at y=chartHeight, dashed elsewhere.
    final gridPaintSolid = Paint()..color = AppTheme.border..strokeWidth = 1..style = PaintingStyle.stroke;
    final gridPaintDashed = Paint()..color = AppTheme.border..strokeWidth = 1..style = PaintingStyle.stroke;
    for (int i = 0; i <= 4; i++) {
      double y = chartHeight - (chartHeight * (i / 4));
      if (i == 0) {
        canvas.drawLine(Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaintSolid);
      } else {
        _drawDashedLine(canvas, Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaintDashed, dash: 2, gap: 3);
      }
    }

    // Vertical x-tick gridlines (dashed) at the same positions as x labels.
    for (int i = 0; i <= 4; i++) {
      final pct = i / 4.0;
      final x = paddingLeft + (pct * chartWidth);
      _drawDashedLine(canvas, Offset(x, 0), Offset(x, chartHeight), gridPaintDashed, dash: 2, gap: 3);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final startMs = graphData.startDate.millisecondsSinceEpoch;
    double todayPct = (nowMs - startMs) / graphData.totalDurationMs;
    double todayX = paddingLeft + (todayPct * chartWidth);
    final bool todayInRange = todayX >= paddingLeft && todayX <= size.width - paddingRight;
    if (todayInRange) {
      canvas.drawLine(
        Offset(todayX, 0),
        Offset(todayX, chartHeight),
        Paint()..color = AppTheme.fg.withValues(alpha: 0.5)..strokeWidth = 1,
      );
    }


    for (var curve in graphData.curves) {
      if (curve.baseName == 'Total Androgens' && !settings.cumulative) continue;
      final path = Path();
      if (curve.points.isNotEmpty) {
        final double maxY = settings.normalized ? normMax[curve.baseName]! : (curve.isOral ? oralMax : leftMax);
        final startX = paddingLeft + (curve.points[0].dx * chartWidth);
        final startY = chartHeight - ((curve.points[0].dy / maxY) * chartHeight);
        path.moveTo(startX, startY);
        for (int i = 1; i < curve.points.length; i++) {
          final x = paddingLeft + (curve.points[i].dx * chartWidth);
          final y = chartHeight - ((curve.points[i].dy / maxY) * chartHeight);
          path.lineTo(x, y);
        }
      }
      if (curve.baseName == 'Total Androgens') {
        path.lineTo(paddingLeft + chartWidth, chartHeight);
        path.lineTo(paddingLeft, chartHeight);
        path.close();
        canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: 0.3), Colors.white.withValues(alpha: 0.0)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
      } else {
        canvas.drawPath(path, Paint()..color = _curveColor(curve)..style = PaintingStyle.stroke..strokeWidth = curve.isOral ? 2.0 : 2.5..strokeCap = StrokeCap.round);
      }
    }

    final tickStyle = AppTheme.mono(
      color: AppTheme.fgDim,
      size: 9,
      weight: FontWeight.w400,
    );
    final oralTickStyle = tickStyle.copyWith(color: AppTheme.warm);
    if (!hasCurves) {
      // Empty chart: no y scale to label (PKChartCard shows the message).
    } else if (!settings.normalized) {
      for (int i = 0; i <= 4; i++) {
        final val = formatDose(leftMax * (i / 4));
        final y = chartHeight - (chartHeight * (i / 4));
        textPainter.text = TextSpan(text: val, style: tickStyle);
        textPainter.layout();
        textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 6, y - textPainter.height / 2));
      }
      if (hasOral) {
        for (int i = 0; i <= 4; i++) {
          final val = formatDose(oralMax * (i / 4));
          final y = chartHeight - (chartHeight * (i / 4));
          textPainter.text = TextSpan(text: val, style: oralTickStyle);
          textPainter.layout();
          textPainter.paint(canvas, Offset(size.width - paddingRight + 6, y - textPainter.height / 2));
        }
      }
    } else {
      for (int i = 0; i <= 4; i++) {
        final val = (i * 25);
        final y = chartHeight - (chartHeight * (i / 4));
        textPainter.text = TextSpan(text: '$val%', style: tickStyle);
        textPainter.layout();
        textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 6, y - textPainter.height / 2));
      }
    }

    // Injection Markers
    for (var marker in graphData.injectionMarkers) {
      final x = paddingLeft + (marker.xPct * chartWidth);
      // "% of peak": the marker's level over its own curve's max (B35).
      final maxY = settings.normalized
          ? (normMax[marker.baseName] ?? 1.0)
          : (marker.isOral ? oralMax : leftMax);
      final y = chartHeight - ((marker.yLevel / maxY) * chartHeight);
      final markerColor = colorResolver?.call(marker.baseName) ?? Color(marker.colorValue);
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = markerColor);
    }

    // X-Axis Labels (Date/Time)
    for (int i = 0; i <= 4; i++) {
      final pct = i / 4.0;
      final x = paddingLeft + (pct * chartWidth);
      final ms = graphData.startDate.millisecondsSinceEpoch + (pct * graphData.totalDurationMs).toInt();
      final date = DateTime.fromMillisecondsSinceEpoch(ms);
      String label = "";

      if (settings.timeRange == 'zoom') {
        label = formatDate(date, 'EEE ha');
      } else {
        label = formatDate(date, 'MMM d');
      }

      textPainter.text = TextSpan(text: label, style: tickStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, chartHeight + 6));
    }

    canvas.restore();
    textPainter.dispose();
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
      {double dash = 2, double gap = 3}) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist == 0) return;
    final ux = dx / dist;
    final uy = dy / dist;
    double covered = 0;
    while (covered < dist) {
      final segLen = math.min(dash, dist - covered);
      final start = Offset(a.dx + ux * covered, a.dy + uy * covered);
      final end = Offset(a.dx + ux * (covered + segLen), a.dy + uy * (covered + segLen));
      canvas.drawLine(start, end, paint);
      covered += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant PKGraphPainter oldDelegate) =>
      oldDelegate.graphData != graphData ||
      oldDelegate.settings != settings ||
      oldDelegate.skipPeptides != skipPeptides ||
      oldDelegate.colorResolver != colorResolver;
}
