// lib/diff/diff_engine.dart
import '../nrbf/nrbf.dart';
import '../main.dart' show DebugLogger, LogLevel;
import 'diff_models.dart';

// ============================================================================
// DIFF ENGINE - COMPARISON LOGIC
// ============================================================================

class DiffEngine {
  static DiffResult compare(NrbfRecord before, NrbfRecord after) {
    DebugLogger.log('=== STARTING DIFF COMPARISON ===', level: LogLevel.info);

    final changes = <FieldChange>[];
    int fieldsCompared = 0;

    _compareRecords(before, after, '', changes, (count) => fieldsCompared = count);

    DebugLogger.log('=== DIFF COMPLETE ===', level: LogLevel.info);
    DebugLogger.log('Total fields compared: $fieldsCompared', level: LogLevel.info);
    DebugLogger.log('Changes found: ${changes.length}', level: LogLevel.info);
    DebugLogger.log('  Modified: ${changes.where((c) => c.changeType == ChangeType.modified).length}',
        level: LogLevel.debug);
    DebugLogger.log('  Added: ${changes.where((c) => c.changeType == ChangeType.added).length}',
        level: LogLevel.debug);
    DebugLogger.log('  Removed: ${changes.where((c) => c.changeType == ChangeType.removed).length}',
        level: LogLevel.debug);

    return DiffResult(
      changes: changes,
      totalFieldsCompared: fieldsCompared,
    );
  }

  static void _compareRecords(
    dynamic before,
    dynamic after,
    String path,
    List<FieldChange> changes,
    Function(int) updateCount,
  ) {
    int count = 0;

    if (before is ClassRecord && after is ClassRecord) {
      _compareClassRecords(before, after, path, changes, (c) => count += c);
    } else if (_isArray(before) && _isArray(after)) {
      _compareArrays(before, after, path, changes, (c) => count += c);
    } else {
      // Primitive comparison
      count++;
      final beforeStr = _formatValue(before);
      final afterStr = _formatValue(after);

      if (beforeStr != afterStr) {
        final fieldName = path.split('.').last.split('[').first;
        changes.add(FieldChange(
          path: path,
          changeType: ChangeType.modified,
          oldValue: beforeStr,
          newValue: afterStr,
          oldRawValue: before,
          newRawValue: after,
          fieldName: fieldName,
        ));

        DebugLogger.log('CHANGE: $path: "$beforeStr" → "$afterStr"',
            level: LogLevel.debug);
      }
    }

    updateCount(count);
  }

  static void _compareClassRecords(
    ClassRecord before,
    ClassRecord after,
    String path,
    List<FieldChange> changes,
    Function(int) updateCount,
  ) {
    int count = 0;

    // Skip if different class types
    if (before.typeName != after.typeName) {
      DebugLogger.log('WARNING: Comparing different class types at $path: '
          '${before.typeName} vs ${after.typeName}',
          level: LogLevel.warning);
      return;
    }

    // Special handling for System.Guid
    if (before.typeName == 'System.Guid' && after.typeName == 'System.Guid') {
      count++;
      final beforeGuid = ClassRecord.reconstructGuid(before);
      final afterGuid = ClassRecord.reconstructGuid(after);

      if (beforeGuid != afterGuid) {
        final fieldName = path.split('.').last;
        changes.add(FieldChange(
          path: path,
          changeType: ChangeType.modified,
          oldValue: beforeGuid,
          newValue: afterGuid,
          oldRawValue: before,
          newRawValue: after,
          fieldName: fieldName,
        ));

        DebugLogger.log('GUID CHANGE: $path: $beforeGuid → $afterGuid',
            level: LogLevel.debug);
      }

      updateCount(count);
      return;
    }

    // Get all unique member names
    final allMembers = <String>{
      ...before.memberNames,
      ...after.memberNames,
    };

    for (final memberName in allMembers) {
      final memberPath = path.isEmpty ? memberName : '$path.$memberName';
      final beforeValue = before.getValue(memberName);
      final afterValue = after.getValue(memberName);

      if (beforeValue == null && afterValue != null) {
        // Added
        changes.add(FieldChange(
          path: memberPath,
          changeType: ChangeType.added,
          newValue: _formatValue(afterValue),
          newRawValue: afterValue,
          fieldName: memberName,
        ));
        count++;
      } else if (beforeValue != null && afterValue == null) {
        // Removed
        changes.add(FieldChange(
          path: memberPath,
          changeType: ChangeType.removed,
          oldValue: _formatValue(beforeValue),
          oldRawValue: beforeValue,
          fieldName: memberName,
        ));
        count++;
      } else if (beforeValue != null && afterValue != null) {
        // Compare recursively
        _compareRecords(beforeValue, afterValue, memberPath, changes, (c) => count += c);
      }
    }

    updateCount(count);
  }

  static void _compareArrays(
    dynamic before,
    dynamic after,
    String path,
    List<FieldChange> changes,
    Function(int) updateCount,
  ) {
    int count = 0;

    final beforeArray = (before as dynamic).getArray() as List;
    final afterArray = (after as dynamic).getArray() as List;

    final maxLength = beforeArray.length > afterArray.length
        ? beforeArray.length
        : afterArray.length;

    for (int i = 0; i < maxLength; i++) {
      final elementPath = '$path[$i]';

      if (i >= beforeArray.length) {
        // Added
        changes.add(FieldChange(
          path: elementPath,
          changeType: ChangeType.added,
          newValue: _formatValue(afterArray[i]),
          newRawValue: afterArray[i],
          fieldName: '[$i]',
        ));
        count++;
      } else if (i >= afterArray.length) {
        // Removed
        changes.add(FieldChange(
          path: elementPath,
          changeType: ChangeType.removed,
          oldValue: _formatValue(beforeArray[i]),
          oldRawValue: beforeArray[i],
          fieldName: '[$i]',
        ));
        count++;
      } else {
        // Compare elements
        _compareRecords(
            beforeArray[i], afterArray[i], elementPath, changes, (c) => count += c);
      }
    }

    updateCount(count);
  }

  static bool _isArray(dynamic value) {
    return value is BinaryArrayRecord ||
        value is ArraySinglePrimitiveRecord ||
        value is ArraySingleObjectRecord ||
        value is ArraySingleStringRecord;
  }

  static String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is bool || value is num) return value.toString();
    if (value is ClassRecord) {
      if (value.typeName == 'System.Guid') {
        try {
          return ClassRecord.reconstructGuid(value);
        } catch (e) {
          return 'System.Guid [invalid]';
        }
      }
      return value.typeName;
    }
    if (value is BinaryObjectStringRecord) return '"${value.value}"';
    if (_isArray(value)) {
      final array = (value as dynamic).getArray() as List;
      return 'Array[${array.length}]';
    }
    return value.runtimeType.toString();
  }
}