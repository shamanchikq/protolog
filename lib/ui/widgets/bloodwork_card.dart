import 'package:flutter/material.dart';
import '../../engine/bloodwork_stats.dart';
import '../../models.dart';
import '../theme.dart';
import 'lab_primitives.dart';

/// Dashboard card (F6): recent lab results, newest first, each with its
/// change vs the previous draw of the same marker. Rows open the full
/// bloodwork page via [onTap]; the pill opens the create dialog via [onCreate].
class BloodworkCard extends StatelessWidget {
  final List<BloodworkEntry> entries;
  final VoidCallback onCreate;
  final void Function(BloodworkEntry entry) onTap;

  /// How many of the most recent entries to list.
  final int maxRows;

  const BloodworkCard({
    super.key,
    required this.entries,
    required this.onCreate,
    required this.onTap,
    this.maxRows = 6,
  });

  static const _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _fmtValue(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Widget _delta(BloodworkEntry e) {
    final d = deltaVsPrevious(e, entries);
    if (d == null || d == 0) return const SizedBox.shrink();
    return Text(
      '${d > 0 ? '↑' : '↓'} ${_fmtValue(d.abs())}',
      textAlign: TextAlign.right,
      style: AppTheme.mono(
        size: 10,
        color: d > 0 ? AppTheme.accent : AppTheme.warn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<BloodworkEntry>.from(entries)
      ..sort((a, b) => b.date.compareTo(a.date));
    final visible = sorted.take(maxRows).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Bloodwork',
                    style: AppTheme.sans(size: 13, weight: FontWeight.w600),
                  ),
                ),
                if (entries.length > maxRows)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${entries.length} total',
                      style: AppTheme.mono(size: 10, color: AppTheme.fgDim),
                    ),
                  ),
                LabPill(label: '+ Add', onTap: onCreate),
              ],
            ),
          ),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                'No lab results yet — log draws to track trends per marker.',
                style: AppTheme.sans(size: 12, color: AppTheme.fgDim),
              ),
            )
          else
            for (int i = 0; i < visible.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(visible[i]),
                child: Container(
                  decoration: BoxDecoration(
                    border: i > 0
                        ? const Border(
                            top: BorderSide(
                              color: AppTheme.borderSoft,
                              width: 1,
                            ),
                          )
                        : null,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${_monthsShort[visible[i].date.month - 1]} ${visible[i].date.day}',
                          style: AppTheme.mono(
                            size: 11,
                            color: AppTheme.fgMute,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          visible[i].marker,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.sans(size: 13, color: AppTheme.fg),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_fmtValue(visible[i].value)} ${visible[i].unit}'
                            .trim(),
                        style: AppTheme.mono(size: 12, color: AppTheme.warm),
                      ),
                      SizedBox(width: 44, child: _delta(visible[i])),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
