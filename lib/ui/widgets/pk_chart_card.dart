import 'package:flutter/material.dart';
import '../../models.dart';
import '../theme.dart';
import 'pk_graph_painter.dart';

class PKChartCard extends StatelessWidget {
  final ComputedGraphData? graphData;
  final GraphSettings settings;
  final ValueChanged<String> onRangeChanged;

  /// Live base→color resolver. Falls back to the static redesign palette when
  /// not supplied (e.g. in widget tests).
  final Color? Function(String baseName)? colorResolver;

  const PKChartCard({
    super.key,
    required this.graphData,
    required this.settings,
    required this.onRangeChanged,
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pharmacokinetics', style: AppTheme.sans(size: 13, weight: FontWeight.w600)),
                _RangePills(active: settings.timeRange, onChange: onRangeChanged),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 14, 14),
            child: graphData == null
                ? const SizedBox(height: 240, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : SizedBox(
                    height: 240,
                    width: double.infinity,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: PKGraphPainter(
                          graphData: graphData!,
                          settings: settings,
                          skipPeptides: true,
                          colorResolver: colorResolver ?? AppTheme.compoundColor,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RangePills extends StatelessWidget {
  final String active;
  final ValueChanged<String> onChange;
  const _RangePills({required this.active, required this.onChange});

  static const _ranges = <(String, String)>[
    ('zoom', '7d'),
    ('standard', '28d'),
    ('cycle', 'Cycle'),
    ('year', '1y'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (id, label) in _ranges) ...[
          GestureDetector(
            onTap: () => onChange(id),
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
