import 'dart:convert';
import 'dart:io';

import 'package:init/init.dart';
import 'package:test/test.dart';

/// This test's own working directory, when run through `dart test` from
/// `tool/init`, is `tool/init` itself — three `..` up is the checkout root,
/// the same arithmetic `bin/init.dart` does from its own script path.
String get _repositoryRoot => Directory.current.parent.parent.absolute.path;

String get _templatesRoot => defaultTemplatesRoot(_repositoryRoot);

void main() {
  test('the four genres this repository ships are the four --list names', () {
    expect(availableTemplates(_templatesRoot), <String>[
      'platformer',
      'racing',
      'shooter',
      'strategy',
    ]);
  });

  test(
    'an unknown genre names what it does know instead of crashing blind',
    () {
      expect(
        () => writeProject(
          templatesRoot: _templatesRoot,
          genre: 'not-a-real-genre',
          targetDirectory: Directory.systemTemp.path,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('platformer'),
          ),
        ),
      );
    },
  );

  for (final genre in <String>['platformer', 'racing', 'shooter', 'strategy']) {
    group(genre, () {
      late Directory target;

      setUp(() {
        target = Directory.systemTemp.createTempSync('flutter3d_init_test_');
      });

      tearDown(() {
        target.deleteSync(recursive: true);
      });

      test('writes a pubspec naming the project, not a path dependency', () {
        writeProject(
          templatesRoot: _templatesRoot,
          genre: genre,
          targetDirectory: target.path,
          projectName: 'my_${genre}_game',
        );

        final pubspec = File('${target.path}/pubspec.yaml').readAsStringSync();
        expect(pubspec, contains('name: my_${genre}_game'));
        expect(pubspec, isNot(contains('path:')));
        expect(pubspec, contains('flutter3d: ^0.7.0'));
      });

      test('writes a starter level a genre-agnostic reader can parse', () {
        writeProject(
          templatesRoot: _templatesRoot,
          genre: genre,
          targetDirectory: target.path,
        );

        final level =
            jsonDecode(
                  File(
                    '${target.path}/assets/levels/first.json',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        // `_disown` (in `scaffold.dart`) strips `generatedBy` so the level
        // belongs to whoever scaffolded it, not to the Python script that
        // built the template — the same check `scaffold_test.dart` in
        // `flutter3d_editor_core` already runs on the function directly;
        // here it is checked end to end, through this CLI's own file writes.
        expect(level.containsKey('generatedBy'), isFalse);
      });

      test('every file the manifest lists actually landed on disk', () {
        writeProject(
          templatesRoot: _templatesRoot,
          genre: genre,
          targetDirectory: target.path,
        );

        final manifest =
            jsonDecode(
                  File('$_templatesRoot/$genre/index.json').readAsStringSync(),
                )
                as Map<String, Object?>;
        final files = manifest['files']! as Map<String, Object?>;
        for (final destination in files.values.cast<String>()) {
          expect(
            File('${target.path}/$destination').existsSync(),
            isTrue,
            reason: destination,
          );
        }
      });

      test('running it twice writes byte-for-byte the same project', () {
        writeProject(
          templatesRoot: _templatesRoot,
          genre: genre,
          targetDirectory: target.path,
          projectName: 'again',
        );
        final before = _readAll(target);

        writeProject(
          templatesRoot: _templatesRoot,
          genre: genre,
          targetDirectory: target.path,
          projectName: 'again',
        );
        final after = _readAll(target);

        expect(after, before);
      });
    });
  }
}

/// Every file under [target], by its path relative to it, as bytes — for an
/// exact idempotency check that a file count alone would miss.
Map<String, List<int>> _readAll(Directory target) => <String, List<int>>{
  for (final entry in target.listSync(recursive: true))
    if (entry is File)
      entry.path.substring(target.path.length + 1): entry.readAsBytesSync(),
};
