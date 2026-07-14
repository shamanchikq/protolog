import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../utils.dart';
import '../theme.dart';

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
        double normalizationMax = 0;
        if (settings.normalized) { for (var p in curve.points) {
          normalizationMax = math.max(normalizationMax, p.dy);
        } if (normalizationMax == 0) normalizationMax = 1; }
        final double maxY = settings.normalized ? normalizationMax : (curve.isOral ? graphData.maxOralMg : graphData.maxMg);
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
    if (!settings.normalized) {
      for (int i = 0; i <= 4; i++) {
        final val = (graphData.maxMg * (i / 4)).round();
        final y = chartHeight - (chartHeight * (i / 4));
        textPainter.text = TextSpan(text: '$val', style: tickStyle);
        textPainter.layout();
        textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 6, y - textPainter.height / 2));
      }
      if (graphData.maxOralMg > 5) {
        for (int i = 0; i <= 4; i++) {
          final val = (graphData.maxOralMg * (i / 4)).round();
          final y = chartHeight - (chartHeight * (i / 4));
          textPainter.text = TextSpan(text: '$val', style: oralTickStyle);
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
      final maxY = settings.normalized ? 1.0 : (marker.isOral ? graphData.maxOralMg : graphData.maxMg);
      final yVal = settings.normalized ? 0.0 : marker.yLevel;
      final y = chartHeight - ((yVal / maxY) * chartHeight);
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
