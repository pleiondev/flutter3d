/// Where a level document actually is.
///
///     flutter test test/documents_test.dart
///
/// **The launch this exists because of.** The editor opened with
/// `--dart-define=level=../flutter3d_demo_dungeon/assets/levels/crypt.json`, which is exactly
/// right relative to `apps/flutter3d_editor`, and it said `PathNotFoundException: Cannot
/// open file`. The path was correct; the place it was being read from was not.
/// `flutter run -d macos` builds an application bundle and launches it, and a
/// bundle's working directory is `/`.
library;

import 'package:flutter3d_editor/src/documents.dart';
import 'package:flutter_test/flutter_test.dart';

/// A disk with exactly these files on it.
bool Function(String) _disk(Set<String> files) => files.contains;

void main() {
  const executable =
      '/repo/apps/flutter3d_editor/build/macos/Build/Products/Debug/editor.app'
      '/Contents/MacOS/editor';

  test('a path relative to the application is found from the bundle', () {
    // The failing launch, as a test. Nothing about the path changes — what
    // changes is that it is looked for from every directory above the
    // executable rather than from whatever the process calls "here".
    final roots = Documents.searchFrom(executable: executable, working: '/');

    final found = Documents.find(
      '../flutter3d_demo_dungeon/assets/levels/crypt.json',
      from: roots,
      exists: _disk(<String>{
        '/repo/apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
      }),
    );

    expect(found, '/repo/apps/flutter3d_demo_dungeon/assets/levels/crypt.json');
  });

  test('and so is the same file spelled from the repository root', () {
    // Both spellings of one intention. Nobody should have to know which
    // directory an application bundle thinks it is in.
    final roots = Documents.searchFrom(executable: executable, working: '/');

    final found = Documents.find(
      'apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
      from: roots,
      exists: _disk(<String>{
        '/repo/apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
      }),
    );

    expect(found, '/repo/apps/flutter3d_demo_dungeon/assets/levels/crypt.json');
  });

  test('and the working directory wins over the bundle', () {
    // A person running from a terminal has said something by being where they
    // are; a bundle launched by the window server has not.
    final roots = Documents.searchFrom(
      executable: executable,
      working: '/elsewhere/apps/flutter3d_editor',
    );

    final found = Documents.find(
      '../flutter3d_demo_dungeon/assets/levels/crypt.json',
      from: roots,
      exists: _disk(<String>{
        '/elsewhere/apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
        '/repo/apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
      }),
    );

    expect(
      found,
      '/elsewhere/apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
    );
  });

  test('and an absolute path is only ever itself', () {
    // Somebody who typed one has said where the file is, and searching would be
    // second-guessing them — and would open a different file with the same name
    // somewhere up the tree, which is worse than failing.
    expect(
      Documents.candidates(
        '/tmp/one.json',
        from: Documents.searchFrom(executable: executable, working: '/repo'),
      ),
      <String>['/tmp/one.json'],
    );
  });

  test('and a file that is nowhere is nowhere, not the nearest guess', () {
    final found = Documents.find(
      'nothing/here.json',
      from: Documents.searchFrom(executable: executable, working: '/'),
      exists: _disk(const <String>{}),
    );

    expect(found, isNull);
  });

  test('and what it could not find says where it looked', () {
    // "No such file" about a path that is plainly there is the least useful
    // sentence a program can produce.
    final tried = Documents.candidates(
      '../flutter3d_demo_dungeon/x.json',
      from: Documents.searchFrom(executable: executable, working: '/repo'),
    );

    final said = Documents.couldNotFind(
      '../flutter3d_demo_dungeon/x.json',
      tried,
    );

    expect(said, contains('Looked in:'));
    expect(said, contains('/flutter3d_demo_dungeon/x.json'));
    expect(
      said.split('\n').length,
      lessThan(12),
      reason: 'it printed the whole tree at somebody',
    );
  });

  group('the paths it builds', () {
    test('are resolved, so what it prints is what it means', () {
      final built = Documents.candidates(
        '../flutter3d_demo_dungeon/assets/levels/crypt.json',
        from: <String>['/repo/apps/flutter3d_editor'],
      );

      expect(
        built.single,
        '/repo/apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
      );
    });

    test('and a climb reaches the root and stops there', () {
      // The loop that has to end. An ancestor walk that mistook `/` for having
      // a parent would spin for ever, on the one platform this application
      // runs on.
      final roots = Documents.searchFrom(executable: '/a/b/c/x', working: '/');

      expect(roots, contains('/'));
      expect(roots.length, lessThan(8));
      expect(roots.toSet().length, roots.length, reason: 'it repeats itself');
    });
  });
}
