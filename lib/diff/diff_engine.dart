// lib/diff/diff_engine.dart
import '../nrbf/nrbf.dart';
import '../main.dart' show DebugLogger, LogLevel;
import 'diff_models.dart';

// ============================================================================
// DIFF ENGINE - COMPARISON LOGIC
// ============================================================================

class DiffEngine {
  static NrbfDecoder? _beforeDecoder;
  static NrbfDecoder? _afterDecoder;

  static DiffResult compare(
    NrbfRecord before,
    NrbfRecord after, {
    NrbfDecoder? beforeDecoder,
    NrbfDecoder? afterDecoder,
  }) {
    DebugLogger.log('=== STARTING DIFF COMPARISON ===', level: LogLevel.info);

    // Store decoders for reference resolution
    _beforeDecoder = beforeDecoder;
    _afterDecoder = afterDecoder;

    final changes = <FieldChange>[];
    int fieldsCompared = 0;

    _compareRecords(before, after, '', changes, (count) => fieldsCompared += count);

    DebugLogger.log('=== DIFF COMPLETE ===', level: LogLevel.info);
    DebugLogger.log('Total fields compared: $fieldsCompared', level: LogLevel.info);
    DebugLogger.log('Changes found: ${changes.length}', level: LogLevel.info);
    DebugLogger.log('  Modified: ${changes.where((c) => c.changeType == ChangeType.modified).length}',
        level: LogLevel.debug);
    DebugLogger.log('  Added: ${changes.where((c) => c.changeType == ChangeType.added).length}',
        level: LogLevel.debug);
    DebugLogger.log('  Removed: ${changes.where((c) => c.changeType == ChangeType.removed).length}',
        level: LogLevel.debug);

    // Clear decoders
    _beforeDecoder = null;
    _afterDecoder = null;

    return DiffResult(
      changes: changes,
      totalFieldsCompared: fieldsCompared,
    );
  }

  // RESOLVE REFERENCES
  static dynamic _resolveValue(dynamic value, bool isBefore) {
    if (value is MemberReferenceRecord) {
      final decoder = isBefore ? _beforeDecoder : _afterDecoder;
      if (decoder != null) {
        final resolved = decoder.getRecord(value.idRef);
        if (resolved != null) {
          DebugLogger.log(
            'Resolved reference ${value.idRef} to ${resolved.runtimeType}',
            level: LogLevel.debug,
          );
          return resolved;
        }
      }
    }
    return value;
  }

  static void _compareRecords(
    dynamic before,
    dynamic after,
    String path,
    List<FieldChange> changes,
    Function(int) updateCount,
  ) {
    // RESOLVE REFERENCES FIRST
    before = _resolveValue(before, true);
    after = _resolveValue(after, false);

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

    DebugLogger.log('Comparing ClassRecord: ${before.typeName} at path: $path',
        level: LogLevel.debug);

    // Special handling for System.Guid
    if (before.typeName == 'System.Guid' && after.typeName == 'System.Guid') {
      count++;
      try {
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
      } catch (e) {
        DebugLogger.log('Error comparing GUIDs at $path: $e',
            level: LogLevel.warning);
      }

      updateCount(count);
      return;
    }

    // Get all unique member names
    final allMembers = <String>{
      ...before.memberNames,
      ...after.memberNames,
    };

    DebugLogger.log('  Members to compare: ${allMembers.length}',
        level: LogLevel.debug);

    for (final memberName in allMembers) {
      final memberPath = path.isEmpty ? memberName : '$path.$memberName';
      var beforeValue = before.getValue(memberName);
      var afterValue = after.getValue(memberName);

      // RESOLVE REFERENCES
      beforeValue = _resolveValue(beforeValue, true);
      afterValue = _resolveValue(afterValue, false);

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
        DebugLogger.log('ADDED: $memberPath = ${_formatValue(afterValue)}',
            level: LogLevel.debug);
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
        DebugLogger.log('REMOVED: $memberPath = ${_formatValue(beforeValue)}',
            level: LogLevel.debug);
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

    DebugLogger.log('Comparing arrays at $path: ${beforeArray.length} vs ${afterArray.length} items',
        level: LogLevel.debug);

    final maxLength = beforeArray.length > afterArray.length
        ? beforeArray.length
        : afterArray.length;

    for (int i = 0; i < maxLength; i++) {
      final elementPath = '$path[$i]';

      if (i >= beforeArray.length) {
        // Added
        var afterElement = _resolveValue(afterArray[i], false);
        changes.add(FieldChange(
          path: elementPath,
          changeType: ChangeType.added,
          newValue: _formatValue(afterElement),
          newRawValue: afterElement,
          fieldName: '[$i]',
        ));
        count++;
      } else if (i >= afterArray.length) {
        // Removed
        var beforeElement = _resolveValue(beforeArray[i], true);
        changes.add(FieldChange(
          path: elementPath,
          changeType: ChangeType.removed,
          oldValue: _formatValue(beforeElement),
          oldRawValue: beforeElement,
          fieldName: '[$i]',
        ));
        count++;
      } else {
        // Compare elements (they get resolved in _compareRecords)
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