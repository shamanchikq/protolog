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
/// into injections. Rows already present in [existing] (same base+ester,
/// date within 1 minute, same dosage) are skipped, as are rows whose compound
/// can't be resolved from [userCompounds] or the built-in library.
List<Injection> parseMarkdownLog(
  String text, {
  required List<CompoundDefinition> userCompounds,
  required List<Injection> existing,
}) {
  final lines = text
      .split('\n')
      .where((l) => l.trim().startsWith('|') && !l.contains('---'))
      .toList();
  // Skip header row.
  final dataLines = lines.length > 1 ? lines.sublist(1) : <String>[];

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

    // Skip if this injection already exists (same compound+date+dosage).
    final alreadyExists = existing.any((i) =>
        i.snapshot.base == base &&
        i.snapshot.ester == ester &&
        i.date.difference(date).inMinutes.abs() < 1 &&
        i.dosage == dosage);
    if (alreadyExists) continue;

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

    final unit = unitStr == 'mcg'
        ? Unit.mcg
        : unitStr == 'iu'
            ? Unit.iu
            : Unit.mg;
    parsed.add(Injection(
      // Suffix with the running count: minute-resolution dates alone would
      // give two same-compound rows in one minute identical ids, and
      // deleting one would then remove both.
      id: '${date.millisecondsSinceEpoch}_${base}_${parsed.length}',
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
