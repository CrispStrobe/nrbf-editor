// lib/presets/preset_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../main.dart' show DebugLogger, LogLevel;
import 'preset_models.dart';
import 'preset_manager.dart';
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as io;
import 'package:file_selector/file_selector.dart' as selector;

// ============================================================================
// PRESET EDITOR SCREEN - FULL CRUD UI
// ============================================================================

enum _EditorLevel {
  list,
  detail,
  fieldEditor,
}

class PresetEditorScreen extends StatefulWidget {
  const PresetEditorScreen({super.key});

  @override
  State<PresetEditorScreen> createState() => _PresetEditorScreenState();
}

class _PresetEditorScreenState extends State<PresetEditorScreen> {
  _EditorLevel _currentLevel = _EditorLevel.list;
  GamePreset? _selectedPreset;
  FieldPreset? _selectedFieldPreset;

  @override
  void initState() {
    super.initState();
    PresetManager.instance.addListener(_onPresetChange);
  }

  @override
  void dispose() {
    PresetManager.instance.removeListener(_onPresetChange);
    super.dispose();
  }

  void _onPresetChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _navigateToDetail(GamePreset preset) {
    setState(() {
      _selectedPreset = preset;
      _currentLevel = _EditorLevel.detail;
    });
  }

  void _navigateToFieldEditor(FieldPreset fieldPreset) {
    setState(() {
      _selectedFieldPreset = fieldPreset;
      _currentLevel = _EditorLevel.fieldEditor;
    });
  }

  void _navigateBack() {
    setState(() {
      if (_currentLevel == _EditorLevel.fieldEditor) {
        _currentLevel = _EditorLevel.detail;
        _selectedFieldPreset = null;
      } else if (_currentLevel == _EditorLevel.detail) {
        _currentLevel = _EditorLevel.list;
        _selectedPreset = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _currentLevel != _EditorLevel.list
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateBack,
              )
            : null,
        title: Text(_getTitle()),
        actions: _buildAppBarActions(),
      ),
      body: _buildBody(),
      floatingActionButton: _buildFAB(),
    );
  }

  String _getTitle() {
    switch (_currentLevel) {
      case _EditorLevel.list:
        return 'Preset Manager';
      case _EditorLevel.detail:
        return _selectedPreset?.displayName ?? 'Preset Details';
      case _EditorLevel.fieldEditor:
        return _selectedFieldPreset?.displayName ?? 'Field Editor';
    }
  }

  List<Widget> _buildAppBarActions() {
    if (_currentLevel == _EditorLevel.list) {
      return [
        IconButton(
          icon: const Icon(Icons.upload_file),
          tooltip: 'Import Preset',
          onPressed: _importPreset,
        ),
      ];
    }
    return [];
  }

  Widget _buildBody() {
    switch (_currentLevel) {
      case _EditorLevel.list:
        return _buildPresetList();
      case _EditorLevel.detail:
        return _buildPresetDetail();
      case _EditorLevel.fieldEditor:
        return _buildFieldPresetEditor();
    }
  }

  Widget? _buildFAB() {
    switch (_currentLevel) {
      case _EditorLevel.list:
        return FloatingActionButton.extended(
          onPressed: _createNewPreset,
          icon: const Icon(Icons.add),
          label: const Text('New Preset'),
        );
      case _EditorLevel.detail:
        return FloatingActionButton.extended(
          onPressed: _addFieldPreset,
          icon: const Icon(Icons.add),
          label: const Text('Add Field Preset'),
        );
      case _EditorLevel.fieldEditor:
        return FloatingActionButton.extended(
          onPressed: _addEntry,
          icon: const Icon(Icons.add),
          label: const Text('Add Entry'),
        );
    }
  }

  // ==========================================================================
  // LEVEL 1: PRESET LIST
  // ==========================================================================

  Widget _buildPresetList() {
    final presets = PresetManager.instance.presets;

    if (presets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No presets available',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new preset or import one',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final preset = presets[index];
        final isActive =
            PresetManager.instance.activePreset?.gameTypeId == preset.gameTypeId;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: Icon(
              Icons.games,
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 32,
            ),
            title: Text(
              preset.displayName,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${preset.gameTypeId}'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(
                      label: Text('${preset.fieldPresets.length} fields'),
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.list, size: 16),
                    ),
                    Chip(
                      label: Text('${preset.favorites.length} favorites'),
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.star, size: 16),
                    ),
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) => _handlePresetAction(value, preset),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.download),
                      SizedBox(width: 8),
                      Text('Export JSON'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () => _navigateToDetail(preset),
          ),
        );
      },
    );
  }

  void _handlePresetAction(String action, GamePreset preset) {
    switch (action) {
      case 'edit':
        _navigateToDetail(preset);
        break;
      case 'export':
        _exportPreset(preset);
        break;
      case 'delete':
        _confirmDeletePreset(preset);
        break;
    }
  }

  void _createNewPreset() {
    final gameTypeIdController = TextEditingController();
    final displayNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Preset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: gameTypeIdController,
              decoration: const InputDecoration(
                labelText: 'Game Type ID *',
                hintText: 'e.g., my_game',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display Name *',
                hintText: 'e.g., My Game',
                border: OutlineInputBorder(),
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
            onPressed: () async {
              final gameTypeId = gameTypeIdController.text.trim();
              final displayName = displayNameController.text.trim();

              if (gameTypeId.isEmpty || displayName.isEmpty) {
                _showSnackBar('Please fill in all fields', success: false);
                return;
              }

              try {
                final newPreset = GamePreset(
                  gameTypeId: gameTypeId,
                  displayName: displayName,
                );

                await PresetManager.instance.createPreset(newPreset);
                Navigator.pop(context);
                _showSnackBar('Preset created successfully', success: true);
              } catch (e) {
                _showSnackBar('Error creating preset: $e', success: false);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _importPreset() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.first.bytes == null) {
        return;
      }

      final bytes = result.files.first.bytes!;
      await PresetManager.instance.importPreset(bytes);
      _showSnackBar('Preset imported successfully', success: true);
    } catch (e) {
      DebugLogger.log('Error importing preset: $e', level: LogLevel.error);
      _showSnackBar('Error importing preset: $e', success: false);
    }
  }

  Future<void> _exportPreset(GamePreset preset) async {
    try {
      final bytes = await PresetManager.instance.exportPreset(preset.gameTypeId);
      final fileName = '${preset.gameTypeId}.json';

      if (kIsWeb) {
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = fileName;
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
          suggestedName: fileName,
          acceptedTypeGroups: [typeGroup],
        );

        if (path != null) {
          final file = io.File(path.path);
          await file.writeAsBytes(bytes);
        }
      }

      _showSnackBar('Preset exported successfully', success: true);
    } catch (e) {
      DebugLogger.log('Error exporting preset: $e', level: LogLevel.error);
      _showSnackBar('Error exporting preset: $e', success: false);
    }
  }

  void _confirmDeletePreset(GamePreset preset) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Preset'),
        content: Text('Are you sure you want to delete "${preset.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              try {
                await PresetManager.instance.deletePreset(preset.gameTypeId);
                Navigator.pop(context);
                _showSnackBar('Preset deleted', success: true);
              } catch (e) {
                Navigator.pop(context);
                _showSnackBar('Error deleting preset: $e', success: false);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // LEVEL 2: PRESET DETAIL
  // ==========================================================================

  Widget _buildPresetDetail() {
    if (_selectedPreset == null) {
      return const Center(child: Text('No preset selected'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Metadata Section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Metadata',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _buildEditableTextField(
                  'Display Name',
                  _selectedPreset!.displayName,
                  (value) => _updatePresetMetadata(displayName: value),
                ),
                const SizedBox(height: 12),
                _buildEditableTextField(
                  'Game Type ID',
                  _selectedPreset!.gameTypeId,
                  (value) => _updatePresetMetadata(gameTypeId: value),
                  readOnly: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Detection Hints Section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Detection Hints',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _addDetectionHint,
                      tooltip: 'Add hint',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_selectedPreset!.detectionHints.isEmpty)
                  const Text('No detection hints configured')
                else
                  ..._selectedPreset!.detectionHints.map(_buildDetectionHint),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Field Presets Section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Field Presets',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (_selectedPreset!.fieldPresets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No field presets configured'),
                  )
                else
                  ..._selectedPreset!.fieldPresets.map(_buildFieldPresetTile),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Favorites Section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Favorites',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _addFavorite,
                      tooltip: 'Add favorite',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_selectedPreset!.favorites.isEmpty)
                  const Text('No favorites')
                else
                  ..._selectedPreset!.favorites.map(_buildFavoriteTile),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditableTextField(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool readOnly = false,
  }) {
    final controller = TextEditingController(text: value);

    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: readOnly
            ? null
            : IconButton(
                icon: const Icon(Icons.check),
                onPressed: () => onChanged(controller.text),
              ),
      ),
      readOnly: readOnly,
      onSubmitted: readOnly ? null : onChanged,
    );
  }

  void _updatePresetMetadata({String? displayName, String? gameTypeId}) async {
    try {
      final updated = _selectedPreset!.copyWith(
        displayName: displayName,
        gameTypeId: gameTypeId,
      );

      await PresetManager.instance.updatePreset(updated);
      setState(() => _selectedPreset = updated);
      _showSnackBar('Preset updated', success: true);
    } catch (e) {
      _showSnackBar('Error updating preset: $e', success: false);
    }
  }

  Widget _buildDetectionHint(DetectionHint hint) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.search, size: 20),
                const SizedBox(width: 8),
                const Text('Detection Hint'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: () => _removeDetectionHint(hint),
                ),
              ],
            ),
            if (hint.classNameFragments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: hint.classNameFragments.map((fragment) {
                  return Chip(
                    label: Text('Class: $fragment'),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
            if (hint.libraryNameFragments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: hint.libraryNameFragments.map((fragment) {
                  return Chip(
                    label: Text('Library: $fragment'),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _addDetectionHint() {
    final classController = TextEditingController();
    final libraryController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Detection Hint'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: classController,
              decoration: const InputDecoration(
                labelText: 'Class Name Fragments',
                hintText: 'Comma-separated',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: libraryController,
              decoration: const InputDecoration(
                labelText: 'Library Name Fragments',
                hintText: 'Comma-separated',
                border: OutlineInputBorder(),
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
            onPressed: () async {
              final classFragments = classController.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();

              final libraryFragments = libraryController.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();

              if (classFragments.isEmpty && libraryFragments.isEmpty) {
                _showSnackBar('Please enter at least one fragment', success: false);
                return;
              }

              try {
                final hints = List<DetectionHint>.from(_selectedPreset!.detectionHints);
                hints.add(DetectionHint(
                  classNameFragments: classFragments,
                  libraryNameFragments: libraryFragments,
                ));

                final updated = _selectedPreset!.copyWith(detectionHints: hints);
                await PresetManager.instance.updatePreset(updated);
                setState(() => _selectedPreset = updated);

                Navigator.pop(context);
                _showSnackBar('Detection hint added', success: true);
              } catch (e) {
                _showSnackBar('Error adding hint: $e', success: false);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removeDetectionHint(DetectionHint hint) async {
    try {
      final hints = List<DetectionHint>.from(_selectedPreset!.detectionHints);
      hints.remove(hint);

      final updated = _selectedPreset!.copyWith(detectionHints: hints);
      await PresetManager.instance.updatePreset(updated);
      setState(() => _selectedPreset = updated);

      _showSnackBar('Detection hint removed', success: true);
    } catch (e) {
      _showSnackBar('Error removing hint: $e', success: false);
    }
  }

  Widget _buildFieldPresetTile(FieldPreset fieldPreset) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.playlist_play),
        title: Text(fieldPreset.displayName),
        subtitle: Text(
          '${fieldPreset.pathPattern} (${fieldPreset.matchMode.name})\n'
          '${fieldPreset.entries.length} entries',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleFieldPresetAction(value, fieldPreset),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _navigateToFieldEditor(fieldPreset),
      ),
    );
  }

  void _handleFieldPresetAction(String action, FieldPreset fieldPreset) {
    switch (action) {
      case 'edit':
        _navigateToFieldEditor(fieldPreset);
        break;
      case 'delete':
        _confirmDeleteFieldPreset(fieldPreset);
        break;
    }
  }

  void _addFieldPreset() {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final patternController = TextEditingController();
    PathMatchMode matchMode = PathMatchMode.fieldName;
    PresetValueType valueType = PresetValueType.string;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Field Preset'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: idController,
                  decoration: const InputDecoration(
                    labelText: 'ID *',
                    hintText: 'unique_id',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: patternController,
                  decoration: const InputDecoration(
                    labelText: 'Path Pattern *',
                    hintText: 'e.g., VehicleID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PathMatchMode>(
                  value: matchMode,
                  decoration: const InputDecoration(
                    labelText: 'Match Mode',
                    border: OutlineInputBorder(),
                  ),
                  items: PathMatchMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(mode.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => matchMode = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PresetValueType>(
                  value: valueType,
                  decoration: const InputDecoration(
                    labelText: 'Value Type',
                    border: OutlineInputBorder(),
                  ),
                  items: PresetValueType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => valueType = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final id = idController.text.trim();
                final name = nameController.text.trim();
                final pattern = patternController.text.trim();

                if (id.isEmpty || name.isEmpty || pattern.isEmpty) {
                  _showSnackBar('Please fill in all fields', success: false);
                  return;
                }

                try {
                  final newFieldPreset = FieldPreset(
                    id: id,
                    displayName: name,
                    pathPattern: pattern,
                    matchMode: matchMode,
                    valueType: valueType,
                  );

                  await PresetManager.instance.addFieldPreset(
                    _selectedPreset!.gameTypeId,
                    newFieldPreset,
                  );

                  // Reload selected preset
                  final updated = PresetManager.instance.presets.firstWhere(
                    (p) => p.gameTypeId == _selectedPreset!.gameTypeId,
                  );
                  setState(() => _selectedPreset = updated);

                  Navigator.pop(context);
                  _showSnackBar('Field preset added', success: true);
                } catch (e) {
                  _showSnackBar('Error adding field preset: $e', success: false);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteFieldPreset(FieldPreset fieldPreset) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Field Preset'),
        content: Text('Delete "${fieldPreset.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              try {
                await PresetManager.instance.removeFieldPreset(
                  _selectedPreset!.gameTypeId,
                  fieldPreset.id,
                );

                final updated = PresetManager.instance.presets.firstWhere(
                  (p) => p.gameTypeId == _selectedPreset!.gameTypeId,
                );
                setState(() => _selectedPreset = updated);

                Navigator.pop(context);
                _showSnackBar('Field preset deleted', success: true);
              } catch (e) {
                Navigator.pop(context);
                _showSnackBar('Error deleting: $e', success: false);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteTile(FavoriteEntry favorite) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.star, color: Colors.amber),
        title: Text(favorite.label),
        subtitle: Text(
          favorite.path,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, size: 20),
          onPressed: () => _removeFavorite(favorite),
        ),
      ),
    );
  }

  void _addFavorite() {
    final pathController = TextEditingController();
    final labelController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Favorite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                labelText: 'Path *',
                hintText: 'e.g., VehiclesData.Vehicles[0].VehicleID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Label *',
                border: OutlineInputBorder(),
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
            onPressed: () async {
              final path = pathController.text.trim();
              final label = labelController.text.trim();

              if (path.isEmpty || label.isEmpty) {
                _showSnackBar('Please fill in all fields', success: false);
                return;
              }

              try {
                final favorites = List<FavoriteEntry>.from(_selectedPreset!.favorites);
                favorites.add(FavoriteEntry(path: path, label: label));

                final updated = _selectedPreset!.copyWith(favorites: favorites);
                await PresetManager.instance.updatePreset(updated);
                setState(() => _selectedPreset = updated);

                Navigator.pop(context);
                _showSnackBar('Favorite added', success: true);
              } catch (e) {
                _showSnackBar('Error adding favorite: $e', success: false);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removeFavorite(FavoriteEntry favorite) async {
    try {
      final favorites = List<FavoriteEntry>.from(_selectedPreset!.favorites);
      favorites.remove(favorite);

      final updated = _selectedPreset!.copyWith(favorites: favorites);
      await PresetManager.instance.updatePreset(updated);
      setState(() => _selectedPreset = updated);

      _showSnackBar('Favorite removed', success: true);
    } catch (e) {
      _showSnackBar('Error removing favorite: $e', success: false);
    }
  }

  // ==========================================================================
  // LEVEL 3: FIELD PRESET ENTRY EDITOR
  // ==========================================================================

  Widget _buildFieldPresetEditor() {
    if (_selectedFieldPreset == null) {
      return const Center(child: Text('No field preset selected'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Metadata
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Field Preset Settings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _buildEditableTextField(
                  'Display Name',
                  _selectedFieldPreset!.displayName,
                  (value) => _updateFieldPresetMetadata(displayName: value),
                ),
                const SizedBox(height: 12),
                _buildEditableTextField(
                  'Path Pattern',
                  _selectedFieldPreset!.pathPattern,
                  (value) => _updateFieldPresetMetadata(pathPattern: value),
                ),
                const SizedBox(height: 12),
                Text(
                  'Match Mode: ${_selectedFieldPreset!.matchMode.name}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Value Type: ${_selectedFieldPreset!.valueType.name}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Entries
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Entries (${_selectedFieldPreset!.entries.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.upload_file),
                      tooltip: 'Import entries',
                      onPressed: _importEntries,
                    ),
                    IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: 'Export entries',
                      onPressed: _exportEntries,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_selectedFieldPreset!.entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No entries yet'),
                  )
                else
                  ..._selectedFieldPreset!.entries.map(_buildEntryTile),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _updateFieldPresetMetadata({
    String? displayName,
    String? pathPattern,
  }) async {
    try {
      final updated = _selectedFieldPreset!.copyWith(
        displayName: displayName,
        pathPattern: pathPattern,
      );

      await PresetManager.instance.updateFieldPreset(
        _selectedPreset!.gameTypeId,
        updated,
      );

      // Reload
      final reloadedPreset = PresetManager.instance.presets.firstWhere(
        (p) => p.gameTypeId == _selectedPreset!.gameTypeId,
      );
      final reloadedFieldPreset = reloadedPreset.fieldPresets.firstWhere(
        (fp) => fp.id == _selectedFieldPreset!.id,
      );

      setState(() {
        _selectedPreset = reloadedPreset;
        _selectedFieldPreset = reloadedFieldPreset;
      });

      _showSnackBar('Field preset updated', success: true);
    } catch (e) {
      _showSnackBar('Error updating: $e', success: false);
    }
  }

  Widget _buildEntryTile(PresetEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.label),
        title: Text(entry.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: entry.tags.map((tag) {
                  return Chip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () => _editEntry(entry),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () => _deleteEntry(entry),
            ),
          ],
        ),
      ),
    );
  }

  void _addEntry() {
    final idController = TextEditingController();
    final valueController = TextEditingController();
    final nameController = TextEditingController();
    final tagsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Entry'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                decoration: const InputDecoration(
                  labelText: 'ID *',
                  hintText: 'unique_id',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueController,
                decoration: const InputDecoration(
                  labelText: 'Value *',
                  hintText: 'The actual value',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma-separated)',
                  hintText: 'tag1, tag2, tag3',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final id = idController.text.trim();
              final value = valueController.text.trim();
              final name = nameController.text.trim();
              final tags = tagsController.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();

              if (id.isEmpty || value.isEmpty || name.isEmpty) {
                _showSnackBar('Please fill in required fields', success: false);
                return;
              }

              try {
                final newEntry = PresetEntry(
                  id: id,
                  value: value,
                  displayName: name,
                  tags: tags,
                );

                await PresetManager.instance.addEntry(
                  _selectedPreset!.gameTypeId,
                  _selectedFieldPreset!.id,
                  newEntry,
                );

                // Reload
                final reloadedPreset = PresetManager.instance.presets.firstWhere(
                  (p) => p.gameTypeId == _selectedPreset!.gameTypeId,
                );
                final reloadedFieldPreset = reloadedPreset.fieldPresets.firstWhere(
                  (fp) => fp.id == _selectedFieldPreset!.id,
                );

                setState(() {
                  _selectedPreset = reloadedPreset;
                  _selectedFieldPreset = reloadedFieldPreset;
                });

                Navigator.pop(context);
                _showSnackBar('Entry added', success: true);
              } catch (e) {
                _showSnackBar('Error adding entry: $e', success: false);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _editEntry(PresetEntry entry) {
    final valueController = TextEditingController(text: entry.value);
    final nameController = TextEditingController(text: entry.displayName);
    final tagsController = TextEditingController(text: entry.tags.join(', '));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valueController,
              decoration: const InputDecoration(
                labelText: 'Value',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags (comma-separated)',
                border: OutlineInputBorder(),
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
            onPressed: () async {
              final value = valueController.text.trim();
              final name = nameController.text.trim();
              final tags = tagsController.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();

              if (value.isEmpty || name.isEmpty) {
                _showSnackBar('Please fill in all fields', success: false);
                return;
              }

              try {
                final updated = entry.copyWith(
                  value: value,
                  displayName: name,
                  tags: tags,
                );

                await PresetManager.instance.updateEntry(
                  _selectedPreset!.gameTypeId,
                  _selectedFieldPreset!.id,
                  updated,
                );

                // Reload
                final reloadedPreset = PresetManager.instance.presets.firstWhere(
                  (p) => p.gameTypeId == _selectedPreset!.gameTypeId,
                );
                final reloadedFieldPreset = reloadedPreset.fieldPresets.firstWhere(
                  (fp) => fp.id == _selectedFieldPreset!.id,
                );

                setState(() {
                  _selectedPreset = reloadedPreset;
                  _selectedFieldPreset = reloadedFieldPreset;
                });

                Navigator.pop(context);
                _showSnackBar('Entry updated', success: true);
              } catch (e) {
                _showSnackBar('Error updating entry: $e', success: false);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteEntry(PresetEntry entry) async {
    try {
      await PresetManager.instance.removeEntry(
        _selectedPreset!.gameTypeId,
        _selectedFieldPreset!.id,
        entry.id,
      );

      // Reload
      final reloadedPreset = PresetManager.instance.presets.firstWhere(
        (p) => p.gameTypeId == _selectedPreset!.gameTypeId,
      );
      final reloadedFieldPreset = reloadedPreset.fieldPresets.firstWhere(
        (fp) => fp.id == _selectedFieldPreset!.id,
      );

      setState(() {
        _selectedPreset = reloadedPreset;
        _selectedFieldPreset = reloadedFieldPreset;
      });

      _showSnackBar('Entry deleted', success: true);
    } catch (e) {
      _showSnackBar('Error deleting entry: $e', success: false);
    }
  }

  Future<void> _importEntries() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.first.bytes == null) return;

      final jsonString = utf8.decode(result.files.first.bytes!);
      final jsonData = json.decode(jsonString);

      if (jsonData is! List) {
        _showSnackBar('Invalid format: expected array', success: false);
        return;
      }

      final entries = List<PresetEntry>.from(_selectedFieldPreset!.entries);
      
      for (final item in jsonData) {
        try {
          final entry = PresetEntry.fromJson(item as Map<String, dynamic>);
          // Replace or add
          final existingIndex = entries.indexWhere((e) => e.id == entry.id);
          if (existingIndex >= 0) {
            entries[existingIndex] = entry;
          } else {
            entries.add(entry);
          }
        } catch (e) {
          DebugLogger.log('Skipping invalid entry: $e', level: LogLevel.warning);
        }
      }

      final updated = _selectedFieldPreset!.copyWith(entries: entries);
      await PresetManager.instance.updateFieldPreset(
        _selectedPreset!.gameTypeId,
        updated,
      );

      // Reload
      final reloadedPreset = PresetManager.instance.presets.firstWhere(
        (p) => p.gameTypeId == _selectedPreset!.gameTypeId,
      );
      final reloadedFieldPreset = reloadedPreset.fieldPresets.firstWhere(
        (fp) => fp.id == _selectedFieldPreset!.id,
      );

      setState(() {
        _selectedPreset = reloadedPreset;
        _selectedFieldPreset = reloadedFieldPreset;
      });

      _showSnackBar('Entries imported successfully', success: true);
    } catch (e) {
      DebugLogger.log('Error importing entries: $e', level: LogLevel.error);
      _showSnackBar('Error importing entries: $e', success: false);
    }
  }

  Future<void> _exportEntries() async {
    try {
      final jsonData = _selectedFieldPreset!.entries.map((e) => e.toJson()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      final bytes = Uint8List.fromList(utf8.encode(jsonString));
      final fileName = '${_selectedFieldPreset!.id}_entries.json';

      if (kIsWeb) {
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = fileName;
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
          suggestedName: fileName,
          acceptedTypeGroups: [typeGroup],
        );

        if (path != null) {
          final file = io.File(path.path);
          await file.writeAsBytes(bytes);
        }
      }

      _showSnackBar('Entries exported successfully', success: true);
    } catch (e) {
      DebugLogger.log('Error exporting entries: $e', level: LogLevel.error);
      _showSnackBar('Error exporting entries: $e', success: false);
    }
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

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
}