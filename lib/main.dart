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
import 'engine/compute_engine.dart';
import 'engine/library_stats.dart';
import 'engine/compound_edits.dart';
import 'ui/widgets/protolog_shell.dart';
import 'ui/widgets/load_hero.dart';
import 'ui/widgets/pk_chart_card.dart';
import 'ui/widgets/swimlane_card.dart';
import 'ui/theme.dart';
import 'engine/dashboard_stats.dart';
import 'ui/views/add_injection_wizard.dart';
import 'ui/views/calendar_page.dart';
import 'ui/views/library_page.dart';
import 'ui/views/compound_detail_page.dart';
import 'ui/views/compound_editor_page.dart';
import 'ui/views/reminders_page.dart';
import 'ui/views/reminder_editor_page.dart';
import 'engine/reminder_schedule.dart';
import 'engine/log_serde.dart';

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
        scaffoldBackgroundColor: AppTheme.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.accent,
          surface: AppTheme.surface,
          onSurface: AppTheme.fg,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: AppTheme.surface2,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        cardTheme: const CardThemeData(
          color: AppTheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: AppTheme.border, width: 1),
          ),
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

  // Notifications
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // Interval reminders pre-schedule this many one-shot notifications so they
  // keep firing even when the app isn't opened for several cycles.
  static const int _kIntervalOccurrences = 10;

  // Cancellation always sweeps this many ids per reminder, regardless of the
  // reminder's *current* mode/slot count — a mode switch must not orphan ids
  // scheduled under the previous shape. (Custom mode realistically uses at
  // most 7 slots; interval mode uses _kIntervalOccurrences.)
  static const int _kMaxNotificationIdsPerReminder = 64;

  // Set when a notification tap arrives before _loadData has finished
  // (cold start); processed at the end of _loadData.
  String? _pendingNotificationPayload;

  @override
  void initState() {
    super.initState();
    settings = const GraphSettings(normalized: false, cumulative: false, showPeptides: true, timeRange: 'standard');
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
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) =>
          _handleNotificationTap(resp.payload),
    );

    // App launched by tapping a notification while terminated.
    final launch = await _notificationsPlugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _handleNotificationTap(launch!.notificationResponse?.payload);
    }

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

  void _handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (_loading) {
      _pendingNotificationPayload = payload;
      return;
    }
    Reminder? match;
    for (final r in reminders) {
      if (r.id == payload) {
        match = r;
        break;
      }
    }
    if (match == null) return;
    final def = _compoundForReminder(match);
    if (def != null) _openAddInjectionWizard(prefill: def);
  }

  /// Lab Sheet-styled snackbar. `color` is the background; `dark` switches the
  /// text to bg-on-light for warm/light backgrounds.
  void _snack(String message, {Color color = AppTheme.surface2, bool dark = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        message,
        style: AppTheme.sans(size: 12, color: dark ? AppTheme.bg : AppTheme.fg),
      ),
      backgroundColor: color,
    ));
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
    _rescheduleAllReminders(); // fire-and-forget

    setState(() => _loading = false);
    _refreshGraph();

    if (_pendingNotificationPayload != null) {
      final p = _pendingNotificationPayload;
      _pendingNotificationPayload = null;
      _handleNotificationTap(p);
    }
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

  Future<void> _rescheduleAllReminders() async {
    for (final r in reminders) {
      if (r.enabled) {
        await _cancelReminder(r);
        await _scheduleReminder(r);
      }
    }
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
            payload: reminder.id,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      } else {
        // Interval mode: schedule the next few one-shots (fractional spacing
        // drifts the time-of-day, so no repeating matchDateTimeComponents).
        var cursor = nextOccurrence(reminder, now);
        for (int i = 0; i < _kIntervalOccurrences; i++) {
          final scheduledTz = tz.TZDateTime.from(cursor, tz.local);
          await _notificationsPlugin.zonedSchedule(
            reminder.id.hashCode + i,
            'ProtoLog Reminder',
            'Time to administer $compoundLabel',
            scheduledTz,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: reminder.id,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: null,
          );
          cursor = cursor.add(Duration(milliseconds: (reminder.intervalDays * 86400000).round()));
        }
      }
    } catch (e) {
      _snack('Failed to schedule notification: $e', color: AppTheme.warn);
    }
  }

  Future<void> _cancelReminder(Reminder reminder) async {
    for (int i = 0; i < _kMaxNotificationIdsPerReminder; i++) {
      await _notificationsPlugin.cancel(reminder.id.hashCode + i);
    }
  }

  void _exportToMarkdown() {
    Clipboard.setData(ClipboardData(text: injectionsToMarkdown(injections)));
    _snack('Log exported to clipboard as Markdown', color: AppTheme.accentDeep);
  }

  Future<void> _importFromMarkdown() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null || data.text!.isEmpty) {
      _snack('Clipboard is empty', color: AppTheme.warn);
      return;
    }

    final parsed = parseMarkdownLog(
      data.text!,
      userCompounds: userCompounds,
      existing: injections,
    );

    if (parsed.isEmpty) {
      _snack('No new entries found in clipboard', color: AppTheme.warm, dark: true);
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: Text('Import data',
            style: AppTheme.sans(size: 14, weight: FontWeight.w600, color: AppTheme.fg)),
        content: Text(
          'Found ${parsed.length} new entries to import. Proceed?',
          style: AppTheme.sans(size: 12, color: AppTheme.fgMute, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Import',
                style: AppTheme.sans(size: 12, weight: FontWeight.w600, color: AppTheme.accent)),
          ),
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

  Future<void> _addInjection(Injection inj, {bool advanceReminder = false}) async {
    setState(() {
      injections.add(inj);
    });
    _saveData();
    _refreshGraph();

    if (advanceReminder) {
      for (int i = 0; i < reminders.length; i++) {
        final r = reminders[i];
        if (r.enabled && r.compoundBase == inj.snapshot.base && r.compoundEster == inj.snapshot.ester) {
          await _cancelReminder(r);
          final updated = advanceAfterDose(r, inj.date);
          reminders[i] = updated;
          await _scheduleReminder(updated);
        }
      }
      _saveReminders();
    }
  }

  void _deleteInjection(String id) {
    setState(() {
      injections.removeWhere((i) => i.id == id);
    });
    _saveData();
    _refreshGraph();
  }

  void _updateInjectionNotes(String id, String? notes) {
    setState(() {
      final i = injections.indexWhere((inj) => inj.id == id);
      if (i < 0) return;
      final cur = injections[i];
      injections[i] = Injection(
        id: cur.id,
        compoundId: cur.compoundId,
        date: cur.date,
        dosage: cur.dosage,
        snapshot: cur.snapshot,
        site: cur.site,
        notes: notes,
      );
    });
    _saveData();
  }

  void _addUserCompound(CompoundDefinition comp) {
    setState(() {
      final i = userCompounds.indexWhere((c) => c.id == comp.id);
      if (i >= 0) {
        userCompounds[i] = comp;
      } else {
        userCompounds.add(comp);
      }
    });
    _saveData();
  }

  void _deleteUserCompound(String id) {
    setState(() {
      userCompounds.removeWhere((c) => c.id == id);
    });
    _saveData();
  }

  void _updateUserCompound(CompoundDefinition updated) {
    setState(() {
      final idx = userCompounds.indexWhere((c) => c.id == updated.id);
      if (idx == -1) {
        // First-time override of a built-in: shadow it in userCompounds.
        userCompounds.add(updated);
      } else {
        userCompounds[idx] = updated;
      }
    });
    _saveData();
    _refreshGraph();
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

      // Read graphType/halfLife from the frozen snapshot so library edits never
      // silently rewrite history. Retroactive changes go through the explicit
      // "apply to past logs" flow (rewriteSnapshots).
      final graphType = inj.snapshot.graphType;
      final double snapHl = inj.snapshot.halfLife;
      final double halfLife = snapHl > 0.05 ? snapHl : 1.0;

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

      final graphType = inj.snapshot.graphType;

      final diffMs = now.difference(inj.date).inMilliseconds;
      final ago = Duration(milliseconds: diffMs);
      final agoString = ago.inDays > 0 ? "${ago.inDays}d ago" : "${ago.inHours}h ago";

      // Skip if latest injection is past the compound's relevance window.
      final statHl = inj.snapshot.halfLife > 0.05 ? inj.snapshot.halfLife : 1.0;
      if (diffMs > statRelevanceWindowDays(statHl) * 86400000) continue;

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

    final tab = ShellTab.values[_currentIndex.clamp(0, ShellTab.values.length - 1)];

    Widget content;
    switch (tab) {
      case ShellTab.today:
        content = _buildDashboard();
        break;
      case ShellTab.calendar:
        content = CalendarPage(
          injections: injections,
          onDeleteInjection: _deleteInjection,
          onUpdateNotes: _updateInjectionNotes,
          onDaySelected: (d) => _calendarSelectedDay = d,
          colorResolver: _buildColorResolver(),
        );
        break;
      case ShellTab.library:
        content = LibraryPage(
          userCompounds: userCompounds,
          injections: injections,
          onExport: _exportToMarkdown,
          onImport: _importFromMarkdown,
          onOpenDetail: _openCompoundDetail,
          onOpenCreate: () => _openCompoundEditor(),
        );
        break;
      case ShellTab.reminders:
        content = RemindersPage(
          reminders: reminders,
          userCompounds: userCompounds,
          onEditReminder: (editing) => _openReminderEditor(editing: editing),
          onToggleEnabled: _toggleReminderEnabled,
          onLogNow: (r) {
            final def = _compoundForReminder(r);
            if (def != null) _openAddInjectionWizard(prefill: def);
          },
          onSkip: _skipReminder,
        );
        break;
    }

    VoidCallback? onFab;
    String? fabLabel;
    if (tab == ShellTab.today) {
      onFab = () => _openAddInjectionWizard();
      fabLabel = 'Log dose';
    } else if (tab == ShellTab.calendar) {
      onFab = () => _openAddInjectionWizard(prefillDate: _calendarSelectedDay);
      fabLabel = 'Log dose';
    } else if (tab == ShellTab.reminders) {
      onFab = () => _openReminderEditor();
      fabLabel = 'New reminder';
    }

    return ProtoLogShell(
      activeTab: tab,
      onTabChanged: (t) => setState(() => _currentIndex = ShellTab.values.indexOf(t)),
      onFabPressed: onFab,
      fabLabel: fabLabel,
      body: content,
    );
  }

  CompoundDefinition? _compoundForReminder(Reminder r) {
    for (final c in cataloguedCompounds(userCompounds: userCompounds)) {
      if (c.base == r.compoundBase && c.ester == r.compoundEster) return c;
    }
    return null;
  }

  void _openReminderEditor({Reminder? editing}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReminderEditorPage(
        editing: editing,
        userCompounds: userCompounds,
        now: DateTime.now(),
        onSave: _upsertReminder,
        onDelete: editing != null
            ? () {
                _cancelReminder(editing);
                setState(() => reminders.removeWhere((x) => x.id == editing.id));
                _saveReminders();
              }
            : null,
      ),
    ));
  }

  void _upsertReminder(Reminder r) {
    setState(() {
      final i = reminders.indexWhere((x) => x.id == r.id);
      if (i >= 0) {
        reminders[i] = r;
      } else {
        reminders.add(r);
      }
    });
    _saveReminders();
    _cancelReminder(r);
    if (r.enabled) _scheduleReminder(r);
  }

  void _toggleReminderEnabled(Reminder r) {
    final updated = r.copyWith(enabled: !r.enabled);
    setState(() {
      final i = reminders.indexWhere((x) => x.id == r.id);
      if (i >= 0) reminders[i] = updated;
    });
    _saveReminders();
    if (updated.enabled) {
      _scheduleReminder(updated);
    } else {
      _cancelReminder(updated);
    }
  }

  void _skipReminder(Reminder r) {
    final updated = advanceAfterSkip(r, now: DateTime.now());
    setState(() {
      final i = reminders.indexWhere((x) => x.id == r.id);
      if (i >= 0) reminders[i] = updated;
    });
    _saveReminders();
    _cancelReminder(updated);
    if (updated.enabled) _scheduleReminder(updated);
  }

  DateTime _calendarSelectedDay = DateTime.now();

  void _openAddInjectionWizard({CompoundDefinition? prefill, DateTime? prefillDate}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppTheme.bg,
        body: SafeArea(
          child: AddInjectionWizard(
            onAdd: (injection, advance) => _addInjection(injection, advanceReminder: advance),
            onCancel: () => Navigator.of(context).pop(),
            onSuccess: () => Navigator.of(context).pop(),
            userCompounds: userCompounds,
            addUserCompound: _addUserCompound,
            injections: injections,
            reminders: reminders,
            prefillCompound: prefill,
            prefillDate: prefillDate,
          ),
        ),
      ),
    ));
  }

  void _openCompoundDetail(CompoundDefinition compound) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CompoundDetailPage(
        compound: compound,
        injections: injections,
        onTabChanged: (t) =>
            setState(() => _currentIndex = ShellTab.values.indexOf(t)),
        openEditor: (comp) =>
            _openCompoundEditor(editing: comp, fromDetail: true),
        onDelete: () {
          _deleteUserCompound(compound.id);
          Navigator.of(context).pop(); // pops the detail
        },
        onLogInjection: (c) {
          Navigator.of(context).pop(); // close detail before pushing wizard
          _openAddInjectionWizard(prefill: c);
        },
      ),
    ));
  }

  /// Pushes the editor route. Returns the updated/created compound on save,
  /// or null on cancel/delete. When `fromDetail` is true, a delete also pops
  /// the detail route that sits underneath the editor. Delete is offered only
  /// for custom compounds — built-ins can be reset to default but not removed.
  Future<CompoundDefinition?> _openCompoundEditor({
    CompoundDefinition? editing,
    bool fromDetail = false,
  }) async {
    final result =
        await Navigator.of(context).push<CompoundDefinition>(MaterialPageRoute(
      builder: (_) => CompoundEditorPage(
        editing: editing,
        onTabChanged: (t) =>
            setState(() => _currentIndex = ShellTab.values.indexOf(t)),
        onCreate: _addUserCompound,
        onUpdate: _updateUserCompound,
        onDelete: (editing != null && editing.isCustom)
            ? () {
                _deleteUserCompound(editing.id);
                // The editor's delete handler pops the editor route (and the
                // detail underneath it if we came from there).
                Navigator.of(context).pop(); // pops the editor
                if (fromDetail) Navigator.of(context).pop(); // pops the detail
              }
            : null,
      ),
    ));

    // After an edit that changed curve-affecting params, offer to apply the new
    // pharmacokinetics to past logs of this compound.
    if (result != null &&
        editing != null &&
        mounted &&
        _curveParamsChanged(editing, result)) {
      final n = injectionCountFor(
        base: result.base, ester: result.ester, injections: injections,
      );
      if (n > 0) await _offerRetroactiveRewrite(result, n);
    }
    return result;
  }

  bool _curveParamsChanged(CompoundDefinition a, CompoundDefinition b) =>
      a.halfLife != b.halfLife ||
      a.timeToPeak != b.timeToPeak ||
      a.ratio != b.ratio ||
      a.graphType != b.graphType;

  /// Confirm dialog offering to rewrite past logs' snapshots to the new PK.
  Future<void> _offerRetroactiveRewrite(CompoundDefinition c, int n) async {
    final logWord = n == 1 ? 'log' : 'logs';
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: Text('Apply to past logs?',
            style: AppTheme.sans(size: 14, weight: FontWeight.w600, color: AppTheme.fg)),
        content: Text(
          'Update $n past $logWord of ${displayName(c)} to the new '
          'pharmacokinetics? Historical curves and stats will recompute. '
          'This rewrites logged history.',
          style: AppTheme.sans(size: 12, color: AppTheme.fgMute, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep history as-is',
                style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Update $n $logWord',
                style: AppTheme.sans(
                    size: 12, weight: FontWeight.w600, color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (apply == true) {
      setState(() {
        injections = rewriteSnapshots(
          injections: injections,
          base: c.base,
          ester: c.ester,
          halfLife: c.halfLife,
          timeToPeak: c.timeToPeak,
          ratio: c.ratio,
          graphType: c.graphType,
        );
      });
      _saveData();
      _refreshGraph();
    }
  }

  /// Builds a live base→color resolver from the *current* catalogue, so library
  /// color edits recolor every surface (graph, swimlanes, calendar, hero)
  /// immediately — including past logs. Precedence per base:
  ///   1. an explicit user color (custom, or a built-in the user recolored)
  ///   2. the static redesign palette (`AppTheme.compoundColor`)
  ///   3. the current catalogue color, else a neutral grey.
  /// Memoized per call so a paint loop over many markers stays O(1) per base.
  Color Function(String) _buildColorResolver() {
    final cache = <String, Color>{};
    return (base) => cache.putIfAbsent(base, () {
          final cand = colorCandidatesForBase(base, userCompounds: userCompounds);
          if (cand.userSet != null) return Color(cand.userSet!);
          return AppTheme.compoundColor(base) ?? Color(cand.any ?? 0xFF9AA0A8);
        });
  }

  Widget _buildDashboard() {
    final colorOf = _buildColorResolver();
    final activeStats = _getActiveStats();
    final injectableStats = activeStats
        .where((s) => s.type == CompoundType.steroid || s.type == CompoundType.oral)
        .toList();
    final totalActive = injectableStats.fold<double>(0.0, (s, x) => s + x.activeAmount);
    final breakdown = (injectableStats.toList()
          ..sort((a, b) => b.activeAmount.compareTo(a.activeAmount)))
        .map((s) => LoadHeroRow(
              label: s.name,
              valueMg: s.activeAmount,
              shareOfTotal: totalActive > 0 ? s.activeAmount / totalActive : 0,
              color: colorOf(s.name),
            ))
        .toList();
    final delta = deltaSteroidNowVsPrior7(injections: injections, now: DateTime.now());

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
            future: _graphDataFuture,
            builder: (context, snapshot) {
              return PKChartCard(
                graphData: snapshot.data,
                settings: settings,
                colorResolver: colorOf,
                onRangeChanged: (range) {
                  setState(() {
                    settings = GraphSettings(
                      normalized: settings.normalized,
                      cumulative: settings.cumulative,
                      showPeptides: settings.showPeptides,
                      timeRange: range,
                    );
                  });
                  _refreshGraph();
                },
              );
            },
          ),
          const SizedBox(height: 18),
          SwimlaneCard(
            injections: injections,
            now: DateTime.now(),
            colorResolver: colorOf,
          ),
        ],
      ),
    );
  }


}
