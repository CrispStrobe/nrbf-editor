# NRBF Editor

A powerful cross-platform tool for viewing, editing, comparing, and managing **.NET Binary Format (NRBF)** files. This format is commonly used by Unity games and .NET applications for serializing object graphs (especially game save files). This tool allows you to modify values deep within the binary structure without needing the original source code.

**Demo:** https://nrbfeditor.vercel.app/

⚠️ **This is work in progress, so always backup your data before editing.**

---

## 🚀 Key Features

### Core Editing
- **Universal Decoding:** Parses complex NRBF structures including nested Classes, Arrays, Lists, and Dictionaries
- **Visual Tree Editor:** Hierarchical navigation of the complete object graph with expand/collapse functionality
- **Deep Search:** Recursive search with partial matching to find keys, values, GUIDs, or class names anywhere in the file
- **Multi-Type Support:** 
  - Primitives: Strings, Booleans, Integers, Floats, Doubles
  - Special types: `System.Guid` with visual fingerprint display
  - Complex types: `BinaryArray`, `ClassRecord`, `MemberReference` resolution
- **Smart Editing:**
  - Click-to-edit for all primitive values
  - Manual GUID editor with format validation
  - Reference resolution (automatically follows `MemberReferenceRecord`)

### 🎮 Preset System
- **Auto-Detection:** Automatically identifies game type from class names and library signatures
- **Dropdown Selectors:** Replace complex values (like vehicle GUIDs) with friendly names
- **Preset Fields Panel:** Quick navigation to all fields with configured presets
- **Field Matching Modes:**
  - Field name matching (e.g., "VehicleID")
  - Exact path matching
  - Contains path matching
  - Ends with matching
- **Value Types:** String, Integer, Float, GUID
- **Tags & Organization:** Add tags to preset entries for categorization

### 📋 Preset Management
- **Full CRUD:** Create, read, update, delete presets and their entries
- **Visual Preset Editor:** Three-level UI for managing presets, field presets, and entries
- **Import/Export:** Share presets as JSON files
- **Cross-Platform Storage:** 
  - Native: Stored in app support directory
  - Web: In-memory storage with import/export
- **Detection Hints:** Configure auto-detection based on class/library name fragments
- **Bundled Presets:** Ships with Wobbly Life vehicle preset (44 vehicles)

### ⭐ Favorites & Quick Access
- **Favorites Panel:** Bookmark frequently accessed fields with custom labels
- **Preset Fields Panel:** View all preset-enabled fields in active game preset
- **Search Results:** Jump directly to any field from search
- **Path Navigation:** Click favorites or preset fields to expand and scroll to location

### 🔍 File Comparison
- **Side-by-Side Diff:** Load before/after save files to see exactly what changed
- **Change Detection:**
  - Modified values (with old → new display)
  - Added fields
  - Removed fields
- **Deep Comparison:** Recursively compares entire object trees including nested structures
- **Smart Filtering:**
  - Filter by change type (modified/added/removed)
  - Search within changes
- **Quick Actions from Diff:**
  - Add changed field to favorites
  - Quick add to preset (auto-detects value type)
  - Copy paths and values
  - Jump to field in main editor

### 📊 Export & Debug Tools
- **Export to JSON:** Convert binary saves to readable JSON for external processing or version control
- **Hex Dump View:** Inspect raw binary data with address/hex/ASCII display
- **Debug Console:** Real-time logging with verbose mode for troubleshooting
- **Statistics Panel:** Record counts, type breakdown, library information

---

## 🛠️ Tech Stack

- **Framework:** Flutter (Material 3 Design)
- **Language:** Dart
- **Key Packages:**
  - `file_picker`: Cross-platform file selection
  - `file_selector`: Native file save dialogs
  - `universal_html`: Web download support
  - `path_provider`: Native storage locations

---

## 📦 Installation & Running

### Prerequisites
- Flutter SDK 3.0 or higher
- Dart SDK 3.0 or higher

### Setup

1. **Clone the repository:**
```bash
   git clone https://github.com/CrispStrobe/nrbf-editor.git
   cd nrbf-editor
```

2. **Install dependencies:**
```bash
   flutter pub get
```

3. **Run the app:**
```bash
   # Web (Chrome)
   flutter run -d chrome

   # Desktop (macOS)
   flutter run -d macos

   # Desktop (Windows)
   flutter run -d windows

   # Desktop (Linux)
   flutter run -d linux
```

4. **Build for production:**
```bash
   # Web
   flutter build web

   # macOS App
   flutter build macos

   # Windows
   flutter build windows
```

---

## 📖 Usage Guide

### Basic Editing

1. **Open File:** Click "Open File" and select a `.sav`, `.dat`, or any NRBF file
2. **Validation:** Tool validates NRBF header and displays decode statistics
3. **Navigation:** 
   - Expand/collapse tree nodes to browse structure
   - Use search bar to find specific fields
   - Click search results to jump to location
4. **Edit Values:**
   - Click pencil icon or tap field to edit primitives
   - For GUIDs: Use preset dropdown (if available) or manual edit button
5. **Save:** Click "Save" to write changes back to binary format

### Using Presets

1. **Auto-Detection:** Preset automatically selected if game is recognized
2. **Manual Selection:** Click game preset dropdown in toolbar to choose
3. **Preset Fields Panel:** Click 🎵 icon to view all preset-enabled fields
4. **Favorites:** Click ⭐ on any field to bookmark it
5. **Editing with Presets:**
   - Fields with presets show dropdown selector
   - Search/filter through preset options
   - Manual edit still available via pencil icon

### Managing Presets

1. **Open Preset Editor:** Click ⚙️ icon in toolbar
2. **Create New Preset:**
   - Set game type ID and display name
   - Add detection hints (class/library name fragments)
3. **Add Field Presets:**
   - Define path pattern and match mode
   - Select value type (GUID/String/Int/Float)
   - Add entries with friendly names
4. **Import/Export:**
   - Share presets as JSON files
   - Import community-created presets

### Comparing Save Files

1. **Open Comparison Tool:** Click ⇄ icon in toolbar
2. **Load Files:**
   - Select "BEFORE" file (e.g., before buying item)
   - Select "AFTER" file (e.g., after buying item)
3. **Review Changes:**
   - See all modified, added, and removed fields
   - Filter by change type
   - Search within changes
4. **Quick Actions:**
   - Add changed fields to favorites
   - Create preset entries from discovered values
   - Jump to field in main editor

---

## 🎮 Supported Games

### Officially Supported (with bundled presets)
- **Wobbly Life** - Vehicle IDs (44 vehicles)

### Compatible (manual preset creation needed)
- Any Unity game using NRBF serialization
- .NET applications using BinaryFormatter
- Games using similar save formats

**Want to add support for your game?**
1. Load a save file
2. Use File Comparison to discover changeable fields
3. Create preset entries for common values
4. Export and share your preset!

---

## 🤝 Contributing

Contributions are welcome! Please open an issue or pull request on GitHub.

---

## 📝 File Structure
```
lib/
├── main.dart              # Main editor UI and tree view
├── nrbf/
│   └── nrbf.dart         # NRBF decoder/encoder
├── presets/
│   ├── preset_models.dart          # Data models
│   ├── preset_storage.dart         # Cross-platform storage
│   ├── preset_manager.dart         # Business logic
│   ├── preset_selector_widget.dart # Dropdown UI
│   └── preset_editor_screen.dart   # Full CRUD editor
├── diff/
│   ├── diff_models.dart    # Change tracking models
│   ├── diff_engine.dart    # Comparison logic
│   └── diff_screen.dart    # Comparison UI
└── assets/
    └── presets/
        └── wobbly_life.json  # Bundled preset
```

---

## ⚠️ Important Notes

### Data Safety
- **Always backup save files before editing**
- Test changes in a copy first
- Some games validate save integrity (checksums, signatures)
- Structural changes may corrupt saves

### Limitations
- Cannot add/remove fields (only edit existing values)
- Cannot modify array lengths
- Complex reference structures may not be fully editable
- Some games use additional encryption/compression

### Best Practices
1. Make incremental changes
2. Test in-game after each edit
3. Keep original backups
4. Use File Comparison to understand game mechanics
5. Share discovered presets with community

---

## 🐛 Troubleshooting

**"Invalid NRBF Header" error:**
- File may be compressed or encrypted
- Try different save slot
- Some games use custom formats

**"Changes not appearing in game:"**
- Game may cache data
- Try clearing game cache
- Check for cloud save synchronization
- Game may validate save integrity

**"Comparison showing no changes:"**
- Ensure files are different versions
- Check if game uses compression
- Enable verbose logging for details

**"Preset not auto-detecting:"**
- Check detection hints in Preset Editor
- Manually select preset from dropdown
- Create custom preset with correct hints

---

## 📄 License

GNU AGPL v3.0

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

---

## 🔗 Links

- **GitHub:** https://github.com/CrispStrobe/nrbf-editor
- **Demo:** https://nrbfeditor.vercel.app/
- **Issues:** https://github.com/CrispStrobe/nrbf-editor/issues

**Made with ❤️ for the modding community**