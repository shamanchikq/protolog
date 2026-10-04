import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'engine/compute_engine.dart';
import 'engine/library_stats.dart';
import 'engine/compound_edits.dart';
import 'ui/widgets/protolog_shell.dart';
import 'ui/widgets/bloodwork_editor_dialog.dart';
import 'ui/views/bloodwork_page.dart';
import 'ui/views/dashboard_view.dart';
import 'ui/theme.dart';
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
      theme: AppTheme.materialTheme,
      home: const MainScreen(),
    );
  }
}

// --- Main Screen ---

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.store, this.notificationBackend, this.backup});

  /// Test seams: default to SharedPreferences, flutter_local_notifications
  /// and the platform share sheet / file picker.
  final AppStore? store;
  final NotificationBackend? notificationBackend;
  final BackupIO? backup;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

/// Owns all app state and routing. Persistence lives in [AppStore],
/// notification plumbing in [ReminderNotificationService], backup file I/O
/// in [BackupIO]; every state change goes through [_mutate].
class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
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
  late final BackupIO _backup = widget.backup ?? BackupIO(_store);
  late final ReminderNotificationService _notifs = ReminderNotificationService(
    backend: widget.notificationBackend ?? LocalNotificationsBackend(),
    injections: () => injections,
    onScheduleError: (e) =>
        _snack('Failed to schedule notification: $e', color: AppTheme.warn),
    onPermissionResult: (_) => _refreshNotificationsBlocked(),
  );

  /// The OS blocks this app's notifications (permission denied or switched
  /// off, B20). Refreshed after the launch permission request, on resume and
  /// after asking again; drives the Reminders tab's banner.
  bool _notificationsBlocked = false;
  bool _blockedNoticeShown = false;

  /// The display-color resolver for the current catalogue (E2), built on
  /// first use and dropped whenever [userCompounds] changes (_loadData,
  /// _mutate). Every build in between hands out the same function, so
  /// PKGraphPainter.shouldRepaint's identity check holds and the chart
  /// doesn't repaint on unrelated setStates.
  Color Function(String base)? _resolver;
  Color Function(String base) get _colorResolver => _resolver ??= _buildColorResolver();

  /// Bumped whenever [injections] changes — the list is mutated in place, so
  /// its identity can't say so. Keys the dashboard's swimlane memo (E2).
  int _injectionsRevision = 0;

  // Set when a notification tap arrives before _loadData has finished
  // (cold start); processed at the end of _loadData.
  String? _pendingNotificationPayload;
  String? _pendingNotificationAction;

  @override
  void initState() {
    super.initState();
    settings = const GraphSettings(normalized: false, cumulative: false, timeRange: 'standard');
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the background (N7/G4): "now" moved on, so rebuild every
  /// now-dependent view and recompute the chart, and reconcile reminders —
  /// re-extending interval one-shots and acked custom slots that fired
  /// meanwhile (cheap: only missing or changed notifications go out).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _loading) return;
    _refreshGraph();
    _notifs.reconcileAll(reminders);
    _refreshNotificationsBlocked(); // the user may have been to Settings
  }

  /// Re-reads whether notifications are blocked; the first time they are
  /// while a reminder is on, says so once per session (B20).
  Future<void> _refreshNotificationsBlocked() async {
    final enabled = await _notifs.notificationsEnabled();
    if (!mounted || enabled == null) return;
    final blocked = !enabled;
    if (blocked != _notificationsBlocked) setState(() => _notificationsBlocked = blocked);
    if (!blocked || _blockedNoticeShown || !reminders.any((r) => r.enabled)) return;
    _blockedNoticeShown = true;
    _snack("Notifications are off for ProtoLog — reminders won't alert you.",
        color: AppTheme.warn,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
            label: 'Allow', textColor: AppTheme.fg, onPressed: _requestNotificationPermission));
  }

  /// Asks the OS again (the snackbar's and the Reminders banner's button).
  /// Android 13+ stops showing the dialog after a second denial; then only
  /// system settings can turn notifications back on.
  Future<void> _requestNotificationPermission() async {
    await _notifs.requestPermission();
    await _refreshNotificationsBlocked();
  }

  // Notification init and data load are independent, so a plugin failure
  // (or hang) can never keep the app on the spinner (A7). The reconcile still
  // runs with the plugin initialized and tz.local set: the service queues
  // every job behind init.
  Future<void> _bootstrap() async {
    _notifs.init(onTap: (payload, actionId) => _handleNotificationTap(payload, actionId: actionId));
    await _loadData();
    _notifs.reconcileAll(reminders);
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
      _resolver = null;
      _injectionsRevision++;
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
    // Current payloads name the occurrence too; older ones are a bare id.
    final tap = ReminderPayload.parse(payload);
    if (tap == null) return;
    if (_loading) {
      _pendingNotificationPayload = payload;
      _pendingNotificationAction = actionId;
      return;
    }
    Reminder? match;
    for (final r in reminders) {
      if (r.id == tap.reminderId) {
        match = r;
        break;
      }
    }
    if (match == null) return;
    if (actionId == 'skip') {
      // Skip the occurrence this notification announced, not the next one;
      // a stale or re-delivered tap changes nothing (B14).
      final now = DateTime.now();
      final moved = !identical(
          advanceAfterNotificationSkip(match, occurrence: tap.occurrence, now: now), match);
      _updateReminder(match.id,
          (current) => advanceAfterNotificationSkip(current, occurrence: tap.occurrence, now: now));
      _snack('Skipped ${match.compoundBase}${moved ? ' — rescheduled' : ''}',
          color: AppTheme.surface2);
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
      if (compounds) _resolver = null; // recolors show everywhere (E2)
      if (injections) _injectionsRevision++;
      if (graph) _graphDataFuture = _computeGraph();
    });
    // Each save snapshots its collection synchronously (and writes land in
    // call order), so this persists the state as of this change even if
    // another one lands meanwhile.
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
    SnackBarAction? action,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        message,
        style: AppTheme.sans(size: 12, color: dark ? AppTheme.bg : AppTheme.fg),
      ),
      backgroundColor: color,
      duration: duration,
      action: action,
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
    _refreshRemindersFor([inj]); // the advanced ones included
    await saved;
  }

  void _updateInjection(Injection updated) {
    final i = injections.indexWhere((inj) => inj.id == updated.id);
    if (i < 0) return;
    final old = injections[i];
    _mutate(() => injections[i] = updated, injections: true, graph: true);
    _refreshRemindersFor([old, updated]);
  }

  void _deleteInjection(String id) {
    final gone = injections.where((i) => i.id == id).toList();
    _mutate(() => injections.removeWhere((i) => i.id == id), injections: true, graph: true);
    _refreshRemindersFor(gone);
  }

  /// Reminder notifications quote the latest matching log, so a change to
  /// a compound's logs re-plans its enabled reminders (B19) — only the
  /// notifications whose text actually changed go out again.
  void _refreshRemindersFor(Iterable<Injection> changed) {
    final keys = {for (final i in changed) compoundKey(i.snapshot.base, i.snapshot.ester)};
    for (final r in reminders) {
      if (r.enabled && keys.contains(compoundKey(r.compoundBase, r.compoundEster))) {
        _notifs.reschedule(r);
      }
    }
  }

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

  /// Deletes a custom compound together with the reminders it leaves
  /// without a compound (B11) — their notifications would keep firing and
  /// "Log now" could find nothing to log.
  void _deleteUserCompound(String id) {
    final i = userCompounds.indexWhere((c) => c.id == id);
    if (i < 0) return;
    final c = userCompounds[i];
    final orphaned = _remindersOrphanedBy(c);
    for (final r in orphaned) {
      _notifs.cancel(r);
    }
    final gone = {for (final r in orphaned) r.id};
    _mutate(() {
      userCompounds.removeWhere((x) => x.id == id);
      reminders.removeWhere((r) => gone.contains(r.id));
    }, compounds: true, reminders: gone.isNotEmpty);
    final n = gone.length;
    _snack('Deleted ${displayName(c)}${n == 0 ? '' : ' and its $n reminder${n == 1 ? '' : 's'}'}');
  }

  /// The reminders deleting [c] would orphan: same base+ester, unless the
  /// catalogue still has that compound without it (a custom that shadowed
  /// a built-in).
  List<Reminder> _remindersOrphanedBy(CompoundDefinition c) {
    final key = keyOf(c);
    final rest = userCompounds.where((x) => x.id != c.id).toList();
    if (cataloguedCompounds(userCompounds: rest).any((x) => keyOf(x) == key)) return const [];
    return [for (final r in reminders) if (compoundKey(r.compoundBase, r.compoundEster) == key) r];
  }

  // A first-time edit of a built-in adds a shadowing override.
  void _updateUserCompound(CompoundDefinition updated) =>
      _mutate(() => _upsert(userCompounds, updated, (c) => c.id), compounds: true, graph: true);

  // Reminders

  void _upsertReminder(Reminder r) {
    final i = reminders.indexWhere((x) => x.id == r.id);
    final previous = i >= 0 ? reminders[i] : null;
    _mutate(() => _upsert(reminders, r, (x) => x.id), reminders: true);
    _notifs.reschedule(r, previous: previous);
  }

  /// Applies [change] to the *current* reminder with [id], then saves and
  /// reschedules it. Rows, routes and notification taps hand over the
  /// Reminder they captured, which may be stale (B15: Pause right after
  /// "Log now" wrote the pre-dose anchor back) — so only its id is trusted.
  void _updateReminder(String id, Reminder Function(Reminder current) change) {
    final i = reminders.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final previous = reminders[i];
    final updated = change(previous);
    if (identical(updated, previous)) return;
    _mutate(() => reminders[i] = updated, reminders: true);
    _notifs.reschedule(updated, previous: previous);
  }

  void _deleteReminder(Reminder r) {
    final i = reminders.indexWhere((x) => x.id == r.id);
    _notifs.cancel(i >= 0 ? reminders[i] : r);
    _mutate(() => reminders.removeWhere((x) => x.id == r.id), reminders: true);
  }

  void _toggleReminderEnabled(Reminder r) =>
      _updateReminder(r.id, (current) => current.copyWith(enabled: !current.enabled));

  // In-app Skip. Notification Skip goes through _handleNotificationTap,
  // which knows the occurrence it announced (B14).
  void _skipReminder(Reminder r) {
    final now = DateTime.now();
    _updateReminder(r.id, (current) => advanceAfterSkip(current, now: now));
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
        colorResolver: _liveColor,
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

  /// F1: full-state backup through the share sheet. iPad needs an anchor
  /// for the share popover (D4): the button the backup was started from
  /// ([origin], from the Library's menu), else this whole screen.
  Future<void> _exportBackupFile({Rect? origin}) async {
    final box = context.findRenderObject() as RenderBox?;
    final anchor = origin ??
        (box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null);
    try {
      await _backup.share(_collections, origin: anchor);
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
      final before = {for (final r in reminders) r.id: r};
      final saved = _mutate(() {
        injections = m.injections;
        userCompounds = m.compounds;
        reminders = m.reminders;
        bloodwork = m.bloodwork;
      }, injections: true, compounds: true, reminders: true, bloodwork: true, graph: true);
      // Every reminder the backup added or replaced is rescheduled — one it
      // disabled has its notifications cancelled (B16); the reconcile then
      // refreshes the others' text for the new logs.
      for (final r in reminders) {
        if (m.changedReminderIds.contains(r.id)) _notifs.reschedule(r, previous: before[r.id]);
      }
      _notifs.reconcileAll(reminders);
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

    final saved = _mutate(() => injections.addAll(parsed), injections: true, graph: true);
    _refreshRemindersFor(parsed);
    if (await saved) {
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
        content = DashboardView(
          injections: injections,
          bloodwork: bloodwork,
          graphData: _graphDataFuture,
          settings: settings,
          colorResolver: _colorResolver,
          injectionsRevision: _injectionsRevision,
          now: DateTime.now(),
          onSettingsChanged: (s) {
            // Cumulative adds a curve engine-side; normalized is paint-only
            // but the recompute is cheap and keeps one path.
            setState(() => settings = s);
            _refreshGraph();
          },
          onAddBloodwork: () => _openBloodworkEditor(),
          onOpenBloodwork: (e) => _openBloodworkPage(initialMarker: e.marker),
        );
        break;
      case ShellTab.calendar:
        content = CalendarPage(
          injections: injections,
          onDeleteInjection: _deleteInjection,
          onUpdateNotes: _updateInjectionNotes,
          onEditInjection: (inj) => _openAddInjectionWizard(editing: inj),
          onDaySelected: (d) => _calendarSelectedDay = d,
          colorResolver: _colorResolver,
        );
        break;
      case ShellTab.library:
        content = LibraryPage(
          userCompounds: userCompounds,
          injections: injections,
          onExport: _exportToMarkdown,
          onImport: _importFromMarkdown,
          onBackup: (origin) => _exportBackupFile(origin: origin),
          onRestore: _importBackupFile,
          onOpenDetail: _openCompoundDetail,
          onOpenCreate: () => _openCompoundEditor(),
          colorResolver: _colorResolver,
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
          notificationsDisabled: _notificationsBlocked,
          onRequestNotificationPermission: _requestNotificationPermission,
          colorResolver: _colorResolver,
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
    final openedAt = DateTime.now();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReminderEditorPage(
        editing: editing,
        userCompounds: userCompounds,
        now: openedAt,
        // An edit applies to the reminder as it is when saved: one that
        // advanced while the editor was open (a dose logged, a Skip from
        // the shade) keeps its progress unless the schedule was changed.
        onSave: editing == null
            ? _upsertReminder
            : (saved) => _updateReminder(
                editing.id,
                (current) => applyReminderEdit(
                    opened: editing, saved: saved, current: current, openedAt: openedAt)),
        onDelete: editing != null ? () => _deleteReminder(editing) : null,
        colorResolver: _liveColor,
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
            colorResolver: _liveColor,
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
        linkedReminderCount: _remindersOrphanedBy(compound).length,
        colorResolver: _liveColor,
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
        userCompounds: userCompounds,
        // B10/B11: a custom in use keeps its identity; delete names what goes.
        logCount: editing == null
            ? 0
            : injectionCountFor(base: editing.base, ester: editing.ester, injections: injections),
        linkedReminderCount: editing == null ? 0 : _remindersOrphanedBy(editing).length,
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

  // Blends are modelled from their component esters, so their snapshot PK
  // never moves a curve — no rewrite offer (B9).
  bool _curveParamsChanged(CompoundDefinition a, CompoundDefinition b) =>
      blendComponentsFor(b.ester) == null &&
          (a.halfLife != b.halfLife ||
      a.timeToPeak != b.timeToPeak ||
      a.ratio != b.ratio ||
      a.graphType != b.graphType);

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
  /// Memoized per base so a paint loop over many markers stays O(1) per base;
  /// use it through [_colorResolver], which keeps one per catalogue state.
  Color Function(String) _buildColorResolver() {
    final cache = <String, Color>{};
    return (base) => cache.putIfAbsent(base, () {
          final cand = colorCandidatesForBase(base, userCompounds: userCompounds);
          if (cand.userSet != null) return Color(cand.userSet!);
          return AppTheme.compoundColor(base) ?? Color(cand.any ?? 0xFF9AA0A8);
        });
  }

  /// The resolver for routes pushed above this screen (detail, editors, the
  /// wizard, bloodwork). A route builds its page once, so it gets this
  /// method, which defers to the *current* resolver on every call — a
  /// recolor saved from the Compound Editor shows on the detail page it
  /// returns to.
  Color _liveColor(String base) => _colorResolver(base);
}
