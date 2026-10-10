/// The material language's version line, and the files written before it.
///
///     dart test test/formats/material_language_version_test.dart
///
/// `.f3dmat` had no version until 1.0 (decision 8 of
/// `tasks/1.0-stability.md`). The fixture under `test/fixtures/v1/` is the
/// example's rim material as it was written then, with no `f3dmat` line, and
/// it is never rewritten: it is what every file on somebody's disk looks like.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

String _fixture(int version) =>
    File('test/fixtures/v$version/rim_glow.f3dmat').readAsStringSync();

void main() {
  test('a file with no version line is read as version 1', () {
    final program = parseMaterial(_fixture(1));

    // Mutation: make the line required and every material written before it
    // stops compiling.
    expect(program.name, 'RimGlow');
    expect(program.languageVersion, 1);
    expect(program.parameters.map((MaterialParameter p) => p.name), <String>[
      'rimPower',
      'rimColor',
    ]);
  });

  test('every version up to this build has a fixture that parses', () {
    // Mutation: bump `materialLanguageVersion` without minting
    // `v2/rim_glow.f3dmat`.
    for (var version = 1; version <= materialLanguageVersion; version++) {
      expect(
        File('test/fixtures/v$version/rim_glow.f3dmat').existsSync(),
        isTrue,
        reason: 'no fixture for material language version $version',
      );
      expect(parseMaterial(_fixture(version)).name, 'RimGlow');
    }
  });

  test('a version line is read and carried through a variant', () {
    final program = parseMaterial('f3dmat 1\n${_fixture(1)}');

    // Mutation: drop `languageVersion` from `specializeMaterial`'s copy and
    // the variant forgets which language its source was written in.
    expect(program.languageVersion, 1);
    expect(
      specializeMaterial(
        program,
        const MaterialVariant('RimGlowSharp'),
      ).languageVersion,
      1,
    );
  });

  test('a newer language is refused with the version that reads it', () {
    final newer = 'f3dmat ${materialLanguageVersion + 1}\n${_fixture(1)}';

    // Mutation: accept any number and a construct whose meaning changed is
    // compiled the old way, silently.
    expect(
      () => parseMaterial(newer),
      throwsA(
        isA<MaterialSyntaxException>()
            .having((MaterialSyntaxException e) => e.line, 'line', 1)
            .having(
              (MaterialSyntaxException e) => e.message,
              'message',
              contains('Update flutter3d'),
            ),
      ),
    );
  });

  test('a version that is not a whole number from 1 is a syntax error', () {
    // Mutation: truncate instead of refusing and `f3dmat 1.5` reads as 1.
    for (final bad in <String>['f3dmat 0', 'f3dmat 1.5', 'f3dmat material']) {
      expect(
        () => parseMaterial('$bad\n${_fixture(1)}'),
        throwsA(isA<MaterialSyntaxException>()),
        reason: bad,
      );
    }
  });
}
