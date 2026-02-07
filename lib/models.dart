import 'package:flutter/material.dart';

// --- Enums ---
enum CompoundType { steroid, oral, peptide, ancillary }
enum GraphType { curve, activeWindow, event }
enum Unit { mg, mcg, iu }

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
    );
  }
}

class Injection {
  final String id;
  final String compoundId;
  final DateTime date;
  final double dosage;
  final CompoundDefinition snapshot;

  const Injection({
    required this.id,
    required this.compoundId,
    required this.date,
    required this.dosage,
    required this.snapshot,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'compoundId': compoundId,
    'date': date.toIso8601String(),
    'dosage': dosage,
    'snapshot': snapshot.toJson(),
  };

  factory Injection.fromJson(Map<String, dynamic> json) {
    return Injection(
      id: json['id'],
      compoundId: json['compoundId'],
      date: DateTime.parse(json['date']),
      dosage: (json['dosage'] as num).toDouble(),
      snapshot: CompoundDefinition.fromJson(json['snapshot']),
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

class ActiveCompoundStat {
  final String name;
  final double activeAmount; // Numeric value for calculations
  final String mainValue;    // String for display (e.g., "200.5" or "2d ago")
  final String subLabel;     // Unit or empty
  final int colorValue;
  final CompoundType type;
  final GraphType graphType;
  final String statusText;

  ActiveCompoundStat(this.name, this.activeAmount, this.mainValue, this.subLabel, this.colorValue, this.type, this.graphType, this.statusText);
}

class InjectionMarkerData {
  final double xPct;
  final double yLevel;
  final bool isOral;
  final int colorValue;
  InjectionMarkerData(this.xPct, this.yLevel, this.isOral, this.colorValue);
}

class IsolateInput {
  final List<Injection> injections;
  final GraphSettings settings;
  IsolateInput(this.injections, this.settings);
}