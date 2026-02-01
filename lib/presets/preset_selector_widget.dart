// lib/presets/preset_selector_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show DebugLogger, LogLevel;
import '../nrbf/nrbf.dart';
import 'preset_models.dart';
import 'preset_manager.dart';

// ============================================================================
// PRESET SELECTOR WIDGET
// ============================================================================

class PresetSelectorWidget extends StatefulWidget {
  final ClassRecord parentRecord;
  final String memberName;
  final dynamic currentValue;
  final FieldPreset fieldPreset;
  final String path;
  final ValueChanged<String> onValueChanged;

  const PresetSelectorWidget({
    super.key,
    required this.parentRecord,
    required this.memberName,
    required this.currentValue,
    required this.fieldPreset,
    required this.path,
    required this.onValueChanged,
  });

  @override
  State<PresetSelectorWidget> createState() => _PresetSelectorWidgetState();
}

class _PresetSelectorWidgetState extends State<PresetSelectorWidget> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getCurrentValueString() {
    // Convert current value to string for comparison
    if (widget.fieldPreset.valueType == PresetValueType.guid) {
      if (widget.currentValue is ClassRecord &&
          widget.currentValue.typeName == 'System.Guid') {
        try {
          return ClassRecord.reconstructGuid(widget.currentValue);
        } catch (e) {
          return 'invalid-guid';
        }
      }
    }
    return widget.currentValue?.toString() ?? '';
  }

  PresetEntry? _getCurrentEntry() {
    final currentValueStr = _getCurrentValueString();
    return findEntryByValue(widget.fieldPreset.entries, currentValueStr);
  }

  void _showSelector() {
    DebugLogger.log('Opening preset selector for: ${widget.memberName}',
        level: LogLevel.debug);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSelectorSheet(),
    );
  }

  Widget _buildSelectorSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.fieldPreset.displayName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.fieldPreset.entries.length} options',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Search field
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                    _searchQuery = '';
                                  });
                                },
                              )
                            : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Entries list
              Expanded(
                child: _buildEntriesList(scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEntriesList(ScrollController scrollController) {
    final currentValueStr = _getCurrentValueString();
    final filteredEntries = _searchQuery.isEmpty
        ? widget.fieldPreset.entries
        : widget.fieldPreset.entries.where((entry) {
            final query = _searchQuery.toLowerCase();
            return entry.displayName.toLowerCase().contains(query) ||
                entry.value.toLowerCase().contains(query) ||
                entry.tags.any((tag) => tag.toLowerCase().contains(query));
          }).toList();

    if (filteredEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filteredEntries.length,
      itemBuilder: (context, index) {
        final entry = filteredEntries[index];
        final isSelected = entry.value == currentValueStr;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(
              entry.displayName,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (entry.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: entry.tags.map((tag) {
                      return Chip(
                        label: Text(
                          tag,
                          style: const TextStyle(fontSize: 10),
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
            onTap: () {
              DebugLogger.log(
                  'Selected preset entry: ${entry.displayName} (${entry.value})',
                  level: LogLevel.info);
              widget.onValueChanged(entry.value);
              Navigator.pop(context);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentEntry = _getCurrentEntry();
    final currentValueStr = _getCurrentValueString();

    return Container(
      margin: const EdgeInsets.only(left: 0, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ListTile(
        leading: Icon(
          Icons.playlist_play,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(widget.memberName),
            ),
            FavoriteToggle(path: widget.path),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (currentEntry != null)
              Text(
                currentEntry.displayName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            else
              Text(
                'Unknown: $currentValueStr',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              currentValueStr,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentEntry != null && currentEntry.tags.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  currentEntry.tags.first,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            const SizedBox(width: 8),
            // ADD MANUAL EDIT BUTTON
            IconButton(
              icon: const Icon(Icons.edit),
              iconSize: 20,
              onPressed: () => _showManualEditDialog(context, currentValueStr),
              tooltip: 'Edit manually',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_drop_down),
              onPressed: _showSelector,
              tooltip: 'Select from preset',
            ),
          ],
        ),
        onTap: _showSelector,
      ),
    );
  }

  void _showManualEditDialog(BuildContext context, String currentValue) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${widget.memberName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter ${widget.fieldPreset.valueType.name} value:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: widget.memberName,
                hintText: currentValue,
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
              maxLines: widget.fieldPreset.valueType == PresetValueType.guid ? 1 : null,
            ),
            if (widget.fieldPreset.valueType == PresetValueType.guid) ...[
              const SizedBox(height: 8),
              Text(
                'Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newValue = controller.text.trim();
              
              // Validate GUID format if needed
              if (widget.fieldPreset.valueType == PresetValueType.guid) {
                final guidPattern = RegExp(
                  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
                  caseSensitive: false,
                );
                if (!guidPattern.hasMatch(newValue)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid GUID format'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
              }
              
              widget.onValueChanged(newValue);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

}

// ============================================================================
// FAVORITE TOGGLE
// ============================================================================

class FavoriteToggle extends StatefulWidget {
  final String path;

  const FavoriteToggle({
    super.key,
    required this.path,
  });

  @override
  State<FavoriteToggle> createState() => _FavoriteToggleState();
}

class _FavoriteToggleState extends State<FavoriteToggle> {
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

  void _toggleFavorite() {
    final isFavorite = PresetManager.instance.isFavorite(widget.path);
    
    if (isFavorite) {
      PresetManager.instance.toggleFavorite(widget.path);
      PresetManager.instance.saveCurrentPreset();
    } else {
      // Show dialog to get label
      _showLabelDialog();
    }
  }

  void _showLabelDialog() {
    final controller = TextEditingController(
      text: widget.path.split('.').last,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Favorites'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Path: ${widget.path}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'Enter a friendly name',
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
              final label = controller.text.trim();
              if (label.isNotEmpty) {
                PresetManager.instance.toggleFavorite(
                  widget.path,
                  label: label,
                );
                PresetManager.instance.saveCurrentPreset();
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PresetManager.instance.hasActivePreset) {
      return const SizedBox.shrink();
    }

    final isFavorite = PresetManager.instance.isFavorite(widget.path);

    return IconButton(
      icon: Icon(
        isFavorite ? Icons.star : Icons.star_border,
        size: 20,
        color: isFavorite ? Colors.amber : null,
      ),
      onPressed: _toggleFavorite,
      tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
      visualDensity: VisualDensity.compact,
    );
  }
}