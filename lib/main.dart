import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'engine/compute_engine.dart';
import 'engine/library_stats.dart';
import 'engine/compound_edits.dart';
import 'ui/widgets/protolog_shell.dart';
import 'ui/widgets/load_hero.dart';
import 'ui/widgets/pk_chart_card.dart';
import 'ui/widgets/swimlane_card.dart';
import 'ui/widgets/bloodwork_card.dart';
import 'ui/widgets/bloodwork_editor_dialog.dart';
import 'ui/views/bloodwork_page.dart';
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
import 'services/app_store.dart';
import 'services/backup_io.dart';
import 'services/reminder_notifications.dart';

// --- Entry Point ---
void main() {
  // Bundled-font OFL notices (Inter, Fraunces, JetBrains Mono) — surfaced in
  // the standard Flutter licenses screen, mirroring what google_fonts did
  // before the fonts were vendored in (F4).
  LicenseRegistry.addLicense(() async* {
    for (final path in const [
      'assets/fonts/OFL-Inter.txt',
      'assets/fonts/OFL-Fraunces.txt',
      'assets/fonts/OFL-JetBrainsMono.txt',
    ]) {
      yield LicenseEntryWithLineBreaks(
          const ['bundled_fonts'], await rootBundle.loadString(path));
    }
  });
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
        // Fill every slot pickers reach for — ColorScheme.dark() defaults
        // secondary/containers to Material teal (#03DAC6), which leaked an
        // "emerald" look into date/time pickers.
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.accent,
          onPrimary: AppTheme.bg,
          secondary: AppTheme.accent,
          onSecondary: AppTheme.bg,
          primaryContainer: AppTheme.accentDeep,
          onPrimaryContainer: AppTheme.fg,
          secondaryContainer: AppTheme.surface2,
          onSecondaryContainer: AppTheme.fg,
          surface: AppTheme.surface,
          onSurface: AppTheme.fg,
          onSurfaceVariant: AppTheme.fgMute,
          outline: AppTheme.border,
        ),
        datePickerTheme: const DatePickerThemeData(
          backgroundColor: AppTheme.surface2,
          headerBackgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        timePickerTheme: const TimePickerThemeData(
          backgroundColor: AppTheme.surface2,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: AppTheme.border, width: 1),
          ),
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
  const MainScreen({super.key, this.store, this.notificationBackend});

  /// Test seams: default to SharedPreferences and flutter_local_notifications.
  final AppStore? store;
  final NotificationBackend? notificationBackend;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

/// Owns all app state and routing. Persistence lives in [AppStore],
/// notification plumbing in [ReminderNotificationService], backup file I/O
/// in [BackupIO]; every state change goes through [_mutate].
class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  List<Injection> injections = [];
  List<CompoundDefinition> userCompounds = [];
  List<Reminder> reminders = [];
  List<BloodworkEntry> bloodwork = [];
  late GraphSettings settings;
  Future<ComputedGraphData>? _graphDataFuture;
  bool _loading = true;
  DateTime _calendarSelectedDay = DateTime.now();

  late final AppStore _store = widget.store ?? AppStore();
  late final BackupIO _backup = BackupIO(_store);
  late final ReminderNotificationService _notifs = ReminderNotificationService(
    backend: widget.notificationBackend ?? LocalNotificationsBackend(),
    injections: () => injections,
    onScheduleError: (e) =>
        _snack('Failed to schedule notification: $e', color: AppTheme.warn),
  );

  // Set when a notification tap arrives before _loadData has finished
  // (cold start); processed at the end of _loadData.
  String? _pendingNotificationPayload;
  String? _pendingNotificationAction;

  @override
  void initState() {
    super.initState();
    settings = const GraphSettings(normalized: false, cumulative: false, showPeptides: true, timeRange: 'standard');
    _bootstrap();
  }

  // Notification init and data load are independent, so a plugin failure
  // (or hang) can never keep the app on the spinner (A7). Rescheduling still
  // happens with the plugin initialized and tz.local set: the service queues
  // every job behind init.
  Future<void> _bootstrap() async {
    _notifs.init(onTap: (payload, actionId) => _handleNotificationTap(payload, actionId: actionId));
    await _loadData();
    _notifs.rescheduleAll(reminders);
    _notifs.idle.then((_) {
      if (!_notifs.ready) {
        _snack("Notifications couldn't start — reminders won't fire this session",
            color: AppTheme.warn);
      }
    });
  }

  /// Tolerant load (A7, see AppStore.load): the spinner always clears, and
  /// whatever couldn't be read was set aside before anything could save
  /// over it; the user is told.
  Future<void> _loadData() async {
    final res = await _store.load();
    if (!mounted) return;
    setState(() {
      injections = res.injections;
      userCompounds = res.compounds;
      reminders = res.reminders;
      bloodwork = res.bloodwork;
      _loading = false;
    });
    _refreshGraph();

    final problem = res.problem;
    if (problem != null) {
      _snack(problem, color: AppTheme.warn, duration: const Duration(seconds: 10));
    }

    if (_pendingNotificationPayload != null) {
      final p = _pendingNotificationPayload;
      final a = _pendingNotificationAction;
      _pendingNotificationPayload = null;
      _pendingNotificationAction = null;
      _handleNotificationTap(p, actionId: a);
    }
  }

  void _handleNotificationTap(String? payload, {String? actionId}) {
    if (payload == null || payload.isEmpty) return;
    if (_loading) {
      _pendingNotificationPayload = payload;
      _pendingNotificationAction = actionId;
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
    if (actionId == 'skip') {
      // Skip the occurrence this notification announced, not the next one.
      _skipReminder(match, fromNotification: true);
      _snack('Skipped ${match.compoundBase} — rescheduled', color: AppTheme.surface2);
      return;
    }
    // Body tap or the "Log now" action: open the wizard prefilled.
    final def = _compoundForReminder(match);
    if (def != null) _openAddInjectionWizard(prefill: def);
  }

  // --- State changes ---

  /// The one way app state changes: applies [change] in setState (and, with
  /// [graph], recomputes the PK chart), then saves the named collections.
  /// Saves are awaited and a failed one shows a snackbar instead of failing
  /// silently. Completes with false if any save failed.
  Future<bool> _mutate(
    VoidCallback change, {
    bool injections = false,
    bool compounds = false,
    bool reminders = false,
    bool bloodwork = false,
    bool graph = false,
  }) async {
    setState(() {
      change();
      if (graph) _graphDataFuture = _computeGraph();
    });
    // Each save encodes its collection synchronously, so this persists the
    // state as of this change even if another one lands meanwhile.
    final saves = [
      if (injections) _store.saveInjections(this.injections),
      if (compounds) _store.saveCompounds(userCompounds),
      if (reminders) _store.saveReminders(this.reminders),
      if (bloodwork) _store.saveBloodwork(this.bloodwork),
    ];
    final ok = (await Future.wait(saves)).every((saved) => saved);
    if (!ok) _reportSaveFailure();
    return ok;
  }

  void _reportSaveFailure() => _snack(
        "Couldn't save your latest change — it may be lost when the app closes.",
        color: AppTheme.warn,
        duration: const Duration(seconds: 10),
      );

  Future<ComputedGraphData> _computeGraph() =>
      compute(calculateGraphData, IsolateInput(injections, settings));

  void _refreshGraph() {
    setState(() {
      _graphDataFuture = _computeGraph();
    });
  }

  /// Lab Sheet-styled snackbar. `color` is the background; `dark` switches the
  /// text to bg-on-light for warm/light backgrounds.
  void _snack(
    String message, {
    Color color = AppTheme.surface2,
    bool dark = false,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        message,
        style: AppTheme.sans(size: 12, color: dark ? AppTheme.bg : AppTheme.fg),
      ),
      backgroundColor: color,
      duration: duration,
    ));
  }

  /// Lab Sheet confirm dialog; true only if the user picked [confirm].
  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirm,
    String cancel = 'Cancel',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: Text(title,
            style: AppTheme.sans(size: 14, weight: FontWeight.w600, color: AppTheme.fg)),
        content: Text(body,
            style: AppTheme.sans(size: 12, color: AppTheme.fgMute, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancel, style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirm,
                style: AppTheme.sans(size: 12, weight: FontWeight.w600, color: AppTheme.accent)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Replaces the item with [item]'s id, or appends it.
  static void _upsert<T>(List<T> list, T item, String Function(T) idOf) {
    final i = list.indexWhere((x) => idOf(x) == idOf(item));
    if (i >= 0) {
      list[i] = item;
    } else {
      list.add(item);
    }
  }

  // Injections

  Future<void> _addInjection(Injection inj, {bool advanceReminder = false}) async {
    // Matching reminders move past the dose (never back: A4).
    final advanced = advanceReminder
        ? remindersAdvancedByDose(reminders,
            base: inj.snapshot.base, ester: inj.snapshot.ester, takenAt: inj.date)
        : const <int, Reminder>{};
    final saved = _mutate(() {
      injections.add(inj);
      advanced.forEach((i, r) => reminders[i] = r);
    }, injections: true, reminders: advanced.isNotEmpty, graph: true);
    for (final r in advanced.values) {
      _notifs.reschedule(r);
    }
    await saved;
  }

  void _updateInjection(Injection updated) => _mutate(() {
        final i = injections.indexWhere((inj) => inj.id == updated.id);
        if (i >= 0) injections[i] = updated;
      }, injections: true, graph: true);

  void _deleteInjection(String id) =>
      _mutate(() => injections.removeWhere((i) => i.id == id), injections: true, graph: true);

  void _updateInjectionNotes(String id, String? notes) => _mutate(() {
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
      }, injections: true);

  // Compounds

  void _addUserCompound(CompoundDefinition comp) =>
      _mutate(() => _upsert(userCompounds, comp, (c) => c.id), compounds: true);

  void _deleteUserCompound(String id) =>
      _mutate(() => userCompounds.removeWhere((c) => c.id == id), compounds: true);

  // A first-time edit of a built-in adds a shadowing override.
  void _updateUserCompound(CompoundDefinition updated) =>
      _mutate(() => _upsert(userCompounds, updated, (c) => c.id), compounds: true, graph: true);

  // Reminders

  void _upsertReminder(Reminder r) {
    _mutate(() => _upsert(reminders, r, (x) => x.id), reminders: true);
    _notifs.reschedule(r);
  }

  /// Swaps in [updated] (matched by id) and reschedules it.
  void _replaceReminder(Reminder updated) {
    _mutate(() {
      final i = reminders.indexWhere((x) => x.id == updated.id);
      if (i >= 0) reminders[i] = updated;
    }, reminders: true);
    _notifs.reschedule(updated);
  }

  void _deleteReminder(Reminder r) {
    _notifs.cancel(r);
    _mutate(() => reminders.removeWhere((x) => x.id == r.id), reminders: true);
  }

  void _toggleReminderEnabled(Reminder r) => _replaceReminder(r.copyWith(enabled: !r.enabled));

  void _skipReminder(Reminder r, {bool fromNotification = false}) {
    final now = DateTime.now();
    final updated = fromNotification
        ? advanceAfterNotificationSkip(r, now: now)
        : advanceAfterSkip(r, now: now);
    if (!identical(updated, r)) _replaceReminder(updated);
  }

  // Bloodwork

  // Common markers with their usual units — tapping a chip in the editor
  // prefills both fields. Free-text stays possible for anything else.
  static const _markerSuggestions = <String, String>{
    'Total T': 'nmol/L',
    'Free T': 'pmol/L',
    'E2': 'pmol/L',
    'SHBG': 'nmol/L',
    'Prolactin': 'mIU/L',
    'HDL': 'mmol/L',
    'LDL': 'mmol/L',
    'ALT': 'U/L',
    'AST': 'U/L',
    'Hct': '%',
  };

  void _openBloodworkPage({String? initialMarker}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BloodworkPage(
        initialEntries: bloodwork,
        initialMarker: initialMarker,
        markerSuggestions: _markerSuggestions,
        injections: injections,
        colorResolver: _buildColorResolver(),
        onChanged: (list) => _mutate(() => bloodwork = List.of(list), bloodwork: true),
      ),
    ));
  }

  Future<void> _openBloodworkEditor({BloodworkEntry? editing}) async {
    final result = await showDialog<BloodworkDialogResult>(
      context: context,
      builder: (_) => BloodworkEditorDialog(
        editing: editing,
        markerSuggestions: _markerSuggestions,
      ),
    );
    if (result == null) return;
    _mutate(() {
      if (result.delete) {
        bloodwork.removeWhere((b) => b.id == editing!.id);
      } else {
        _upsert(bloodwork, result.entry!, (b) => b.id);
      }
    }, bloodwork: true);
  }

  // --- Import / export ---

  AppCollections get _collections => (
        injections: injections,
        compounds: userCompounds,
        reminders: reminders,
        bloodwork: bloodwork,
      );

  /// F1: full-state backup through the share sheet.
  Future<void> _exportBackupFile() async {
    try {
      await _backup.share(_collections);
    } catch (e) {
      _snack('Backup failed: $e', color: AppTheme.warn);
    }
  }

  /// F1 restore: additive merge after a confirmation that shows what changes.
  Future<void> _importBackupFile() async {
    try {
      final text = await _backup.pickFile();
      if (text == null) return;
      final preview = await _backup.preview(text, _collections);
      if (preview == null) {
        _snack('Not a valid ProtoLog backup file', color: AppTheme.warn);
        return;
      }
      if (preview.isNoOp) {
        _snack(preview.nothingToMergeMessage, color: AppTheme.warm, dark: true);
        return;
      }
      if (!mounted) return;
      if (!await _confirm(title: 'Merge backup?', body: preview.summary, confirm: 'Merge')) return;

      final m = preview.merged;
      final saved = _mutate(() {
        injections = m.injections;
        userCompounds = m.compounds;
        reminders = m.reminders;
        bloodwork = m.bloodwork;
      }, injections: true, compounds: true, reminders: true, bloodwork: true, graph: true);
      _notifs.rescheduleAll(reminders);
      if (!await saved) return; // _mutate reported it
      if (await _backup.commitSites(preview)) {
        _snack('Backup merged', color: AppTheme.accentDeep);
      } else {
        _reportSaveFailure();
      }
    } catch (e) {
      _snack('Restore failed: $e', color: AppTheme.warn);
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
    if (!await _confirm(
        title: 'Import data',
        body: 'Found ${parsed.length} new entries to import. Proceed?',
        confirm: 'Import')) {
      return;
    }

    if (await _mutate(() => injections.addAll(parsed), injections: true, graph: true)) {
      _snack('Imported ${parsed.length} entries', color: AppTheme.accentDeep);
    }
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
          onEditInjection: (inj) => _openAddInjectionWizard(editing: inj),
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
          onBackup: _exportBackupFile,
          onRestore: _importBackupFile,
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
        onDelete: editing != null ? () => _deleteReminder(editing) : null,
      ),
    ));
  }

  void _openAddInjectionWizard({
    CompoundDefinition? prefill,
    DateTime? prefillDate,
    Injection? editing,
  }) {
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
            editingInjection: editing,
            onEdit: _updateInjection,
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
    final apply = await _confirm(
      title: 'Apply to past logs?',
      body: 'Update $n past $logWord of ${displayName(c)} to the new '
          'pharmacokinetics? Historical curves and stats will recompute. '
          'This rewrites logged history.',
      confirm: 'Update $n $logWord',
      cancel: 'Keep history as-is',
    );
    if (apply) {
      _mutate(() {
        injections = rewriteSnapshots(
          injections: injections,
          base: c.base,
          ester: c.ester,
          halfLife: c.halfLife,
          timeToPeak: c.timeToPeak,
          ratio: c.ratio,
          graphType: c.graphType,
        );
      }, injections: true, graph: true);
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
    final load = activeInjectableLoad(injections: injections, now: DateTime.now());
    final totalActive = load.fold<double>(0.0, (s, e) => s + e.activeMg);
    final breakdown = (load.toList()
          ..sort((a, b) => b.activeMg.compareTo(a.activeMg)))
        .map((e) => LoadHeroRow(
              label: e.base,
              valueMg: e.activeMg,
              shareOfTotal: totalActive > 0 ? e.activeMg / totalActive : 0,
              color: colorOf(e.base),
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
                onSettingsChanged: (s) {
                  setState(() => settings = s);
                  // Cumulative adds a curve engine-side; normalized is
                  // paint-only but the recompute is cheap and keeps one path.
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
          const SizedBox(height: 18),
          BloodworkCard(
            entries: bloodwork,
            onCreate: () => _openBloodworkEditor(),
            onTap: (e) => _openBloodworkPage(initialMarker: e.marker),
          ),
        ],
      ),
    );
  }
}
