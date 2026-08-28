import 'dart:io';

/// Where a level document actually is.
///
/// **A relative path is relative to the process, and a process is not where
/// anybody thinks it is.** `flutter run -d macos` builds a bundle and launches
/// it; the bundle's working directory is `/`, not the directory the command was
/// typed in — so `../flutter3d_demo_dungeon/assets/levels/crypt.json` opened nothing and said
/// only that there was no such file. The path was right and the place it was
/// being read from was not.
///
/// So a relative path is looked for from every directory above the executable
/// and above the working directory, nearest first. In this repository the
/// executable sits at `apps/flutter3d_editor/build/macos/Build/Products/Debug/…`, so
/// walking up reaches `apps/flutter3d_editor`, where `../flutter3d_demo_dungeon/…` is exactly right —
/// and it reaches the repository root too, where `apps/flutter3d_demo_dungeon/…` is. Both
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

  /// The directory a level's own `assets/…` paths are relative to.
  ///
  /// **A document says `assets/textures/floor_albedo.jpg` and means its own
  /// application's**, which for `apps/flutter3d_demo_dungeon/assets/levels/crypt.json` is
  /// `apps/flutter3d_demo_dungeon`. A game never has to work this out — its assets are in its
  /// own bundle — and an editor always does, because the document it has open
  /// belongs to somebody else.
  ///
  /// Found by climbing until a directory has an `assets` in it, rather than by
  /// counting two levels up: `assets/levels/` is this repository's habit and
  /// not a rule, and a document sitting directly in `assets/` would break a
  /// count.
  static String? assetRootFor(
    String levelPath, {
    required bool Function(String) hasAssets,
  }) {
    var directory = _parent(_normalise(levelPath));
    while (directory != null) {
      if (hasAssets('$directory/assets')) return directory;
      final parent = _parent(directory);
      if (parent == directory) return null;
      directory = parent;
    }
    return null;
  }

  /// **POSIX only, and said out loud rather than assumed.**
  ///
  /// A Windows path — `C:\levels\first.json` — is absolute and this reads it
  /// as relative, so it would be joined onto every search root and found
  /// nowhere. That is the whole of what is wrong here, and it costs nothing
  /// today: this editor is macOS-only ([main.dart] says so in its first
  /// paragraph, and there is no `windows/` directory in the tree). It is
  /// written down because this is the file that decides where somebody's work
  /// is read from and written to, and a silent wrong answer there is the
  /// expensive kind.
  ///
  /// The fix, when there is a Windows build to fix it for, is `package:path`'s
  /// `Context` rather than more cases here — it is already a transitive
  /// dependency.
  static bool _isAbsolute(String path) =>
      path.startsWith('/') || _hasDriveLetter(path);

  /// `C:\` and `C:/`, which is enough to stop treating one as relative.
  static bool _hasDriveLetter(String path) =>
      path.length >= 3 &&
      (path[1] == ':') &&
      (path[2] == '/' || path[2] == r'\') &&
      RegExp('[A-Za-z]').hasMatch(path[0]);

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
