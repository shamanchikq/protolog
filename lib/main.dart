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
import 'utils.dart';
import 'engine/compute_engine.dart';
import 'ui/widgets/pk_graph_painter.dart';
import 'ui/views/add_injection_wizard.dart';
import 'ui/views/compound_manager.dart';
import 'ui/views/reminders_page.dart';

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

    // Request POST_NOTIFICATIONS permission after the first frame,
    // so the Activity is fully ready to show the system dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission();
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    } catch (_) {
      // Permission request may fail on older Android versions; safe to ignore.
    }
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
    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to schedule notification: $e'), backgroundColor: Colors.red),
        );
      }
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
      def ??= lookupLibraryDef(base, ester);
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
      final libraryDef = lookupLibraryDef(base, inj.snapshot.ester);
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
        active = calculateActiveLevel(inj.dosage, diffDays, halfLife, inj.snapshot.timeToPeak, inj.snapshot.ratio, inj.snapshot.ester);
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

      final libraryDef = lookupLibraryDef(base, inj.snapshot.ester);
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
        if (ago.inDays > 0) {
          mainValue = "${ago.inDays}d ago";
        } else {
          mainValue = "${ago.inHours}h ago";
        }

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
              border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.3)),
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
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Color(stat.colorValue).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 16, color: Color(stat.colorValue))),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(stat.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(showTimeOnly ? capitalize(stat.type.name) : stat.statusText, style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
          }),
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
            leading: CircleAvatar(backgroundColor: Color(inj.snapshot.colorValue).withValues(alpha: 0.2), child: Icon(Icons.circle, color: Color(inj.snapshot.colorValue), size: 14)),
            title: Text(inj.snapshot.base, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: Text("${inj.snapshot.ester.isNotEmpty && inj.snapshot.ester != 'None' ? inj.snapshot.ester : ''} • ${formatDate(inj.date, 'MM/dd HH:mm')}"),
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
                      color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.transparent,
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
            leading: CircleAvatar(backgroundColor: Color(inj.snapshot.colorValue).withValues(alpha: 0.2), child: Icon(Icons.circle, color: Color(inj.snapshot.colorValue), size: 14)),
            title: Text(inj.snapshot.base, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: Text("${inj.snapshot.ester.isNotEmpty && inj.snapshot.ester != 'None' ? inj.snapshot.ester : ''} • ${formatDate(inj.date, 'MM/dd HH:mm')}"),
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
