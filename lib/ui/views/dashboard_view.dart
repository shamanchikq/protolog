import 'package:flutter/material.dart';

import '../../engine/dashboard_stats.dart';
import '../../models.dart';
import '../widgets/bloodwork_card.dart';
import '../widgets/load_hero.dart';
import '../widgets/pk_chart_card.dart';
import '../widgets/swimlane_card.dart';

/// The Today tab: active-load hero, PK chart, peptide/ancillary swimlanes
/// and the latest lab results. A view over MainScreen's state; its only own
/// state is the swimlane memo (E2).
class DashboardView extends StatefulWidget {
  const DashboardView({
    super.key,
    required this.injections,
    required this.bloodwork,
    required this.graphData,
    required this.settings,
    required this.colorResolver,
    this.injectionsRevision = 0,
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

  /// Live base → display color (see MainScreen's resolver). Pass the same
  /// function until the catalogue changes: the chart repaints and the
  /// swimlanes resample whenever it's a different one.
  final Color Function(String base) colorResolver;

  /// The owner's change counter for [injections], which it mutates in place
  /// (so neither identity nor length reveals an edited dose). Together they
  /// decide when the swimlanes must resample.
  final int injectionsRevision;

  /// The instant every card is drawn for.
  final DateTime now;

  /// New chart settings (a range pill or a mode); the owner recomputes
  /// [graphData].
  final ValueChanged<GraphSettings> onSettingsChanged;
  final VoidCallback onAddBloodwork;
  final ValueChanged<BloodworkEntry> onOpenBloodwork;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  /// "Now" may lag by up to this before the swimlanes are redrawn for it:
  /// their today line and current levels don't visibly move in less.
  static const _swimlaneNowTolerance = Duration(minutes: 1);

  // E2: SwimlaneCard samples every lane's Bateman curve while building, so
  // it gets a new widget only when its inputs change. Handing Flutter the
  // identical instance otherwise (a chart range pill, a reminder or lab
  // change, a permission refresh) skips its subtree entirely.
  SwimlaneCard? _swimlanes;
  int _swimlanesLength = 0;
  int _swimlanesRevision = 0;

  SwimlaneCard _swimlaneCard() {
    final w = widget;
    final cached = _swimlanes;
    if (cached != null &&
        identical(cached.injections, w.injections) &&
        _swimlanesLength == w.injections.length &&
        _swimlanesRevision == w.injectionsRevision &&
        identical(cached.colorResolver, w.colorResolver) &&
        w.now.difference(cached.now).abs() < _swimlaneNowTolerance) {
      return cached;
    }
    _swimlanesLength = w.injections.length;
    _swimlanesRevision = w.injectionsRevision;
    return _swimlanes = SwimlaneCard(
      injections: w.injections,
      now: w.now,
      colorResolver: w.colorResolver,
    );
  }

  @override
  Widget build(BuildContext context) {
    final injections = widget.injections;
    final now = widget.now;
    final colorResolver = widget.colorResolver;
    final settings = widget.settings;
    final onSettingsChanged = widget.onSettingsChanged;
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
            future: widget.graphData,
            builder: (context, snapshot) => PKChartCard(
              graphData: snapshot.data,
              settings: settings,
              colorResolver: colorResolver,
              onRangeChanged: (range) =>
                  onSettingsChanged(settings.copyWith(timeRange: range)),
              onSettingsChanged: onSettingsChanged,
            ),
          ),
          const SizedBox(height: 18),
          _swimlaneCard(),
          const SizedBox(height: 18),
          BloodworkCard(
            entries: widget.bloodwork,
            onCreate: widget.onAddBloodwork,
            onTap: widget.onOpenBloodwork,
          ),
        ],
      ),
    );
  }
}
