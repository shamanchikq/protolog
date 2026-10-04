import 'dart:io';
import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/backup.dart';
import '../models.dart';
import 'app_store.dart';
import 'custom_sites_store.dart';

/// The app state a backup is made from / merged into.
typedef AppCollections = ({
  List<Injection> injections,
  List<CompoundDefinition> compounds,
  List<Reminder> reminders,
  List<BloodworkEntry> bloodwork,
});

/// A decoded backup merged (in memory) with the current state, waiting for
/// the user's confirmation. Nothing has been written yet.
class RestorePreview {
  final BackupMergeResult merged;

  /// Entries in the file that were malformed or invalid and are left out (A7).
  final int skipped;

  const RestorePreview(this.merged, {this.skipped = 0});

  /// The backup adds or changes nothing.
  bool get isNoOp => merged.totalChanges == 0;

  String? get _invalid => skipped == 0
      ? null
      : '$skipped invalid ${skipped == 1 ? 'entry' : 'entries'} in the file';

  /// Snackbar text for a no-op restore.
  String get nothingToMergeMessage => _invalid == null
      ? 'Backup matches current data — nothing to merge'
      : 'Nothing new to merge — $_invalid ${skipped == 1 ? 'was' : 'were'} skipped';

  /// Body of the "Merge backup?" confirmation. Says plainly that records
  /// this device already has are overwritten by the backup's copy (B23).
  String get summary {
    final m = merged;
    final adds = _listing([
      _count(m.newInjections, 'log'),
      _count(m.newCompounds, 'compound'),
      _count(m.newReminders, 'reminder'),
      _count(m.newBloodwork, 'lab result'),
      _count(m.newSites, 'injection site'),
    ]);
    final replaces = _listing([
      _count(m.replacedCompounds, 'compound'),
      _count(m.replacedReminders, 'reminder'),
      _count(m.replacedBloodwork, 'lab result'),
    ]);
    return [
      if (adds != null) 'Adds $adds.',
      if (replaces != null)
        "Replaces the matching $replaces on this device with the backup's copy.",
      if (_invalid != null) '$_invalid will be skipped.',
      'Nothing else changes.',
    ].join(' ');
  }

  static String? _count(int n, String noun) => n == 0 ? null : '$n $noun${n == 1 ? '' : 's'}';

  /// "a", "a and b", "a, b and c" — null when there's nothing to list.
  static String? _listing(List<String?> parts) {
    final p = parts.whereType<String>().toList();
    if (p.isEmpty) return null;
    if (p.length == 1) return p.single;
    return '${p.sublist(0, p.length - 1).join(', ')} and ${p.last}';
  }
}

/// F1 backup file I/O: share-sheet export, picker import, and the merge
/// with stored custom sites. Dialogs stay with the caller.
class BackupIO {
  BackupIO(
    this._store, {
    DateTime Function()? clock,
    Future<Directory> Function()? tempDir,
    Future<void> Function(ShareParams params)? shareSheet,
  })  : _clock = clock ?? DateTime.now,
        _tempDir = tempDir ?? getTemporaryDirectory,
        _shareSheet = shareSheet ?? ((p) => SharePlus.instance.share(p));

  final AppStore _store;
  final DateTime Function() _clock;
  final Future<Directory> Function() _tempDir;
  final Future<void> Function(ShareParams params) _shareSheet;

  /// Full-state backup — every collection, the custom sites and any data set
  /// aside at load — as one versioned JSON file pushed through the share
  /// sheet. [origin] (global coordinates) anchors the sheet's popover on
  /// iPad, where it's required (D4). The plaintext file is deleted from the
  /// temp dir once the sheet returns (D8; share_plus hands targets its own
  /// copy). Throws on failure.
  Future<void> share(AppCollections current, {Rect? origin}) async {
    final payload = await encode(current);
    final dir = await _tempDir();
    final file = File('${dir.path}${Platform.pathSeparator}${backupFileName(_clock())}');
    await file.writeAsString(payload);
    try {
      await _shareSheet(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'ProtoLog backup',
        sharePositionOrigin: origin,
      ));
    } finally {
      try {
        await file.delete();
      } catch (_) {
        // Best effort: the OS clears the temp dir eventually.
      }
    }
  }

  /// The backup file's contents for [current].
  Future<String> encode(AppCollections current) async {
    final sites = await _store.readCustomSites();
    return encodeBackup(
      injections: current.injections,
      compounds: current.compounds,
      reminders: current.reminders,
      customSitesIM: sites.im,
      customSitesSubQ: sites.subQ,
      bloodwork: current.bloodwork,
      unreadable: await _store.setAsideData(),
    );
  }

  /// Opens the system file picker; the chosen file's text, or null if the
  /// user cancelled. Throws if the file can't be read.
  Future<String?> pickFile() async {
    const group = XTypeGroup(
      label: 'ProtoLog backup',
      extensions: ['json'],
      // Broad mime list: share targets sometimes re-tag JSON attachments.
      mimeTypes: ['application/json', 'application/octet-stream', 'text/plain'],
      // iOS filters by UTI and throws without one (D4).
      uniformTypeIdentifiers: ['public.json', 'public.plain-text'],
    );
    final picked = await openFile(acceptedTypeGroups: const [group]);
    return picked?.readAsString();
  }

  /// Decodes [text] and merges it with [current] plus the stored custom
  /// sites. Null if it isn't a ProtoLog backup.
  Future<RestorePreview?> preview(String text, AppCollections current) async {
    final data = decodeBackup(text);
    if (data == null) return null;
    final sites = await _store.readCustomSites();
    final merged = mergeBackup(
      injections: current.injections,
      compounds: current.compounds,
      reminders: current.reminders,
      customSitesIM: sites.im,
      customSitesSubQ: sites.subQ,
      bloodwork: current.bloodwork,
      incoming: data,
    );
    return RestorePreview(merged, skipped: data.skipped);
  }

  /// Writes the merged custom sites (the collections are the caller's
  /// state and saved with it). False on failure.
  Future<bool> commitSites(RestorePreview p) =>
      _store.writeCustomSites(CustomSites(im: p.merged.customSitesIM, subQ: p.merged.customSitesSubQ));
}
