// lib/diff/diff_models.dart
import 'package:flutter/foundation.dart';
import '../nrbf/nrbf.dart';

// ============================================================================
// DIFF MODELS
// ============================================================================

enum ChangeType {
  modified,  // Value changed
  added,     // Field exists in 'after' but not in 'before'
  removed,   // Field exists in 'before' but not in 'after'
}

@immutable
class FieldChange {
  final String path;
  final ChangeType changeType;
  final String? oldValue;
  final String? newValue;
  final dynamic oldRawValue;
  final dynamic newRawValue;
  final String fieldName;

  const FieldChange({
    required this.path,
    required this.changeType,
    this.oldValue,
    this.newValue,
    this.oldRawValue,
    this.newRawValue,
    required this.fieldName,
  });

  String get displayOldValue => oldValue ?? 'N/A';
  String get displayNewValue => newValue ?? 'N/A';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FieldChange &&
        other.path == path &&
        other.changeType == changeType &&
        other.oldValue == oldValue &&
        other.newValue == newValue;
  }

  @override
  int get hashCode => Object.hash(path, changeType, oldValue, newValue);
}

class DiffResult {
  final List<FieldChange> changes;
  final int totalFieldsCompared;
  final DateTime comparisonTime;

  DiffResult({
    required this.changes,
    required this.totalFieldsCompared,
  }) : comparisonTime = DateTime.now();

  int get modifiedCount =>
      changes.where((c) => c.changeType == ChangeType.modified).length;
  int get addedCount =>
      changes.where((c) => c.changeType == ChangeType.added).length;
  int get removedCount =>
      changes.where((c) => c.changeType == ChangeType.removed).length;

  List<FieldChange> get modifiedChanges =>
      changes.where((c) => c.changeType == ChangeType.modified).toList();
  List<FieldChange> get addedChanges =>
      changes.where((c) => c.changeType == ChangeType.added).toList();
  List<FieldChange> get removedChanges =>
      changes.where((c) => c.changeType == ChangeType.removed).toList();
}