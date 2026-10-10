/// Where this editor's documents are read from and written to.
///
/// **Every file the editor touches goes through here, so a browser can be a
/// place the editor runs.** On a desktop that is the disk, the way it always
/// was: a level is opened from a path, written back over itself atomically,
/// and a new project is a directory of files beside the others. A browser has
/// no disk to give an application, so the web build (P11) keeps its
/// documents in the page — see `MemoryDisk` — opens one by reading the bytes
/// a person picks, and saves by handing the browser a download, because that
/// is the most a page is allowed to do.
///
/// One small interface rather than `kIsWeb` through `main.dart`, because the
/// difference is where the bytes live and not what the editor does with
/// them: `Documents`, `RecentProjects` and the templates ask the same
/// questions of either, and the answers are what changes.
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XTypeGroup;

import 'disk_io.dart' if (dart.library.js_interop) 'disk_web.dart';

/// What [EditorDisk] needs to know about the program it serves.
abstract interface class EditorDisk {
  /// True when a save writes over the file it came from, false when it hands
  /// the browser a download. What the chooser and the bar say depends on it.
  bool get savesInPlace;

  /// The directories a relative path is looked for in, nearest first — see
  /// `Documents.searchFrom`.
  List<String> searchFrom();

  /// [path] as an absolute path, for saying where something will land.
  String absolute(String path);

  /// Whether there is a file at [path].
  bool exists(String path);

  /// Whether there is a directory at [path].
  bool hasDirectory(String path);

  /// Whether a directory is at [path] and has anything in it — the question a
  /// template asks before writing a project there.
  bool hasFilesUnder(String path);

  Future<String> readText(String path);
  Future<Uint8List> readBytes(String path);

  /// Writes a level document at [path], and answers what the bar should say.
  ///
  /// Throws when it could not, which the caller turns into a sentence too.
  Future<String> writeDocument(String path, String text);

  /// Where a new project called [name] lands, given the level path the
  /// editor was asked to open.
  String newProjectRoot(String levelPath, String name);

  /// Writes a new project's [files], keyed by their path under [root].
  ///
  /// Answers something worth saying about where it went, or null when "the
  /// level is open" says it all.
  Future<String?> writeProject(String root, Map<String, Uint8List> files);

  /// Asks for one file of [group] and answers the path it can now be read
  /// at, or null when the person dismissed the panel.
  Future<String?> choose(XTypeGroup group);

  /// Puts [text] wherever the person says — a save panel on a desktop, a
  /// download in a browser. False when they said nowhere.
  Future<bool> saveAs(String suggestedName, String text, XTypeGroup group);
}

/// The disk this build has: `dart:io`'s on a desktop, the page's in a
/// browser.
final EditorDisk editorDisk = platformDisk();
