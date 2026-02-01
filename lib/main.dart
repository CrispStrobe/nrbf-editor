// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'dart:typed_data';
import 'nrbf/nrbf.dart';
import 'dart:convert';

// import 'dart:html' as html;
import 'package:universal_html/html.dart' as html;

import 'dart:developer' as developer;

import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as selector;

import 'presets/preset_manager.dart';
import 'presets/preset_models.dart';
import 'presets/preset_selector_widget.dart';
import 'presets/preset_editor_screen.dart';
import 'diff/diff_screen.dart';

void main() {
  runApp(const NrbfEditorApp());
}

// ============================================================================
// DEBUG LOGGER
// ============================================================================

class DebugLogger {
  static final List<LogEntry> _logs = [];
  static final _listeners = <VoidCallback>[];
  static bool enabled = true;

  static void log(String message, {LogLevel level = LogLevel.info}) {
    if (!enabled) return;
    
    final entry = LogEntry(
      message: message,
      level: level,
      timestamp: DateTime.now(),
    );
    
    _logs.add(entry);
    developer.log(message, name: 'NrbfEditor', level: level.value);
    print('[${level.name.toUpperCase()}] ${entry.timestamp.toIso8601String()} - $message');
    
    // Notify listeners
    for (final listener in _listeners) {
      listener();
    }
    
    // Keep only last 1000 logs
    if (_logs.length > 1000) {
      _logs.removeRange(0, _logs.length - 1000);
    }
  }

  static void clear() {
    _logs.clear();
    for (final listener in _listeners) {
      listener();
    }
  }

  static List<LogEntry> get logs => List.unmodifiable(_logs);

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
}

enum LogLevel {
  debug(0),
  info(1),
  warning(2),
  error(3);

  final int value;
  const LogLevel(this.value);
}

class LogEntry {
  final String message;
  final LogLevel level;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.level,
    required this.timestamp,
  });
}

// ============================================================================
// MAIN APP
// ============================================================================

class NrbfEditorApp extends StatelessWidget {
  const NrbfEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NRBF Save Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const EditorScreen(),
    );
  }
}

// ============================================================================
// EDITOR SCREEN
// ============================================================================

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  Uint8List? _fileBytes;
  String? _fileName;
  NrbfDecoder? _decoder;
  NrbfRecord? _rootRecord;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expandedNodes = {};
  bool _isLoading = false;
  String? _error;
  List<SearchResult> _searchResults = [];
  SearchResult? _selectedSearchResult;
  bool _showDebugConsole = false;
  bool _verboseLogging = false;
  int _totalRecords = 0;
  Map<String, int> _recordTypeStats = {};
  final Map<String, GlobalKey> _nodeKeys = {};
  bool _showFavoritesPanel = false;
  bool _showPresetFieldsPanel = false;
  
  @override
  void initState() {
    super.initState();
    DebugLogger.addListener(_onLogUpdate);
    DebugLogger.log('NRBF Editor initialized', level: LogLevel.info);
    
    // Initialize PresetManager
    PresetManager.instance.initialize().then((_) {
      DebugLogger.log('PresetManager initialized', level: LogLevel.info);
      if (mounted) setState(() {});
    }).catchError((e) {
      DebugLogger.log('ERROR initializing PresetManager: $e', level: LogLevel.error);
    });
    
    PresetManager.instance.addListener(_onPresetChange);
  }

  void _onPresetChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    DebugLogger.removeListener(_onLogUpdate);
    PresetManager.instance.removeListener(_onPresetChange);
    super.dispose();
  }

  dynamic _resolveValue(dynamic value) {
    if (value is MemberReferenceRecord && _decoder != null) {
      final resolved = _decoder!.getRecord(value.idRef);
      if (resolved != null) {
        return resolved;
      }
    }
    return value;
  }

  void _onLogUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickFile() async {
    try {
        setState(() {
        _isLoading = true;
        _error = null;
        });

        DebugLogger.log('=== FILE PICKER INITIATED ===', level: LogLevel.info);

        final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
        );

        if (result == null || result.files.first.bytes == null) {
        DebugLogger.log('File picker cancelled by user', level: LogLevel.info);
        setState(() => _isLoading = false);
        return;
        }

        final bytes = result.files.first.bytes!;
        final fileName = result.files.first.name;

        DebugLogger.log('File selected: $fileName', level: LogLevel.info);
        DebugLogger.log('File size: ${bytes.length} bytes (${_formatBytes(bytes.length)})', level: LogLevel.info);

        // Validate NRBF header
        DebugLogger.log('Validating NRBF header...', level: LogLevel.info);
        if (!NrbfUtils.startsWithPayloadHeader(bytes)) {
        DebugLogger.log('WARNING: File does not start with valid NRBF header', level: LogLevel.warning);
        
        final shouldContinue = await _showConfirmDialog(
            'Invalid NRBF Header',
            'This file does not appear to be a valid NRBF file. Continue anyway?',
        );
        
        if (!shouldContinue) {
            setState(() => _isLoading = false);
            return;
        }
        } else {
        DebugLogger.log('✓ Valid NRBF header detected', level: LogLevel.info);
        }

        // Show first 64 bytes for debugging
        final hexDump = _createHexDump(bytes.sublist(0, bytes.length < 64 ? bytes.length : 64));
        DebugLogger.log('First 64 bytes:\n$hexDump', level: LogLevel.debug);

        DebugLogger.log('=== STARTING NRBF DECODE ===', level: LogLevel.info);
        
        final stopwatch = Stopwatch()..start();
        _decoder = NrbfDecoder(bytes, verbose: _verboseLogging);
        final root = _decoder!.decode();
        stopwatch.stop();

        DebugLogger.log('=== DECODE COMPLETED ===', level: LogLevel.info);
        DebugLogger.log('Decode time: ${stopwatch.elapsedMilliseconds}ms', level: LogLevel.info);
        
        // Gather statistics (DECLARE ONCE, USE TWICE)
        final allRecords = _decoder!.getAllRecords();
        _totalRecords = allRecords.length;
        _recordTypeStats = _gatherRecordTypeStats(allRecords);
        
        DebugLogger.log('Total records decoded: $_totalRecords', level: LogLevel.info);
        DebugLogger.log('Record type breakdown:', level: LogLevel.info);
        _recordTypeStats.forEach((type, count) {
        DebugLogger.log('  - $type: $count', level: LogLevel.info);
        });

        final libraries = _decoder!.getLibraries();
        DebugLogger.log('Libraries found: ${libraries.length}', level: LogLevel.info);
        libraries.forEach((id, name) {
        DebugLogger.log('  - Library $id: $name', level: LogLevel.info);
        });

        setState(() {
        _fileBytes = bytes;
        _fileName = fileName;
        _nodeKeys.clear();
        _rootRecord = root;
        _isLoading = false;
        _expandedNodes.clear();
        _expandedNodes[''] = true;
        });

        DebugLogger.log('✓ File loaded successfully', level: LogLevel.info);

        // Auto-detect preset (REUSE allRecords and libraries)
        DebugLogger.log('=== AUTO-DETECTING PRESET ===', level: LogLevel.info);
        
        final classNames = <String>[];
        for (final record in allRecords.values) {
        if (record is ClassRecord) {
            if (!classNames.contains(record.typeName)) {
            classNames.add(record.typeName);
            }
        }
        }
        
        final libraryNames = libraries.values.toList();
        
        DebugLogger.log('Found ${classNames.length} unique class names', level: LogLevel.debug);
        DebugLogger.log('Found ${libraryNames.length} libraries', level: LogLevel.debug);
        
        final detectedPreset = PresetManager.instance.autoDetectPreset(classNames, libraryNames);
        if (detectedPreset != null) {
        PresetManager.instance.setActivePreset(detectedPreset.gameTypeId);
        DebugLogger.log('✓ Preset auto-detected: ${detectedPreset.displayName}', 
                        level: LogLevel.info);
        _showSnackBar('Preset detected: ${detectedPreset.displayName}', success: true);
        } else {
        DebugLogger.log('No matching preset found', level: LogLevel.warning);
        }
        
        // Initial search
        _performSearch();

        _showSnackBar('File loaded: $_totalRecords records decoded', success: true);
    } catch (e, stackTrace) {
        DebugLogger.log('ERROR loading file: $e', level: LogLevel.error);
        DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
        
        setState(() {
        _error = 'Error loading file: $e';
        _isLoading = false;
        });

        _showSnackBar('Failed to load file: $e', success: false);
    }
    }

  void _performSearch() {
    if (_rootRecord == null) return;

    DebugLogger.log('=== SEARCH INITIATED ===', level: LogLevel.debug);
    DebugLogger.log('Search query: "$_searchQuery"', level: LogLevel.debug);

    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _expandedNodes.clear();
      });
      DebugLogger.log('Search cleared', level: LogLevel.debug);
      return;
    }

    final stopwatch = Stopwatch()..start();
    final results = <SearchResult>[];
    _searchNode(_rootRecord!, '', results, query);
    stopwatch.stop();

    DebugLogger.log('Search completed in ${stopwatch.elapsedMilliseconds}ms', level: LogLevel.debug);
    DebugLogger.log('Found ${results.length} matches', level: LogLevel.debug);

    setState(() {
      _searchResults = results;
      if (results.isNotEmpty) {
        _selectedSearchResult = results.first;
        DebugLogger.log('First result: ${results.first.path}', level: LogLevel.debug);
      }
    });
  }

  void _searchNode(dynamic node, String path, List<SearchResult> results, String query) {
    // Resolve if it's a reference
    final resolvedNode = _resolveValue(node);
    
    if (resolvedNode is ClassRecord) {
        // 1. Check Class Name
        if (resolvedNode.typeName.toLowerCase().contains(query)) {
        results.add(SearchResult(
            path: path.isEmpty ? resolvedNode.typeName : '$path.${resolvedNode.typeName}',
            type: 'Class',
            value: resolvedNode.typeName,
            record: resolvedNode,
        ));
        }

        // 2. Special GUID handling
        if (resolvedNode.typeName == 'System.Guid') {
        try {
            final guidString = ClassRecord.reconstructGuid(resolvedNode);
            if (guidString.toLowerCase().contains(query)) {
            results.add(SearchResult(
                path: path, // GUID is treated as a leaf value for the path
                type: 'GUID',
                value: guidString,
                record: resolvedNode,
            ));
            }
        } catch (e) { /* ignore */ }
        }

        // 3. Check Members
        for (final memberName in resolvedNode.memberNames) {
        final memberPath = path.isEmpty ? memberName : '$path.$memberName';
        var memberValue = resolvedNode.getValue(memberName);
        memberValue = _resolveValue(memberValue);

        // A. Match Member Name
        if (memberName.toLowerCase().contains(query)) {
            results.add(SearchResult(
            path: memberPath,
            type: 'Field',
            value: _formatValue(memberValue),
            record: resolvedNode,
            ));
        }

        // B. Match Member Value (String/Primitive)
        if (memberValue != null) {
            final valueStr = _formatValue(memberValue).toLowerCase();
            if (valueStr.contains(query)) {
            results.add(SearchResult(
                path: memberPath,
                type: 'Value',
                value: _formatValue(memberValue),
                record: resolvedNode,
            ));
            }

            // C. Recurse (Deep Search)
            if (memberValue is NrbfRecord && 
                memberValue is! MemberReferenceRecord &&
                (memberValue is! ClassRecord || memberValue.typeName != 'System.Guid')) {
            _searchNode(memberValue, memberPath, results, query);
            }
        }
        }
    } 
    // 4. Handle Arrays
    else if (resolvedNode is BinaryArrayRecord ||
        resolvedNode is ArraySinglePrimitiveRecord ||
        resolvedNode is ArraySingleObjectRecord ||
        resolvedNode is ArraySingleStringRecord) {
        
        final array = (resolvedNode as dynamic).getArray() as List;
        for (int i = 0; i < array.length; i++) {
        var element = array[i];
        element = _resolveValue(element);
        final elementPath = '$path[$i]';

        // Check content of primitives inside array
        final valStr = _formatValue(element).toLowerCase();
        if (valStr.contains(query)) {
            results.add(SearchResult(
            path: elementPath,
            type: 'ArrayItem',
            value: _formatValue(element),
            record: resolvedNode,
            ));
        }

        // Recurse if complex object
        if (element is NrbfRecord && element is! MemberReferenceRecord) {
            _searchNode(element, elementPath, results, query);
        }
        }
    }
    }

  String _formatValue(dynamic value) {
    // Try to resolve references first
    final resolvedValue = _resolveValue(value);
    
    if (resolvedValue == null) return 'null';
    if (resolvedValue is String) return '"$resolvedValue"';
    if (resolvedValue is bool || resolvedValue is num) return resolvedValue.toString();
    if (resolvedValue is ClassRecord) {
      // AUTOMATICALLY RECONSTRUCT GUID!
      if (resolvedValue.typeName == 'System.Guid') {
        try {
          return ClassRecord.reconstructGuid(resolvedValue);
        } catch (e) {
          return 'System.Guid [invalid]';
        }
      }
      return resolvedValue.typeName;
    }
    if (resolvedValue is BinaryObjectStringRecord) return '"${resolvedValue.value}"';
    if (resolvedValue is MemberReferenceRecord) {
      return 'Reference(${resolvedValue.idRef}) [UNRESOLVED]';
    }
    if (resolvedValue is BinaryArrayRecord ||
        resolvedValue is ArraySinglePrimitiveRecord ||
        resolvedValue is ArraySingleObjectRecord ||
        resolvedValue is ArraySingleStringRecord) {
      final array = (resolvedValue as dynamic).getArray() as List;
      return 'Array[${array.length}]';
    }
    return resolvedValue.runtimeType.toString();
  }

  Future<void> _saveFile() async {
    if (_rootRecord == null || _fileBytes == null) return;

    try {
        setState(() => _isLoading = true);

        DebugLogger.log('=== STARTING CROSS-PLATFORM NRBF ENCODE ===', level: LogLevel.info);

        final stopwatch = Stopwatch()..start();
        final encoder = NrbfEncoder();
        final encoded = encoder.encode(_rootRecord!, decoder: _decoder);
        stopwatch.stop();

        DebugLogger.log('=== ENCODE COMPLETED ===', level: LogLevel.info);
        DebugLogger.log('Encode time: ${stopwatch.elapsedMilliseconds}ms', level: LogLevel.info);
        DebugLogger.log('Output size: ${encoded.length} bytes (${_formatBytes(encoded.length)})', level: LogLevel.info);

        final String suggestedName = _fileName ?? 'edited.sav';

        if (kIsWeb) {
        // WEB / PWA
        DebugLogger.log('Platform detected: Web. Initializing Blob download.', level: LogLevel.debug);
        
        final blob = html.Blob([encoded]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
            ..href = url
            ..style.display = 'none'
            ..download = suggestedName;
        
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
        
        DebugLogger.log('✓ Web download triggered via anchor element', level: LogLevel.info);
        } else {
        // MACOS / WINDOWS / MOBILE
        DebugLogger.log('Platform detected: Native. Opening Save Dialog.', level: LogLevel.debug);

        const typeGroup = selector.XTypeGroup(
            label: 'NRBF Files',
            extensions: ['sav', 'dat', 'bin'],
        );

        // Note: use getSaveLocation (v1.0+) or getSavePath depending on your exact version
        final path = await selector.getSaveLocation(
            suggestedName: suggestedName,
            acceptedTypeGroups: [typeGroup],
        );

        if (path == null) {
            DebugLogger.log('Save operation cancelled by user', level: LogLevel.info);
            setState(() => _isLoading = false);
            return;
        }

        final io.File file = io.File(path.path);
        await file.writeAsBytes(encoded);
        
        DebugLogger.log('✓ File written to disk: ${path.path}', level: LogLevel.info);
        }

        setState(() => _isLoading = false);
        _showSnackBar('File saved successfully: ${_formatBytes(encoded.length)}', success: true);

    } catch (e, stackTrace) {
        DebugLogger.log('ERROR saving file: $e', level: LogLevel.error);
        DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);

        setState(() {
        _error = 'Error saving file: $e';
        _isLoading = false;
        });

        _showSnackBar('Failed to save file: $e', success: false);
    }
    }

  Future<void> _exportToJson() async {
    if (_rootRecord == null) return;

    try {
        DebugLogger.log('=== EXPORTING TO JSON ===', level: LogLevel.info);

        final stopwatch = Stopwatch()..start();
        final jsonData = _recordToJson(_rootRecord!);
        final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
        stopwatch.stop();

        final String jsonFileName = '${_fileName ?? 'export'}.json';

        if (kIsWeb) {
        final blob = html.Blob([jsonString]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
            ..href = url
            ..style.display = 'none'
            ..download = jsonFileName;
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
        } else {
        const typeGroup = selector.XTypeGroup(
            label: 'JSON Files',
            extensions: ['json'],
        );

        final path = await selector.getSaveLocation(
            suggestedName: jsonFileName,
            acceptedTypeGroups: [typeGroup],
        );

        if (path != null) {
            final io.File file = io.File(path.path);
            await file.writeAsString(jsonString);
        }
        }

        DebugLogger.log('✓ JSON exported successfully', level: LogLevel.info);
        _showSnackBar('Exported to JSON successfully', success: true);
    } catch (e, stackTrace) {
        DebugLogger.log('ERROR exporting to JSON: $e', level: LogLevel.error);
        _showSnackBar('Failed to export JSON: $e', success: false);
    }
    }

  Map<String, dynamic> _recordToJson(dynamic record) {
    if (record is ClassRecord) {
      // Special handling for System.Guid
      if (record.typeName == 'System.Guid') {
        try {
          return {
            '_type': 'System.Guid',
            'value': ClassRecord.reconstructGuid(record),
          };
        } catch (e) {
          // Fall through to normal handling
        }
      }
      
      final map = <String, dynamic>{
        '_type': 'ClassRecord',
        'recordType': record.recordType.name,
        'objectId': record.objectId,
        'typeName': record.typeName,
        'members': {},
      };

      for (final memberName in record.memberNames) {
        var value = record.getValue(memberName);
        value = _resolveValue(value);
        map['members'][memberName] = _valueToJson(value);
      }

      return map;
    } else if (record is BinaryArrayRecord) {
      return {
        '_type': 'BinaryArrayRecord',
        'objectId': record.objectId,
        'arrayType': record.binaryArrayTypeEnum.name,
        'rank': record.rank,
        'lengths': record.lengths,
        'elements': record.getArray().map((e) => _valueToJson(_resolveValue(e))).toList(),
      };
    } else if (record is ArraySinglePrimitiveRecord) {
      return {
        '_type': 'ArraySinglePrimitiveRecord',
        'objectId': record.objectId,
        'primitiveType': record.primitiveTypeEnum.name,
        'length': record.length,
        'elements': record.getArray(),
      };
    } else if (record is ArraySingleObjectRecord) {
      return {
        '_type': 'ArraySingleObjectRecord',
        'objectId': record.objectId,
        'length': record.length,
        'elements': record.getArray().map((e) => _valueToJson(_resolveValue(e))).toList(),
      };
    } else if (record is ArraySingleStringRecord) {
      return {
        '_type': 'ArraySingleStringRecord',
        'objectId': record.objectId,
        'length': record.length,
        'elements': record.getArray(),
      };
    } else if (record is BinaryObjectStringRecord) {
      return {
        '_type': 'BinaryObjectStringRecord',
        'objectId': record.objectId,
        'value': record.value,
      };
    } else if (record is MemberReferenceRecord) {
      return {
        '_type': 'MemberReferenceRecord',
        'idRef': record.idRef,
      };
    } else {
      return {'_type': record.runtimeType.toString()};
    }
  }

  dynamic _valueToJson(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num || value is bool) return value;
    if (value is NrbfRecord) return _recordToJson(value);
    return value.toString();
  }

  Map<String, int> _gatherRecordTypeStats(Map<int, NrbfRecord> records) {
    final stats = <String, int>{};
    for (final record in records.values) {
      final typeName = record.runtimeType.toString();
      stats[typeName] = (stats[typeName] ?? 0) + 1;
    }
    return stats;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _createHexDump(Uint8List bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i += 16) {
      buffer.write('${i.toRadixString(16).padLeft(4, '0')}: ');
      
      // Hex
      for (int j = 0; j < 16; j++) {
        if (i + j < bytes.length) {
          buffer.write('${bytes[i + j].toRadixString(16).padLeft(2, '0')} ');
        } else {
          buffer.write('   ');
        }
      }
      
      buffer.write(' ');
      
      // ASCII
      for (int j = 0; j < 16 && i + j < bytes.length; j++) {
        final byte = bytes[i + j];
        if (byte >= 32 && byte <= 126) {
          buffer.write(String.fromCharCode(byte));
        } else {
          buffer.write('.');
        }
      }
      
      buffer.writeln();
    }
    return buffer.toString();
  }

  void _showSnackBar(String message, {required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.edit_document),
            const SizedBox(width: 8),
            const Text('NRBF Save Editor'),
            if (_fileName != null) ...[
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  _fileName!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Stats badge
          if (_totalRecords > 0)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Chip(
                avatar: const Icon(Icons.data_object, size: 16),
                label: Text('$_totalRecords records'),
              ),
            ),
          
          // Verbose logging toggle
          IconButton(
            icon: Icon(_verboseLogging ? Icons.bug_report : Icons.bug_report_outlined),
            tooltip: _verboseLogging ? 'Disable verbose logging' : 'Enable verbose logging',
            onPressed: () {
              setState(() {
                _verboseLogging = !_verboseLogging;
                DebugLogger.enabled = _verboseLogging;
              });
              DebugLogger.log(
                'Verbose logging ${_verboseLogging ? 'enabled' : 'disabled'}',
                level: LogLevel.info,
              );
            },
          ),
          
          // Debug console toggle
          IconButton(
            icon: Icon(_showDebugConsole ? Icons.terminal : Icons.terminal_outlined),
            tooltip: _showDebugConsole ? 'Hide debug console' : 'Show debug console',
            onPressed: () {
              setState(() => _showDebugConsole = !_showDebugConsole);
            },
          ),
          
          // Clear logs
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear debug logs',
            onPressed: () {
              DebugLogger.clear();
              _showSnackBar('Debug logs cleared', success: true);
            },
          ),

          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Processing...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Error',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () => setState(() => _error = null),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : Row(
                  children: [
                    // Main content area
                    Expanded(
                      flex: _showDebugConsole ? 3 : 1,
                      child: Column(
                        children: [
                          // Top toolbar
                          _buildToolbar(),

                          // Content
                          Expanded(
                            child: _rootRecord == null
                                ? _buildWelcomeScreen()
                                : Row(
                                    children: [
                                      // Tree view
                                      Expanded(
                                        flex: 3,
                                        child: _buildTreeView(),
                                      ),

                                      // Preset Fields panel (ADD THIS)
                                      if (_showPresetFieldsPanel && 
                                          PresetManager.instance.hasActivePreset)
                                        Container(
                                          width: 300,
                                          decoration: BoxDecoration(
                                            border: Border(
                                              left: BorderSide(
                                                color: Theme.of(context).dividerColor,
                                              ),
                                            ),
                                          ),
                                          child: _buildPresetFieldsPanel(),
                                        ),

                                      // Favorites panel
                                      if (_showFavoritesPanel && 
                                          PresetManager.instance.hasActivePreset)
                                        Container(
                                          width: 300,
                                          decoration: BoxDecoration(
                                            border: Border(
                                              left: BorderSide(
                                                color: Theme.of(context).dividerColor,
                                              ),
                                            ),
                                          ),
                                          child: _buildFavoritesPanel(),
                                        ),

                                      // Search results
                                      if (_searchResults.isNotEmpty)
                                        Container(
                                          width: 350,
                                          decoration: BoxDecoration(
                                            border: Border(
                                              left: BorderSide(
                                                color: Theme.of(context).dividerColor,
                                              ),
                                            ),
                                          ),
                                          child: _buildSearchResults(),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),

                    // Debug console
                    if (_showDebugConsole)
                      Container(
                        width: 500,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: Theme.of(context).dividerColor, width: 2),
                          ),
                        ),
                        child: _buildDebugConsole(),
                      ),
                  ],
                ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // File operations
          FilledButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.file_open),
            label: const Text('Open File'),
          ),
          const SizedBox(width: 8),

          if (_rootRecord != null) ...[
            FilledButton.tonalIcon(
              onPressed: _saveFile,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
            const SizedBox(width: 8),

            OutlinedButton.icon(
              onPressed: _exportToJson,
              icon: const Icon(Icons.download),
              label: const Text('Export JSON'),
            ),
            const SizedBox(width: 16),
            
            // Preset selector dropdown
            PopupMenuButton<String>(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.games),
                    const SizedBox(width: 8),
                    Text(PresetManager.instance.activePreset?.displayName ?? 
                         'No preset'),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
              onSelected: (gameTypeId) {
                if (gameTypeId.isEmpty) {
                  PresetManager.instance.setActivePreset(null);
                } else {
                  PresetManager.instance.setActivePreset(gameTypeId);
                }
                setState(() {});
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: '',
                  child: Row(
                    children: [
                      Icon(Icons.clear),
                      SizedBox(width: 8),
                      Text('No preset'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                ...PresetManager.instance.presets.map((preset) {
                  return PopupMenuItem(
                    value: preset.gameTypeId,
                    child: Row(
                      children: [
                        Icon(
                          Icons.games,
                          color: PresetManager.instance.activePreset?.gameTypeId == 
                                 preset.gameTypeId
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(preset.displayName),
                      ],
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(width: 8),
            
            // Favorites toggle
            IconButton(
              icon: Icon(_showFavoritesPanel ? Icons.star : Icons.star_border),
              tooltip: _showFavoritesPanel ? 'Hide favorites' : 'Show favorites',
              onPressed: PresetManager.instance.hasActivePreset
                  ? () => setState(() => _showFavoritesPanel = !_showFavoritesPanel)
                  : null,
            ),

            // Preset fields toggle
            IconButton(
              icon: Icon(_showPresetFieldsPanel ? Icons.playlist_play : Icons.playlist_play_outlined),
              tooltip: _showPresetFieldsPanel ? 'Hide preset fields' : 'Show preset fields',
              onPressed: PresetManager.instance.hasActivePreset
                  ? () => setState(() => _showPresetFieldsPanel = !_showPresetFieldsPanel)
                  : null,
            ),
            
            // Preset editor
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Preset Editor',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PresetEditorScreen(),
                  ),
                );
              },
            ),

            IconButton(
              icon: const Icon(Icons.compare_arrows),
              tooltip: 'Compare Files',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DiffScreen(),
                  ),
                );
              },
            ),
            
            const SizedBox(width: 16),
          ],

          

          // Search
          if (_rootRecord != null) ...[
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search fields and values...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                            _performSearch();
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                  _performSearch();
                },
              ),
            ),
            const SizedBox(width: 8),

            // Expand/Collapse all
            IconButton(
              icon: const Icon(Icons.unfold_more),
              tooltip: 'Expand All',
              onPressed: () {
                setState(() {
                  _expandedNodes.clear();
                  _expandAll(_rootRecord!, '');
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.unfold_less),
              tooltip: 'Collapse All',
              onPressed: () {
                setState(() => _expandedNodes.clear());
              },
            ),
          ],
        ],
      ),
    );
  }

  void _expandAll(dynamic node, String path) {
    // RESOLVE REFERENCE
    final resolvedNode = _resolveValue(node);
    
    // We do not rename empty path to 'root' but use path as-is.
    // The UI builder uses '' for the root key, so we must use '' here too.
    _expandedNodes[path] = true;

    if (resolvedNode is ClassRecord) {
      for (final memberName in resolvedNode.memberNames) {
        final memberPath = path.isEmpty ? memberName : '$path.$memberName';
        final value = resolvedNode.getValue(memberName);
        _expandAll(value, memberPath);
      }
    } 
    // Handle Arrays so "Expand All" doesn't stop at lists
    else if (resolvedNode is BinaryArrayRecord ||
        resolvedNode is ArraySinglePrimitiveRecord ||
        resolvedNode is ArraySingleObjectRecord ||
        resolvedNode is ArraySingleStringRecord) {
      
      final array = (resolvedNode as dynamic).getArray() as List;
      for (int i = 0; i < array.length; i++) {
        final elementPath = '$path[$i]';
        final element = array[i];
        if (element is NrbfRecord) {
          _expandAll(element, elementPath);
        }
      }
    }
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.file_upload_outlined,
            size: 120,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'NRBF Save File Editor',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Universal parser for .NET Binary Format files',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.file_open),
            label: const Text('Open NRBF File'),
          ),
          const SizedBox(height: 48),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 48),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Load',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _buildFeature(Icons.visibility, 'Files with NRBF structures like unity game .sav files'),

                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text(text),
        ],
      ),
    );
  }

  Widget _buildTreeView() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        // if (_rootRecord != null) _buildRecordTree(_rootRecord!, 'root', 0),
        if (_rootRecord != null) _buildRecordTree(_rootRecord!, '', 0),
      ],
    );
  }

  Widget _buildRecordTree(NrbfRecord record, String path, int depth) {
    // FIRST: Resolve if it's a reference
    if (record is MemberReferenceRecord && _decoder != null) {
      final resolved = _decoder!.getRecord(record.idRef);
      if (resolved != null) {
        record = resolved;
      }
    }
    
    if (record is ClassRecord) {
      return _buildClassRecordTile(record, path, depth);
    } else if (record is BinaryArrayRecord ||
        record is ArraySinglePrimitiveRecord ||
        record is ArraySingleObjectRecord ||
        record is ArraySingleStringRecord) {
      return _buildArrayRecordTile(record as dynamic, path, depth);
    } else if (record is BinaryObjectStringRecord) {
      return _buildValueTile('String', record.value, depth);
    } else if (record is MemberReferenceRecord) {
      // If we couldn't resolve it, show as reference
      return _buildValueTile('Reference [UNRESOLVED]', 'ID: ${record.idRef}', depth);
    } else {
      return _buildValueTile(record.runtimeType.toString(), '', depth);
    }
  }

  Widget _buildClassRecordTile(ClassRecord record, String path, int depth) {
    final nodePath = path;
    final isExpanded = _expandedNodes[nodePath] ?? false;
    final matchesSearch = _matchesSearch(record, path);
    final key = _nodeKeys.putIfAbsent(path, () => GlobalKey());

    // Special handling for System.Guid - show as single value
    if (record.typeName == 'System.Guid') {
      try {
        final guidString = ClassRecord.reconstructGuid(record);
        return Container(
          margin: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: matchesSearch
                ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: const Icon(Icons.fingerprint, size: 20),
            title: const Text('GUID'),
            subtitle: Text(guidString),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: guidString));
                _showSnackBar('GUID copied to clipboard', success: true);
              },
            ),
          ),
        );
      } catch (e) {
        // If GUID reconstruction fails, show the raw fields
      }
    }

    return Card(
      key: key,
      margin: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4),
      color: matchesSearch
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
          : null,
      child: ExpansionTile(
        key: Key('${nodePath}_$isExpanded'),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          setState(() => _expandedNodes[nodePath] = expanded);
        },
        leading: Icon(
          Icons.class_,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                record.typeName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (record.objectId != null)
              Chip(
                label: Text('ID: ${record.objectId}'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        subtitle: Text('${record.memberNames.length} members'),
        children: record.memberNames.map((memberName) {
          final memberPath = path.isEmpty ? memberName : '$path.$memberName';

          var value = record.getValue(memberName);
          
          // RESOLVE REFERENCES HERE!
          value = _resolveValue(value);

          // Build nested field with member name preserved
          return _buildMemberField(record, memberName, value, memberPath, depth + 1);
        }).toList(),
      ),
    );
  }

  // Build member field that preserves field names for nested records
  Widget _buildMemberField(ClassRecord parentRecord, String memberName, dynamic value, String path, int depth) {
    // Resolve references
    value = _resolveValue(value);
    final key = _nodeKeys.putIfAbsent(path, () => GlobalKey()); // Register key
    
    // If it's a nested ClassRecord, show field name + class
    if (value is ClassRecord) {
    final nodePath = path;
    final isExpanded = _expandedNodes[nodePath] ?? false;
    final matchesSearch = _searchQuery.isNotEmpty &&
        (memberName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            value.typeName.toLowerCase().contains(_searchQuery.toLowerCase()));

    // Special handling for System.Guid - CHECK FOR PRESET FIRST!
    if (value.typeName == 'System.Guid') {
      // Check if there's a preset for this path
      final fieldPreset = PresetManager.instance.findPresetForPath(path);
      
      if (fieldPreset != null) {
        // Use PresetSelectorWidget
        DebugLogger.log('Using preset selector for GUID at path: $path', level: LogLevel.debug);
        return PresetSelectorWidget(
          key: key,
          parentRecord: parentRecord,
          memberName: memberName,
          currentValue: value,
          fieldPreset: fieldPreset,
          path: path,
          onValueChanged: (newValue) {
            try {
              applyGuidToRecord(value, newValue);
              setState(() {});
              _showSnackBar('GUID updated', success: true);
            } catch (e) {
              _showSnackBar('Error updating GUID: $e', success: false);
            }
          },
        );
      }
      
      // Default GUID display (no preset found)
      try {
        final guidString = ClassRecord.reconstructGuid(value);
        return Container(
          key: key,
          margin: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: matchesSearch
                ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: const Icon(Icons.fingerprint, size: 20),
            title: Row(
              children: [
                Expanded(child: Text(memberName)),
                FavoriteToggle(path: path),
              ],
            ),
            subtitle: Text(guidString),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ADD EDIT BUTTON
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showGuidEditDialog(value, memberName, guidString),
                  tooltip: 'Edit GUID',
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: guidString));
                    _showSnackBar('GUID copied to clipboard', success: true);
                  },
                  tooltip: 'Copy GUID',
                ),
              ],
            ),
          ),
        );
      } catch (e) {
        // Fall through to normal handling
      }

    } // if System.Guid

      // For other ClassRecords, show as expandable with field name
      return Card(
        key: key,
        margin: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4),
        color: matchesSearch
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
            : null,
        child: ExpansionTile(
          key: Key('${nodePath}_$isExpanded'),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (expanded) {
            setState(() => _expandedNodes[nodePath] = expanded);
          },
          leading: Icon(
            Icons.class_,
            color: Theme.of(context).colorScheme.secondary,
          ),
          title: Row(
            children: [
                Expanded(
                child: Text.rich( // Changed from RichText to Text.rich
                    TextSpan(
                    // Text.rich will now automatically inherit the theme
                    children: [
                        TextSpan(
                        text: memberName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                        text: ' [${value.typeName}]',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.normal, // Ensure type name isn't bold
                        ),
                        ),
                    ],
                    ),
                ),
                ),
                if (value.objectId != null)
                Chip(
                    label: Text('ID: ${value.objectId}'),
                    visualDensity: VisualDensity.compact,
                ),
            ],
            ),
          subtitle: Text('${value.memberNames.length} members'),
          children: value.memberNames.map((nestedMemberName) {
            final nestedMemberPath = '$path.$nestedMemberName';
            var nestedValue = value.getValue(nestedMemberName);
            nestedValue = _resolveValue(nestedValue);

            // Recursively build nested members
            return _buildMemberField(value, nestedMemberName, nestedValue, nestedMemberPath, depth + 1);
          }).toList(),
        ),
      );
    }
    
    // If it's an array, show field name + array
    if (value is BinaryArrayRecord ||
        value is ArraySinglePrimitiveRecord ||
        value is ArraySingleObjectRecord ||
        value is ArraySingleStringRecord) {
      return _buildArrayMemberField(memberName, value, path, depth);
    }
    
    // Otherwise, it's a primitive - show as editable field
    return _buildEditableField(parentRecord, memberName, value, path, depth);
  }

  void _showGuidEditDialog(ClassRecord guidRecord, String fieldName, String currentGuid) {
    final controller = TextEditingController(text: currentGuid);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $fieldName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter GUID value:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'GUID',
                hintText: currentGuid,
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newGuid = controller.text.trim();
              
              // Validate GUID format
              final guidPattern = RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
                caseSensitive: false,
              );
              
              if (!guidPattern.hasMatch(newGuid)) {
                _showSnackBar('Invalid GUID format', success: false);
                return;
              }
              
              try {
                applyGuidToRecord(guidRecord, newGuid);
                setState(() {});
                Navigator.pop(context);
                _showSnackBar('GUID updated successfully', success: true);
              } catch (e) {
                _showSnackBar('Error updating GUID: $e', success: false);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Build array member field with field name preserved
  Widget _buildArrayMemberField(String memberName, dynamic arrayRecord, String path, int depth) {
    final nodePath = path;
    final isExpanded = _expandedNodes[nodePath] ?? false;
    final array = (arrayRecord as dynamic).getArray() as List;
    final key = _nodeKeys.putIfAbsent(path, () => GlobalKey());
    final matchesSearch = _searchQuery.isNotEmpty &&
        memberName.toLowerCase().contains(_searchQuery.toLowerCase());

    return Card(
      key: key,
      margin: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4),
      color: matchesSearch
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
          : null,
      child: ExpansionTile(
        key: Key('${nodePath}_$isExpanded'),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          setState(() => _expandedNodes[nodePath] = expanded);
        },
        leading: Icon(Icons.view_list, color: Theme.of(context).colorScheme.tertiary),
        title: Text.rich( // Changed from RichText to Text.rich
            TextSpan(
                children: [
                TextSpan(
                    text: memberName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                    text: ' [Array: ${array.length} items]',
                    style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    ),
                ),
                ],
            ),
            ),
        children: array.asMap().entries.map((entry) {
          final index = entry.key;
          var element = entry.value;
          element = _resolveValue(element);
          final elementPath = '$path[$index]';

          if (element is NrbfRecord && element is! MemberReferenceRecord) {
            return _buildRecordTree(element, elementPath, depth + 1);
          } else {
            return _buildValueTile('[$index]', element, depth + 1);
          }
        }).toList(),
      ),
    );
  }

  Widget _buildEditableField(ClassRecord record, String memberName, dynamic value, String path, int depth) {
    // Check if there's a preset for this path
    final fieldPreset = PresetManager.instance.findPresetForPath(path);
    
    if (fieldPreset != null && _canEdit(value)) {
      // Use PresetSelectorWidget
      return PresetSelectorWidget(
        parentRecord: record,
        memberName: memberName,
        currentValue: value,
        fieldPreset: fieldPreset,
        path: path,
        onValueChanged: (newValue) {
          try {
            // Parse the value according to type
            dynamic parsedValue;
            switch (fieldPreset.valueType) {
              case PresetValueType.intValue:
                parsedValue = int.parse(newValue);
                break;
              case PresetValueType.floatValue:
                parsedValue = double.parse(newValue);
                break;
              case PresetValueType.string:
                parsedValue = newValue;
                break;
              case PresetValueType.guid:
                // This shouldn't happen here (GUIDs handled separately)
                parsedValue = newValue;
                break;
            }
            
            record.setValue(memberName, parsedValue);
            setState(() {});
            _showSnackBar('Value updated', success: true);
          } catch (e) {
            _showSnackBar('Error updating value: $e', success: false);
          }
        },
      );
    }
    
    // Default editable field (existing code)
    final key = _nodeKeys.putIfAbsent(path, () => GlobalKey());
    final matchesSearch = _searchQuery.isNotEmpty &&
        (memberName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            _formatValue(value).toLowerCase().contains(_searchQuery.toLowerCase()));

    return Container(
      key: key,
      margin: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: matchesSearch
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: _getValueIcon(value),
        title: Row(
          children: [
            Expanded(child: Text(memberName)),
            if (PresetManager.instance.hasActivePreset)
              FavoriteToggle(path: path),
          ],
        ),
        subtitle: Text(_formatValue(value)),
        trailing: _canEdit(value)
            ? IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _showEditDialog(record, memberName, value),
              )
            : null,
        onTap: _canEdit(value) ? () => _showEditDialog(record, memberName, value) : null,
      ),
    );
  }

  // for arrays at root level
  Widget _buildArrayRecordTile(dynamic record, String path, int depth) {
    final nodePath = path;
    final key = _nodeKeys.putIfAbsent(path, () => GlobalKey());
    final isExpanded = _expandedNodes[nodePath] ?? false;
    final array = record.getArray() as List;

    return Card(
      margin: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4),
      child: ExpansionTile(
        key: Key('${nodePath}_$isExpanded'),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          setState(() => _expandedNodes[nodePath] = expanded);
        },
        leading: Icon(Icons.view_list, color: Theme.of(context).colorScheme.tertiary),
        title: Text('Array [${array.length} items]'),
        children: array.asMap().entries.map((entry) {
          final index = entry.key;
          var element = entry.value;
          element = _resolveValue(element);
          final elementPath = '$path[$index]';

          if (element is NrbfRecord && element is! MemberReferenceRecord) {
            return _buildRecordTree(element, elementPath, depth + 1);
          } else {
            return _buildValueTile('[$index]', element, depth + 1);
          }
        }).toList(),
      ),
    );
  }

  Widget _buildValueTile(String label, dynamic value, int depth) {
    return Container(
      margin: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4),
      child: ListTile(
        leading: _getValueIcon(value),
        title: Text(label),
        subtitle: Text(_formatValue(value)),
      ),
    );
  }

  Icon _getValueIcon(dynamic value) {
    final resolved = _resolveValue(value);
    
    if (resolved is String) return const Icon(Icons.text_fields, size: 20);
    if (resolved is bool) return Icon(resolved ? Icons.check_box : Icons.check_box_outline_blank, size: 20);
    if (resolved is num) return const Icon(Icons.numbers, size: 20);
    if (resolved == null) return const Icon(Icons.block, size: 20);
    if (resolved is ClassRecord && resolved.typeName == 'System.Guid') {
      return const Icon(Icons.fingerprint, size: 20);
    }
    return const Icon(Icons.data_object, size: 20);
  }

  bool _canEdit(dynamic value) {
    return value is String || value is num || value is bool;
  }

  bool _matchesSearch(dynamic node, String path) {
    if (_searchQuery.isEmpty) return false;

    final query = _searchQuery.toLowerCase();

    if (node is ClassRecord) {
      if (node.typeName.toLowerCase().contains(query)) return true;

      for (final memberName in node.memberNames) {
        if (memberName.toLowerCase().contains(query)) return true;
        final value = node.getValue(memberName);
        if (_formatValue(value).toLowerCase().contains(query)) return true;
      }
    }

    return false;
  }

  void _showEditDialog(ClassRecord record, String memberName, dynamic currentValue) {
    DebugLogger.log('Opening edit dialog for: $memberName', level: LogLevel.debug);
    DebugLogger.log('Current value: $currentValue (${currentValue.runtimeType})', level: LogLevel.debug);

    final controller = TextEditingController(text: currentValue.toString());
    final isNumber = currentValue is num;
    final isBool = currentValue is bool;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $memberName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isBool)
              SwitchListTile(
                title: const Text('Value'),
                value: currentValue as bool,
                onChanged: (value) {
                  DebugLogger.log('Setting $memberName = $value', level: LogLevel.info);
                  setState(() {
                    record.setValue(memberName, value);
                  });
                  Navigator.pop(context);
                  _showSnackBar('Updated $memberName to $value', success: true);
                },
              )
            else
              TextField(
                controller: controller,
                keyboardType: isNumber ? TextInputType.number : TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'New Value',
                  hintText: currentValue.toString(),
                ),
                autofocus: true,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              DebugLogger.log('Edit cancelled', level: LogLevel.debug);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          if (!isBool)
            FilledButton(
              onPressed: () {
                try {
                  dynamic newValue;
                  if (isNumber) {
                    if (currentValue is int) {
                      newValue = int.parse(controller.text);
                    } else if (currentValue is double) {
                      newValue = double.parse(controller.text);
                    } else {
                      newValue = num.parse(controller.text);
                    }
                  } else {
                    newValue = controller.text;
                  }

                  DebugLogger.log('Setting $memberName = $newValue', level: LogLevel.info);

                  setState(() {
                    record.setValue(memberName, newValue);
                  });

                  Navigator.pop(context);
                  _showSnackBar('Updated $memberName', success: true);
                } catch (e) {
                  DebugLogger.log('ERROR parsing value: $e', level: LogLevel.error);
                  _showSnackBar('Invalid value: $e', success: false);
                }
              },
              child: const Text('Save'),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Search Results (${_searchResults.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final result = _searchResults[index];
              final isSelected = result == _selectedSearchResult;

              return Card(
                color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
                child: ListTile(
                  leading: Icon(
                    result.type == 'Class'
                        ? Icons.class_
                        : result.type == 'Field'
                            ? Icons.label
                            : Icons.data_object,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    result.path,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Type: ${result.type}'),
                      Text(
                        'Value: ${result.value}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  onTap: () => _jumpToResult(result),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesPanel() {
    final favorites = PresetManager.instance.activePreset?.favorites ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.star, color: Colors.amber),
              const SizedBox(width: 8),
              Text(
                'Favorites (${favorites.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.star_border,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No favorites yet',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Click ★ on any field',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: favorites.length,
                  itemBuilder: (context, index) {
                    final favorite = favorites[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.star, color: Colors.amber, size: 20),
                        title: Text(favorite.label),
                        subtitle: Text(
                          favorite.path,
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            PresetManager.instance.toggleFavorite(favorite.path);
                            PresetManager.instance.saveCurrentPreset();
                          },
                        ),
                        onTap: () {
                          // Jump to this path using existing search result logic
                          final fakeResult = SearchResult(
                            path: favorite.path,
                            type: 'Favorite',
                            value: favorite.label,
                            record: _rootRecord!,
                          );
                          _jumpToResult(fakeResult);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPresetFieldsPanel() {
    final fieldPresets = PresetManager.instance.activePreset?.fieldPresets ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.playlist_play),
              const SizedBox(width: 8),
              Text(
                'Preset Fields (${fieldPresets.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: fieldPresets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.playlist_add,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No preset fields',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add fields in Preset Editor',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: fieldPresets.length,
                  itemBuilder: (context, index) {
                    final fieldPreset = fieldPresets[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        leading: const Icon(Icons.playlist_play, size: 20),
                        title: Text(fieldPreset.displayName),
                        subtitle: Text(
                          '${fieldPreset.pathPattern} (${fieldPreset.matchMode.name})\n'
                          '${fieldPreset.entries.length} options',
                          style: const TextStyle(fontSize: 11),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Search for fields matching this preset:',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: () => _searchForPresetFields(fieldPreset),
                                  icon: const Icon(Icons.search),
                                  label: const Text('Find All Matches'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _searchForPresetFields(FieldPreset fieldPreset) {
    // Search the entire tree for paths that match this preset
    DebugLogger.log('Searching for fields matching preset: ${fieldPreset.displayName}',
        level: LogLevel.info);
    
    setState(() {
      _searchQuery = fieldPreset.pathPattern;
      _searchController.text = fieldPreset.pathPattern;
    });
    
    _performSearch();
    
    _showSnackBar('Found ${_searchResults.length} matches for ${fieldPreset.displayName}',
        success: true);
  }

  void _jumpToResult(SearchResult result) {
    DebugLogger.log('=== JUMP TO RESULT ===', level: LogLevel.info);
    DebugLogger.log('Target Path: ${result.path}', level: LogLevel.info);

    setState(() {
      _selectedSearchResult = result;

      // 1. Force the Root Node to expand
      // The tree view uses empty string '' for the root key.
      _expandedNodes[''] = true;

      // 2. Expand all parents recursively
      String currentPath = result.path;
      _expandedNodes[currentPath] = true;

      while (currentPath.isNotEmpty) {
        final lastDot = currentPath.lastIndexOf('.');
        final lastBracket = currentPath.lastIndexOf('[');
        
        int cutIndex = -1;
        if (lastDot > lastBracket) {
          cutIndex = lastDot;
        } else if (lastBracket > -1) {
          cutIndex = lastBracket;
        }

        if (cutIndex <= 0) {
          // If we are at the top level item (e.g. "MiscData"), ensure it's marked
          if (currentPath.isNotEmpty) {
            _expandedNodes[currentPath] = true;
          }
          break; 
        }

        currentPath = currentPath.substring(0, cutIndex);
        if (currentPath.isNotEmpty) {
          _expandedNodes[currentPath] = true;
        }
      }
    });

    // 3. Wait for rebuild, then scroll
    // 300ms is usually enough for the UI to generate the new keys
    Future.delayed(const Duration(milliseconds: 300), () {
      _attemptScrollToPath(result.path);
    });
  }

  void _attemptScrollToPath(String targetPath) {
    // 1. Try exact match
    if (_scrollToKey(targetPath)) {
      DebugLogger.log('✓ Found and scrolled to exact target: $targetPath', level: LogLevel.info);
      return;
    }

    DebugLogger.log('⚠ Exact target UI not found. Attempting parents...', level: LogLevel.warning);

    // 2. Fallback: Walk up the path to find the nearest visible parent
    // This handles cases where the item is inside a list that isn't fully rendered
    String currentPath = targetPath;
    while (currentPath.isNotEmpty) {
       final lastDot = currentPath.lastIndexOf('.');
       final lastBracket = currentPath.lastIndexOf('[');
       int cutIndex = -1;
       if (lastDot > lastBracket) cutIndex = lastDot;
       else if (lastBracket > -1) cutIndex = lastBracket;

       if (cutIndex <= 0) break;

       currentPath = currentPath.substring(0, cutIndex);
       if (_scrollToKey(currentPath)) {
         DebugLogger.log('✓ Scrolled to parent container: $currentPath', level: LogLevel.info);
         return;
       }
    }
    
    // 3. Last Resort: Scroll to Root
    if (_scrollToKey('')) {
       DebugLogger.log('✓ Scrolled to Root', level: LogLevel.info);
       return;
    }

    DebugLogger.log('❌ Could not scroll to target or any of its parents.', level: LogLevel.error);
    _showSnackBar('Item expanded, but could not auto-scroll to it.', success: false);
  }

  bool _scrollToKey(String path) {
    final key = _nodeKeys[path];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      return true;
    }
    return false;
  }

  
  Widget _buildDebugConsole() {
    final logs = DebugLogger.logs;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor, width: 2),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.terminal),
              const SizedBox(width: 8),
              Text(
                'Debug Console',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Text(
                '${logs.length} logs',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),

        // Stats panel
        if (_totalRecords > 0)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Statistics',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text('Total: $_totalRecords'),
                      avatar: const Icon(Icons.analytics, size: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                    ..._recordTypeStats.entries.take(3).map((e) => Chip(
                          label: Text('${e.key}: ${e.value}'),
                          visualDensity: VisualDensity.compact,
                        )),
                  ],
                ),
              ],
            ),
          ),

        // Logs
        Expanded(
          child: logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No logs yet',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  reverse: true, // Show newest logs first
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[logs.length - 1 - index];
                    return _buildLogEntry(log);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLogEntry(LogEntry log) {
    Color getColor(LogLevel level) {
      switch (level) {
        case LogLevel.debug:
          return Colors.grey;
        case LogLevel.info:
          return Colors.blue;
        case LogLevel.warning:
          return Colors.orange;
        case LogLevel.error:
          return Colors.red;
      }
    }

    IconData getIcon(LogLevel level) {
      switch (level) {
        case LogLevel.debug:
          return Icons.bug_report;
        case LogLevel.info:
          return Icons.info;
        case LogLevel.warning:
          return Icons.warning;
        case LogLevel.error:
          return Icons.error;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              getIcon(log.level),
              size: 16,
              color: getColor(log.level),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.message,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: getColor(log.level),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${log.timestamp.hour.toString().padLeft(2, '0')}:'
                    '${log.timestamp.minute.toString().padLeft(2, '0')}:'
                    '${log.timestamp.second.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SEARCH RESULT CLASS
// ============================================================================

class SearchResult {
  final String path;
  final String type;
  final String value;
  final NrbfRecord record;

  SearchResult({
    required this.path,
    required this.type,
    required this.value,
    required this.record,
  });
}