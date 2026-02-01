// lib/presets/preset_storage.dart
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../main.dart' show DebugLogger, LogLevel;
import 'preset_models.dart';

// ============================================================================
// PRESET STORAGE - CROSS-PLATFORM PERSISTENCE
// ============================================================================

class PresetStorage {
  // Singleton instance
  static final PresetStorage instance = PresetStorage._();
  PresetStorage._();

  // Storage locations
  String? _appSupportPath; // Native only
  final Map<String, GamePreset> _webPresets = {}; // Web only

  bool _initialized = false;

  /// Initialize the storage system
  /// - Native: Resolves app support directory and creates presets folder
  /// - Web: No-op (uses in-memory storage)
  Future<void> initialize() async {
    if (_initialized) {
      DebugLogger.log('PresetStorage already initialized', level: LogLevel.debug);
      return;
    }

    DebugLogger.log('=== INITIALIZING PRESET STORAGE ===', level: LogLevel.info);

    if (kIsWeb) {
      DebugLogger.log('Platform: Web - using in-memory storage', level: LogLevel.info);
      _initialized = true;
      
      // Load bundled presets into memory
      await _loadBundledAssetsWeb();
      
      DebugLogger.log('✓ Preset storage initialized (Web)', level: LogLevel.info);
    } else {
      DebugLogger.log('Platform: Native - using filesystem storage', level: LogLevel.info);
      
      try {
        // Get app support directory
        final appSupportDir = await getApplicationSupportDirectory();
        _appSupportPath = appSupportDir.path;
        DebugLogger.log('App support directory: $_appSupportPath', level: LogLevel.debug);

        // Create presets subdirectory
        await _ensurePresetsDir();

        // Copy bundled assets if they don't exist
        await _loadBundledAssetsNative();

        _initialized = true;
        DebugLogger.log('✓ Preset storage initialized (Native)', level: LogLevel.info);
      } catch (e, stackTrace) {
        DebugLogger.log('ERROR initializing preset storage: $e', level: LogLevel.error);
        DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
        rethrow;
      }
    }
  }

  /// Ensure the presets directory exists (Native only)
  Future<void> _ensurePresetsDir() async {
    if (kIsWeb || _appSupportPath == null) return;

    final presetsDir = io.Directory(path.join(_appSupportPath!, 'presets'));
    if (!await presetsDir.exists()) {
      DebugLogger.log('Creating presets directory: ${presetsDir.path}', level: LogLevel.debug);
      await presetsDir.create(recursive: true);
    } else {
      DebugLogger.log('Presets directory exists: ${presetsDir.path}', level: LogLevel.debug);
    }
  }

  /// Get the file path for a preset (Native only)
  String _presetFilePath(String gameTypeId) {
    if (_appSupportPath == null) {
      throw Exception('App support path not initialized');
    }
    return path.join(_appSupportPath!, 'presets', '$gameTypeId.json');
  }

  /// Load bundled assets for Web platform
  Future<void> _loadBundledAssetsWeb() async {
    DebugLogger.log('Loading bundled presets for Web...', level: LogLevel.debug);
    
    try {
      // Try to load wobbly_life preset
      final wobblyLifeJson = await rootBundle.loadString('assets/presets/wobbly_life.json');
      final preset = GamePreset.fromJson(json.decode(wobblyLifeJson) as Map<String, dynamic>);
      _webPresets[preset.gameTypeId] = preset;
      DebugLogger.log('✓ Loaded bundled preset: ${preset.gameTypeId}', level: LogLevel.info);
    } catch (e) {
      DebugLogger.log('No bundled presets found or error loading: $e', level: LogLevel.warning);
    }
  }

  /// Load bundled assets for Native platform
  Future<void> _loadBundledAssetsNative() async {
    DebugLogger.log('Loading bundled presets for Native...', level: LogLevel.debug);

    // List of bundled preset files
    final bundledPresets = ['wobbly_life'];

    for (final presetId in bundledPresets) {
      try {
        final filePath = _presetFilePath(presetId);
        final file = io.File(filePath);

        // Only copy if it doesn't exist
        if (!await file.exists()) {
          DebugLogger.log('Copying bundled preset: $presetId', level: LogLevel.debug);
          
          final assetPath = 'assets/presets/$presetId.json';
          final assetJson = await rootBundle.loadString(assetPath);
          
          await file.writeAsString(assetJson);
          DebugLogger.log('✓ Copied bundled preset: $presetId', level: LogLevel.info);
        } else {
          DebugLogger.log('Bundled preset already exists: $presetId', level: LogLevel.debug);
        }
      } catch (e) {
        DebugLogger.log('Warning: Could not load bundled preset $presetId: $e', 
                       level: LogLevel.warning);
      }
    }
  }

  /// Load all available presets
  Future<List<GamePreset>> loadAllPresets() async {
    if (!_initialized) {
      await initialize();
    }

    DebugLogger.log('=== LOADING ALL PRESETS ===', level: LogLevel.info);

    if (kIsWeb) {
      DebugLogger.log('Returning ${_webPresets.length} presets from memory', 
                     level: LogLevel.debug);
      return _webPresets.values.toList();
    } else {
      // Native: Read all .json files from presets directory
      try {
        final presetsDir = io.Directory(path.join(_appSupportPath!, 'presets'));
        
        if (!await presetsDir.exists()) {
          DebugLogger.log('Presets directory does not exist, returning empty list', 
                         level: LogLevel.warning);
          return [];
        }

        final presets = <GamePreset>[];
        final files = presetsDir.listSync()
            .whereType<io.File>()
            .where((f) => f.path.endsWith('.json'));

        DebugLogger.log('Found ${files.length} preset files', level: LogLevel.debug);

        for (final file in files) {
          try {
            final jsonString = await file.readAsString();
            final jsonData = json.decode(jsonString) as Map<String, dynamic>;
            final preset = GamePreset.fromJson(jsonData);
            presets.add(preset);
            DebugLogger.log('✓ Loaded preset: ${preset.gameTypeId}', level: LogLevel.debug);
          } catch (e) {
            DebugLogger.log('ERROR loading preset file ${file.path}: $e', 
                           level: LogLevel.error);
          }
        }

        DebugLogger.log('✓ Loaded ${presets.length} presets total', level: LogLevel.info);
        return presets;
      } catch (e, stackTrace) {
        DebugLogger.log('ERROR loading presets: $e', level: LogLevel.error);
        DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
        return [];
      }
    }
  }

  /// Load a single preset by game type ID
  Future<GamePreset?> loadPreset(String gameTypeId) async {
    if (!_initialized) {
      await initialize();
    }

    DebugLogger.log('Loading preset: $gameTypeId', level: LogLevel.debug);

    if (kIsWeb) {
      final preset = _webPresets[gameTypeId];
      if (preset != null) {
        DebugLogger.log('✓ Loaded preset from memory: $gameTypeId', level: LogLevel.debug);
      } else {
        DebugLogger.log('Preset not found in memory: $gameTypeId', level: LogLevel.warning);
      }
      return preset;
    } else {
      try {
        final filePath = _presetFilePath(gameTypeId);
        final file = io.File(filePath);

        if (!await file.exists()) {
          DebugLogger.log('Preset file does not exist: $gameTypeId', level: LogLevel.warning);
          return null;
        }

        final jsonString = await file.readAsString();
        final jsonData = json.decode(jsonString) as Map<String, dynamic>;
        final preset = GamePreset.fromJson(jsonData);
        
        DebugLogger.log('✓ Loaded preset from disk: $gameTypeId', level: LogLevel.debug);
        return preset;
      } catch (e, stackTrace) {
        DebugLogger.log('ERROR loading preset $gameTypeId: $e', level: LogLevel.error);
        DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
        return null;
      }
    }
  }

  /// Save a preset
  Future<void> savePreset(GamePreset preset) async {
    if (!_initialized) {
      await initialize();
    }

    DebugLogger.log('=== SAVING PRESET: ${preset.gameTypeId} ===', level: LogLevel.info);

    if (kIsWeb) {
      _webPresets[preset.gameTypeId] = preset;
      DebugLogger.log('✓ Saved preset to memory: ${preset.gameTypeId}', level: LogLevel.info);
    } else {
      try {
        await _ensurePresetsDir();
        
        final filePath = _presetFilePath(preset.gameTypeId);
        final file = io.File(filePath);

        final jsonData = preset.toJson();
        final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);

        await file.writeAsString(jsonString);
        
        DebugLogger.log('✓ Saved preset to disk: $filePath', level: LogLevel.info);
        DebugLogger.log('File size: ${jsonString.length} bytes', level: LogLevel.debug);
      } catch (e, stackTrace) {
        DebugLogger.log('ERROR saving preset ${preset.gameTypeId}: $e', 
                       level: LogLevel.error);
        DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
        rethrow;
      }
    }
  }

  /// Delete a preset
  Future<void> deletePreset(String gameTypeId) async {
    if (!_initialized) {
      await initialize();
    }

    DebugLogger.log('=== DELETING PRESET: $gameTypeId ===', level: LogLevel.info);

    if (kIsWeb) {
      _webPresets.remove(gameTypeId);
      DebugLogger.log('✓ Deleted preset from memory: $gameTypeId', level: LogLevel.info);
    } else {
      try {
        final filePath = _presetFilePath(gameTypeId);
        final file = io.File(filePath);

        if (await file.exists()) {
          await file.delete();
          DebugLogger.log('✓ Deleted preset file: $filePath', level: LogLevel.info);
        } else {
          DebugLogger.log('Preset file does not exist: $gameTypeId', level: LogLevel.warning);
        }
      } catch (e, stackTrace) {
        DebugLogger.log('ERROR deleting preset $gameTypeId: $e', level: LogLevel.error);
        DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
        rethrow;
      }
    }
  }

  /// Import a preset from bytes (JSON data)
  Future<GamePreset> importPresetFromBytes(Uint8List bytes) async {
    DebugLogger.log('=== IMPORTING PRESET FROM BYTES ===', level: LogLevel.info);
    DebugLogger.log('Data size: ${bytes.length} bytes', level: LogLevel.debug);

    try {
      final jsonString = utf8.decode(bytes);
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      final preset = GamePreset.fromJson(jsonData);

      DebugLogger.log('✓ Parsed preset: ${preset.gameTypeId}', level: LogLevel.info);
      DebugLogger.log('  Display name: ${preset.displayName}', level: LogLevel.debug);
      DebugLogger.log('  Field presets: ${preset.fieldPresets.length}', level: LogLevel.debug);
      DebugLogger.log('  Favorites: ${preset.favorites.length}', level: LogLevel.debug);

      // Save it
      await savePreset(preset);

      DebugLogger.log('✓ Import complete', level: LogLevel.info);
      return preset;
    } catch (e, stackTrace) {
      DebugLogger.log('ERROR importing preset: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
      rethrow;
    }
  }

  /// Export a preset to bytes (JSON data)
  Future<Uint8List> exportPreset(String gameTypeId) async {
    DebugLogger.log('=== EXPORTING PRESET: $gameTypeId ===', level: LogLevel.info);

    final preset = await loadPreset(gameTypeId);
    if (preset == null) {
      throw Exception('Preset not found: $gameTypeId');
    }

    try {
      final jsonData = preset.toJson();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      final bytes = Uint8List.fromList(utf8.encode(jsonString));

      DebugLogger.log('✓ Exported preset to ${bytes.length} bytes', level: LogLevel.info);
      return bytes;
    } catch (e, stackTrace) {
      DebugLogger.log('ERROR exporting preset $gameTypeId: $e', level: LogLevel.error);
      DebugLogger.log('Stack trace:\n$stackTrace', level: LogLevel.error);
      rethrow;
    }
  }
}