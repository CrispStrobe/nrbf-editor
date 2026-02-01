// lib/presets/preset_manager.dart
import 'package:flutter/foundation.dart';
import '../main.dart' show DebugLogger, LogLevel;
import '../nrbf/nrbf.dart';
import 'preset_models.dart';
import 'preset_storage.dart';

// ============================================================================
// PRESET MANAGER - BUSINESS LOGIC & STATE MANAGEMENT
// ============================================================================

class PresetManager extends ChangeNotifier {
  // Singleton instance
  static final PresetManager instance = PresetManager._();
  PresetManager._();

  // State
  List<GamePreset> _presets = [];
  GamePreset? _activePreset;
  
  // Fast lookup cache for active preset's field presets
  final Map<String, FieldPreset> _fieldPresetCache = {};
  
  bool _initialized = false;

  // Getters
  List<GamePreset> get presets => List.unmodifiable(_presets);
  GamePreset? get activePreset => _activePreset;
  bool get hasActivePreset => _activePreset != null;

  /// Initialize the preset manager
  Future<void> initialize() async {
    if (_initialized) {
      DebugLogger.log('PresetManager already initialized', level: LogLevel.debug);
      return;
    }

    DebugLogger.log('=== INITIALIZING PRESET MANAGER ===', level: LogLevel.info);

    try {
      // Initialize storage
      await PresetStorage.instance.initialize();

      // Load all presets
      await loadAllPresets();

      _initialized = true;
      DebugLogger.log('✓ PresetManager initialized with ${_presets.length} presets', 
                     level: LogLevel.info);
    } catch (e, stackTrace) {
      DebugLogger.log('ERROR initializing PresetManager: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
      rethrow;
    }
  }

  /// Load all presets from storage
  Future<void> loadAllPresets() async {
    DebugLogger.log('Loading all presets...', level: LogLevel.debug);
    
    try {
      _presets = await PresetStorage.instance.loadAllPresets();
      DebugLogger.log('✓ Loaded ${_presets.length} presets', level: LogLevel.info);
      
      for (final preset in _presets) {
        DebugLogger.log('  - ${preset.gameTypeId}: ${preset.displayName}', 
                       level: LogLevel.debug);
      }
      
      notifyListeners();
    } catch (e, stackTrace) {
      DebugLogger.log('ERROR loading presets: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
      rethrow;
    }
  }

  /// Auto-detect preset based on class names and library names
  GamePreset? autoDetectPreset(List<String> classNames, List<String> libraryNames) {
    DebugLogger.log('=== AUTO-DETECTING PRESET ===', level: LogLevel.info);
    DebugLogger.log('Class names to check: ${classNames.length}', level: LogLevel.debug);
    DebugLogger.log('Library names to check: ${libraryNames.length}', level: LogLevel.debug);

    if (_presets.isEmpty) {
      DebugLogger.log('No presets available for detection', level: LogLevel.warning);
      return null;
    }

    for (final preset in _presets) {
      DebugLogger.log('Checking preset: ${preset.gameTypeId}', level: LogLevel.debug);
      
      if (preset.detectionHints.isEmpty) {
        DebugLogger.log('  - No detection hints configured, skipping', 
                       level: LogLevel.debug);
        continue;
      }

      for (final hint in preset.detectionHints) {
        DebugLogger.log('  - Testing detection hint...', level: LogLevel.debug);
        DebugLogger.log('    Class fragments: ${hint.classNameFragments}', 
                       level: LogLevel.debug);
        DebugLogger.log('    Library fragments: ${hint.libraryNameFragments}', 
                       level: LogLevel.debug);

        if (hint.matches(classNames, libraryNames)) {
          DebugLogger.log('✓ MATCH FOUND: ${preset.gameTypeId}', level: LogLevel.info);
          return preset;
        } else {
          DebugLogger.log('    No match', level: LogLevel.debug);
        }
      }
    }

    DebugLogger.log('No preset detected', level: LogLevel.warning);
    return null;
  }

  /// Set the active preset and rebuild cache
  void setActivePreset(String? gameTypeId) {
    DebugLogger.log('=== SETTING ACTIVE PRESET: ${gameTypeId ?? "null"} ===', 
                   level: LogLevel.info);

    if (gameTypeId == null) {
      _activePreset = null;
      _fieldPresetCache.clear();
      DebugLogger.log('✓ Cleared active preset', level: LogLevel.info);
      notifyListeners();
      return;
    }

    try {
      final preset = _presets.firstWhere(
        (p) => p.gameTypeId == gameTypeId,
        orElse: () => throw Exception('Preset not found: $gameTypeId'),
      );

      _activePreset = preset;
      _rebuildFieldPresetCache();
      
      DebugLogger.log('✓ Active preset set: ${preset.displayName}', level: LogLevel.info);
      DebugLogger.log('  Field presets: ${preset.fieldPresets.length}', 
                     level: LogLevel.debug);
      DebugLogger.log('  Favorites: ${preset.favorites.length}', level: LogLevel.debug);
      
      notifyListeners();
    } catch (e) {
      DebugLogger.log('ERROR setting active preset: $e', level: LogLevel.error);
      rethrow;
    }
  }

  /// Rebuild the field preset lookup cache
  void _rebuildFieldPresetCache() {
    _fieldPresetCache.clear();
    
    if (_activePreset == null) return;

    DebugLogger.log('Rebuilding field preset cache...', level: LogLevel.debug);
    
    // This is a simple cache - we could optimize with better indexing if needed
    // For now, we just clear it and let findPresetForPath do the work
    
    DebugLogger.log('Cache rebuilt (lazy evaluation mode)', level: LogLevel.debug);
  }

  /// Find a field preset that matches the given path
  FieldPreset? findPresetForPath(String path) {
    if (_activePreset == null) return null;

    // Check cache first
    if (_fieldPresetCache.containsKey(path)) {
        return _fieldPresetCache[path];
    }

    // Search through field presets
    for (final fieldPreset in _activePreset!.fieldPresets) {
        if (fieldPreset.matchesPath(path)) {
        _fieldPresetCache[path] = fieldPreset;
        DebugLogger.log('Found preset for path "$path": ${fieldPreset.displayName}', 
                        level: LogLevel.debug);
        return fieldPreset;
        }
    }

    // Don't cache negative results - just return null
    // (Caching nulls with null! causes crashes when retrieved)
    return null;
    }

  /// Check if a path is favorited
  bool isFavorite(String path) {
    if (_activePreset == null) return false;
    return _activePreset!.favorites.any((f) => f.path == path);
  }

  /// Toggle favorite status for a path
  void toggleFavorite(String path, {String? label}) {
    if (_activePreset == null) {
      DebugLogger.log('Cannot toggle favorite: no active preset', 
                     level: LogLevel.warning);
      return;
    }

    DebugLogger.log('Toggling favorite for path: $path', level: LogLevel.debug);

    final favorites = List<FavoriteEntry>.from(_activePreset!.favorites);
    final existingIndex = favorites.indexWhere((f) => f.path == path);

    if (existingIndex >= 0) {
      // Remove existing favorite
      favorites.removeAt(existingIndex);
      DebugLogger.log('✓ Removed favorite: $path', level: LogLevel.info);
    } else {
      // Add new favorite
      final newFavorite = FavoriteEntry(
        path: path,
        label: label ?? path.split('.').last,
      );
      favorites.add(newFavorite);
      DebugLogger.log('✓ Added favorite: $path (${newFavorite.label})', 
                     level: LogLevel.info);
    }

    // Update preset
    _activePreset = _activePreset!.copyWith(favorites: favorites);
    _updatePresetInList(_activePreset!);
    
    notifyListeners();
  }

  /// Save the current active preset to storage
  Future<void> saveCurrentPreset() async {
    if (_activePreset == null) {
      DebugLogger.log('Cannot save: no active preset', level: LogLevel.warning);
      return;
    }

    DebugLogger.log('Saving current preset: ${_activePreset!.gameTypeId}', 
                   level: LogLevel.info);

    try {
      await PresetStorage.instance.savePreset(_activePreset!);
      DebugLogger.log('✓ Preset saved successfully', level: LogLevel.info);
    } catch (e, stackTrace) {
      DebugLogger.log('ERROR saving preset: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
      rethrow;
    }
  }

  /// Create a new preset
  Future<void> createPreset(GamePreset preset) async {
    DebugLogger.log('=== CREATING NEW PRESET: ${preset.gameTypeId} ===', 
                   level: LogLevel.info);

    // Check for duplicates
    if (_presets.any((p) => p.gameTypeId == preset.gameTypeId)) {
      throw Exception('Preset with ID ${preset.gameTypeId} already exists');
    }

    try {
      await PresetStorage.instance.savePreset(preset);
      _presets.add(preset);
      
      DebugLogger.log('✓ Preset created: ${preset.displayName}', level: LogLevel.info);
      notifyListeners();
    } catch (e, stackTrace) {
      DebugLogger.log('ERROR creating preset: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
      rethrow;
    }
  }

  /// Delete a preset
  Future<void> deletePreset(String gameTypeId) async {
    DebugLogger.log('=== DELETING PRESET: $gameTypeId ===', level: LogLevel.info);

    try {
      await PresetStorage.instance.deletePreset(gameTypeId);
      _presets.removeWhere((p) => p.gameTypeId == gameTypeId);

      // Clear active preset if it was deleted
      if (_activePreset?.gameTypeId == gameTypeId) {
        _activePreset = null;
        _fieldPresetCache.clear();
      }

      DebugLogger.log('✓ Preset deleted', level: LogLevel.info);
      notifyListeners();
    } catch (e, stackTrace) {
      DebugLogger.log('ERROR deleting preset: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
      rethrow;
    }
  }

  /// Update a preset (for editing metadata)
  Future<void> updatePreset(GamePreset preset) async {
    DebugLogger.log('Updating preset: ${preset.gameTypeId}', level: LogLevel.info);

    try {
      await PresetStorage.instance.savePreset(preset);
      _updatePresetInList(preset);

      // Update active preset if it's the one being edited
      if (_activePreset?.gameTypeId == preset.gameTypeId) {
        _activePreset = preset;
        _rebuildFieldPresetCache();
      }

      DebugLogger.log('✓ Preset updated', level: LogLevel.info);
      notifyListeners();
    } catch (e, stackTrace) {
      DebugLogger.log('ERROR updating preset: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
      rethrow;
    }
  }

  /// Add a field preset to a game preset
  Future<void> addFieldPreset(String gameTypeId, FieldPreset fieldPreset) async {
    DebugLogger.log('Adding field preset "${fieldPreset.displayName}" to $gameTypeId', 
                   level: LogLevel.info);

    final preset = _findPresetById(gameTypeId);
    final fieldPresets = List<FieldPreset>.from(preset.fieldPresets);
    fieldPresets.add(fieldPreset);

    final updated = preset.copyWith(fieldPresets: fieldPresets);
    await updatePreset(updated);
  }

  /// Update a field preset
  Future<void> updateFieldPreset(String gameTypeId, FieldPreset fieldPreset) async {
    DebugLogger.log('Updating field preset "${fieldPreset.id}" in $gameTypeId', 
                   level: LogLevel.info);

    final preset = _findPresetById(gameTypeId);
    final fieldPresets = List<FieldPreset>.from(preset.fieldPresets);
    final index = fieldPresets.indexWhere((fp) => fp.id == fieldPreset.id);

    if (index < 0) {
      throw Exception('Field preset not found: ${fieldPreset.id}');
    }

    fieldPresets[index] = fieldPreset;
    final updated = preset.copyWith(fieldPresets: fieldPresets);
    await updatePreset(updated);
  }

  /// Remove a field preset
  Future<void> removeFieldPreset(String gameTypeId, String fieldPresetId) async {
    DebugLogger.log('Removing field preset "$fieldPresetId" from $gameTypeId', 
                   level: LogLevel.info);

    final preset = _findPresetById(gameTypeId);
    final fieldPresets = List<FieldPreset>.from(preset.fieldPresets);
    fieldPresets.removeWhere((fp) => fp.id == fieldPresetId);

    final updated = preset.copyWith(fieldPresets: fieldPresets);
    await updatePreset(updated);
  }

  /// Add an entry to a field preset
  Future<void> addEntry(String gameTypeId, String fieldPresetId, PresetEntry entry) async {
    DebugLogger.log('Adding entry "${entry.displayName}" to field preset $fieldPresetId', 
                   level: LogLevel.debug);

    final preset = _findPresetById(gameTypeId);
    final fieldPresets = List<FieldPreset>.from(preset.fieldPresets);
    final fpIndex = fieldPresets.indexWhere((fp) => fp.id == fieldPresetId);

    if (fpIndex < 0) {
      throw Exception('Field preset not found: $fieldPresetId');
    }

    final entries = List<PresetEntry>.from(fieldPresets[fpIndex].entries);
    entries.add(entry);
    
    fieldPresets[fpIndex] = fieldPresets[fpIndex].copyWith(entries: entries);
    final updated = preset.copyWith(fieldPresets: fieldPresets);
    await updatePreset(updated);
  }

  /// Update an entry in a field preset
  Future<void> updateEntry(String gameTypeId, String fieldPresetId, PresetEntry entry) async {
    DebugLogger.log('Updating entry "${entry.id}" in field preset $fieldPresetId', 
                   level: LogLevel.debug);

    final preset = _findPresetById(gameTypeId);
    final fieldPresets = List<FieldPreset>.from(preset.fieldPresets);
    final fpIndex = fieldPresets.indexWhere((fp) => fp.id == fieldPresetId);

    if (fpIndex < 0) {
      throw Exception('Field preset not found: $fieldPresetId');
    }

    final entries = List<PresetEntry>.from(fieldPresets[fpIndex].entries);
    final entryIndex = entries.indexWhere((e) => e.id == entry.id);

    if (entryIndex < 0) {
      throw Exception('Entry not found: ${entry.id}');
    }

    entries[entryIndex] = entry;
    fieldPresets[fpIndex] = fieldPresets[fpIndex].copyWith(entries: entries);
    final updated = preset.copyWith(fieldPresets: fieldPresets);
    await updatePreset(updated);
  }

  /// Remove an entry from a field preset
  Future<void> removeEntry(String gameTypeId, String fieldPresetId, String entryId) async {
    DebugLogger.log('Removing entry "$entryId" from field preset $fieldPresetId', 
                   level: LogLevel.debug);

    final preset = _findPresetById(gameTypeId);
    final fieldPresets = List<FieldPreset>.from(preset.fieldPresets);
    final fpIndex = fieldPresets.indexWhere((fp) => fp.id == fieldPresetId);

    if (fpIndex < 0) {
      throw Exception('Field preset not found: $fieldPresetId');
    }

    final entries = List<PresetEntry>.from(fieldPresets[fpIndex].entries);
    entries.removeWhere((e) => e.id == entryId);
    
    fieldPresets[fpIndex] = fieldPresets[fpIndex].copyWith(entries: entries);
    final updated = preset.copyWith(fieldPresets: fieldPresets);
    await updatePreset(updated);
  }

  /// Import a preset from bytes
  Future<GamePreset> importPreset(Uint8List bytes) async {
    DebugLogger.log('Importing preset from bytes...', level: LogLevel.info);

    try {
      final preset = await PresetStorage.instance.importPresetFromBytes(bytes);
      
      // Reload all presets to include the new one
      await loadAllPresets();
      
      DebugLogger.log('✓ Preset imported: ${preset.gameTypeId}', level: LogLevel.info);
      return preset;
    } catch (e, stackTrace) {
      DebugLogger.log('ERROR importing preset: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
      rethrow;
    }
  }

  /// Export a preset to bytes
  Future<Uint8List> exportPreset(String gameTypeId) async {
    DebugLogger.log('Exporting preset: $gameTypeId', level: LogLevel.info);

    try {
      return await PresetStorage.instance.exportPreset(gameTypeId);
    } catch (e, stackTrace) {
      DebugLogger.log('ERROR exporting preset: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
      rethrow;
    }
  }

  // Helper methods

  GamePreset _findPresetById(String gameTypeId) {
    return _presets.firstWhere(
      (p) => p.gameTypeId == gameTypeId,
      orElse: () => throw Exception('Preset not found: $gameTypeId'),
    );
  }

  void _updatePresetInList(GamePreset preset) {
    final index = _presets.indexWhere((p) => p.gameTypeId == preset.gameTypeId);
    if (index >= 0) {
      _presets[index] = preset;
    }
  }
}