import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../utils.dart';
import '../format.dart';
import '../theme.dart';

/// Largest system text scale the chart's tick labels follow: past it the
/// labels would crowd the fixed plot insets (and the chart's summary is
/// spoken anyway).
const double maxChartTextScale = 1.3;

/// The user's text scale for painted chart labels, capped at
/// [maxChartTextScale].
TextScaler chartTextScaler(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: maxChartTextScale);

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

/// Paints a [ComputedGraphData] using the settings it was computed with
/// (`graphData.settings`: range, "% of peak", Σ total) — deliberately not
/// the live selection, which may be newer than the data while a recompute
/// is pending (B40).
class PKGraphPainter extends CustomPainter {
  final ComputedGraphData graphData;
  final Color? Function(String baseName)? colorResolver;

  /// Scales the tick labels with the system text size (see
  /// [chartTextScaler]). At 1.0× the plot insets are unchanged; taller
  /// labels only deepen the bottom inset.
  final TextScaler textScaler;

  PKGraphPainter({
    required this.graphData,
    this.colorResolver,
    this.textScaler = TextScaler.noScaling,
  });

  Color _curveColor(CurveData curve) {
    final override = colorResolver?.call(curve.baseName);
    return override ?? curve.color;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final settings = graphData.settings;
    final textPainter = TextPainter(textDirection: TextDirection.ltr, textScaler: textScaler);
    final tickStyle = AppTheme.mono(
      color: AppTheme.fgDimText,
      size: 9,
      weight: FontWeight.w400,
    );
    final oralTickStyle = tickStyle.copyWith(color: AppTheme.warm);

    final paddingLeft = 45.0;
    final paddingRight = 20.0;
    // Room for the date labels (6 px gap + label): 20 px until large text
    // makes them taller.
    textPainter.text = TextSpan(text: '0', style: tickStyle);
    textPainter.layout();
    final paddingBottom = math.max(20.0, 6 + textPainter.height + 2);
    final chartWidth = size.width - paddingLeft - paddingRight;
    final chartHeight = size.height - paddingBottom;

    // Dose curves (the Σ total fill only exists on top of them). No curves
    // → nothing to put on a y axis.
    final hasCurves = graphData.hasDoseCurves;
    // maxOralMg is floored even without orals, so the right axis keys off
    // an actual oral curve rather than that value (B36).
    final hasOral = graphData.hasOralCurve;
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
      if (curve.isTotal && !settings.cumulative) continue;
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
      if (curve.isTotal) {
        path.lineTo(paddingLeft + chartWidth, chartHeight);
        path.lineTo(paddingLeft, chartHeight);
        path.close();
        canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: 0.3), Colors.white.withValues(alpha: 0.0)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
      } else {
        canvas.drawPath(path, Paint()..color = _curveColor(curve)..style = PaintingStyle.stroke..strokeWidth = curve.isOral ? 2.0 : 2.5..strokeCap = StrokeCap.round);
      }
    }

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
      oldDelegate.colorResolver != colorResolver ||
      oldDelegate.textScaler != textScaler;
}
