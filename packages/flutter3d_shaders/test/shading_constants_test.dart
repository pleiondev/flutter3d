/// The dielectric's F0 is one number: the Dart constant, and the GLSL the
/// generator writes from it, which every stage that shades a dielectric
/// reads instead of a literal of its own.
library;

import 'dart:io';

import 'package:flutter3d_shaders/flutter3d_shaders.dart';
import 'package:flutter3d_shaders/src/shading_constants.dart'
    show shadingConstantsGlsl;
import 'package:test/test.dart';

/// [source] without its comments, so a sentence about four percent is not
/// read as a constant.
String _code(String source) => source
    .split('\n')
    .map((String line) {
      final comment = line.indexOf('//');
      return comment < 0 ? line : line.substring(0, comment);
    })
    .join('\n');

void main() {
  test('a dielectric reflects what an index of 1.5 does head-on', () {
    // Mutation: any other F0 and the software backend, the stages and the
    // converter all move off glTF's default together, which this names.
    const n = 1.5;
    const r = (n - 1.0) / (n + 1.0);
    expect(dielectricF0, closeTo(r * r, 1e-15));
    expect(dielectricF0, 0.04);
  });

  test('the GLSL constants are the ones the Dart says', () {
    // Mutation: edit the GLSL by hand, or move the Dart constant without
    // running `tool/gen_shading_constants.dart`, and the file differs.
    final file = File('shaders/lib/shading_constants.glsl');
    expect(file.existsSync(), isTrue, reason: 'run from the package root');
    expect(file.readAsStringSync(), shadingConstantsGlsl());
    expect(
      shadingConstantsGlsl(),
      contains('const float kDielectricF0 = 0.04;'),
    );
  });

  test('no stage writes the dielectric F0 as a literal of its own', () {
    // Every stage that shades a dielectric reads `kDielectricF0`: the base
    // layer's F0, the iridescence's starting Fresnel, the coat's lobe and
    // its ambient, and the reflections' Schlick term. Mutation: put
    // `0.04 + 0.96` back in any of them and it is named here.
    final literal = RegExp(r'(?<![\w.])0\.(04|96)(?!\d)');
    final found = <String>[
      for (final path in <String>['lib/pbr.glsl', 'post/reflections.frag'])
        for (final (index, line) in _code(
          File('shaders/$path').readAsStringSync(),
        ).split('\n').indexed)
          if (literal.hasMatch(line)) '$path:${index + 1}: ${line.trim()}',
    ];
    expect(found, isEmpty);
  });

  test('the stages that read it include it', () {
    for (final path in <String>['lib/pbr.glsl', 'post/reflections.frag']) {
      expect(
        File('shaders/$path').readAsStringSync(),
        contains('#include <lib/shading_constants.glsl>'),
        reason: path,
      );
    }
  });
}
