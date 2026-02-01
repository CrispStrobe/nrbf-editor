// lib/diff/diff_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../main.dart' show DebugLogger, LogLevel;
import '../nrbf/nrbf.dart';
import '../presets/preset_manager.dart';
import '../presets/preset_models.dart';
import 'diff_models.dart';
import 'diff_engine.dart';

// ============================================================================
// DIFF SCREEN - COMPARISON UI
// ============================================================================

class DiffScreen extends StatefulWidget {
  const DiffScreen({super.key});

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  Uint8List? _beforeBytes;
  Uint8List? _afterBytes;
  String? _beforeFileName;
  String? _afterFileName;
  NrbfRecord? _beforeRecord;
  NrbfRecord? _afterRecord;
  NrbfDecoder? _beforeDecoder;
  NrbfDecoder? _afterDecoder; 
  DiffResult? _diffResult;
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  ChangeType? _filterType;

  Future<void> _pickFile(bool isBefore) async {
    try {
      setState(() => _isLoading = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.first.bytes == null) {
        setState(() => _isLoading = false);
        return;
      }

      final bytes = result.files.first.bytes!;
      final fileName = result.files.first.name;

      DebugLogger.log('Loading ${isBefore ? "BEFORE" : "AFTER"} file: $fileName',
          level: LogLevel.info);

      // Decode NRBF
      final decoder = NrbfDecoder(bytes);
      final record = decoder.decode();

      setState(() {
        if (isBefore) {
          _beforeBytes = bytes;
          _beforeFileName = fileName;
          _beforeRecord = record;
          _beforeDecoder = decoder;
        } else {
          _afterBytes = bytes;
          _afterFileName = fileName;
          _afterRecord = record;
          _afterDecoder = decoder;
        }
        _isLoading = false;
        _error = null;
      });

      // Auto-compare if both loaded
      if (_beforeRecord != null && _afterRecord != null) {
        _runComparison();
      }
    } catch (e, stackTrace) {
      DebugLogger.log('Error loading file: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);

      setState(() {
        _error = 'Error loading file: $e';
        _isLoading = false;
      });
    }
  }

  void _runComparison() {
    if (_beforeRecord == null || _afterRecord == null) return;

    setState(() => _isLoading = true);

    try {
      DebugLogger.log('Running comparison...', level: LogLevel.info);
      
      // Pass decoders for reference resolution
      final result = DiffEngine.compare(
        _beforeRecord!,
        _afterRecord!,
        beforeDecoder: _beforeDecoder,
        afterDecoder: _afterDecoder,
      );

      setState(() {
        _diffResult = result;
        _isLoading = false;
      });

      _showSnackBar('Comparison complete: ${result.changes.length} changes found',
          success: true);
    } catch (e, stackTrace) {
      DebugLogger.log('Error during comparison: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);

      setState(() {
        _error = 'Comparison failed: $e';
        _isLoading = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _beforeBytes = null;
      _afterBytes = null;
      _beforeFileName = null;
      _afterFileName = null;
      _beforeRecord = null;
      _afterRecord = null;
      _diffResult = null;
      _error = null;
      _searchQuery = '';
      _filterType = null;
    });
  }

  List<FieldChange> _getFilteredChanges() {
    if (_diffResult == null) return [];

    var changes = _diffResult!.changes;

    // Filter by type
    if (_filterType != null) {
      changes = changes.where((c) => c.changeType == _filterType).toList();
    }

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      changes = changes.where((c) {
        return c.path.toLowerCase().contains(query) ||
            c.fieldName.toLowerCase().contains(query) ||
            (c.oldValue?.toLowerCase().contains(query) ?? false) ||
            (c.newValue?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    return changes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Comparison'),
        actions: [
          if (_diffResult != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset',
              onPressed: _reset,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _diffResult != null
                  ? _buildResults()
                  : _buildFilePickers(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePickers() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.compare_arrows,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Compare Two Files',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Load two NRBF save files to see what changed',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: _buildFileCard(
                    title: 'BEFORE',
                    fileName: _beforeFileName,
                    onPick: () => _pickFile(true),
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildFileCard(
                    title: 'AFTER',
                    fileName: _afterFileName,
                    onPick: () => _pickFile(false),
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            if (_beforeRecord != null && _afterRecord != null) ...[
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _runComparison,
                icon: const Icon(Icons.analytics),
                label: const Text('Run Comparison'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileCard({
    required String title,
    String? fileName,
    required VoidCallback onPick,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Icon(
              fileName != null ? Icons.check_circle : Icons.upload_file,
              size: 48,
              color: fileName != null ? Colors.green : color,
            ),
            const SizedBox(height: 16),
            if (fileName != null)
              Text(
                fileName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            else
              const Text('No file selected'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open),
              label: Text(fileName != null ? 'Change' : 'Select File'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final filteredChanges = _getFilteredChanges();

    return Column(
      children: [
        // Summary header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.analytics),
                  const SizedBox(width: 8),
                  Text(
                    'Comparison Results',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'BEFORE: ${_beforeFileName ?? "unknown"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'AFTER: ${_afterFileName ?? "unknown"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.all_inclusive, size: 16),
                    label: Text('Total: ${_diffResult!.changes.length}'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.edit, size: 16),
                    label: Text('Modified: ${_diffResult!.modifiedCount}'),
                    backgroundColor: Colors.orange.withOpacity(0.2),
                  ),
                  Chip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text('Added: ${_diffResult!.addedCount}'),
                    backgroundColor: Colors.green.withOpacity(0.2),
                  ),
                  Chip(
                    avatar: const Icon(Icons.remove, size: 16),
                    label: Text('Removed: ${_diffResult!.removedCount}'),
                    backgroundColor: Colors.red.withOpacity(0.2),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Filter toolbar
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search changes...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<ChangeType?>(
                segments: const [
                  ButtonSegment(
                    value: null,
                    label: Text('All'),
                    icon: Icon(Icons.all_inclusive),
                  ),
                  ButtonSegment(
                    value: ChangeType.modified,
                    label: Text('Modified'),
                    icon: Icon(Icons.edit),
                  ),
                  ButtonSegment(
                    value: ChangeType.added,
                    label: Text('Added'),
                    icon: Icon(Icons.add),
                  ),
                  ButtonSegment(
                    value: ChangeType.removed,
                    label: Text('Removed'),
                    icon: Icon(Icons.remove),
                  ),
                ],
                selected: {_filterType},
                onSelectionChanged: (Set<ChangeType?> selection) {
                  setState(() => _filterType = selection.first);
                },
              ),
            ],
          ),
        ),

        // Changes list
        Expanded(
          child: filteredChanges.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty && _filterType == null
                            ? 'No changes detected'
                            : 'No matching changes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filteredChanges.length,
                  itemBuilder: (context, index) {
                    return _buildChangeCard(filteredChanges[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildChangeCard(FieldChange change) {
    Color getColor() {
      switch (change.changeType) {
        case ChangeType.modified:
          return Colors.orange;
        case ChangeType.added:
          return Colors.green;
        case ChangeType.removed:
          return Colors.red;
      }
    }

    IconData getIcon() {
      switch (change.changeType) {
        case ChangeType.modified:
          return Icons.edit;
        case ChangeType.added:
          return Icons.add_circle;
        case ChangeType.removed:
          return Icons.remove_circle;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(getIcon(), color: getColor()),
        title: Text(
          change.fieldName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              change.path,
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            if (change.changeType == ChangeType.modified)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      change.displayOldValue,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        decoration: TextDecoration.lineThrough,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_forward, size: 16),
                  Expanded(
                    child: Text(
                      change.displayNewValue,
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            else if (change.changeType == ChangeType.added)
              Text(
                '+ ${change.displayNewValue}',
                style: TextStyle(color: Colors.green.shade700),
              )
            else
              Text(
                '- ${change.displayOldValue}',
                style: TextStyle(color: Colors.red.shade700),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Full values
                if (change.changeType == ChangeType.modified) ...[
                  _buildValueDisplay('Before', change.displayOldValue, Colors.red),
                  const SizedBox(height: 12),
                  _buildValueDisplay('After', change.displayNewValue, Colors.green),
                ] else if (change.changeType == ChangeType.added)
                  _buildValueDisplay('Value', change.displayNewValue, Colors.green)
                else
                  _buildValueDisplay('Value', change.displayOldValue, Colors.red),

                const Divider(height: 24),

                // Action buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _addToFavorites(change),
                      icon: const Icon(Icons.star),
                      label: const Text('Add to Favorites'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _quickAddToPreset(change),
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Quick Add to Preset'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copyPath(change.path),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy Path'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copyValue(change),
                      icon: const Icon(Icons.content_copy),
                      label: const Text('Copy Value'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueDisplay(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            border: Border.all(color: color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  void _addToFavorites(FieldChange change) {
    if (!PresetManager.instance.hasActivePreset) {
      _showSnackBar('No active preset. Please select or create a preset first.',
          success: false);
      return;
    }

    final labelController = TextEditingController(text: change.fieldName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Favorites'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Path: ${change.path}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Label',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
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
              final label = labelController.text.trim();
              if (label.isNotEmpty) {
                PresetManager.instance.toggleFavorite(change.path, label: label);
                PresetManager.instance.saveCurrentPreset();
                Navigator.pop(context);
                _showSnackBar('Added to favorites', success: true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _quickAddToPreset(FieldChange change) {
    if (!PresetManager.instance.hasActivePreset) {
      _showSnackBar('No active preset. Please select or create a preset first.',
          success: false);
      return;
    }

    // Show dialog to either add to existing field preset or create new one
    showDialog(
      context: context,
      builder: (context) => _QuickAddDialog(change: change),
    );
  }

  void _copyPath(String path) {
    Clipboard.setData(ClipboardData(text: path));
    _showSnackBar('Path copied to clipboard', success: true);
  }

  void _copyValue(FieldChange change) {
    final value = change.changeType == ChangeType.removed
        ? change.displayOldValue
        : change.displayNewValue;
    Clipboard.setData(ClipboardData(text: value));
    _showSnackBar('Value copied to clipboard', success: true);
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
      ),
    );
  }
}

// ============================================================================
// QUICK ADD DIALOG
// ============================================================================

class _QuickAddDialog extends StatefulWidget {
  final FieldChange change;

  const _QuickAddDialog({required this.change});

  @override
  State<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<_QuickAddDialog> {
  FieldPreset? _selectedFieldPreset;
  bool _createNew = false;

  final _fieldPresetIdController = TextEditingController();
  final _fieldPresetNameController = TextEditingController();
  final _pathPatternController = TextEditingController();
  PathMatchMode _matchMode = PathMatchMode.fieldName;
  PresetValueType _valueType = PresetValueType.string;

  final _entryIdController = TextEditingController();
  final _entryNameController = TextEditingController();
  final _tagsController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Try to find existing field preset for this path
    _selectedFieldPreset =
        PresetManager.instance.findPresetForPath(widget.change.path);

    // Pre-fill form
    _fieldPresetNameController.text = widget.change.fieldName;
    _pathPatternController.text = widget.change.fieldName;
    _entryNameController.text = 'Changed Value';

    // Detect value type
    _valueType = _detectValueType(widget.change.newValue);
  }

  PresetValueType _detectValueType(String? value) {
    if (value == null) return PresetValueType.string;

    // Check if it's a GUID
    final guidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false);
    if (guidPattern.hasMatch(value)) return PresetValueType.guid;

    // Check if it's a number
    if (int.tryParse(value) != null) return PresetValueType.intValue;
    if (double.tryParse(value) != null) return PresetValueType.floatValue;

    return PresetValueType.string;
  }

  @override
  Widget build(BuildContext context) {
    final activePreset = PresetManager.instance.activePreset!;

    return AlertDialog(
      title: const Text('Add to Preset'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Select existing or create new
              if (activePreset.fieldPresets.isNotEmpty && !_createNew) ...[
                const Text('Select Field Preset:'),
                const SizedBox(height: 8),
                DropdownButtonFormField<FieldPreset?>(
                  value: _selectedFieldPreset,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('-- Create New --'),
                    ),
                    ...activePreset.fieldPresets.map((fp) {
                      return DropdownMenuItem(
                        value: fp,
                        child: Text(fp.displayName),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedFieldPreset = value;
                      _createNew = value == null;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Create new field preset form
              if (_createNew || activePreset.fieldPresets.isEmpty) ...[
                const Text(
                  'New Field Preset',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _fieldPresetIdController,
                  decoration: const InputDecoration(
                    labelText: 'Preset ID',
                    hintText: 'unique_id',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _fieldPresetNameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pathPatternController,
                  decoration: const InputDecoration(
                    labelText: 'Path Pattern',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<PathMatchMode>(
                  value: _matchMode,
                  decoration: const InputDecoration(
                    labelText: 'Match Mode',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: PathMatchMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(mode.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _matchMode = value);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<PresetValueType>(
                  value: _valueType,
                  decoration: const InputDecoration(
                    labelText: 'Value Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: PresetValueType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _valueType = value);
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Entry details
              const Text(
                'Preset Entry',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _entryIdController,
                decoration: const InputDecoration(
                  labelText: 'Entry ID',
                  hintText: 'auto-generated if empty',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _entryNameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma-separated)',
                  hintText: 'optional',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Value:', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      widget.change.newValue ?? 'N/A',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _addToPreset,
          child: const Text('Add'),
        ),
      ],
    );
  }

  Future<void> _addToPreset() async {
    try {
      final activePreset = PresetManager.instance.activePreset!;
      FieldPreset targetPreset;

      // Create new field preset if needed
      if (_createNew || activePreset.fieldPresets.isEmpty) {
        final id = _fieldPresetIdController.text.trim().isEmpty
            ? 'fp_${DateTime.now().millisecondsSinceEpoch}'
            : _fieldPresetIdController.text.trim();
        final name = _fieldPresetNameController.text.trim();
        final pattern = _pathPatternController.text.trim();

        if (name.isEmpty || pattern.isEmpty) {
          _showError('Please fill in all required fields');
          return;
        }

        targetPreset = FieldPreset(
          id: id,
          displayName: name,
          pathPattern: pattern,
          matchMode: _matchMode,
          valueType: _valueType,
        );

        await PresetManager.instance.addFieldPreset(
          activePreset.gameTypeId,
          targetPreset,
        );

        // Reload to get the updated preset
        final reloaded = PresetManager.instance.presets.firstWhere(
          (p) => p.gameTypeId == activePreset.gameTypeId,
        );
        targetPreset = reloaded.fieldPresets.firstWhere((fp) => fp.id == id);
      } else {
        targetPreset = _selectedFieldPreset!;
      }

      // Add entry
      final entryId = _entryIdController.text.trim().isEmpty
          ? 'entry_${DateTime.now().millisecondsSinceEpoch}'
          : _entryIdController.text.trim();
      final entryName = _entryNameController.text.trim();
      final tags = _tagsController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (entryName.isEmpty) {
        _showError('Please provide an entry name');
        return;
      }

      final entry = PresetEntry(
        id: entryId,
        value: widget.change.newValue ?? '',
        displayName: entryName,
        tags: tags,
      );

      await PresetManager.instance.addEntry(
        activePreset.gameTypeId,
        targetPreset.id,
        entry,
      );

      Navigator.pop(context);
      _showSuccess('Added to preset successfully');
    } catch (e) {
      _showError('Error: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }
}