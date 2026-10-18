/// Every `.f3dmat` in the repository reads as it read before the material
/// language stood on the expression language: the same tree, the same
/// GLSL, and the same colour from the software evaluator.
///
///     dart test test/formats/material_language_read_as_before_test.dart
///
/// The record in `test/fixtures/material_language_read.txt` was written by
/// the parser of the release before the rebase, from these same files, and
/// grew by the version 3 fixtures; `dart run tool/material_record.dart`
/// writes it again, which is only ever right when the language itself
/// changes on purpose or a source joins.
///
/// Mutation: let the base parser fold a sum of two constants, and the tree
/// of `rim_glow.f3dmat` changes; take `exp` out of the material's own
/// builtins' exclusion, and a `let exp` in a version 1 file stops reading;
/// emit the instanced half without the instance's rows, and the v3
/// fixture's record changes.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'material_record.dart';

void main() {
  test('every .f3dmat reads, emits and evaluates as it did', () {
    expect(
      materialLanguageRecord(),
      File(materialRecordPath).readAsStringSync(),
    );
  });

  test('the record reads a fixture of every version', () {
    // Mutation: leave the v3 fixture out of the sources, and what version
    // 3 emits is pinned nowhere.
    for (var version = 1; version <= materialLanguageVersion; version++) {
      expect(
        materialRecordSources,
        contains('test/fixtures/v$version/rim_glow.f3dmat'),
      );
    }
    expect(
      File(materialRecordPath).readAsStringSync(),
      allOf(
        contains('--- vertex glsl RimGlowVertexInstanced'),
        contains('--- vertex glsl RimGlowVertexLightmapped'),
        contains('f3d_lighttype_tube'),
      ),
    );
  });

  test('a name the expression language added stays free in a material', () {
    final program = parseMaterial('''
material Free {
  fragment {
    let exp = 2.0;
    let atan2 = exp * 0.5;
    return vec4(albedo * atan2, alpha);
  }
}
''');
    expect(program.body, hasLength(3));
  });
}
