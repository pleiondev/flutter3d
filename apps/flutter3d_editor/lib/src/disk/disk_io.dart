/// The disk, on a desktop: what the editor always did, behind [EditorDisk].
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter3d_app/native.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart'
    show projectAt;

import '../documents.dart';
import 'editor_disk.dart';

EditorDisk platformDisk() => const IoDisk();

/// `dart:io`, and nothing cleverer.
final class IoDisk implements EditorDisk {
  const IoDisk();

  @override
  bool get savesInPlace => true;

  @override
  List<String> searchFrom() => Documents.searchFrom(
    working: Directory.current.path,
    executable: Platform.resolvedExecutable,
  );

  @override
  String absolute(String path) =>
      File(path).isAbsolute ? path : '${Directory.current.path}/$path';

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  bool hasDirectory(String path) => Directory(path).existsSync();

  @override
  bool hasFilesUnder(String path) {
    final directory = Directory(path);
    return directory.existsSync() && directory.listSync().isNotEmpty;
  }

  @override
  Future<String> readText(String path) => File(path).readAsString();

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  /// **Atomically, which it was not.** This wrote a person's hand-built level
  /// with a bare `writeAsString` while settings and saves — documents a game
  /// can afford to lose — have gone through a temporary and a rename since
  /// they were written. A crash or a full disk halfway through left a
  /// truncated level where the good one had been, so one lost session became
  /// every future one.
  @override
  Future<String> writeDocument(String path, String text) async {
    await writeFileAtomically(path, text);
    return 'written to $path';
  }

  /// Beside the define's own project, not inside it, so a second template
  /// does not have to fight the first one for the same folder.
  @override
  String newProjectRoot(String levelPath, String name) =>
      '${File(projectAt(absolute(levelPath)).root).parent.path}/$name';

  @override
  Future<String?> writeProject(
    String root,
    Map<String, Uint8List> files,
  ) async {
    for (final entry in files.entries) {
      final file = File('$root/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.value);
    }
    return null;
  }

  /// The system's open panel. The macOS sandbox is off for this application
  /// already — see `macos/Runner/*.entitlements`, which explains why — so a
  /// chosen path is readable and writable the same way a `--dart-define` one
  /// is. The panel is here to save somebody typing a path, not to buy access.
  @override
  Future<String?> choose(XTypeGroup group) async =>
      (await openFile(acceptedTypeGroups: <XTypeGroup>[group]))?.path;

  @override
  Future<bool> saveAs(
    String suggestedName,
    String text,
    XTypeGroup group,
  ) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: <XTypeGroup>[group],
    );
    if (location == null) return false;
    // Sync: what goes through here is a few kilobytes of JSON — not the kind
    // of write async I/O exists to keep off a frame.
    File(location.path).writeAsStringSync(text);
    return true;
  }
}
