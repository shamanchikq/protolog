import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'data.dart';

// --- Entry Point ---
void main() {
  runApp(const ProtoLogApp());
}

class ProtoLogApp extends StatelessWidget {
  const ProtoLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProtoLog',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF020617), // Slate 950
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981), // Emerald 500
          surface: Color(0xFF1E293B), // Slate 800
          onSurface: Color(0xFFE2E8F0), // Slate 200
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.zero,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// --- Utils ---

String _formatDate(DateTime date, String format) {
  final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String twoDigits(int n) => n.toString().padLeft(2, '0');

  if (format == 'MM/dd HH:mm') {
    return "${twoDigits(date.month)}/${twoDigits(date.day)} ${twoDigits(date.hour)}:${twoDigits(date.minute)}";
  }
  if (format == 'yyyy-MM-dd') {
    return "${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}";
  }
  if (format == 'EEE ha') {
    final dayName = days[date.weekday - 1];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return "$dayName $hour$ampm";
  }
  if (format == 'MMM d') {
    return "${months[date.month - 1]} ${date.day}";
  }
  return date.toString();
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

// --- Math Engine (Top Level for Isolate) ---

double _solveKa(double ke, double tmax) {
  if (tmax <= 0.01) return 100.0;
  double low = ke + 0.001;
  double high = 100.0;
  double mid = 0.0;
  for (int i = 0; i < 20; i++) {
    mid = (low + high) / 2;
    double calculatedTmax = (math.log(mid) - math.log(ke)) / (mid - ke);
    if (calculatedTmax > tmax) low = mid; else high = mid;
  }
  return mid;
}

double _calculateBatemanValue(double dose, double t, double halfLife, double tmax, double ratio) {
  if (t < 0) return 0.0;
  double effectiveDose = dose * ratio;
  double ke = math.log(2) / halfLife;
  double ka = _solveKa(ke, tmax);
  double term1 = (effectiveDose * ka) / (ka - ke);
  double term2 = math.exp(-ke * t) - math.exp(-ka * t);
  return math.max(0.0, term1 * term2);
}

double _calculateActiveLevel(double dosage, double diffDays, double halfLife, double timeToPeak, double ratio, String esterName) {
  if (esterName.contains('Sustanon')) {
    double level = 0;
    for (var comp in SUSTANON_BLEND) {
      level += _calculateBatemanValue(
        dosage * comp['fraction']!,
        diffDays,
        comp['halfLife']!,
        comp['timeToPeak']!,
        comp['ratio']!,
      );
    }
    return level;
  }
  return _calculateBatemanValue(dosage, diffDays, halfLife, timeToPeak, ratio);
}

CompoundDefinition? _lookupLibraryDef(String base, String ester) {
  for (var entry in BASE_LIBRARY.values) {
    if (entry.base == base && entry.ester == ester) return entry;
  }
  return BASE_LIBRARY[base]; // fallback for orals/peptides/ancillaries keyed by base name
}

// --- HEAVY COMPUTATION ---
Future<ComputedGraphData> calculateGraphData(IsolateInput input) async {
  final injections = input.injections;
  final settings = input.settings;

  int daysBack = 28;
  int daysFwd = 35;
  if (settings.timeRange == 'zoom') { daysBack = 7; daysFwd = 7; }
  if (settings.timeRange == 'cycle') { daysBack = 90; daysFwd = 30; }
  if (settings.timeRange == 'year') { daysBack = 365; daysFwd = 30; }

  final now = DateTime.now();
  final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysBack));
  final endDate = DateTime(now.year, now.month, now.day).add(Duration(days: daysFwd)).add(const Duration(hours: 23, minutes: 59));
  final totalDurationMs = endDate.difference(startDate).inMilliseconds;
  final startMs = startDate.millisecondsSinceEpoch;

  final relevantInjections = injections.where((i) {
    final injTime = i.date.millisecondsSinceEpoch;
    final windowMs = (i.snapshot.halfLife * 8 * 86400000).toInt();
    return injTime <= endDate.millisecondsSinceEpoch && (injTime >= startMs || (startMs - injTime) < windowMs);
  }).toList();

  final curveInjections = relevantInjections.where((i) => i.snapshot.type == CompoundType.steroid || i.snapshot.type == CompoundType.oral).toList();
  final peptideInjections = relevantInjections.where((i) => i.snapshot.type == CompoundType.peptide || i.snapshot.type == CompoundType.ancillary).toList();

  final uniquePeptideBases = peptideInjections.map((i) => i.snapshot.base).toSet().toList()..sort();
  final laneMap = {for (var e in uniquePeptideBases) e: uniquePeptideBases.indexOf(e)};
  final List<PeptideLaneData> lanes = [];

  for (var inj in peptideInjections) {
    // Check Library for latest settings override
    final libraryDef = _lookupLibraryDef(inj.snapshot.base, inj.snapshot.ester);
    final graphType = libraryDef?.graphType ?? inj.snapshot.graphType;
    final halfLife = libraryDef?.halfLife ?? inj.snapshot.halfLife;

    final msSinceStart = inj.date.millisecondsSinceEpoch - startMs;
    final startPct = msSinceStart / totalDurationMs;
    final fadeDurationMs = (halfLife * 6) * 86400000;
    final durationPct = fadeDurationMs / totalDurationMs;

    if (startPct + durationPct > 0 && startPct < 1.0) {
      lanes.add(PeptideLaneData(
          inj.snapshot.base,
          inj.snapshot.colorValue,
          laneMap[inj.snapshot.base] ?? 0,
          startPct,
          durationPct,
          graphType
      ));
    }
  }

  final uniqueCurveBases = curveInjections.map((i) => i.snapshot.base).toSet();
  double maxMg = 10.0;
  double maxOralMg = 5.0;
  final List<CurveData> curves = [];

  final stepsPerDay = settings.timeRange == 'zoom' ? 12 : (settings.timeRange == 'standard' ? 4 : 2);
  final stepSizeMs = 86400000 ~/ stepsPerDay;

  final Map<String, List<Injection>> injectionsByBase = {};
  for(var base in uniqueCurveBases) {
    injectionsByBase[base] = curveInjections.where((i) => i.snapshot.base == base).toList();
  }

  final Map<String, List<Offset>> tempPoints = {for (var base in uniqueCurveBases) base: []};

  for (int currentTime = startMs; currentTime <= endDate.millisecondsSinceEpoch; currentTime += stepSizeMs) {
    final timePct = (currentTime - startMs) / totalDurationMs;

    for (var base in uniqueCurveBases) {
      double level = 0.0;
      final baseInjections = injectionsByBase[base] ?? [];

      for (var inj in baseInjections) {
        final diffMs = currentTime - inj.date.millisecondsSinceEpoch;
        if (diffMs >= 0) {
          final diffDays = diffMs / 86400000.0;
          level += _calculateActiveLevel(
              inj.dosage, diffDays, inj.snapshot.halfLife, inj.snapshot.timeToPeak, inj.snapshot.ratio, inj.snapshot.ester
          );
        }
      }
      tempPoints[base]!.add(Offset(timePct, level));

      final isOral = baseInjections.isNotEmpty && baseInjections.first.snapshot.type == CompoundType.oral;
      if (isOral) {
        maxOralMg = math.max(maxOralMg, level);
      } else {
        maxMg = math.max(maxMg, level);
      }
    }
  }

  if (settings.cumulative) {
    final List<Offset> totalPoints = [];
    double dailyMaxTotal = 0;
    for (int currentTime = startMs; currentTime <= endDate.millisecondsSinceEpoch; currentTime += stepSizeMs) {
      double totalLevel = 0.0;
      final timePct = (currentTime - startMs) / totalDurationMs;
      for(var inj in curveInjections.where((i) => i.snapshot.type == CompoundType.steroid)) {
        final diffMs = currentTime - inj.date.millisecondsSinceEpoch;
        if (diffMs >= 0) {
          totalLevel += _calculateActiveLevel(inj.dosage, diffMs/86400000.0, inj.snapshot.halfLife, inj.snapshot.timeToPeak, inj.snapshot.ratio, inj.snapshot.ester);
        }
      }
      totalPoints.add(Offset(timePct, totalLevel));
      dailyMaxTotal = math.max(dailyMaxTotal, totalLevel);
    }
    curves.add(CurveData('Total Androgens', 0xFFFFFFFF, false, totalPoints));
    maxMg = math.max(maxMg, dailyMaxTotal);
  }

  for (var base in uniqueCurveBases) {
    final baseInjections = injectionsByBase[base];
    if (baseInjections == null || baseInjections.isEmpty) continue;
    final sample = baseInjections.first.snapshot;
    curves.add(CurveData(base, sample.colorValue, sample.type == CompoundType.oral, tempPoints[base]!));
  }

  return ComputedGraphData(
    curves: curves,
    peptideLanes: lanes,
    laneLabels: uniquePeptideBases,
    maxMg: maxMg * 1.1,
    maxOralMg: maxOralMg * 1.2,
    startDate: startDate,
    endDate: endDate,
    totalDurationMs: totalDurationMs,
    laneCount: uniquePeptideBases.length,
  );
}

// --- Main Screen ---

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  List<Injection> injections = [];
  List<CompoundDefinition> userCompounds = [];
  late GraphSettings settings;
  Future<ComputedGraphData>? _graphDataFuture;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    settings = const GraphSettings(normalized: false, cumulative: false, showPeptides: true, timeRange: 'standard');
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Injections
    final injString = prefs.getString('injections');
    if (injString != null) {
      final List<dynamic> jsonList = jsonDecode(injString);
      injections = jsonList.map((j) => Injection.fromJson(j)).toList();
    }

    // Load Compounds
    final compString = prefs.getString('compounds');
    if (compString != null) {
      final List<dynamic> jsonList = jsonDecode(compString);
      userCompounds = jsonList.map((j) => CompoundDefinition.fromJson(j)).toList();
    } else {
      userCompounds = List.from(INITIAL_COMPOUNDS);
    }

    setState(() => _loading = false);
    _refreshGraph();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('injections', jsonEncode(injections.map((e) => e.toJson()).toList()));
    prefs.setString('compounds', jsonEncode(userCompounds.map((e) => e.toJson()).toList()));
  }

  void _refreshGraph() {
    setState(() {
      _graphDataFuture = compute(calculateGraphData, IsolateInput(injections, settings));
    });
  }

  void _addInjection(Injection inj) {
    setState(() {
      injections.add(inj);
    });
    _saveData();
    _refreshGraph();
  }

  void _deleteInjection(String id) {
    setState(() {
      injections.removeWhere((i) => i.id == id);
    });
    _saveData();
    _refreshGraph();
  }

  void _addUserCompound(CompoundDefinition comp) {
    setState(() {
      userCompounds.add(comp);
    });
    _saveData();
  }

  void _deleteUserCompound(String id) {
    setState(() {
      userCompounds.removeWhere((c) => c.id == id);
    });
    _saveData();
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  List<ActiveCompoundStat> _getActiveStats() {
    final now = DateTime.now();
    final Map<String, ActiveCompoundStat> stats = {};

    // Sort to handle timeline correctly
    final sortedInjections = List<Injection>.from(injections)..sort((a,b) => a.date.compareTo(b.date));

    // Map to hold cumulative active amounts by BASE
    final Map<String, double> activeTotals = {};
    // Map to hold reference injection for metadata (the latest one)
    final Map<String, Injection> latestInjections = {};

    for(var inj in sortedInjections) {
      final diffMs = now.difference(inj.date).inMilliseconds;
      if (diffMs < 0) continue; // Future injection

      final base = inj.snapshot.base;
      latestInjections[base] = inj; // Overwrite, so last loop item is latest by date

      // Force library settings lookup to get fresh graphType/halfLife
      final libraryDef = _lookupLibraryDef(base, inj.snapshot.ester);
      final graphType = libraryDef?.graphType ?? inj.snapshot.graphType;

      // Determine correct Half Life to use
      final double libHl = libraryDef?.halfLife ?? 0;
      final double snapHl = inj.snapshot.halfLife;
      // If library has a valid non-zero HL, use it. Otherwise use snapshot. Fallback to 1.0.
      final double halfLife = (libHl > 0.05) ? libHl : (snapHl > 0.05 ? snapHl : 1.0);

      // Calculate Active Amount to Sum
      double active = 0;
      if (inj.snapshot.type == CompoundType.steroid || inj.snapshot.type == CompoundType.oral) {
        final diffDays = diffMs / 86400000.0;
        active = _calculateActiveLevel(inj.dosage, diffDays, halfLife, inj.snapshot.timeToPeak, inj.snapshot.ratio, inj.snapshot.ester);
      } else if (graphType == GraphType.activeWindow) {
        // Active Window Peptide: Cumulative exponential decay
        final diffDays = diffMs / 86400000.0;
        active = inj.dosage * math.pow(0.5, diffDays / halfLife);
      }

      // Only add to total if it's not effectively zero (arbitrary large decay)
      if (diffMs <= halfLife * 8 * 86400000) {
        activeTotals[base] = (activeTotals[base] ?? 0) + active;
      }
    }

    // Now generate the stats cards based on unique bases found
    for (var entry in latestInjections.entries) {
      final base = entry.key;
      final inj = entry.value;

      final libraryDef = _lookupLibraryDef(base, inj.snapshot.ester);
      final graphType = libraryDef?.graphType ?? inj.snapshot.graphType;

      final diffMs = now.difference(inj.date).inMilliseconds;
      final ago = Duration(milliseconds: diffMs);
      final agoString = ago.inDays > 0 ? "${ago.inDays}d ago" : "${ago.inHours}h ago";

      // Skip if latest injection is very old
      if (diffMs > 2592000000) continue;

      String mainValue = "";
      String subLabel = "";
      String status = "";

      // TYPE 1: Summed Values (Curve & Active Window)
      if (inj.snapshot.type == CompoundType.steroid || inj.snapshot.type == CompoundType.oral || graphType == GraphType.activeWindow) {
        double val = activeTotals[base] ?? 0;

        // Check if recently pinned even if active levels haven't spiked yet (Bateman start)
        bool recentlyPinned = diffMs < 172800000; // < 48 hours

        if (val < 0.05 && !recentlyPinned) continue; // Don't show if zero and not recent

        mainValue = val.toStringAsFixed(1);
        subLabel = inj.snapshot.unit.toString().split('.').last;

        status = agoString;
      }
      // TYPE 2: Event Only
      else {
        if (ago.inDays > 0) mainValue = "${ago.inDays}d ago";
        else mainValue = "${ago.inHours}h ago";

        subLabel = "";
        status = "$agoString • Last: ${inj.dosage} ${inj.snapshot.unit.toString().split('.').last}";
      }

      stats[base] = ActiveCompoundStat(base, activeTotals[base] ?? 0, mainValue, subLabel, inj.snapshot.colorValue, inj.snapshot.type, graphType, status);
    }

    return stats.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    Widget content;
    switch (_currentIndex) {
      case 0: content = _buildDashboard(); break;
      case 1: content = _buildHistory(); break;
      case 2: content = AddInjectionWizard(
        onAdd: _addInjection,
        onCancel: () => _onTabTapped(0),
        onSuccess: () => _onTabTapped(0),
        userCompounds: userCompounds,
        addUserCompound: _addUserCompound,
      ); break;
      case 3: content = CompoundManager(
        userCompounds: userCompounds,
        onAdd: _addUserCompound,
        onDelete: _deleteUserCompound,
      ); break;
      default: content = _buildDashboard();
    }

    return Scaffold(
      body: SafeArea(child: content),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        backgroundColor: const Color(0xFF0F172A),
        selectedItemColor: const Color(0xFF10B981),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dash'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Log'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle, size: 40), label: 'Add'),
          BottomNavigationBarItem(icon: Icon(Icons.science), label: 'Libs'),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final activeStats = _getActiveStats();
    double totalLoad = activeStats.where((s) => s.type == CompoundType.steroid).fold(0, (sum, item) => sum + item.activeAmount);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('ProtoLog', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF312E81), Color(0xFF0F172A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOTAL INJECTABLE LOAD', style: TextStyle(color: Colors.indigo[200], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(totalLoad.toStringAsFixed(1), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(width: 8),
                    const Text('mg active', style: TextStyle(fontSize: 14, color: Color(0xFF818CF8))),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Combined saturation of Injectable Steroids.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Container(
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF334155))),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('PK Plotter', style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          _settingBtn(Icons.percent, settings.normalized, () { setState(() { settings = GraphSettings(normalized: !settings.normalized, cumulative: settings.cumulative, showPeptides: settings.showPeptides, timeRange: settings.timeRange); }); _refreshGraph(); }),
                          const SizedBox(width: 8),
                          _settingBtn(Icons.layers, settings.cumulative, () { setState(() { settings = GraphSettings(normalized: settings.normalized, cumulative: !settings.cumulative, showPeptides: settings.showPeptides, timeRange: settings.timeRange); }); _refreshGraph(); }),
                        ],
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: ['zoom', 'standard', 'cycle', 'year'].map((range) {
                        final isActive = settings.timeRange == range;
                        return Expanded(child: GestureDetector(
                          onTap: () { setState(() { settings = GraphSettings(normalized: settings.normalized, cumulative: settings.cumulative, showPeptides: settings.showPeptides, timeRange: range); }); _refreshGraph(); },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(color: isActive ? const Color(0xFF334155) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                            child: Center(child: Text(range.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.grey))),
                          ),
                        ));
                      }).toList(),
                    ),
                  ),
                ),
                FutureBuilder<ComputedGraphData>(
                  future: _graphDataFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                    final swimlaneH = math.max(40.0, (snapshot.data!.laneCount * 24.0) + 20.0);
                    return SizedBox(
                        height: 300.0 + swimlaneH,
                        width: double.infinity,
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
                            child: RepaintBoundary(child: CustomPaint(painter: PKGraphPainter(graphData: snapshot.data!, settings: settings)))
                        )
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text("ACTIVE SERUM LEVELS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 12),
          ...activeStats.map((stat) {
            IconData icon = Icons.water_drop;
            if (stat.type == CompoundType.oral) icon = Icons.medication;
            if (stat.type == CompoundType.peptide) icon = Icons.science;
            if (stat.type == CompoundType.ancillary) icon = Icons.medical_services;

            bool showTimeOnly = (stat.graphType == GraphType.event);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: Color(stat.colorValue), width: 4))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Color(stat.colorValue).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 16, color: Color(stat.colorValue))),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(stat.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(showTimeOnly ? _capitalize(stat.type.name) : stat.statusText, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ]),
                    ],
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                        showTimeOnly
                            ? stat.statusText
                            : stat.mainValue,
                        style: TextStyle(fontSize: showTimeOnly ? 13 : 18, fontWeight: FontWeight.bold)
                    ),
                    if (!showTimeOnly) Text(stat.subLabel, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ])
                ],
              ),
            );
          }).toList(),
          if (activeStats.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(32), child: Text("No active compounds", style: TextStyle(color: Colors.grey)))),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: injections.length,
      itemBuilder: (context, index) {
        final sorted = List<Injection>.from(injections)..sort((a, b) => b.date.compareTo(a.date));
        final inj = sorted[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Color(inj.snapshot.colorValue).withOpacity(0.2), child: Icon(Icons.circle, color: Color(inj.snapshot.colorValue), size: 14)),
            title: Text(inj.snapshot.base, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: Text("${inj.snapshot.ester.isNotEmpty && inj.snapshot.ester != 'None' ? inj.snapshot.ester : ''} • ${_formatDate(inj.date, 'MM/dd HH:mm')}"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${inj.dosage} ${inj.snapshot.unit.toString().split('.').last}", style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.grey), onPressed: () => _deleteInjection(inj.id))
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _settingBtn(IconData icon, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: isActive ? const Color(0xFF10B981) : const Color(0xFF334155), borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}

// --- WIZARD COMPONENTS ---

class AddInjectionWizard extends StatefulWidget {
  final Function(Injection) onAdd;
  final VoidCallback onCancel;
  final VoidCallback onSuccess;
  final List<CompoundDefinition> userCompounds;
  final Function(CompoundDefinition) addUserCompound;

  const AddInjectionWizard({super.key, required this.onAdd, required this.onCancel, required this.onSuccess, required this.userCompounds, required this.addUserCompound});

  @override
  State<AddInjectionWizard> createState() => _AddInjectionWizardState();
}

class _AddInjectionWizardState extends State<AddInjectionWizard> {
  int step = 1;
  CompoundDefinition? selectedCompound;
  String dose = '';
  Unit unit = Unit.mg;
  DateTime date = DateTime.now();
  TimeOfDay time = TimeOfDay.now();
  bool calcMode = false;
  String concentration = '';
  String volume = '';
  String _typeFilter = 'steroid';
  String? _selectedBase;

  int _esterCountForBase(String base) {
    final Set<String> esters = {};
    for (var comp in widget.userCompounds) {
      if (comp.type == CompoundType.steroid && comp.base == base) esters.add(comp.ester);
    }
    BASE_LIBRARY.forEach((key, val) {
      if (val.type == CompoundType.steroid && val.base == base) esters.add(val.ester);
    });
    return esters.length;
  }

  List<CompoundDefinition> get availableCompounds {
    final targetType = _typeFilter == 'steroid' ? CompoundType.steroid
        : _typeFilter == 'oral' ? CompoundType.oral
        : _typeFilter == 'peptide' ? CompoundType.peptide
        : CompoundType.ancillary;

    if (targetType == CompoundType.steroid) {
      if (_selectedBase != null) {
        // Show esters for selected base, recently used first
        final Map<String, CompoundDefinition> esters = {};
        for (var comp in widget.userCompounds) {
          if (comp.type == CompoundType.steroid && comp.base == _selectedBase && !esters.containsKey(comp.ester)) {
            esters[comp.ester] = comp;
          }
        }
        BASE_LIBRARY.forEach((key, val) {
          if (val.type == CompoundType.steroid && val.base == _selectedBase && !esters.containsKey(val.ester)) {
            esters[val.ester] = val;
          }
        });
        return esters.values.toList();
      }
      // Show unique base names, recently used first
      final Map<String, CompoundDefinition> bases = {};
      for (var comp in widget.userCompounds) {
        if (comp.type == CompoundType.steroid && !bases.containsKey(comp.base)) {
          bases[comp.base] = comp;
        }
      }
      BASE_LIBRARY.forEach((key, val) {
        if (val.type == CompoundType.steroid && !bases.containsKey(val.base)) {
          bases[val.base] = val;
        }
      });
      return bases.values.toList();
    }

    // Non-steroid: flat list, recently used first
    final Map<String, CompoundDefinition> compounds = {};
    for (var comp in widget.userCompounds) {
      if (comp.type == targetType && !compounds.containsKey(comp.base)) {
        compounds[comp.base] = comp;
      }
    }
    BASE_LIBRARY.forEach((key, val) {
      if (val.type == targetType && !compounds.containsKey(val.base)) {
        compounds[val.base] = val;
      }
    });
    return compounds.values.toList();
  }

  void _onCompoundSelected(CompoundDefinition compound) {
    setState(() {
      selectedCompound = compound;
      unit = compound.unit;
      step = 2;
    });
  }

  void _goBack() {
    if (_selectedBase != null && step == 1) {
      setState(() => _selectedBase = null);
    } else {
      setState(() { step = 1; _selectedBase = null; });
    }
  }

  void _submit() {
    if (selectedCompound == null) return;
    final DateTime fullDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    var compDef = widget.userCompounds.firstWhere(
            (c) => c.base == selectedCompound!.base && c.ester == selectedCompound!.ester,
        orElse: () {
          final newComp = CompoundDefinition(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            base: selectedCompound!.base,
            ester: selectedCompound!.ester,
            type: selectedCompound!.type,
            graphType: selectedCompound!.graphType,
            halfLife: selectedCompound!.halfLife,
            defaultHalfLife: selectedCompound!.defaultHalfLife,
            timeToPeak: selectedCompound!.timeToPeak,
            ratio: selectedCompound!.ratio,
            unit: unit,
            colorValue: selectedCompound!.colorValue,
          );
          widget.addUserCompound(newComp);
          return newComp;
        }
    );

    widget.onAdd(Injection(id: DateTime.now().toIso8601String(), compoundId: compDef.id, date: fullDate, dosage: double.parse(dose), snapshot: compDef));
    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (step > 1 || _selectedBase != null) IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack),
              Text(step == 1 ? (_selectedBase ?? "Select Compound") : "Details", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel)
            ],
          ),
          const SizedBox(height: 16),

          if (step == 1) ...[
            // Filter tabs
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  {'key': 'steroid', 'label': 'Injectable'},
                  {'key': 'oral', 'label': 'Oral'},
                  {'key': 'peptide', 'label': 'Peptide'},
                  {'key': 'ancillary', 'label': 'Ancillary'},
                ].map((tab) {
                  final isActive = _typeFilter == tab['key'];
                  return Expanded(child: GestureDetector(
                    onTap: () => setState(() { _typeFilter = tab['key']!; _selectedBase = null; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: isActive ? const Color(0xFF334155) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                      child: Center(child: Text(tab['label']!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.grey))),
                    ),
                  ));
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 2.5, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: availableCompounds.length,
              itemBuilder: (c, i) {
                final compound = availableCompounds[i];
                String displayName;
                String subtitle;
                if (_typeFilter == 'steroid' && _selectedBase == null) {
                  displayName = compound.base;
                  final count = _esterCountForBase(compound.base);
                  subtitle = '$count ${count == 1 ? 'variant' : 'variants'}';
                } else if (compound.type == CompoundType.steroid) {
                  displayName = compound.ester;
                  subtitle = 'HL: ${compound.halfLife}d';
                } else {
                  displayName = compound.base;
                  subtitle = compound.type.name.toUpperCase();
                }
                return GestureDetector(
                  onTap: () {
                    if (_typeFilter == 'steroid' && _selectedBase == null) {
                      if (_esterCountForBase(compound.base) == 1) {
                        _onCompoundSelected(compound);
                      } else {
                        setState(() => _selectedBase = compound.base);
                      }
                    } else {
                      _onCompoundSelected(compound);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF334155))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
                        Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              },
            )
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    width: double.infinity,
                    decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF334155))),
                    child: Column(
                      children: [
                        Text(
                          selectedCompound!.type == CompoundType.steroid
                              ? '${selectedCompound!.base} ${selectedCompound!.ester}'.trim()
                              : selectedCompound!.base,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(selectedCompound!.colorValue)),
                        ),
                        const SizedBox(height: 4),
                        Text(selectedCompound!.type.name.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton.icon(icon: const Icon(Icons.calculate, size: 16), label: Text(calcMode ? "Manual Entry" : "Calc by Volume"), onPressed: () => setState(() => calcMode = !calcMode))]),

                  if (calcMode)
                    Row(children: [Expanded(child: _styledInput("Conc (mg/ml)", concentration, (v) { setState(() { concentration = v; dose = ((double.tryParse(v)??0) * (double.tryParse(volume)??0)).toString(); }); })), const SizedBox(width: 10), Expanded(child: _styledInput("Vol (ml)", volume, (v) { setState(() { volume = v; dose = ((double.tryParse(concentration)??0) * (double.tryParse(v)??0)).toString(); }); }))]),

                  const SizedBox(height: 10),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _styledInput("Dosage", dose, (v) => setState(() => dose = v), readOnly: calcMode)),
                      const SizedBox(width: 10),
                      Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<Unit>(
                            value: unit,
                            dropdownColor: const Color(0xFF1E293B),
                            items: Unit.values.map((u) => DropdownMenuItem(value: u, child: Text(u.name.toLowerCase()))).toList(),
                            onChanged: (u) => setState(() => unit = u!),
                          ),
                        ),
                      )
                    ],
                  ),

                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => time = const TimeOfDay(hour: 10, minute: 0)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: time.hour == 10 && time.minute == 0 ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: const Center(child: Text('AM', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))),
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => time = const TimeOfDay(hour: 22, minute: 0)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: time.hour == 22 && time.minute == 0 ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: const Center(child: Text('PM', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))),
                      ),
                    )),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: InkWell(onTap: () async { final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2030), initialDate: date); if (d != null) setState(() => date = d); }, child: _fakeInput(Icons.calendar_today, _formatDate(date, 'yyyy-MM-dd')))),
                    const SizedBox(width: 10),
                    Expanded(child: InkWell(onTap: () async { final t = await showTimePicker(context: context, initialTime: time); if (t != null) setState(() => time = t); }, child: _fakeInput(Icons.access_time, time.format(context)))),
                  ]),

                  const SizedBox(height: 30),
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(vertical: 16)), icon: const Icon(Icons.check, color: Colors.white), label: const Text("CONFIRM ENTRY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: dose.isNotEmpty ? _submit : null))
                ],
              ),
            )
          ]
        ],
      ),
    );
  }

  Widget _styledInput(String label, String value, Function(String) onChanged, {bool readOnly = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(height: 4), TextField(controller: TextEditingController(text: value)..selection = TextSelection.fromPosition(TextPosition(offset: value.length)), onChanged: onChanged, readOnly: readOnly, keyboardType: TextInputType.number, style: TextStyle(color: readOnly ? Colors.grey : Colors.white), decoration: InputDecoration(filled: true, fillColor: const Color(0xFF0F172A), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981))), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)))]);
  }

  Widget _fakeInput(IconData icon, String text) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))), child: Row(children: [Icon(icon, size: 16, color: Colors.grey), const SizedBox(width: 8), Text(text, style: const TextStyle(color: Colors.white))]));
  }
}

class CompoundManager extends StatefulWidget {
  final List<CompoundDefinition> userCompounds;
  final Function(CompoundDefinition) onAdd;
  final Function(String) onDelete;

  const CompoundManager({super.key, required this.userCompounds, required this.onAdd, required this.onDelete});

  @override
  State<CompoundManager> createState() => _CompoundManagerState();
}

class _CompoundManagerState extends State<CompoundManager> {
  bool isCreating = false;
  String base = '';
  String ester = '';
  CompoundType type = CompoundType.steroid;
  GraphType graphType = GraphType.curve;
  String halfLife = '2';
  String timeToPeak = '1';
  String ratio = '100';
  Unit unit = Unit.mg;

  void _save() {
    final comp = CompoundDefinition(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      base: base,
      ester: ester.isEmpty ? 'None' : ester,
      type: type,
      // Removed Curve option for Peptides/Ancillaries per request
      graphType: (type == CompoundType.steroid || type == CompoundType.oral) ? GraphType.curve : graphType,
      halfLife: double.tryParse(halfLife) ?? 0,
      timeToPeak: double.tryParse(timeToPeak) ?? 0,
      ratio: (double.tryParse(ratio) ?? 100) / 100,
      unit: unit,
      colorValue: type == CompoundType.steroid ? 0xFF10B981 : 0xFF8B5CF6,
      isCustom: true,
    );
    widget.onAdd(comp);
    setState(() => isCreating = false);
  }

  @override
  Widget build(BuildContext context) {
    if (isCreating) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => isCreating = false)), const Text("Create Compound", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 16),
            _buildField("Base Name", (v) => base = v),
            const SizedBox(height: 12),
            _buildDropdown("Type", type, CompoundType.values, (v) => setState(() => type = v!)),
            const SizedBox(height: 12),
            if (type == CompoundType.steroid) ...[_buildField("Ester", (v) => ester = v), const SizedBox(height: 12)],

            if (type == CompoundType.peptide || type == CompoundType.ancillary) ...[
              const Text("Visual Mode", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: GestureDetector(onTap: () => setState(() => graphType = GraphType.activeWindow), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: graphType == GraphType.activeWindow ? const Color(0xFF10B981) : const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)), child: const Center(child: Text("Active Window", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))))),
                const SizedBox(width: 8),
                Expanded(child: GestureDetector(onTap: () => setState(() => graphType = GraphType.event), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: graphType == GraphType.event ? const Color(0xFF10B981) : const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)), child: const Center(child: Text("Event Marker", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))))),
              ]),
              const SizedBox(height: 12)
            ],

            if (type == CompoundType.steroid || type == CompoundType.oral || (graphType == GraphType.activeWindow))
              Row(children: [
                Expanded(child: _buildField("Half Life (days)", (v) => halfLife = v, init: halfLife)),
                const SizedBox(width: 10),
                if (type == CompoundType.steroid || type == CompoundType.oral) Expanded(child: _buildField("Time to Peak", (v) => timeToPeak = v, init: timeToPeak)),
              ]),

            const SizedBox(height: 12),
            Row(children: [
              if (type == CompoundType.steroid) Expanded(child: _buildField("Yield %", (v) => ratio = v, init: ratio)),
              const SizedBox(width: 10),
              Expanded(child: _buildDropdown("Unit", unit, Unit.values, (v) => setState(() => unit = v!))),
            ]),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.all(16)), child: const Text("SAVE", style: TextStyle(color: Colors.white))))
          ],
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(backgroundColor: const Color(0xFF10B981), child: const Icon(Icons.add, color: Colors.white), onPressed: () => setState(() => isCreating = true)),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.userCompounds.length,
        itemBuilder: (c, i) {
          final comp = widget.userCompounds[i];
          return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(title: Text(comp.base, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), subtitle: Text("${comp.ester} • ${comp.type.name.toUpperCase()}"), trailing: comp.isCustom == true ? IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: () => widget.onDelete(comp.id)) : null));
        },
      ),
    );
  }

  Widget _buildField(String label, Function(String) onChange, {String? init}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(height: 4), TextFormField(initialValue: init, onChanged: onChange, style: const TextStyle(color: Colors.white), decoration: InputDecoration(filled: true, fillColor: const Color(0xFF0F172A), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981)))))]);
  }

  Widget _buildDropdown<T>(String label, T value, List<T> items, Function(T?) onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 4),
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))),
          child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E293B),
                  items: items.map((e) {
                    String text = e.toString().split('.').last;
                    if (e is Unit) text = text.toLowerCase();
                    else text = _capitalize(text);
                    return DropdownMenuItem(value: e, child: Text(text));
                  }).toList(),
                  onChanged: onChanged
              )
          )
      )
    ]);
  }
}

class PKGraphPainter extends CustomPainter {
  final ComputedGraphData graphData;
  final GraphSettings settings;
  final double peptideLaneHeight = 24.0;
  final double leftLabelAreaWidth = 60.0;

  PKGraphPainter({required this.graphData, required this.settings});

  @override
  void paint(Canvas canvas, Size size) {
    final laneCount = graphData.laneLabels.length;
    final topAreaHeight = math.max(40.0, (laneCount * peptideLaneHeight) + 20.0);
    final graphHeight = size.height - topAreaHeight;
    final paddingLeft = 45.0;
    final paddingRight = 20.0;
    final paddingBottom = 20.0;
    final chartWidth = size.width - paddingLeft - paddingRight;
    final chartHeight = graphHeight - paddingBottom;

    final laneBgPaint = Paint()..color = const Color(0xFF0F172A).withOpacity(0.5);
    final RRect laneRect = RRect.fromRectAndRadius(Rect.fromLTWH(paddingLeft, 0, chartWidth, topAreaHeight), const Radius.circular(4));
    canvas.drawRRect(laneRect, laneBgPaint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < graphData.laneLabels.length; i++) {
      final name = graphData.laneLabels[i];
      final colorValue = graphData.peptideLanes.firstWhere((l) => l.baseName == name, orElse: () => PeptideLaneData(name, 0xFF999999, 0, 0, 0, GraphType.event)).colorValue;
      textPainter.text = TextSpan(text: name, style: TextStyle(color: Color(colorValue), fontSize: 9, fontWeight: FontWeight.bold));
      textPainter.layout();
      // Draw label inside the rect, left aligned, slightly offset from top of lane
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
        final paint = Paint()..shader = LinearGradient(colors: [lane.color.withOpacity(0.95), lane.color.withOpacity(0.5), lane.color.withOpacity(0.25), lane.color.withOpacity(0.0)], stops: const [0.0, 0.166, 0.333, 1.0]).createShader(rect);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
      } else {
        canvas.drawCircle(Offset(x, y + 17), 3, Paint()..color = lane.color);
      }
    }
    canvas.restore();

    canvas.save();
    canvas.translate(0, topAreaHeight);

    final gridPaint = Paint()..color = const Color(0xFF334155)..strokeWidth = 0.5..style = PaintingStyle.stroke;
    for (int i = 0; i <= 4; i++) {
      double y = chartHeight - (chartHeight * (i / 4));
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaint);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final startMs = graphData.startDate.millisecondsSinceEpoch;
    double todayPct = (nowMs - startMs) / graphData.totalDurationMs;
    double todayX = paddingLeft + (todayPct * chartWidth);
    if(todayX >= paddingLeft && todayX <= size.width - paddingRight) {
      canvas.drawLine(Offset(todayX, 0), Offset(todayX, chartHeight), Paint()..color = const Color(0xFFF59E0B)..strokeWidth = 1.5);
    }

    for (var curve in graphData.curves) {
      if (curve.baseName == 'Total Androgens' && !settings.cumulative) continue;
      final path = Path();
      if (curve.points.isNotEmpty) {
        double normalizationMax = 0;
        if (settings.normalized) { for (var p in curve.points) normalizationMax = math.max(normalizationMax, p.dy); if (normalizationMax == 0) normalizationMax = 1; }
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
        canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.0)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
      } else {
        canvas.drawPath(path, Paint()..color = curve.color..style = PaintingStyle.stroke..strokeWidth = curve.isOral ? 2.0 : 2.5..strokeCap = StrokeCap.round);
      }
    }

    final textStyle = TextStyle(color: Colors.grey[500], fontSize: 10, fontFamily: 'monospace');
    if (!settings.normalized) {
      for (int i = 0; i <= 4; i++) {
        final val = (graphData.maxMg * (i / 4)).round();
        final y = chartHeight - (chartHeight * (i / 4));
        textPainter.text = TextSpan(text: '$val', style: textStyle);
        textPainter.layout();
        textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 5, y - textPainter.height / 2));
      }
      if (graphData.maxOralMg > 5) {
        for (int i = 0; i <= 4; i++) {
          final val = (graphData.maxOralMg * (i / 4)).round();
          final y = chartHeight - (chartHeight * (i / 4));
          textPainter.text = TextSpan(text: '$val', style: textStyle.copyWith(color: const Color(0xFFF43F5E)));
          textPainter.layout();
          textPainter.paint(canvas, Offset(size.width - paddingRight + 5, y - textPainter.height / 2));
        }
      }
    } else {
      for (int i = 0; i <= 4; i++) {
        final val = (i * 25);
        final y = chartHeight - (chartHeight * (i / 4));
        textPainter.text = TextSpan(text: '$val%', style: textStyle);
        textPainter.layout();
        textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 5, y - textPainter.height / 2));
      }
    }

    // X-Axis Labels (Date/Time)
    for (int i = 0; i <= 4; i++) {
      final pct = i / 4.0;
      final x = paddingLeft + (pct * chartWidth);
      final ms = graphData.startDate.millisecondsSinceEpoch + (pct * graphData.totalDurationMs).toInt();
      final date = DateTime.fromMillisecondsSinceEpoch(ms);
      String label = "";

      if (settings.timeRange == 'zoom') {
        label = _formatDate(date, 'EEE ha');
      } else {
        label = _formatDate(date, 'MMM d');
      }

      textPainter.text = TextSpan(text: label, style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width/2, chartHeight + 5));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PKGraphPainter oldDelegate) =>
      oldDelegate.graphData != graphData || oldDelegate.settings != settings;
}