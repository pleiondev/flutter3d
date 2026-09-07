/// That the skills `dart run flutter3d:skills` promises are shipped, and that
/// the entry point looks for them where they are.
///
///     flutter test test/skills_test.dart
///
/// **The shape of this file is `flutter3d_impeller/test/build_shaders_test.dart`,
/// and the reason is the failure that file was written for.** Its entry point
/// resolved `package:flutter3d/` to find its own root while the script it ran
/// had moved to `flutter3d_impeller`, so the command reported that the copy
/// "did not ship its shader tooling" for a fortnight with nothing red. Nothing
/// checked the one line that ties an entry point to the package it lives in.
///
/// The same line is here, resolving `package:flutter3d/` — this time correctly,
/// because this time the files are in `flutter3d` — and it is pinned as text
/// for the reason that file gives: the alternative is running `dart run` from a
/// test, which wants a pub cache and a network and turns a millisecond of
/// reading into a build.
///
/// What no test can see is the other half of the trap. `.claude/` is ignored at
/// this repository's root and pub drops ignored files from the archive, which
/// is why `skills/` sits inside the package rather than beside a `CLAUDE.md`.
/// Whether an archive actually carries them is `tool/publish_check.sh`'s
/// question, not this file's.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `flutter test` runs with the package root as the working directory.
Directory get _thisPackage => Directory.current;

Directory get _skills => Directory('${_thisPackage.path}/skills');

/// Every directory under `skills/`, whether or not it holds a `SKILL.md` — the
/// point of several checks below is to catch one that does not.
List<Directory> get _skillDirectories =>
    _skills.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

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
  group('the skills this package promises', () {
    test('are shipped', () {
      // Mutation: rename or remove `skills/` — fails here. This is the whole
      // of the impeller bug in one assertion: the command's own error message
      // is "did not ship its skills", and nothing but this notices that it is
      // the truth rather than a misconfiguration on the reader's machine.
      expect(
        _skills.existsSync(),
        isTrue,
        reason: 'skills/ is what bin/skills.dart copies',
      );
      expect(
        _skillDirectories,
        isNotEmpty,
        reason: 'a skills/ with nothing in it installs nothing',
      );
    });

    test('and each one is a directory holding a SKILL.md', () {
      // Mutation: delete any one SKILL.md, leaving its directory — fails here.
      // The entry point walks directories rather than globbing `*/SKILL.md`, so
      // a directory with references and no skill would be copied in full and
      // read by nobody.
      for (final directory in _skillDirectories) {
        expect(
          File('${directory.path}/SKILL.md').existsSync(),
          isTrue,
          reason: '${directory.path} has no SKILL.md',
        );
      }
    });

    test('and every one says what it is and when to use it', () {
      // Mutation: drop the `description:` line from any SKILL.md — fails here.
      // A skill with no description is one an agent never loads, which is the
      // quietest way for all of this prose to be shipped and never read.
      for (final directory in _skillDirectories) {
        final text = File('${directory.path}/SKILL.md').readAsStringSync();
        final where = directory.path.split('/').last;
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
      // Mutation: change the `name:` in any SKILL.md to something else — fails
      // here. The two are addressed separately — a directory is what lands on
      // disk, a name is what the agent asks for — so they can disagree without
      // anything failing to load, and then a skill is installed under one name
      // and invoked under another.
      for (final directory in _skillDirectories) {
        final where = directory.path.split('/').last;
        final text = File('${directory.path}/SKILL.md').readAsStringSync();
        expect(
          _frontmatter(text, 'name'),
          where,
          reason: '$where/SKILL.md names itself something else',
        );
      }
    });

    test('and the entry point looks for them in this package', () {
      // **The impeller bug, transplanted.** The entry point resolves a
      // `package:` URI to find its own root, and there it named the wrong
      // package while the files sat elsewhere. Pinned as text because the
      // alternative is `dart run` in a test.
      //
      // Mutation: point it at `package:flutter3d_impeller/…`, or have it read
      // `${ownPackage.path}/agent_skills` — either fails here.
      //
      // The second expectation names the interpolation and not the bare word
      // `/skills`, which the file's own usage block already contains in
      // `--into docs/skills`: an assertion a comment can satisfy is an
      // assertion about nothing.
      final entry = File(
        '${_thisPackage.path}/bin/skills.dart',
      ).readAsStringSync();
      expect(
        entry,
        contains('package:flutter3d/'),
        reason: 'the entry point must resolve the package it lives in',
      );
      expect(
        entry,
        contains(r'${ownPackage.path}/skills'),
        reason: 'and must look for the skills beside itself',
      );
    });

    test('and it needs nothing a plain dart run does not have', () {
      // Mutation: add `import 'package:flutter/foundation.dart';` to
      // bin/skills.dart — fails here. Everything still builds and every other
      // test still passes, because this package is a Flutter package and its
      // suite runs under `flutter test`; what breaks is `dart run` in a
      // consumer's project without a Flutter SDK on the path, which is the one
      // place this command is ever used and the one place nothing here runs.
      // The same argument `flutter3d_sim` makes about a server in a container.
      final entry = File(
        '${_thisPackage.path}/bin/skills.dart',
      ).readAsStringSync();
      final imports = RegExp(
        r"^import '([^']+)';",
        multiLine: true,
      ).allMatches(entry).map((m) => m.group(1)!).toList();
      expect(imports, <String>[
        'dart:io',
        'dart:isolate',
      ], reason: 'this runs under a plain dart run, with no Flutter anywhere');
    });
  });
}
