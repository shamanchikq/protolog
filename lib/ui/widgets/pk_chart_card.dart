import 'package:flutter/material.dart';
import '../../models.dart';
import '../theme.dart';
import 'lab_tap.dart';
import 'pk_graph_painter.dart';

/// The PK chart's range pills: (range key, pill label, days back, days
/// ahead). The spans mirror the engine's windows (computeGraphData) — a test
/// keeps them in step — and are spoken / shown on long-press, because the
/// swimlane card's pills of the same name cover other spans.
const pkChartRanges = <(String, String, int, int)>[
  ('zoom', '7d', 7, 7),
  ('standard', '28d', 28, 35),
  ('cycle', 'Cycle', 90, 30),
  ('year', '1y', 365, 30),
];

/// "28 days back, 35 ahead".
String rangeSpanLabel(int daysBack, int daysAhead) =>
    '$daysBack ${daysBack == 1 ? 'day' : 'days'} back, $daysAhead ahead';

/// What a screen reader says for the chart itself: its span, the compounds
/// drawn and the display modes — e.g. "Pharmacokinetics chart, 28 days back,
/// 35 ahead. Testosterone, Oxandrolone (oral)."
String pkChartSemanticsLabel(ComputedGraphData? data) {
  if (data == null) return 'Pharmacokinetics chart, loading';
  final s = data.settings;
  final range = pkChartRanges.where((r) => r.$1 == s.timeRange).firstOrNull;
  final b = StringBuffer('Pharmacokinetics chart');
  if (range != null) b.write(', ${rangeSpanLabel(range.$3, range.$4)}');
  b.write('. ');
  if (!data.hasDoseCurves) {
    b.write('No injectable or oral doses in this range.');
    return b.toString();
  }
  b.write([
    for (final c in data.curves)
      if (!c.isTotal) c.isOral ? '${c.baseName} (oral)' : c.baseName,
  ].join(', '));
  b.write('.');
  if (s.normalized) b.write(' Each curve as a percentage of its peak.');
  if (s.cumulative) b.write(' With the summed total.');
  return b.toString();
}

class PKChartCard extends StatelessWidget {
  /// The latest computed chart, or null before the first one. It may lag
  /// [settings] while a recompute is pending; the chart is drawn with the
  /// settings it was computed with (`graphData.settings`, B40).
  final ComputedGraphData? graphData;

  /// The live selection: drives the range / mode pills only.
  final GraphSettings settings;
  final ValueChanged<String> onRangeChanged;
  final ValueChanged<GraphSettings> onSettingsChanged;

  /// Live base→color resolver. Falls back to the static redesign palette when
  /// not supplied (e.g. in widget tests).
  final Color? Function(String baseName)? colorResolver;

  const PKChartCard({
    super.key,
    required this.graphData,
    required this.settings,
    required this.onRangeChanged,
    required this.onSettingsChanged,
    this.colorResolver,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            // Wrap, not Row: at large text sizes the range pills drop under
            // the title instead of overflowing (C1).
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 6,
              children: [
                Semantics(
                  header: true,
                  child: Text('Pharmacokinetics', style: AppTheme.sans(size: 13, weight: FontWeight.w600)),
                ),
                _RangePills(active: settings.timeRange, onChange: onRangeChanged),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Row(
              children: [
                _ModePill(
                  label: '% of peak',
                  active: settings.normalized,
                  onTap: () => onSettingsChanged(
                      settings.copyWith(normalized: !settings.normalized)),
                ),
                const SizedBox(width: 6),
                _ModePill(
                  label: 'Σ total',
                  semanticLabel: 'Summed total',
                  active: settings.cumulative,
                  onTap: () => onSettingsChanged(
                      settings.copyWith(cumulative: !settings.cumulative)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 14, 14),
            // One spoken summary instead of tick labels and markers.
            child: Semantics(
              container: true,
              label: pkChartSemanticsLabel(graphData),
              child: ExcludeSemantics(child: _chart(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chart(BuildContext context) {
    final data = graphData;
    if (data == null) {
      return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return SizedBox(
      height: 240,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: PKGraphPainter(
                  graphData: data,
                  colorResolver: colorResolver ?? AppTheme.compoundColor,
                  textScaler: chartTextScaler(context),
                ),
              ),
            ),
          ),
          if (!data.hasDoseCurves)
            Positioned.fill(
              // Inset to the plot area (painter pads 45 left, 20 right/bottom).
              left: 45,
              right: 20,
              bottom: 20,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'No injectable or oral doses in this range',
                    textAlign: TextAlign.center,
                    style: AppTheme.sans(size: 11, color: AppTheme.fgMute),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small toggle for the engine-side graph modes (normalized / cumulative).
class _ModePill extends StatelessWidget {
  final String label;
  final String? semanticLabel;
  final bool active;
  final VoidCallback onTap;
  const _ModePill({required this.label, this.semanticLabel, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LabTap(
      onTap: onTap,
      toggled: active,
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppTheme.surface2 : Colors.transparent,
          border: Border.all(
            color: active ? AppTheme.accentDeep : AppTheme.borderSoft,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.sans(
            size: 10,
            color: active ? AppTheme.accent : AppTheme.fgDimText,
            weight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _RangePills extends StatelessWidget {
  final String active;
  final ValueChanged<String> onChange;
  const _RangePills({required this.active, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (id, label, back, ahead) in pkChartRanges) ...[
          LabTap(
            onTap: () => onChange(id),
            selected: active == id,
            inMutuallyExclusiveGroup: true,
            tooltip: rangeSpanLabel(back, ahead),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active == id ? AppTheme.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: AppTheme.sans(
                  size: 11,
                  color: active == id ? AppTheme.fg : AppTheme.fgMute,
                  weight: active == id ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
  }
}
