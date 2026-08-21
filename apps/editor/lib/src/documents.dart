import 'dart:io';

/// Where a level document actually is.
///
/// **A relative path is relative to the process, and a process is not where
/// anybody thinks it is.** `flutter run -d macos` builds a bundle and launches
/// it; the bundle's working directory is `/`, not the directory the command was
/// typed in — so `../dungeon/assets/levels/crypt.json` opened nothing and said
/// only that there was no such file. The path was right and the place it was
/// being read from was not.
///
/// So a relative path is looked for from every directory above the executable
/// and above the working directory, nearest first. In this repository the
/// executable sits at `apps/editor/build/macos/Build/Products/Debug/…`, so
/// walking up reaches `apps/editor`, where `../dungeon/…` is exactly right —
/// and it reaches the repository root too, where `apps/dungeon/…` is. Both
/// spellings of the same intention work, which is the point: nobody should have
/// to know which directory an application bundle thinks it is in.
abstract final class Documents {
  /// The absolute path [path] means, or null if it is nowhere.
  ///
  /// [exists] is injected so this can be tested without a disk. [from] is the
  /// list of directories to try, nearest first — [searchFrom] builds the real
  /// one.
  static String? find(
    String path, {
    required List<String> from,
    required bool Function(String) exists,
  }) {
    for (final candidate in candidates(path, from: from)) {
      if (exists(candidate)) return candidate;
    }
    return null;
  }

  /// Every place [path] might be, nearest first.
  ///
  /// An absolute path is only ever itself: somebody who typed one has said
  /// where the file is, and searching would be second-guessing them.
  static List<String> candidates(String path, {required List<String> from}) {
    if (_isAbsolute(path)) return <String>[_normalise(path)];
    return <String>[
      for (final directory in from) _normalise('$directory/$path'),
    ];
  }

  /// The directories to look in: every one above the executable and above the
  /// working directory, nearest first, without repeats.
  ///
  /// The working directory first, because a person running from a terminal has
  /// said something by being where they are, and the bundle has not.
  static List<String> searchFrom({String? executable, String? working}) {
    final roots = <String>[];
    void climb(String? path) {
      if (path == null) return;
      var directory = _normalise(path);
      while (true) {
        if (!roots.contains(directory)) roots.add(directory);
        final parent = _parent(directory);
        if (parent == null || parent == directory) return;
        directory = parent;
      }
    }

    climb(working ?? Directory.current.path);
    climb(_parent(executable ?? Platform.resolvedExecutable));
    return roots;
  }

  /// What to say when it is nowhere. Names the places rather than the file,
  /// because "no such file" about a path that is plainly there is the least
  /// useful sentence a program can produce.
  static String couldNotFind(String path, List<String> tried) => <String>[
        'no level document at "$path".',
        'Looked in:',
        ...tried.take(8).map((String it) => '  $it'),
        if (tried.length > 8) '  … and ${tried.length - 8} more',
      ].join('\n');

  static bool _isAbsolute(String path) => path.startsWith('/');

  static String? _parent(String path) {
    final at = path.lastIndexOf('/');
    if (at <= 0) return at == 0 && path.length > 1 ? '/' : null;
    return path.substring(0, at);
  }

  /// Resolves `.` and `..` without touching the disk, so a candidate that does
  /// not exist can still be printed as the path it means.
  static String _normalise(String path) {
    final absolute = _isAbsolute(path);
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty && parts.last != '..') {
          parts.removeLast();
          continue;
        }
        if (absolute) continue;
      }
      parts.add(part);
    }
    return '${absolute ? '/' : ''}${parts.join('/')}';
  }
}
