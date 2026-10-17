/// Version 3 of the material language: a material's own version and the
/// updates that carry what an older instance set to it.
///
///     dart test test/formats/material_language_v3_test.dart
///
/// Mutation: apply a scale before the rename it follows in `lift`, and the
/// version 1 instance keeps its full brightness; drop the check that an
/// update leads to at most the material's version, and the version 4 update
/// of a version 3 material is read.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

Matcher _refused(String message) => throwsA(
  isA<MaterialSyntaxException>().having(
    (MaterialSyntaxException e) => e.message,
    'message',
    message,
  ),
);

String _hatch(String updates, {String version = '3', String header = '3'}) =>
    '''
f3dmat $header
material Hatch version $version {
  uniform vec3 inkColor = vec3(0.1, 0.1, 0.1);
  uniform float grain = 0.5;
  updates {
$updates
  }
  fragment { return vec4(albedo * inkColor * grain, alpha); }
}
''';

void main() {
  test('the version 3 fixture reads its version and updates', () {
    final program = parseMaterial(
      File('test/fixtures/v3/rim_glow.f3dmat').readAsStringSync(),
    );
    expect(program.languageVersion, 3);
    expect(program.version, 3);
    expect(program.updates.map((u) => '$u'), <String>[
      '2: rename rim -> rimColor',
      '3: scale rimColor 0.5',
      '3: remove pulse',
    ]);
    // The rest of the file is the version 2 rim, read the same.
    final v2 = parseMaterial(
      File('test/fixtures/v2/rim_glow.f3dmat').readAsStringSync(),
    );
    expect(
      emitMaterialFragment(
        specializeMaterial(program, const MaterialVariant('RimGlow')),
      ),
      emitMaterialFragment(
        specializeMaterial(v2, const MaterialVariant('RimGlow')),
      ),
    );
    expect(v2.version, 1);
    expect(v2.updates, isEmpty);
  });

  test('an instance of each older version is lifted to the current one', () {
    final program = parseMaterial(
      File('test/fixtures/v3/rim_glow.f3dmat').readAsStringSync(),
    );
    expect(
      program.lift(<String, List<double>>{
        'rim': <double>[1, 0.5, 0.25],
        'breath': <double>[0.5],
        'pulse': <double>[2],
      }, from: 1),
      <String, List<double>>{
        'breath': <double>[0.5],
        'rimColor': <double>[0.5, 0.25, 0.125],
      },
    );
    expect(
      program.lift(<String, List<double>>{
        'rimColor': <double>[1, 1, 1],
      }, from: 2),
      <String, List<double>>{
        'rimColor': <double>[0.5, 0.5, 0.5],
      },
    );
    final current = <String, List<double>>{
      'rimColor': <double>[1, 1, 1],
      'unknown': <double>[7],
    };
    expect(program.lift(current, from: 3), current);
    expect(
      () => program.lift(current, from: 4),
      throwsA(
        isA<MaterialVersionException>()
            .having((e) => e.written, 'written', 4)
            .having((e) => e.current, 'current', 3),
      ),
    );
  });

  test('a variant keeps the version and the updates', () {
    final program = parseMaterial(_hatch('    2: rename ink -> inkColor;'));
    final variant = specializeMaterial(program, const MaterialVariant('Ink'));
    expect(variant.version, 3);
    expect(variant.updates, program.updates);
  });

  test('an update past the material\'s version is refused', () {
    expect(
      () => parseMaterial(_hatch('    4: scale grain 0.5;')),
      _refused(
        'an update leads to a version from 2 to the material\'s own, 3, and '
        'this one leads to 4: raise the material\'s version with '
        '"material Hatch version 4".',
      ),
    );
    expect(
      () => parseMaterial(_hatch('    1: scale grain 0.5;')),
      _refused('an update\'s version is a whole number from 2, not "1".'),
    );
  });

  test('an update of a parameter the material does not have is refused', () {
    expect(
      () => parseMaterial(_hatch('    2: rename ink -> inkColour;')),
      _refused('"inkColour" is not a parameter "Hatch" declares.'),
    );
    expect(
      () => parseMaterial(
        _hatch('    2: rename ink -> paint;\n    3: rename paint -> pen;'),
      ),
      // The first rename is the one whose chain ends nowhere.
      _refused('"paint" becomes "pen", which "Hatch" does not declare.'),
    );
    expect(
      () => parseMaterial(
        _hatch('    2: scale ink 2.0;\n    3: rename ink -> pen;'),
      ),
      _refused('"ink" becomes "pen", which "Hatch" does not declare.'),
    );
    // A chain that ends on a declared name reads.
    expect(
      parseMaterial(
        _hatch('    2: rename ink -> paint;\n    3: rename paint -> inkColor;'),
      ).updates,
      hasLength(2),
    );
    expect(
      () => parseMaterial(_hatch('    2: bleach grain;')),
      _refused('"bleach" is not an update: rename, scale and remove are.'),
    );
  });

  test('version and updates are version 3, and older files say so', () {
    expect(
      () => parseMaterial(_hatch('', header: '2')),
      _refused(
        'a material\'s own version is material language version 3: open the '
        'file with "f3dmat 3".',
      ),
    );
    expect(
      () => parseMaterial('''
f3dmat 2
material Hatch {
  updates { 2: remove ink; }
  fragment { return vec4(albedo, alpha); }
}
'''),
      _refused(
        '"updates" is material language version 3: open the file with '
        '"f3dmat 3".',
      ),
    );
  });
}
