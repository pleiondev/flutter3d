/// What a plugin teaches the editor about files: importers that bring one in
/// from outside the project, and asset-browser entries that say what a file
/// of the project is and what dropping it into the level does.
library;

import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'editor_command.dart';

/// A file to import, and where it is going.
///
/// Made by the editor, never by a plugin. **One object, so it can grow.**
final class ImportRequest {
  ImportRequest({
    required this.path,
    required this.bytes,
    required this.level,
    Vector3? at,
  }) : at = at?.clone();

  /// Where the file was picked from, outside the project.
  final String path;

  /// Its bytes.
  final Uint8List bytes;

  /// The level open in the editor.
  final Level level;

  /// Where in the level the person dropped it, or null for an import from a
  /// menu.
  final Vector3? at;

  /// The file's name, without its directory.
  String get name => path.split(RegExp(r'[\\/]')).last;
}

/// What an import produced: files to write into the project, commands to run
/// on the level, and what to tell the person.
final class ImportResult {
  const ImportResult({
    this.files = const <String, Uint8List>{},
    this.commands = const <DocumentCommand>[],
    this.notes = const <String>[],
  });

  /// Files to write, by path relative to the project's root.
  final Map<String, Uint8List> files;

  /// Commands to run on the level once the files are written, in order, as
  /// one step of undo each.
  final List<DocumentCommand> commands;

  /// Sentences for the console: what was carried and what was not.
  final List<String> notes;
}

/// Brings a kind of file into a project: reads it, writes what the project
/// keeps, and says what to do to the level.
///
/// **The editor writes the files, not the importer**, so an importer works
/// the same in a browser, where the project is in memory, and an agent can
/// run it through the editor's MCP server. `base`, so a member added in a
/// minor arrives with a body; the hook takes one request.
abstract base class EditorImporter {
  const EditorImporter();

  /// What a menu says: `Boat hull`.
  String get label;

  /// The suffixes it reads (`.boat`), compared without case.
  List<String> get suffixes;

  /// Reads [request]. Throws a `Flutter3dException` for a file it cannot
  /// read, which the editor says rather than half-importing.
  Future<ImportResult> import(ImportRequest request);
}

/// An importer an editor has, by the name it is published under.
final class AddedImporter {
  const AddedImporter(this.name, this.importer);

  /// `<pluginId>.<name>`, or the application's own name.
  final String name;

  final EditorImporter importer;
}

/// Where a file from the asset browser was dropped.
///
/// Made by the editor, never by a plugin.
final class AssetPlacement {
  AssetPlacement({required this.path, required Vector3 at, required this.level})
    : at = at.clone();

  /// The file's path, relative to the project's assets.
  final String path;

  /// The point in the level it was dropped on.
  final Vector3 at;

  /// The level open in the editor.
  final Level level;
}

/// A kind of file the asset browser lists, and what dropping one into the
/// level does.
final class AssetBrowserEntry {
  const AssetBrowserEntry({
    required this.label,
    required this.suffixes,
    this.icon,
    this.place,
  });

  /// What the browser calls the kind: `Hull`.
  final String label;

  /// The suffixes a file of the kind ends in, compared without case.
  final List<String> suffixes;

  /// A name an editor's icon set knows (`model`, `level`, `material`), or
  /// null for a plain file.
  final String? icon;

  /// The command dropping one at a point is, or null for a file that is
  /// listed and not placed.
  final DocumentCommand? Function(AssetPlacement placement)? place;

  /// Whether [path] ends in one of [suffixes].
  bool matches(String path) {
    final lower = path.toLowerCase();
    return suffixes.any((String s) => lower.endsWith(s.toLowerCase()));
  }
}

/// An asset-browser entry an editor has, by the name it is published under.
final class AddedAssetEntry {
  const AddedAssetEntry(this.name, this.entry);

  /// `<pluginId>.<name>`, or the editor's own name.
  final String name;

  final AssetBrowserEntry entry;
}

/// The kinds of file the editor lists without a plugin, by name. A plugin's
/// entry is asked first, so a plugin may claim a suffix listed here.
const List<AddedAssetEntry> builtInAssetEntries = <AddedAssetEntry>[
  AddedAssetEntry(
    'level',
    AssetBrowserEntry(
      label: 'Level',
      suffixes: <String>['.json'],
      icon: 'level',
    ),
  ),
  AddedAssetEntry(
    'model',
    AssetBrowserEntry(
      label: 'Model',
      suffixes: <String>['.glb', '.gltf', '.obj', '.f3d'],
      icon: 'model',
    ),
  ),
  AddedAssetEntry(
    'material',
    AssetBrowserEntry(
      label: 'Material',
      suffixes: <String>['.fmat', '.f3dmat'],
      icon: 'material',
    ),
  ),
  AddedAssetEntry(
    'texture',
    AssetBrowserEntry(
      label: 'Texture',
      suffixes: <String>['.png', '.jpg', '.jpeg', '.webp', '.ktx2', '.hdr'],
      icon: 'texture',
    ),
  ),
  AddedAssetEntry(
    'plugin',
    AssetBrowserEntry(
      label: 'Data plugin',
      suffixes: <String>['.f3dplugin'],
      icon: 'plugin',
    ),
  ),
];
