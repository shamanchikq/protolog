import 'package:flutter/material.dart';

import '../../engine/dashboard_stats.dart';
import '../../models.dart';
import '../widgets/bloodwork_card.dart';
import '../widgets/load_hero.dart';
import '../widgets/pk_chart_card.dart';
import '../widgets/swimlane_card.dart';

/// The Today tab: active-load hero, PK chart, peptide/ancillary swimlanes
/// and the latest lab results. A plain view over MainScreen's state.
class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.injections,
    required this.bloodwork,
    required this.graphData,
    required this.settings,
    required this.colorResolver,
    required this.now,
    required this.onSettingsChanged,
    required this.onAddBloodwork,
    required this.onOpenBloodwork,
  });

  final List<Injection> injections;
  final List<BloodworkEntry> bloodwork;

  /// The PK chart's curves, computed off the UI isolate by the owner.
  final Future<ComputedGraphData>? graphData;
  final GraphSettings settings;

  /// Live base → display color (see MainScreen's resolver).
  final Color Function(String base) colorResolver;

  /// The instant every card is drawn for.
  final DateTime now;

  /// New chart settings (a range pill or a mode); the owner recomputes
  /// [graphData].
  final ValueChanged<GraphSettings> onSettingsChanged;
  final VoidCallback onAddBloodwork;
  final ValueChanged<BloodworkEntry> onOpenBloodwork;

  @override
  Widget build(BuildContext context) {
    final load = activeInjectableLoad(injections: injections, now: now);
    final totalActive = load.fold<double>(0.0, (s, e) => s + e.activeMg);
    final breakdown = (load.toList()..sort((a, b) => b.activeMg.compareTo(a.activeMg)))
        .map((e) => LoadHeroRow(
              label: e.base,
              valueMg: e.activeMg,
              shareOfTotal: totalActive > 0 ? e.activeMg / totalActive : 0,
              color: colorResolver(e.base),
            ))
        .toList();
    final delta = deltaSteroidNowVsPrior7(injections: injections, now: now);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoadHero(
            data: LoadHeroData(
              totalActiveMg: totalActive,
              delta: delta,
              breakdown: breakdown,
            ),
          ),
          const SizedBox(height: 18),
          FutureBuilder<ComputedGraphData>(
            future: graphData,
            builder: (context, snapshot) => PKChartCard(
              graphData: snapshot.data,
              settings: settings,
              colorResolver: colorResolver,
              onRangeChanged: (range) => onSettingsChanged(GraphSettings(
                normalized: settings.normalized,
                cumulative: settings.cumulative,
                showPeptides: settings.showPeptides,
                timeRange: range,
              )),
              onSettingsChanged: onSettingsChanged,
            ),
          ),
          const SizedBox(height: 18),
          SwimlaneCard(
            injections: injections,
            now: now,
            colorResolver: colorResolver,
          ),
          const SizedBox(height: 18),
          BloodworkCard(
            entries: bloodwork,
            onCreate: onAddBloodwork,
            onTap: onOpenBloodwork,
          ),
        ],
      ),
    );
  }
}
