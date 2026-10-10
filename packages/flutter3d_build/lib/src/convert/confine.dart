/// Where a file a document names may be read from: inside one directory.
///
/// A glTF names its buffers and images, an OBJ its material library, a USD
/// layer the layers it references and its textures. A converter that opens
/// whatever they name is one that hands back `/etc/passwd` inside a `.f3d`
/// to whoever uploaded a glTF saying `"uri": "../../../../etc/passwd"`. So
/// every such reference is resolved against its document's directory and
/// read only when the result is still inside the root: the input's own
/// directory for `flutter3d convert`, the upload for `convertFiles`.
///
/// **Lexical, on purpose.** `..` and absolute paths are what a document can
/// say; a symbolic link inside the root is something the owner of the disk
/// put there, and following it is theirs to decide.
library;

import 'dart:io';

/// [reference], a path a document names, resolved against [directory]: the
/// absolute, normalised path, or null when it is not inside [root].
///
/// Backslashes count as separators, so `sub\..\..\x` climbs on every
/// platform, and a drive letter (`C:`) makes a path absolute.
String? resolveInside(
  String reference, {
  required String directory,
  required String root,
}) {
  final clean = reference.replaceAll(r'\', '/');
  final absolute = clean.startsWith('/') || _drive.hasMatch(clean);
  final path = normalizePath(
    absolute ? clean : '${Directory(directory).absolute.path}/$clean',
  );
  return isInside(path, root) ? path : null;
}

/// Whether [path] is [root] or lies below it.
bool isInside(String path, String root) {
  final base = normalizePath(Directory(root).absolute.path);
  final target = normalizePath(path);
  return target == base ||
      target.startsWith(base.endsWith('/') ? base : '$base/');
}

/// [path] with `.` and `..` segments folded and separators made `/`. A `..`
/// above the top of an absolute path stays at the top, as the file system
/// would have it.
String normalizePath(String path) {
  final clean = path.replaceAll(r'\', '/');
  final drive = _drive.firstMatch(clean)?[0] ?? '';
  final rest = clean.substring(drive.length);
  final rooted = rest.startsWith('/');
  final segments = <String>[];
  for (final segment in rest.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty && segments.last != '..') {
        segments.removeLast();
      } else if (!rooted) {
        segments.add('..');
      }
      continue;
    }
    segments.add(segment);
  }
  return '$drive${rooted ? '/' : ''}${segments.join('/')}';
}

/// The sentence a refused reference is reported with.
String outsideMessage(String reference, String root) =>
    '"$reference" names a file outside $root, which a converted document may '
    'not read from';

final RegExp _drive = RegExp(r'^[A-Za-z]:');
