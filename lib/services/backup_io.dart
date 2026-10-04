import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/backup.dart';
import '../models.dart';
import 'app_store.dart';

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

  /// Body of the "Merge backup?" confirmation.
  String get summary => '${merged.newInjections} new logs, ${merged.changedCompounds} compound '
      'updates, ${merged.changedReminders} reminder updates, '
      '${merged.newBloodwork} lab results, ${merged.newSites} new sites. '
      '${_invalid == null ? '' : '$_invalid will be skipped. '}'
      'Existing data is never deleted.';
}

/// F1 backup file I/O: share-sheet export, picker import, and the merge
/// with stored custom sites. Dialogs stay with the caller.
class BackupIO {
  BackupIO(this._store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppStore _store;
  final DateTime Function() _clock;

  /// Full-state backup — every collection, the custom sites and any data set
  /// aside at load — as one versioned JSON file pushed through the share
  /// sheet. Throws on failure.
  Future<void> share(AppCollections current) async {
    final payload = await encode(current);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${backupFileName(_clock())}');
    await file.writeAsString(payload);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'ProtoLog backup',
    ));
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
      _store.writeCustomSites((im: p.merged.customSitesIM, subQ: p.merged.customSitesSubQ));
}
