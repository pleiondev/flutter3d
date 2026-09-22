/// That the skills this package ships are shaped the way an agent host reads
/// them — `rel-14`'s own row, `flutter3d/test/skills_test.dart`'s shape
/// minus the checks that need a `bin/skills.dart` entry point this package
/// does not have; `tool/structure.dart`'s own `_skillNames` rule already
/// checks the package-prefix half of this across every package in the
/// repository, and this is the package-local half that rule leaves to a
/// test that actually reads each `SKILL.md`.
///
///     dart test test/skills_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';

Directory get _thisPackage => Directory.current;

Directory get _skills => Directory('${_thisPackage.path}/skills');

/// Every directory under `skills/`, whether or not it holds a `SKILL.md` —
/// the point of several checks below is to catch one that does not.
List<Directory> get _skillDirectories =>
    _skills.listSync().whereType<Directory>().toList()
      ..sort((Directory a, Directory b) => a.path.compareTo(b.path));

/// The value of a one-line `key: value` in a `---` frontmatter block.
String? _frontmatter(String text, String key) {
  final lines = text.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') return null;
  for (final line in lines.skip(1)) {
    if (line.trim() == '---') return null;
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    if (line.substring(0, colon).trim() != key) continue;
    return line.substring(colon + 1).trim();
  }
  return null;
}

void main() {
  group('the skills this package ships', () {
    test('are there, and skills/ holds at least one', () {
      // Mutation: rename or remove `skills/` — fails here.
      expect(
        _skills.existsSync(),
        isTrue,
        reason:
            'rel-14 promises editing-order, project-document and '
            'what-it-refuses',
      );
      expect(
        _skillDirectories,
        isNotEmpty,
        reason: 'a skills/ with nothing in it installs nothing',
      );
    });

    test('and each one is a directory holding a SKILL.md', () {
      // Mutation: delete any one SKILL.md, leaving its directory — fails
      // here, rather than the directory being copied whole and read by
      // nobody.
      for (final Directory directory in _skillDirectories) {
        expect(
          File('${directory.path}/SKILL.md').existsSync(),
          isTrue,
          reason: '${directory.path} has no SKILL.md',
        );
      }
    });

    test('and every one says what it is and when to use it', () {
      // Mutation: drop the `description:` line from any SKILL.md — fails
      // here. A skill with no description is one an agent never loads.
      for (final Directory directory in _skillDirectories) {
        final String text = File(
          '${directory.path}/SKILL.md',
        ).readAsStringSync();
        final String where = directory.path.split('/').last;
        expect(
          _frontmatter(text, 'name'),
          isNotNull,
          reason: '$where/SKILL.md has no name in its frontmatter',
        );
        expect(
          _frontmatter(text, 'description'),
          isNotNull,
          reason: '$where/SKILL.md has no description in its frontmatter',
        );
        expect(
          _frontmatter(text, 'description'),
          isNot(isEmpty),
          reason: '$where/SKILL.md has an empty description',
        );
      }
    });

    test('and the name in the file is the name of the directory', () {
      // Mutation: change the `name:` in any SKILL.md to something else —
      // fails here. Installed under one name, invoked under another
      // otherwise.
      for (final Directory directory in _skillDirectories) {
        final String where = directory.path.split('/').last;
        final String text = File(
          '${directory.path}/SKILL.md',
        ).readAsStringSync();
        expect(
          _frontmatter(text, 'name'),
          where,
          reason: '$where/SKILL.md names itself something else',
        );
      }
    });

    test('and every directory is named for this package', () {
      // The same check `tool/structure.dart`'s own `_skillNames` rule makes
      // across every package in the repository, kept here too: a skill this
      // test walks by directory and a skill that rule walks by directory
      // are the same list, and a regression in one is worth catching from
      // either side.
      for (final Directory directory in _skillDirectories) {
        final String where = directory.path.split('/').last;
        expect(
          where,
          startsWith('flutter3d-model-mcp-'),
          reason: '$where is not named for this package',
        );
      }
    });
  });
}
