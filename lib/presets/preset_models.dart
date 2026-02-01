// lib/presets/preset_models.dart
import 'package:flutter/foundation.dart';
import '../nrbf/nrbf.dart';

// ============================================================================
// ENUMS
// ============================================================================

enum PathMatchMode {
  fieldName,    // Matches if the field name (last segment) equals pathPattern
  exactPath,    // Matches if the full path equals pathPattern
  containsPath, // Matches if the full path contains pathPattern
  endsWith;     // Matches if the full path ends with pathPattern

  String toJson() => name;
  
  static PathMatchMode fromJson(String value) {
    return PathMatchMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PathMatchMode.fieldName,
    );
  }
}

enum PresetValueType {
  guid,
  string,
  intValue,
  floatValue;

  String toJson() => name;
  
  static PresetValueType fromJson(String value) {
    return PresetValueType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PresetValueType.string,
    );
  }
}

// ============================================================================
// PRESET ENTRY
// ============================================================================

@immutable
class PresetEntry {
  final String id;
  final String value;
  final String displayName;
  final List<String> tags;

  const PresetEntry({
    required this.id,
    required this.value,
    required this.displayName,
    this.tags = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'value': value,
      'displayName': displayName,
      if (tags.isNotEmpty) 'tags': tags,
    };
  }

  factory PresetEntry.fromJson(Map<String, dynamic> json) {
    return PresetEntry(
      id: json['id'] as String,
      value: json['value'] as String,
      displayName: json['displayName'] as String,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  PresetEntry copyWith({
    String? id,
    String? value,
    String? displayName,
    List<String>? tags,
  }) {
    return PresetEntry(
      id: id ?? this.id,
      value: value ?? this.value,
      displayName: displayName ?? this.displayName,
      tags: tags ?? this.tags,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PresetEntry &&
        other.id == id &&
        other.value == value &&
        other.displayName == displayName &&
        listEquals(other.tags, tags);
  }

  @override
  int get hashCode => Object.hash(id, value, displayName, Object.hashAll(tags));
}

// ============================================================================
// FIELD PRESET
// ============================================================================

@immutable
class FieldPreset {
  final String id;
  final String displayName;
  final String pathPattern;
  final PathMatchMode matchMode;
  final PresetValueType valueType;
  final List<PresetEntry> entries;

  const FieldPreset({
    required this.id,
    required this.displayName,
    required this.pathPattern,
    required this.matchMode,
    required this.valueType,
    this.entries = const [],
  });

  bool matchesPath(String treePath) {
    switch (matchMode) {
      case PathMatchMode.fieldName:
        // Extract last segment (after last . or ])
        final lastDot = treePath.lastIndexOf('.');
        final lastBracket = treePath.lastIndexOf(']');
        final lastSep = lastDot > lastBracket ? lastDot : lastBracket;
        final fieldName = lastSep >= 0 ? treePath.substring(lastSep + 1) : treePath;
        return fieldName == pathPattern;

      case PathMatchMode.exactPath:
        return treePath == pathPattern;

      case PathMatchMode.containsPath:
        return treePath.contains(pathPattern);

      case PathMatchMode.endsWith:
        return treePath.endsWith(pathPattern);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'pathPattern': pathPattern,
      'matchMode': matchMode.toJson(),
      'valueType': valueType.toJson(),
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  factory FieldPreset.fromJson(Map<String, dynamic> json) {
    return FieldPreset(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      pathPattern: json['pathPattern'] as String,
      matchMode: PathMatchMode.fromJson(json['matchMode'] as String),
      valueType: PresetValueType.fromJson(json['valueType'] as String),
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) => PresetEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  FieldPreset copyWith({
    String? id,
    String? displayName,
    String? pathPattern,
    PathMatchMode? matchMode,
    PresetValueType? valueType,
    List<PresetEntry>? entries,
  }) {
    return FieldPreset(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      pathPattern: pathPattern ?? this.pathPattern,
      matchMode: matchMode ?? this.matchMode,
      valueType: valueType ?? this.valueType,
      entries: entries ?? this.entries,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FieldPreset &&
        other.id == id &&
        other.displayName == displayName &&
        other.pathPattern == pathPattern &&
        other.matchMode == matchMode &&
        other.valueType == valueType &&
        listEquals(other.entries, entries);
  }

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        pathPattern,
        matchMode,
        valueType,
        Object.hashAll(entries),
      );
}

// ============================================================================
// FAVORITE ENTRY
// ============================================================================

@immutable
class FavoriteEntry {
  final String path;
  final String label;

  const FavoriteEntry({
    required this.path,
    required this.label,
  });

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'label': label,
    };
  }

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) {
    return FavoriteEntry(
      path: json['path'] as String,
      label: json['label'] as String,
    );
  }

  FavoriteEntry copyWith({
    String? path,
    String? label,
  }) {
    return FavoriteEntry(
      path: path ?? this.path,
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FavoriteEntry && other.path == path && other.label == label;
  }

  @override
  int get hashCode => Object.hash(path, label);
}

// ============================================================================
// DETECTION HINT
// ============================================================================

@immutable
class DetectionHint {
  final List<String> classNameFragments;
  final List<String> libraryNameFragments;

  const DetectionHint({
    this.classNameFragments = const [],
    this.libraryNameFragments = const [],
  });

  bool matches(List<String> classNames, List<String> libraryNames) {
    // Must match at least one fragment from each non-empty list
    bool classMatch = classNameFragments.isEmpty;
    bool libraryMatch = libraryNameFragments.isEmpty;

    if (classNameFragments.isNotEmpty) {
      for (final fragment in classNameFragments) {
        if (classNames.any((name) => name.contains(fragment))) {
          classMatch = true;
          break;
        }
      }
    }

    if (libraryNameFragments.isNotEmpty) {
      for (final fragment in libraryNameFragments) {
        if (libraryNames.any((name) => name.contains(fragment))) {
          libraryMatch = true;
          break;
        }
      }
    }

    return classMatch && libraryMatch;
  }

  Map<String, dynamic> toJson() {
    return {
      if (classNameFragments.isNotEmpty)
        'classNameFragments': classNameFragments,
      if (libraryNameFragments.isNotEmpty)
        'libraryNameFragments': libraryNameFragments,
    };
  }

  factory DetectionHint.fromJson(Map<String, dynamic> json) {
    return DetectionHint(
      classNameFragments:
          (json['classNameFragments'] as List<dynamic>?)?.cast<String>() ?? [],
      libraryNameFragments:
          (json['libraryNameFragments'] as List<dynamic>?)?.cast<String>() ??
              [],
    );
  }

  DetectionHint copyWith({
    List<String>? classNameFragments,
    List<String>? libraryNameFragments,
  }) {
    return DetectionHint(
      classNameFragments: classNameFragments ?? this.classNameFragments,
      libraryNameFragments: libraryNameFragments ?? this.libraryNameFragments,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DetectionHint &&
        listEquals(other.classNameFragments, classNameFragments) &&
        listEquals(other.libraryNameFragments, libraryNameFragments);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(classNameFragments),
        Object.hashAll(libraryNameFragments),
      );
}

// ============================================================================
// GAME PRESET
// ============================================================================

@immutable
class GamePreset {
  final int version;
  final String gameTypeId;
  final String displayName;
  final List<DetectionHint> detectionHints;
  final List<FieldPreset> fieldPresets;
  final List<FavoriteEntry> favorites;

  const GamePreset({
    this.version = 1,
    required this.gameTypeId,
    required this.displayName,
    this.detectionHints = const [],
    this.fieldPresets = const [],
    this.favorites = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'gameTypeId': gameTypeId,
      'displayName': displayName,
      'detectionHints': detectionHints.map((h) => h.toJson()).toList(),
      'fieldPresets': fieldPresets.map((fp) => fp.toJson()).toList(),
      'favorites': favorites.map((f) => f.toJson()).toList(),
    };
  }

  factory GamePreset.fromJson(Map<String, dynamic> json) {
    return GamePreset(
      version: json['version'] as int? ?? 1,
      gameTypeId: json['gameTypeId'] as String,
      displayName: json['displayName'] as String,
      detectionHints: (json['detectionHints'] as List<dynamic>?)
              ?.map((h) => DetectionHint.fromJson(h as Map<String, dynamic>))
              .toList() ??
          [],
      fieldPresets: (json['fieldPresets'] as List<dynamic>?)
              ?.map((fp) => FieldPreset.fromJson(fp as Map<String, dynamic>))
              .toList() ??
          [],
      favorites: (json['favorites'] as List<dynamic>?)
              ?.map((f) => FavoriteEntry.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  GamePreset copyWith({
    int? version,
    String? gameTypeId,
    String? displayName,
    List<DetectionHint>? detectionHints,
    List<FieldPreset>? fieldPresets,
    List<FavoriteEntry>? favorites,
  }) {
    return GamePreset(
      version: version ?? this.version,
      gameTypeId: gameTypeId ?? this.gameTypeId,
      displayName: displayName ?? this.displayName,
      detectionHints: detectionHints ?? this.detectionHints,
      fieldPresets: fieldPresets ?? this.fieldPresets,
      favorites: favorites ?? this.favorites,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GamePreset &&
        other.version == version &&
        other.gameTypeId == gameTypeId &&
        other.displayName == displayName &&
        listEquals(other.detectionHints, detectionHints) &&
        listEquals(other.fieldPresets, fieldPresets) &&
        listEquals(other.favorites, favorites);
  }

  @override
  int get hashCode => Object.hash(
        version,
        gameTypeId,
        displayName,
        Object.hashAll(detectionHints),
        Object.hashAll(fieldPresets),
        Object.hashAll(favorites),
      );
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/// Apply a GUID string to a System.Guid ClassRecord by parsing it into
/// the 11 component fields (_a through _k).
void applyGuidToRecord(ClassRecord record, String guidString) {
  if (record.typeName != 'System.Guid') {
    throw ArgumentError(
        'applyGuidToRecord requires a System.Guid record, got ${record.typeName}');
  }

  // Remove dashes and parse hex
  final hex = guidString.replaceAll('-', '');
  if (hex.length != 32) {
    throw ArgumentError('Invalid GUID format: $guidString');
  }

  // Parse into bytes
  final bytes = <int>[];
  for (int i = 0; i < 16; i++) {
    bytes.add(int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16));
  }

  // Reconstruct the 11 fields
  // _a: int32 (bytes 0-3, little-endian)
  final a = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  
  // _b: int16 (bytes 4-5, little-endian)
  final b = bytes[4] | (bytes[5] << 8);
  
  // _c: int16 (bytes 6-7, little-endian)
  final c = bytes[6] | (bytes[7] << 8);
  
  // _d through _k: individual bytes
  final d = bytes[8];
  final e = bytes[9];
  final f = bytes[10];
  final g = bytes[11];
  final h = bytes[12];
  final i = bytes[13];
  final j = bytes[14];
  final k = bytes[15];

  // Set the values on the record
  record.setValue('_a', a);
  record.setValue('_b', b);
  record.setValue('_c', c);
  record.setValue('_d', d);
  record.setValue('_e', e);
  record.setValue('_f', f);
  record.setValue('_g', g);
  record.setValue('_h', h);
  record.setValue('_i', i);
  record.setValue('_j', j);
  record.setValue('_k', k);
}

/// Find a preset entry by its value (for looking up display names)
PresetEntry? findEntryByValue(List<PresetEntry> entries, String value) {
  try {
    return entries.firstWhere((e) => e.value == value);
  } catch (_) {
    return null;
  }
}