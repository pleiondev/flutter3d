/// The one directory an MCP server's file tools read and write inside.
library;

import 'dart:io';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

/// The directory a server's file tools are held to, and the one place a
/// path an agent sent becomes a path on the disk.
///
/// **Every path a tool takes goes through [resolve], or it is a hole.** An
/// agent's arguments are whatever a model read out of a prompt, and a prompt
/// can be somebody else's text: a level, a README, a web page. A `save` to
/// `../../.ssh/authorized_keys` or an `open` of `/etc/passwd` whose parse
/// error quotes the first line back is the same tool call as a fair one,
/// so the check is made where the path arrives and not trusted to callers.
///
/// **Inside means inside after the links are followed.** A path is made
/// absolute against [path], its `.` and `..` folded away, and then the
/// deepest part of it that exists is resolved through its symbolic links; a
/// link inside the root that points out of it is refused like a `..`. A
/// link that points nowhere is refused too, since writing through one writes
/// wherever it is later made to point.
final class ProjectRoot {
  /// The root at [directory], made absolute and with its links resolved;
  /// a directory that does not exist yet is taken as written.
  ProjectRoot(String directory) : path = _canonical(_absolute(directory));

  /// The root a document at [documentPath] belongs to: the nearest directory
  /// above it with a `pubspec.yaml`, as `flutter run` finds a project, or
  /// the document's own directory when there is none. With no document, the
  /// working directory this process was started in.
  factory ProjectRoot.around(String? documentPath) {
    if (documentPath == null) return ProjectRoot(Directory.current.path);
    final directory = File(_absolute(documentPath)).parent;
    final project = _upwards(directory).where(
      (Directory it) =>
          File('${it.path}${Platform.pathSeparator}pubspec.yaml').existsSync(),
    );
    return ProjectRoot(project.firstOrNull?.path ?? directory.path);
  }

  /// The root, absolute, its links resolved, with no trailing separator.
  final String path;

  /// [requested] as an absolute path inside this root.
  ///
  /// A relative path is read from [path]; an absolute one is taken only when
  /// it lies inside. Throws a [PathOutsideRootException] for anything else: a path
  /// that leaves by `..`, an absolute path elsewhere, a link out, a link to
  /// nothing, an empty path or one with a NUL in it.
  String resolve(String requested) {
    if (requested.isEmpty || requested.contains('\u0000')) {
      throw PathOutsideRootException(
        requested,
        root: path,
        why: 'it is not a path',
      );
    }
    final absolute = _absolute(requested, against: path);
    // Follow the links of the part of the path that is there; the rest is
    // what a write is about to create, and has no links to follow yet.
    final (:existing, :rest) = _split(absolute);
    final String real;
    try {
      real = _canonical(existing);
    } on FileSystemException {
      throw PathOutsideRootException(
        requested,
        root: path,
        why: 'it goes through a link that points nowhere',
      );
    }
    final resolved = rest.isEmpty
        ? real
        : '$real${Platform.pathSeparator}'
              '${rest.join(Platform.pathSeparator)}';
    // Judged on the resolved path alone: the text may reach the root through
    // a link of its own (`/var` is `/private/var` on macOS) and be inside,
    // or stay inside by its text and leave through a link.
    if (!_inside(resolved)) {
      throw PathOutsideRootException(
        requested,
        root: path,
        why: _inside(absolute) ? 'a link in it leads out of the project' : null,
      );
    }
    return resolved;
  }

  /// [resolve], with the refusal as a sentence: `(path: …, refused: null)`
  /// or `(path: null, refused: …)`, for a tool that answers rather than
  /// throws.
  ({String? path, String? refused}) tryResolve(String requested) {
    try {
      return (path: resolve(requested), refused: null);
    } on PathOutsideRootException catch (outside) {
      return (path: null, refused: outside.message);
    }
  }

  bool _inside(String absolute) {
    final root = _segments(path);
    final it = _segments(absolute);
    if (it.length < root.length) return false;
    for (var i = 0; i < root.length; i++) {
      if (!_sameSegment(root[i], it[i])) return false;
    }
    return true;
  }

  /// [absolute] split into the longest prefix that exists on the disk (a
  /// link that points nowhere counts as existing, so it is resolved and
  /// refused) and the segments after it.
  ({String existing, List<String> rest}) _split(String absolute) {
    final segments = _segments(absolute);
    for (var keep = segments.length; keep > 0; keep--) {
      final candidate = _join(absolute, segments.take(keep));
      if (FileSystemEntity.typeSync(candidate, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return (existing: candidate, rest: segments.sublist(keep));
      }
    }
    return (existing: _join(absolute, const <String>[]), rest: segments);
  }

  @override
  String toString() => 'ProjectRoot($path)';
}

/// A path a file tool was handed that lies outside its [ProjectRoot].
final class PathOutsideRootException extends ResourceException {
  const PathOutsideRootException(
    this.requested, {
    required this.root,
    this.why,
  });

  /// The path as the caller sent it.
  final String requested;

  /// The root it had to be inside.
  final String root;

  /// What about it was refused, when it is more than lying outside.
  final String? why;

  @override
  String get message =>
      '"$requested" is refused: ${why ?? 'it is outside the project'} '
      '(file tools read and write inside $root)';

  @override
  String toString() => 'PathOutsideRootException: $message';
}

final bool _windows = Platform.isWindows;

/// [p] as an absolute path with `.` and `..` folded away, read against
/// [against] (the working directory when null) when relative.
String _absolute(String p, {String? against}) {
  final base = against ?? Directory.current.path;
  final Uri uri = Uri.file(p, windows: _windows);
  final Uri absolute = uri.isAbsolute || uri.hasAbsolutePath
      ? uri
      : Uri.directory(base, windows: _windows).resolveUri(uri);
  final folded = absolute.normalizePath().toFilePath(windows: _windows);
  return folded.length > 1 && _isSeparator(folded[folded.length - 1])
      ? folded.substring(0, folded.length - 1)
      : folded;
}

/// [absolute] with its links resolved, when it exists; as it is otherwise.
String _canonical(String absolute) =>
    FileSystemEntity.typeSync(absolute, followLinks: false) ==
        FileSystemEntityType.notFound
    ? absolute
    : File(absolute).resolveSymbolicLinksSync();

Iterable<Directory> _upwards(Directory from) sync* {
  var at = from.absolute;
  while (true) {
    yield at;
    final up = at.parent;
    if (up.path == at.path) return;
    at = up;
  }
}

bool _isSeparator(String c) => c == '/' || (_windows && c == r'\');

List<String> _segments(String absolute) => <String>[
  for (final s in absolute.split(_windows ? RegExp(r'[\\/]') : RegExp('/')))
    if (s.isNotEmpty) s,
];

bool _sameSegment(String a, String b) =>
    _windows ? a.toLowerCase() == b.toLowerCase() : a == b;

/// The first [keep] segments of [absolute] as a path again, with the root
/// (`/`, or a drive or share on Windows) [absolute] started with.
String _join(String absolute, Iterable<String> keep) {
  final sep = Platform.pathSeparator;
  final joined = keep.join(sep);
  if (!_windows) return '/$joined';
  // `C:\a` keeps its drive as the first segment; `\\server\share\a` its
  // leading pair of separators.
  if (absolute.startsWith(r'\\')) return '\\\\$joined';
  return joined.endsWith(':') ? '$joined$sep' : joined;
}
