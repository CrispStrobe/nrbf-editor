# NRBF Editor

A cross-platform tool for viewing, editing, and converting **.NET Binary Format (NRBF)** files. 

This format is commonly used by Unity games and .NET applications for serializing object graphs (esp. Game Save files). This tool allows you to modify primitive values deep within the binary structure without needing the original source code.

Demo: https://nrbfeditor.vercel.app/

This is work in progress, so use after backing up your data only.

## 🚀 Features

- **Universal Decoding:** Parses complex NRBF structures including nested Classes, Arrays, and Dictionaries.
- **Visual Editor:** Tree-based navigation of the object graph.
- **Deep Search:** Recursive search functionality to find keys, values, or class names anywhere in the file (supports Regex-like partial matching).
- **Type Handling:** - Special rendering for `System.Guid`.
  - Support for `BinaryArray`, `Primitive`, and `Object` records.
- **Editing:** Modify Strings, Booleans, Integers, and Floating-point numbers.
- **Export Tools:** - **Export to JSON:** Convert binary save files to readable JSON for diffing or external processing.
  - **Hex Dump:** Debug view for inspecting raw binary data.
- **Cross-Platform:** - Runs in the browser (using `universal_html`).
  - Runs natively on desktop (using `dart:io`).

## 🛠️ Tech Stack

- **Framework:** Flutter (Material 3)
- **Language:** Dart
- **Key Packages:**
  - `file_picker`: For cross-platform file selection.
  - `file_selector`: For saving files on desktop.
  - `universal_html`: For web download support.

## 📦 Installation & Running

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/CrispStrobe/nrbf-editor.git](https://github.com/CrispStrobe/nrbf-editor.git)
   cd nrbf-editor

```

2. **Install dependencies:**
```bash
flutter pub get

```


3. **Run the app (examples):**
```bash
# Run on Chrome
flutter run -d chrome

# Run on Desktop
flutter run -d macos

```

## 📖 How to Use (simple example)

1. Click **Open File** and select a `.sav` or `.dat` file.
2. If the file has a valid NRBF header, the tree view will populate.
3. Use the **Search Bar** to find a specific variable (e.g., "Money", "XP").
4. Click on a search result to jump to its location in the tree.
5. Click on any primitive value (blue text) to **Edit** it.
6. Click **Save** to write the changes back to a binary file.

## ⚠️ Disclaimer

**Always backup your save files before editing.** While the NRBF encoder tries to preserve the structure exactly, binary serialization is fragile. Incorrectly editing values or structural modifications may corrupt your save file.

Plus, this is work in progress.

## 📄 License

GNU APGL v.3
