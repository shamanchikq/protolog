import 'package:flutter/material.dart';

// --- Enums ---
enum CompoundType { steroid, oral, peptide, ancillary }
enum GraphType { curve, activeWindow, event }
enum Unit { mg, mcg, iu }
enum ReminderState { overdue, due, on, paused }

// --- Helpers ---
T _enumFromString<T>(List<T> values, String str) {
  return values.firstWhere(
        (e) => e.toString().split('.').last == str,
    orElse: () => values.first,
  );
}

// --- Data Models ---

class Ester {
  final String name;
  final double halfLife;
  final double timeToPeak;
  final double molecularWeightRatio;

  const Ester({
    required this.name,
    required this.halfLife,
    required this.timeToPeak,
    required this.molecularWeightRatio
  });
}

class CompoundDefinition {
  final String id;
  final String base;
  final String ester;
  final CompoundType type;
  final GraphType graphType;
  final double halfLife;
  final double? defaultHalfLife;
  final double timeToPeak;
  final double ratio;
  final Unit unit;
  final int colorValue;
  final bool isCustom;
  final double? concentration; // NEW — mg/mL (or mcg/mL for mcg compounds). Null = unknown.

  const CompoundDefinition({
    required this.id,
    required this.base,
    required this.ester,
    required this.type,
    required this.graphType,
    required this.halfLife,
    this.defaultHalfLife,
    required this.timeToPeak,
    required this.ratio,
    required this.unit,
    required this.colorValue,
    this.isCustom = false,
    this.concentration, // NEW
  });

  Color get color => Color(colorValue);

  // JSON Serialization
  Map<String, dynamic> toJson() => {
    'id': id,
    'base': base,
    'ester': ester,
    'type': type.toString().split('.').last,
    'graphType': graphType.toString().split('.').last,
    'halfLife': halfLife,
    'defaultHalfLife': defaultHalfLife,
    'timeToPeak': timeToPeak,
    'ratio': ratio,
    'unit': unit.toString().split('.').last,
    'colorValue': colorValue,
    'isCustom': isCustom,
    'concentration': concentration, // NEW
  };

  factory CompoundDefinition.fromJson(Map<String, dynamic> json) {
    return CompoundDefinition(
      id: json['id'],
      base: json['base'],
      ester: json['ester'],
      type: _enumFromString(CompoundType.values, json['type']),
      graphType: _enumFromString(GraphType.values, json['graphType']),
      halfLife: (json['halfLife'] as num).toDouble(),
      defaultHalfLife: json['defaultHalfLife'] != null ? (json['defaultHalfLife'] as num).toDouble() : null,
      timeToPeak: (json['timeToPeak'] as num).toDouble(),
      ratio: (json['ratio'] as num).toDouble(),
      unit: _enumFromString(Unit.values, json['unit']),
      colorValue: json['colorValue'],
      isCustom: json['isCustom'] ?? false,
      concentration: json['concentration'] != null ? (json['concentration'] as num).toDouble() : null, // NEW
    );
  }

  CompoundDefinition copyWith({
    String? id,
    String? base,
    String? ester,
    CompoundType? type,
    GraphType? graphType,
    double? halfLife,
    double? defaultHalfLife,
    double? timeToPeak,
    double? ratio,
    Unit? unit,
    int? colorValue,
    bool? isCustom,
    double? concentration,
  }) {
    return CompoundDefinition(
      id: id ?? this.id,
      base: base ?? this.base,
      ester: ester ?? this.ester,
      type: type ?? this.type,
      graphType: graphType ?? this.graphType,
      halfLife: halfLife ?? this.halfLife,
      defaultHalfLife: defaultHalfLife ?? this.defaultHalfLife,
      timeToPeak: timeToPeak ?? this.timeToPeak,
      ratio: ratio ?? this.ratio,
      unit: unit ?? this.unit,
      colorValue: colorValue ?? this.colorValue,
      isCustom: isCustom ?? this.isCustom,
      concentration: concentration ?? this.concentration,
    );
  }
}

class Injection {
  final String id;
  final String compoundId;
  final DateTime date;
  final double dosage;
  final CompoundDefinition snapshot;
  final String? site;   // NEW — e.g. "Vent. glute R"; null for orals/legacy
  final String? notes;  // NEW — optional free text

  const Injection({
    required this.id,
    required this.compoundId,
    required this.date,
    required this.dosage,
    required this.snapshot,
    this.site,   // NEW
    this.notes,  // NEW
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'compoundId': compoundId,
    'date': date.toIso8601String(),
    'dosage': dosage,
    'snapshot': snapshot.toJson(),
    'site': site,     // NEW
    'notes': notes,   // NEW
  };

  factory Injection.fromJson(Map<String, dynamic> json) {
    return Injection(
      id: json['id'],
      compoundId: json['compoundId'],
      date: DateTime.parse(json['date']),
      dosage: (json['dosage'] as num).toDouble(),
      snapshot: CompoundDefinition.fromJson(json['snapshot']),
      site: json['site'] as String?,    // NEW
      notes: json['notes'] as String?,  // NEW
    );
  }
}

class GraphSettings {
  final bool normalized;
  final bool cumulative;
  final bool showPeptides;
  final String timeRange;

  const GraphSettings({
    required this.normalized,
    required this.cumulative,
    required this.showPeptides,
    required this.timeRange
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is GraphSettings &&
              runtimeType == other.runtimeType &&
              normalized == other.normalized &&
              cumulative == other.cumulative &&
              showPeptides == other.showPeptides &&
              timeRange == other.timeRange;

  @override
  int get hashCode => Object.hash(normalized, cumulative, showPeptides, timeRange);
}

// --- View Models for Painting ---

class ComputedGraphData {
  final List<CurveData> curves;
  final List<PeptideLaneData> peptideLanes;
  final List<String> laneLabels;
  final double maxMg;
  final double maxOralMg;
  final DateTime startDate;
  final DateTime endDate;
  final int totalDurationMs;
  final int laneCount;
  final List<InjectionMarkerData> injectionMarkers;

  ComputedGraphData({
    required this.curves,
    required this.peptideLanes,
    required this.laneLabels,
    required this.maxMg,
    required this.maxOralMg,
    required this.startDate,
    required this.endDate,
    required this.totalDurationMs,
    required this.laneCount,
    required this.injectionMarkers,
  });
}

class CurveData {
  final String baseName;
  final int colorValue;
  final bool isOral;
  final List<Offset> points;

  CurveData(this.baseName, this.colorValue, this.isOral, this.points);
  Color get color => Color(colorValue);
}

class PeptideLaneData {
  final String baseName;
  final int colorValue;
  final int laneIndex;
  final double startPct;
  final double durationPct;
  final GraphType type;

  PeptideLaneData(this.baseName, this.colorValue, this.laneIndex, this.startPct, this.durationPct, this.type);
  Color get color => Color(colorValue);
}

/// One lab result (F6): a measured blood marker at a point in time,
/// overlaid on the PK chart and listed on the dashboard.
class BloodworkEntry {
  final String id;
  final DateTime date;
  final String marker; // e.g. 'Total T', 'E2', 'SHBG'
  final double value;
  final String unit;   // free text, e.g. 'nmol/L', 'pmol/L'
  final String? notes;

  const BloodworkEntry({
    required this.id,
    required this.date,
    required this.marker,
    required this.value,
    required this.unit,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'marker': marker,
        'value': value,
        'unit': unit,
        'notes': notes,
      };

  factory BloodworkEntry.fromJson(Map<String, dynamic> json) => BloodworkEntry(
        id: json['id'],
        date: DateTime.parse(json['date'] as String),
        marker: json['marker'],
        value: (json['value'] as num).toDouble(),
        unit: json['unit'] ?? '',
        notes: json['notes'],
      );

  BloodworkEntry copyWith({
    String? id,
    DateTime? date,
    String? marker,
    double? value,
    String? unit,
    String? notes,
  }) =>
      BloodworkEntry(
        id: id ?? this.id,
        date: date ?? this.date,
        marker: marker ?? this.marker,
        value: value ?? this.value,
        unit: unit ?? this.unit,
        notes: notes ?? this.notes,
      );
}

class InjectionMarkerData {
  final double xPct;
  final double yLevel;
  final bool isOral;
  final int colorValue;
  final String baseName;
  InjectionMarkerData(this.xPct, this.yLevel, this.isOral, this.colorValue, this.baseName);
}

class IsolateInput {
  final List<Injection> injections;
  final GraphSettings settings;
  IsolateInput(this.injections, this.settings);
}

class ReminderSlot {
  final int weekday; // 1=Mon ... 7=Sun
  final int hour;
  final int minute;

  const ReminderSlot({required this.weekday, required this.hour, required this.minute});

  Map<String, dynamic> toJson() => {'weekday': weekday, 'hour': hour, 'minute': minute};

  factory ReminderSlot.fromJson(Map<String, dynamic> json) {
    return ReminderSlot(
      weekday: (json['weekday'] as num).toInt(),
      hour: (json['hour'] as num).toInt(),
      minute: (json['minute'] as num).toInt(),
    );
  }
}

class Reminder {
  final String id;
  final String compoundBase;
  final String compoundEster;
  final String scheduleMode; // 'interval' or 'custom'
  final double intervalDays;
  final int hour;
  final int minute;
  final List<ReminderSlot> customSlots;
  final bool enabled;
  final DateTime? lastScheduledDate; // legacy; superseded by anchorDate
  final DateTime? anchorDate;        // interval: next expected dose (rhythm origin)
  final DateTime? acknowledgedUntil; // custom: suppress occurrences at/before this
  // Base for platform notification ids. Persisted because String.hashCode is
  // not guaranteed stable across Dart versions — a recomputed base would
  // orphan already-scheduled notifications. Null only until first save.
  final int? notificationSeed;

  /// Stable base for notification ids; falls back to id.hashCode for
  /// reminders that predate the seed (toJson freezes the fallback).
  int get notificationIdBase => notificationSeed ?? id.hashCode;

  const Reminder({
    required this.id,
    required this.compoundBase,
    required this.compoundEster,
    this.scheduleMode = 'interval',
    required this.intervalDays,
    required this.hour,
    required this.minute,
    this.customSlots = const [],
    required this.enabled,
    this.lastScheduledDate,
    this.anchorDate,
    this.acknowledgedUntil,
    this.notificationSeed,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'compoundBase': compoundBase,
    'compoundEster': compoundEster,
    'scheduleMode': scheduleMode,
    'intervalDays': intervalDays,
    'hour': hour,
    'minute': minute,
    'customSlots': customSlots.map((s) => s.toJson()).toList(),
    'enabled': enabled,
    'lastScheduledDate': lastScheduledDate?.toIso8601String(),
    'anchorDate': anchorDate?.toIso8601String(),
    'acknowledgedUntil': acknowledgedUntil?.toIso8601String(),
    'notificationSeed': notificationIdBase,
  };

  factory Reminder.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String key) =>
        json[key] != null ? DateTime.parse(json[key] as String) : null;
    final legacyLast = parse('lastScheduledDate');
    return Reminder(
      id: json['id'],
      compoundBase: json['compoundBase'],
      compoundEster: json['compoundEster'],
      scheduleMode: json['scheduleMode'] ?? 'interval',
      intervalDays: (json['intervalDays'] as num).toDouble(),
      hour: (json['hour'] as num).toInt(),
      minute: (json['minute'] as num).toInt(),
      customSlots: json['customSlots'] != null
          ? (json['customSlots'] as List).map((s) => ReminderSlot.fromJson(s)).toList()
          : [],
      enabled: json['enabled'] ?? true,
      lastScheduledDate: legacyLast,
      anchorDate: parse('anchorDate') ?? legacyLast,
      acknowledgedUntil: parse('acknowledgedUntil'),
      notificationSeed: (json['notificationSeed'] as num?)?.toInt(),
    );
  }

  Reminder copyWith({
    String? id,
    String? compoundBase,
    String? compoundEster,
    String? scheduleMode,
    double? intervalDays,
    int? hour,
    int? minute,
    List<ReminderSlot>? customSlots,
    bool? enabled,
    DateTime? lastScheduledDate,
    DateTime? anchorDate,
    DateTime? acknowledgedUntil,
    int? notificationSeed,
  }) {
    return Reminder(
      id: id ?? this.id,
      compoundBase: compoundBase ?? this.compoundBase,
      compoundEster: compoundEster ?? this.compoundEster,
      scheduleMode: scheduleMode ?? this.scheduleMode,
      intervalDays: intervalDays ?? this.intervalDays,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      customSlots: customSlots ?? this.customSlots,
      enabled: enabled ?? this.enabled,
      lastScheduledDate: lastScheduledDate ?? this.lastScheduledDate,
      anchorDate: anchorDate ?? this.anchorDate,
      acknowledgedUntil: acknowledgedUntil ?? this.acknowledgedUntil,
      notificationSeed: notificationSeed ?? this.notificationSeed,
    );
  }
}