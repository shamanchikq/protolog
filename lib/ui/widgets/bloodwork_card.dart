import 'package:flutter/material.dart';
import '../../engine/bloodwork_stats.dart';
import '../../models.dart';
import '../format.dart';
import '../theme.dart';
import 'lab_primitives.dart';
import 'lab_tap.dart';

/// Dashboard card (F6): the latest draw of each marker, most recently drawn
/// first, with its change vs the previous draw. Older draws live on the
/// bloodwork page, opened by tapping a row; the pill opens the create dialog.
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

  Widget _delta(BloodworkEntry e) {
    final prev = previousDraw(e, entries);
    final text = prev == null ? '' : formatLabDelta(e.value, prev.value);
    if (text.isEmpty) return const SizedBox.shrink();
    // Neutral color on purpose: "up" is good for some markers (Total T)
    // and bad for others (LDL, E2) — the app shouldn't editorialize.
    return Text(
      text,
      textAlign: TextAlign.right,
      style: AppTheme.mono(size: 10, color: AppTheme.fgMute),
    );
  }

  @override
  Widget build(BuildContext context) {
    // One row per marker — its latest draw — ordered by draw recency.
    final markers = distinctMarkers(entries);
    final visible = [
      for (final m in markers.take(maxRows)) historyFor(m, entries).last,
    ];
    final hiddenMarkers = markers.length - visible.length;

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
                if (hiddenMarkers > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '+$hiddenMarkers more',
                      style: AppTheme.mono(size: 10, color: AppTheme.fgDimText),
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
                style: AppTheme.sans(size: 12, color: AppTheme.fgDimText),
              ),
            )
          else
            for (int i = 0; i < visible.length; i++)
              LabTap(
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
                          formatMonthDay(visible[i].date),
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
                        '${formatLabValue(visible[i].value)} ${visible[i].unit}'
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
