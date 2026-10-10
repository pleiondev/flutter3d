/// Keeping a conversion inside the directory its upload was unpacked into.
///
/// **The converters were written for somebody's own disk.** They follow the
/// paths a source file names — a USD reference, a MaterialX image, a Godot
/// `res://` path, a texture beside a Unity material — and on a laptop that
/// is the point. On a server the file was written by a stranger, and a
/// reference to `/etc/passwd` or to another account's stored model would be
/// read and, as a "texture", handed back in the download.
///
/// So the conversion runs under [IOOverrides] that answer every file,
/// directory and link outside [ConfinedFiles.root] as one that does not
/// exist. The converter then reports that reference the way it reports any
/// missing file: as something it could not carry over.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Runs [body] with every filesystem path outside [root] answered as a
/// missing file. [root] must be absolute.
Future<T> confinedTo<T>(String root, Future<T> Function() body) =>
    IOOverrides.runWithIOOverrides(body, ConfinedFiles(root));

/// The overrides [confinedTo] installs. Public so a test can ask what a path
/// would become.
final class ConfinedFiles extends IOOverrides {
  ConfinedFiles(String root) : root = p.normalize(root);

  /// The directory the upload was unpacked into, normalised.
  final String root;

  /// Where a path outside [root] is sent: a directory nothing creates, so
  /// whatever is asked of it there does not exist.
  String get _nowhere => p.join(root, '.outside-the-upload');

  /// [path] if it lies inside [root], otherwise a path that does not exist.
  ///
  /// Lexical: `..` is resolved by [p.normalize], not by the filesystem. The
  /// archive is unpacked by `zip_guard.dart`, which writes no links, so
  /// there is nothing inside [root] that a lexical answer would get wrong.
  String confine(String path) {
    final absolute = p.isAbsolute(path)
        ? p.normalize(path)
        : p.normalize(p.join(super.getCurrentDirectory().path, path));
    if (absolute == root || p.isWithin(root, absolute)) return absolute;
    return p.join(_nowhere, p.basename(absolute));
  }

  @override
  File createFile(String path) => super.createFile(confine(path));

  @override
  Directory createDirectory(String path) =>
      super.createDirectory(confine(path));

  @override
  Link createLink(String path) => super.createLink(confine(path));

  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) =>
      super.fseGetType(confine(path), followLinks);

  @override
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) =>
      super.fseGetTypeSync(confine(path), followLinks);

  @override
  Future<bool> fseIdentical(String path1, String path2) =>
      super.fseIdentical(confine(path1), confine(path2));

  @override
  bool fseIdenticalSync(String path1, String path2) =>
      super.fseIdenticalSync(confine(path1), confine(path2));

  @override
  Future<FileStat> stat(String path) => super.stat(confine(path));

  @override
  FileStat statSync(String path) => super.statSync(confine(path));

  /// The system temporary directory, which the converters only reach for
  /// to hand a file to an external program — never here — is the upload's
  /// own directory instead.
  @override
  Directory getSystemTempDirectory() => super.createDirectory(root);
}
