import '../models.dart';
import 'compute_engine.dart';

/// Markdown table cells may not contain pipes or newlines; replace them so a
/// note like "a|b" can't break the column layout on re-import.
String _sanitizeCell(String s) =>
    s.replaceAll('|', '/').replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

/// Serializes the full log as a markdown table, most recent first.
/// Columns: Date, Compound, Ester, Dosage, Unit, Site, Notes.
String injectionsToMarkdown(List<Injection> injections) {
  final sorted = List<Injection>.from(injections)
    ..sort((a, b) => b.date.compareTo(a.date));
  final buf = StringBuffer();
  buf.writeln('| Date | Compound | Ester | Dosage | Unit | Site | Notes |');
  buf.writeln('|------|----------|-------|--------|------|------|-------|');
  for (final inj in sorted) {
    final d = inj.date;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final ester = inj.snapshot.ester == 'None' ? '' : inj.snapshot.ester;
    final unit = inj.snapshot.unit.toString().split('.').last;
    final site = _sanitizeCell(inj.site ?? '');
    final notes = _sanitizeCell(inj.notes ?? '');
    buf.writeln(
        '| $dateStr | ${inj.snapshot.base} | $ester | ${inj.dosage} | $unit | $site | $notes |');
  }
  return buf.toString();
}

/// Parses a markdown log table (legacy 5-column or current 7-column format)
/// into injections. Rows already present in [existing] or earlier in the
/// same paste (same base+ester, date within 1 minute, same dosage) are
/// skipped, as are rows whose compound can't be resolved from [userCompounds]
/// or the built-in library. The header row (and any other row whose date or
/// dosage doesn't parse) is skipped by validation, so a paste without the
/// header keeps its first row.
List<Injection> parseMarkdownLog(
  String text, {
  required List<CompoundDefinition> userCompounds,
  required List<Injection> existing,
}) {
  // Only a real delimiter row (every cell `---`, `:--`, `--:`, `:-:`) is
  // dropped — not any row that merely contains "---", like a note (B22).
  final dataLines = text
      .split('\n')
      .where((l) => l.trim().startsWith('|') && !_isDelimiterRow(l))
      .toList();

  // Ids already in the log: an import must never reuse one, or deleting the
  // new entry would delete the old one too (B21).
  final takenIds = {for (final i in existing) i.id};

  final parsed = <Injection>[];
  for (final line in dataLines) {
    // Split by | and keep empty cells to preserve column positions.
    final rawCells = line.split('|').map((c) => c.trim()).toList();
    // Remove first and last if empty (from leading/trailing |).
    if (rawCells.isNotEmpty && rawCells.first.isEmpty) rawCells.removeAt(0);
    if (rawCells.isNotEmpty && rawCells.last.isEmpty) rawCells.removeLast();
    if (rawCells.length < 5) continue;

    final dateStr = rawCells[0]; // dd/MM/yyyy HH:mm
    final base = rawCells[1];
    final ester = rawCells[2].isEmpty ? 'None' : rawCells[2];
    final dosage = double.tryParse(rawCells[3]);
    final unitStr = rawCells[4];
    final site = rawCells.length > 5 && rawCells[5].isNotEmpty ? rawCells[5] : null;
    final notes = rawCells.length > 6 && rawCells[6].isNotEmpty ? rawCells[6] : null;
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
    if (day == null || month == null || year == null || hour == null || minute == null) {
      continue;
    }
    final date = DateTime(year, month, day, hour, minute);

    // Look up compound definition: user compounds first, then built-ins.
    CompoundDefinition? def;
    for (final c in userCompounds) {
      if (c.base == base && c.ester == ester) {
        def = c;
        break;
      }
    }
    def ??= lookupLibraryDef(base, ester);
    if (def == null) continue;

    // Skip if this injection already exists — in the log or earlier in this
    // paste (same compound+date+dosage). Compared against the resolved
    // compound, which is what the new snapshot will carry.
    final resolved = def;
    bool isSame(Injection i) =>
        i.snapshot.base == resolved.base &&
        i.snapshot.ester == resolved.ester &&
        i.date.difference(date).inMinutes.abs() < 1 &&
        i.dosage == dosage;
    if (existing.any(isSame) || parsed.any(isSame)) continue;

    final unit = unitStr == 'mcg'
        ? Unit.mcg
        : unitStr == 'iu'
            ? Unit.iu
            : Unit.mg;
    parsed.add(Injection(
      id: _freshImportId('${date.millisecondsSinceEpoch}_$base', takenIds),
      compoundId: def.id,
      date: date,
      dosage: dosage,
      snapshot: CompoundDefinition(
        id: def.id,
        base: def.base,
        ester: def.ester,
        type: def.type,
        graphType: def.graphType,
        halfLife: def.halfLife,
        timeToPeak: def.timeToPeak,
        ratio: def.ratio,
        unit: unit,
        colorValue: def.colorValue,
      ),
      site: site,
      notes: notes,
    ));
  }
  return parsed;
}

final _delimiterCell = RegExp(r'^:?-+:?$');

/// True for a markdown table delimiter row: every cell is dashes with
/// optional alignment colons.
bool _isDelimiterRow(String line) {
  var body = line.trim();
  if (body.startsWith('|')) body = body.substring(1);
  if (body.endsWith('|')) body = body.substring(0, body.length - 1);
  final cells = body.split('|').map((c) => c.trim()).toList();
  return cells.isNotEmpty && cells.every(_delimiterCell.hasMatch);
}

/// `<stem>_<n>` with the smallest n ≥ 0 not in [taken]; the id is added to
/// [taken]. Minute-resolution dates alone would give two same-compound rows
/// in one minute identical ids, and the per-paste row count alone repeats
/// across imports (B21) — deleting either entry would then remove both.
String _freshImportId(String stem, Set<String> taken) {
  var n = 0;
  while (!taken.add('${stem}_$n')) {
    n++;
  }
  return '${stem}_$n';
}
