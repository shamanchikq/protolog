import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
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
    return "${twoDigits(date.day)}/${twoDigits(date.month)} ${twoDigits(date.hour)}:${twoDigits(date.minute)}";
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
  } else if (esterName.contains('Tri-Tren')) {
    double level = 0;
    for (var comp in TREN_BLEND) {
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
    final fadeDurationMs = (halfLife * 4) * 86400000;
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

  final injectionMarkers = <InjectionMarkerData>[];
  for (var inj in curveInjections) {
    final ms = inj.date.millisecondsSinceEpoch - startMs;
    final pct = ms / totalDurationMs;
    if (pct >= 0 && pct <= 1.0) {
      final baseInjs = injectionsByBase[inj.snapshot.base] ?? [];
      double level = 0;
      for (var other in baseInjs) {
        final diffMs = inj.date.millisecondsSinceEpoch - other.date.millisecondsSinceEpoch;
        if (diffMs >= 0) {
          level += _calculateActiveLevel(other.dosage, diffMs / 86400000.0,
              other.snapshot.halfLife, other.snapshot.timeToPeak, other.snapshot.ratio, other.snapshot.ester);
        }
      }
      injectionMarkers.add(InjectionMarkerData(pct, level, inj.snapshot.type == CompoundType.oral, inj.snapshot.colorValue));
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
    injectionMarkers: injectionMarkers,
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
  List<Reminder> reminders = [];
  late GraphSettings settings;
  Future<ComputedGraphData>? _graphDataFuture;
  bool _loading = true;

  // Calendar state
  late DateTime _calendarMonth;
  DateTime? _selectedDay;
  bool _showFullHistory = false;

  // Notifications
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    settings = const GraphSettings(normalized: false, cumulative: false, showPeptides: true, timeRange: 'standard');
    final now = DateTime.now();
    _calendarMonth = DateTime(now.year, now.month);
    _initNotifications();
    _loadData();
  }

  Future<void> _initNotifications() async {
    tz.initializeTimeZones();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notificationsPlugin.initialize(initSettings);
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

    // Load Reminders
    final remString = prefs.getString('reminders');
    if (remString != null) {
      final List<dynamic> jsonList = jsonDecode(remString);
      reminders = jsonList.map((j) => Reminder.fromJson(j)).toList();
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

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('reminders', jsonEncode(reminders.map((r) => r.toJson()).toList()));
  }

  Future<void> _scheduleReminder(Reminder reminder) async {
    if (!reminder.enabled) return;
    final now = DateTime.now();
    final compoundLabel = '${reminder.compoundBase}${reminder.compoundEster != 'None' ? ' ${reminder.compoundEster}' : ''}';
    final androidDetails = AndroidNotificationDetails(
      'protolog_reminders',
      'Administration Reminders',
      channelDescription: 'Recurring compound administration reminders',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    if (reminder.scheduleMode == 'custom' && reminder.customSlots.isNotEmpty) {
      // Schedule one notification per custom slot (next occurrence of each weekday+time)
      for (int i = 0; i < reminder.customSlots.length; i++) {
        final slot = reminder.customSlots[i];
        var next = DateTime(now.year, now.month, now.day, slot.hour, slot.minute);
        // Advance to the correct weekday
        while (next.weekday != slot.weekday || next.isBefore(now)) {
          next = next.add(const Duration(days: 1));
        }
        final scheduledTz = tz.TZDateTime.from(next, tz.local);
        await _notificationsPlugin.zonedSchedule(
          reminder.id.hashCode + i + 1,
          'ProtoLog Reminder',
          'Time to administer $compoundLabel',
          scheduledTz,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    } else {
      // Interval mode
      final baseDate = reminder.lastScheduledDate ?? now;
      var nextDate = DateTime(baseDate.year, baseDate.month, baseDate.day, reminder.hour, reminder.minute);
      nextDate = nextDate.add(Duration(days: reminder.intervalDays));
      while (nextDate.isBefore(now)) {
        nextDate = nextDate.add(Duration(days: reminder.intervalDays));
      }
      final scheduledTz = tz.TZDateTime.from(nextDate, tz.local);
      await _notificationsPlugin.zonedSchedule(
        reminder.id.hashCode,
        'ProtoLog Reminder',
        'Time to administer $compoundLabel',
        scheduledTz,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: null,
      );
    }
  }

  Future<void> _cancelReminder(Reminder reminder) async {
    await _notificationsPlugin.cancel(reminder.id.hashCode);
    // Cancel all custom slot notifications too
    for (int i = 0; i < reminder.customSlots.length; i++) {
      await _notificationsPlugin.cancel(reminder.id.hashCode + i + 1);
    }
  }

  void _exportToMarkdown() {
    final sorted = List<Injection>.from(injections)..sort((a, b) => b.date.compareTo(a.date));
    final buf = StringBuffer();
    buf.writeln('| Date | Compound | Ester | Dosage | Unit |');
    buf.writeln('|------|----------|-------|--------|------|');
    for (var inj in sorted) {
      final d = inj.date;
      final dateStr = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      final ester = inj.snapshot.ester == 'None' ? '' : inj.snapshot.ester;
      final unit = inj.snapshot.unit.toString().split('.').last;
      buf.writeln('| $dateStr | ${inj.snapshot.base} | $ester | ${inj.dosage} | $unit |');
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log exported to clipboard as Markdown'), backgroundColor: Color(0xFF10B981)),
      );
    }
  }

  Future<void> _importFromMarkdown() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null || data.text!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    final lines = data.text!.split('\n').where((l) => l.trim().startsWith('|') && !l.contains('---')).toList();
    // Skip header row
    final dataLines = lines.length > 1 ? lines.sublist(1) : <String>[];
    if (dataLines.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid data found in clipboard'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final List<Injection> parsed = [];
    for (var line in dataLines) {
      // Split by | and keep empty cells to preserve column positions
      // A line like "| date | base |  | 100 | mg |" splits to ['', ' date ', ' base ', '  ', ' 100 ', ' mg ', '']
      // Drop the leading/trailing empty strings from the outer pipes, keep inner empties
      final rawCells = line.split('|').map((c) => c.trim()).toList();
      // Remove first and last if empty (from leading/trailing |)
      if (rawCells.isNotEmpty && rawCells.first.isEmpty) rawCells.removeAt(0);
      if (rawCells.isNotEmpty && rawCells.last.isEmpty) rawCells.removeLast();
      if (rawCells.length < 5) continue;
      final dateStr = rawCells[0]; // dd/MM/yyyy HH:mm
      final base = rawCells[1];
      final ester = rawCells[2].isEmpty ? 'None' : rawCells[2];
      final dosage = double.tryParse(rawCells[3]);
      final unitStr = rawCells[4];
      if (dosage == null || base.isEmpty) continue;

      // Parse date: dd/MM/yyyy HH:mm
      final parts = dateStr.split(' ');
      if (parts.length < 2) continue;
      final dateParts = parts[0].split('/');
      final timeParts = parts[1].split(':');
      if (dateParts.length < 3 || timeParts.length < 2) continue;
      final day = int.tryParse(dateParts[0]);
      final month = int.tryParse(dateParts[1]);
      final year = int.tryParse(dateParts[2]);
      final hour = int.tryParse(timeParts[0]);
      final minute = int.tryParse(timeParts[1]);
      if (day == null || month == null || year == null || hour == null || minute == null) continue;
      final date = DateTime(year, month, day, hour, minute);

      // Skip if this injection already exists (same compound+date+dosage)
      final alreadyExists = injections.any((i) =>
        i.snapshot.base == base && i.snapshot.ester == ester &&
        i.date.difference(date).inMinutes.abs() < 1 && i.dosage == dosage
      );
      if (alreadyExists) continue;

      // Look up compound definition
      CompoundDefinition? def;
      for (var c in userCompounds) {
        if (c.base == base && c.ester == ester) { def = c; break; }
      }
      def ??= _lookupLibraryDef(base, ester);
      if (def == null) continue;

      final unit = unitStr == 'mcg' ? Unit.mcg : unitStr == 'iu' ? Unit.iu : Unit.mg;
      parsed.add(Injection(
        id: '${date.millisecondsSinceEpoch}_$base',
        compoundId: def.id,
        date: date,
        dosage: dosage,
        snapshot: CompoundDefinition(
          id: def.id, base: def.base, ester: def.ester, type: def.type,
          graphType: def.graphType, halfLife: def.halfLife, timeToPeak: def.timeToPeak,
          ratio: def.ratio, unit: unit, colorValue: def.colorValue,
        ),
      ));
    }

    if (parsed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No new entries to import'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Import Data'),
        content: Text('Found ${parsed.length} new entries to import. Proceed?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import', style: TextStyle(color: Color(0xFF10B981)))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => injections.addAll(parsed));
    _saveData();
    _refreshGraph();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${parsed.length} entries'), backgroundColor: const Color(0xFF10B981)),
      );
    }
  }

  void _openReminders() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => RemindersPage(
        reminders: reminders,
        userCompounds: userCompounds,
        onSave: (updated) {
          setState(() => reminders = updated);
          _saveReminders();
        },
        onSchedule: _scheduleReminder,
        onCancel: _cancelReminder,
      ),
    ));
  }

  Future<void> _addInjection(Injection inj) async {
    setState(() {
      injections.add(inj);
    });
    _saveData();
    _refreshGraph();

    // Auto-reschedule matching reminders
    for (int i = 0; i < reminders.length; i++) {
      final r = reminders[i];
      if (r.compoundBase == inj.snapshot.base && r.compoundEster == inj.snapshot.ester && r.enabled) {
        await _cancelReminder(r);
        final updated = r.copyWith(lastScheduledDate: inj.date);
        reminders[i] = updated;
        await _scheduleReminder(updated);
      }
    }
    _saveReminders();
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
      case 1: content = _buildCalendar(); break;
      case 2: content = AddInjectionWizard(
        onAdd: _addInjection,
        onCancel: () => _onTabTapped(0),
        onSuccess: () => _onTabTapped(0),
        userCompounds: userCompounds,
        addUserCompound: _addUserCompound,
        injections: injections,
      ); break;
      case 3: content = CompoundManager(
        userCompounds: userCompounds,
        onAdd: _addUserCompound,
        onDelete: _deleteUserCompound,
        onExport: _exportToMarkdown,
        onImport: _importFromMarkdown,
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
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Calendar'),
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
          Row(
            children: [
              const Icon(Icons.monitor_heart_outlined, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              const Text('ProtoLog', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.grey),
                onPressed: _openReminders,
              ),
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
                    return Column(
                      children: [
                        SizedBox(
                            height: 300.0 + swimlaneH,
                            width: double.infinity,
                            child: Padding(
                                padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
                                child: RepaintBoundary(child: CustomPaint(painter: PKGraphPainter(graphData: snapshot.data!, settings: settings)))
                            )
                        ),
                        if (snapshot.data!.curves.where((c) => c.baseName != 'Total Androgens').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Wrap(
                              spacing: 12, runSpacing: 4,
                              children: snapshot.data!.curves
                                .where((c) => c.baseName != 'Total Androgens')
                                .map((c) => Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(width: 8, height: 8, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
                                  const SizedBox(width: 4),
                                  Text(c.baseName, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ])).toList(),
                            ),
                          ),
                      ],
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
                IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.grey), onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E293B),
                    title: const Text('Delete Entry?'),
                    content: Text('${inj.snapshot.base} ${inj.snapshot.ester != 'None' ? inj.snapshot.ester : ''} — ${inj.dosage} ${inj.snapshot.unit.toString().split('.').last}'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      TextButton(onPressed: () { Navigator.pop(ctx); _deleteInjection(inj.id); }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ))
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalendar() {
    if (_showFullHistory) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _showFullHistory = false)),
                const Text('Full History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(child: _buildHistory()),
        ],
      );
    }

    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=Mon
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final today = DateTime.now();

    // Build map of day -> list of color values for that day
    final Map<int, List<int>> dayColors = {};
    for (var inj in injections) {
      if (inj.date.year == year && inj.date.month == month) {
        dayColors.putIfAbsent(inj.date.day, () => []);
        if (!dayColors[inj.date.day]!.contains(inj.snapshot.colorValue)) {
          dayColors[inj.date.day]!.add(inj.snapshot.colorValue);
        }
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () {
                setState(() {
                  _calendarMonth = DateTime(year, month - 1);
                  _selectedDay = null;
                });
              }),
              Text('${months[month - 1]} $year', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: () {
                    setState(() {
                      _calendarMonth = DateTime(year, month + 1);
                      _selectedDay = null;
                    });
                  }),
                  IconButton(icon: const Icon(Icons.list, color: Colors.grey), onPressed: () => setState(() => _showFullHistory = true)),
                ],
              ),
            ],
          ),
        ),
        // Day-of-week headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                .map((d) => Expanded(child: Center(child: Text(d, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)))))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        // Calendar grid
        GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null) {
              setState(() {
                if (details.primaryVelocity! > 0) {
                  _calendarMonth = DateTime(year, month - 1);
                } else {
                  _calendarMonth = DateTime(year, month + 1);
                }
                _selectedDay = null;
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1),
              itemCount: (firstWeekday - 1) + daysInMonth,
              itemBuilder: (context, index) {
                if (index < firstWeekday - 1) return const SizedBox();
                final day = index - (firstWeekday - 1) + 1;
                final isToday = today.year == year && today.month == month && today.day == day;
                final isSelected = _selectedDay != null && _selectedDay!.year == year && _selectedDay!.month == month && _selectedDay!.day == day;
                final colors = dayColors[day] ?? [];

                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = DateTime(year, month, day)),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF10B981).withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isToday ? Border.all(color: const Color(0xFF10B981), width: 1.5) : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$day', style: TextStyle(fontSize: 13, color: isSelected ? const Color(0xFF10B981) : Colors.white)),
                        if (colors.isNotEmpty)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: colors.take(3).map((c) => Container(
                              width: 5, height: 5,
                              margin: const EdgeInsets.only(top: 2, left: 1, right: 1),
                              decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle),
                            )).toList(),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Selected day injections
        if (_selectedDay != null)
          Expanded(child: _buildDayInjections(_selectedDay!))
        else
          const Expanded(child: Center(child: Text('Tap a day to view entries', style: TextStyle(color: Colors.grey)))),
      ],
    );
  }

  Widget _buildDayInjections(DateTime day) {
    final dayInjs = injections.where((i) =>
      i.date.year == day.year && i.date.month == day.month && i.date.day == day.day
    ).toList()..sort((a, b) => a.date.compareTo(b.date));

    if (dayInjs.isEmpty) {
      return const Center(child: Text('No entries for this day', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: dayInjs.length,
      itemBuilder: (context, index) {
        final inj = dayInjs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Color(inj.snapshot.colorValue).withOpacity(0.2), child: Icon(Icons.circle, color: Color(inj.snapshot.colorValue), size: 14)),
            title: Text(inj.snapshot.base, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: Text("${inj.snapshot.ester.isNotEmpty && inj.snapshot.ester != 'None' ? inj.snapshot.ester : ''} • ${_formatDate(inj.date, 'MM/dd HH:mm')}"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${inj.dosage} ${inj.snapshot.unit.toString().split('.').last}", style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.grey), onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E293B),
                    title: const Text('Delete Entry?'),
                    content: Text('${inj.snapshot.base} ${inj.snapshot.ester != 'None' ? inj.snapshot.ester : ''} — ${inj.dosage} ${inj.snapshot.unit.toString().split('.').last}'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      TextButton(onPressed: () { Navigator.pop(ctx); _deleteInjection(inj.id); }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ))
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
  final List<Injection> injections;

  const AddInjectionWizard({super.key, required this.onAdd, required this.onCancel, required this.onSuccess, required this.userCompounds, required this.addUserCompound, required this.injections});

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
  Injection? _lastForCompound;

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
    final matches = widget.injections
        .where((i) => i.snapshot.base == compound.base && i.snapshot.ester == compound.ester)
        .toList()..sort((a, b) => b.date.compareTo(a.date));

    setState(() {
      selectedCompound = compound;
      unit = compound.unit;
      _lastForCompound = matches.isNotEmpty ? matches.first : null;
      if (_lastForCompound != null) {
        dose = _lastForCompound!.dosage.toString();
      }
      step = 2;
    });
  }

  void _goBack() {
    if (_selectedBase != null && step == 1) {
      setState(() => _selectedBase = null);
    } else {
      setState(() { step = 1; _selectedBase = null; _lastForCompound = null; });
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
                  if (_lastForCompound != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Last: ${_lastForCompound!.dosage} ${_lastForCompound!.snapshot.unit.toString().split('.').last} — ${_formatDate(_lastForCompound!.date, 'MMM d')}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)),
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
  final VoidCallback onExport;
  final VoidCallback onImport;

  const CompoundManager({super.key, required this.userCompounds, required this.onAdd, required this.onDelete, required this.onExport, required this.onImport});

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.science, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Text('My Compounds', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  color: const Color(0xFF1E293B),
                  onSelected: (value) {
                    if (value == 'export') widget.onExport();
                    if (value == 'import') widget.onImport();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'export', child: Text('Export Log to Clipboard')),
                    PopupMenuItem(value: 'import', child: Text('Import Log from Clipboard')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.userCompounds.length,
              itemBuilder: (c, i) {
                final comp = widget.userCompounds[i];
                return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(title: Text(comp.base, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), subtitle: Text("${comp.ester} • ${comp.type.name.toUpperCase()}"), trailing: comp.isCustom == true ? IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: () => widget.onDelete(comp.id)) : null));
              },
            ),
          ),
        ],
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
        final paint = Paint()..shader = LinearGradient(colors: [lane.color.withOpacity(0.95), lane.color.withOpacity(0.45), lane.color.withOpacity(0.12), lane.color.withOpacity(0.0)], stops: const [0.0, 0.25, 0.5, 1.0]).createShader(rect);
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

    // Injection Markers
    for (var marker in graphData.injectionMarkers) {
      final x = paddingLeft + (marker.xPct * chartWidth);
      final maxY = settings.normalized ? 1.0 : (marker.isOral ? graphData.maxOralMg : graphData.maxMg);
      final yVal = settings.normalized ? 0.0 : marker.yLevel;
      final y = chartHeight - ((yVal / maxY) * chartHeight);
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = Color(marker.colorValue));
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

// --- Reminders Page ---

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class RemindersPage extends StatefulWidget {
  final List<Reminder> reminders;
  final List<CompoundDefinition> userCompounds;
  final Function(List<Reminder>) onSave;
  final Function(Reminder) onSchedule;
  final Function(Reminder) onCancel;

  const RemindersPage({super.key, required this.reminders, required this.userCompounds, required this.onSave, required this.onSchedule, required this.onCancel});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  late List<Reminder> _reminders;
  bool _isAdding = false;
  String? _selectedBase;
  String? _selectedEster;
  String _scheduleMode = 'interval';
  String _intervalDays = '3';
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  // Custom mode state: which days are selected, and per-day time (AM/PM or custom)
  final Map<int, TimeOfDay> _customDayTimes = {}; // weekday (1-7) -> time
  // Compound selector state (category tabs + steroid drill-down)
  String _typeFilter = 'steroid';
  String? _selectedBaseForSteroid;

  @override
  void initState() {
    super.initState();
    _reminders = List.from(widget.reminders);
  }

  void _resetForm() {
    _selectedBase = null;
    _selectedEster = null;
    _scheduleMode = 'interval';
    _intervalDays = '3';
    _time = const TimeOfDay(hour: 10, minute: 0);
    _customDayTimes.clear();
    _typeFilter = 'steroid';
    _selectedBaseForSteroid = null;
  }

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

  List<CompoundDefinition> get _availableCompounds {
    final targetType = _typeFilter == 'steroid' ? CompoundType.steroid
        : _typeFilter == 'oral' ? CompoundType.oral
        : _typeFilter == 'peptide' ? CompoundType.peptide
        : CompoundType.ancillary;

    if (targetType == CompoundType.steroid) {
      if (_selectedBaseForSteroid != null) {
        final Map<String, CompoundDefinition> esters = {};
        for (var comp in widget.userCompounds) {
          if (comp.type == CompoundType.steroid && comp.base == _selectedBaseForSteroid && !esters.containsKey(comp.ester)) {
            esters[comp.ester] = comp;
          }
        }
        BASE_LIBRARY.forEach((key, val) {
          if (val.type == CompoundType.steroid && val.base == _selectedBaseForSteroid && !esters.containsKey(val.ester)) {
            esters[val.ester] = val;
          }
        });
        return esters.values.toList();
      }
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

  String _formatSchedule(Reminder r) {
    if (r.scheduleMode == 'custom' && r.customSlots.isNotEmpty) {
      // Check if all slots are weekdays at the same time
      final weekdaySlots = r.customSlots.where((s) => s.weekday >= 1 && s.weekday <= 5).toList();
      final allSameTime = r.customSlots.every((s) => s.hour == r.customSlots.first.hour && s.minute == r.customSlots.first.minute);
      if (weekdaySlots.length == 5 && r.customSlots.length == 5 && allSameTime) {
        return 'Weekdays at ${r.customSlots.first.hour.toString().padLeft(2, '0')}:${r.customSlots.first.minute.toString().padLeft(2, '0')}';
      }
      return r.customSlots.map((s) {
        final dayName = _dayNames[s.weekday - 1];
        final h = s.hour;
        return '$dayName ${h < 12 ? 'AM' : 'PM'}';
      }).join(', ');
    }
    final timeStr = '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}';
    return 'Every ${r.intervalDays} days at $timeStr';
  }

  void _saveReminder() {
    if (_selectedBase == null) return;

    List<ReminderSlot> slots = [];
    if (_scheduleMode == 'custom') {
      if (_customDayTimes.isEmpty) return;
      final sortedDays = _customDayTimes.keys.toList()..sort();
      for (var day in sortedDays) {
        final t = _customDayTimes[day]!;
        slots.add(ReminderSlot(weekday: day, hour: t.hour, minute: t.minute));
      }
    }

    final reminder = Reminder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      compoundBase: _selectedBase!,
      compoundEster: _selectedEster ?? 'None',
      scheduleMode: _scheduleMode,
      intervalDays: int.tryParse(_intervalDays) ?? 3,
      hour: _time.hour,
      minute: _time.minute,
      customSlots: slots,
      enabled: true,
    );
    setState(() {
      _reminders.add(reminder);
      _isAdding = false;
    });
    _resetForm();
    widget.onSave(_reminders);
    widget.onSchedule(reminder);
  }

  void _toggleReminder(int index) {
    final r = _reminders[index];
    final updated = r.copyWith(enabled: !r.enabled);
    setState(() => _reminders[index] = updated);
    widget.onSave(_reminders);
    if (updated.enabled) {
      widget.onSchedule(updated);
    } else {
      widget.onCancel(updated);
    }
  }

  void _deleteReminder(int index) {
    final r = _reminders[index];
    widget.onCancel(r);
    setState(() => _reminders.removeAt(index));
    widget.onSave(_reminders);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Reminders'),
      ),
      floatingActionButton: _isAdding ? null : FloatingActionButton(
        backgroundColor: const Color(0xFF10B981),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => setState(() {
          _resetForm();
          _isAdding = true;
        }),
      ),
      body: _isAdding ? _buildAddForm() : _buildList(),
    );
  }

  Widget _buildList() {
    if (_reminders.isEmpty) {
      return const Center(child: Text('No reminders yet', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reminders.length,
      itemBuilder: (context, index) {
        final r = _reminders[index];
        return Card(
          color: const Color(0xFF1E293B),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              '${r.compoundBase}${r.compoundEster != 'None' ? ' ${r.compoundEster}' : ''}',
              style: TextStyle(fontWeight: FontWeight.bold, color: r.enabled ? Colors.white : Colors.grey),
            ),
            subtitle: Text(_formatSchedule(r), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: r.enabled,
                  activeTrackColor: const Color(0xFF10B981),
                  onChanged: (_) => _toggleReminder(index),
                ),
                IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.grey), onPressed: () => _deleteReminder(index)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {
                if (_selectedBaseForSteroid != null) {
                  setState(() => _selectedBaseForSteroid = null);
                } else {
                  setState(() { _isAdding = false; _resetForm(); });
                }
              }),
              Text(_selectedBaseForSteroid ?? 'New Reminder', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          // Compound selector - category tabs
          if (_selectedBase == null) ...[
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
                    onTap: () => setState(() { _typeFilter = tab['key']!; _selectedBaseForSteroid = null; }),
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
              itemCount: _availableCompounds.length,
              itemBuilder: (c, i) {
                final compound = _availableCompounds[i];
                String displayName;
                String subtitle;
                if (_typeFilter == 'steroid' && _selectedBaseForSteroid == null) {
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
                    if (_typeFilter == 'steroid' && _selectedBaseForSteroid == null) {
                      if (_esterCountForBase(compound.base) == 1) {
                        setState(() {
                          _selectedBase = compound.base;
                          _selectedEster = compound.ester;
                        });
                      } else {
                        setState(() => _selectedBaseForSteroid = compound.base);
                      }
                    } else {
                      setState(() {
                        _selectedBase = compound.base;
                        _selectedEster = compound.ester;
                      });
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
            ),
          ],
          if (_selectedBase != null) ...[
            // Show selected compound chip with clear button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))),
              child: Row(
                children: [
                  Expanded(child: Text(
                    '$_selectedBase${_selectedEster != null && _selectedEster != 'None' ? ' $_selectedEster' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  )),
                  GestureDetector(
                    onTap: () => setState(() { _selectedBase = null; _selectedEster = null; _selectedBaseForSteroid = null; }),
                    child: const Icon(Icons.close, size: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
          if (_selectedBase != null) ...[
          const SizedBox(height: 20),
          // Schedule mode toggle
          const Text('Schedule Type', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                _modeTab('Interval', 'interval'),
                _modeTab('Custom Days', 'custom'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_scheduleMode == 'interval') ...[
            const Text('Interval (days)', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            TextField(
              controller: TextEditingController(text: _intervalDays),
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => _intervalDays = v,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Time', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            InkWell(
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))),
                child: Row(children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(_time.format(context), style: const TextStyle(color: Colors.white)),
                ]),
              ),
            ),
          ],

          if (_scheduleMode == 'custom') ...[
            const Text('Select days and times', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            // Quick-select row
            Row(
              children: [
                _quickSelectBtn('Weekdays', () {
                  setState(() {
                    _customDayTimes.clear();
                    for (int d = 1; d <= 5; d++) {
                      _customDayTimes[d] = const TimeOfDay(hour: 10, minute: 0);
                    }
                  });
                }),
                const SizedBox(width: 8),
                _quickSelectBtn('MWF', () {
                  setState(() {
                    _customDayTimes.clear();
                    for (var d in [1, 3, 5]) {
                      _customDayTimes[d] = const TimeOfDay(hour: 10, minute: 0);
                    }
                  });
                }),
                const SizedBox(width: 8),
                _quickSelectBtn('TTS', () {
                  setState(() {
                    _customDayTimes.clear();
                    for (var d in [2, 4, 6]) {
                      _customDayTimes[d] = const TimeOfDay(hour: 10, minute: 0);
                    }
                  });
                }),
              ],
            ),
            const SizedBox(height: 12),
            // Day grid with toggles
            ...List.generate(7, (i) {
              final weekday = i + 1; // 1=Mon
              final isSelected = _customDayTimes.containsKey(weekday);
              final dayTime = _customDayTimes[weekday] ?? const TimeOfDay(hour: 10, minute: 0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() {
                        if (isSelected) {
                          _customDayTimes.remove(weekday);
                        } else {
                          _customDayTimes[weekday] = const TimeOfDay(hour: 10, minute: 0);
                        }
                      }),
                      child: Container(
                        width: 56,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSelected ? const Color(0xFF10B981) : const Color(0xFF334155)),
                        ),
                        child: Center(child: Text(_dayNames[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey))),
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 10),
                      _amPmBtn('AM', weekday, dayTime, const TimeOfDay(hour: 10, minute: 0)),
                      const SizedBox(width: 6),
                      _amPmBtn('PM', weekday, dayTime, const TimeOfDay(hour: 22, minute: 0)),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () async {
                          final t = await showTimePicker(context: context, initialTime: dayTime);
                          if (t != null) setState(() => _customDayTimes[weekday] = t);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: (dayTime.hour != 10 || dayTime.minute != 0) && (dayTime.hour != 22 || dayTime.minute != 0)
                                ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Text(dayTime.format(context), style: const TextStyle(fontSize: 12, color: Colors.white)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: (_scheduleMode == 'interval' || _customDayTimes.isNotEmpty) ? _saveReminder : null,
              child: const Text('SAVE REMINDER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          ],
        ],
      ),
    );
  }

  Widget _modeTab(String label, String mode) {
    final isActive = _scheduleMode == mode;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _scheduleMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: isActive ? const Color(0xFF334155) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Center(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.grey))),
      ),
    ));
  }

  Widget _quickSelectBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF334155))),
        child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _amPmBtn(String label, int weekday, TimeOfDay current, TimeOfDay target) {
    final isActive = current.hour == target.hour && current.minute == target.minute;
    return GestureDetector(
      onTap: () => setState(() => _customDayTimes[weekday] = target),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF10B981) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? const Color(0xFF10B981) : const Color(0xFF334155)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.grey)),
      ),
    );
  }
}