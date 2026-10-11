/// The software backend shades a dielectric with the F0 the GLSL stages do,
/// read from one constant (`dielectricF0` in `flutter3d_shaders`) rather
/// than written as a literal beside each formula.
library;

import 'dart:io';

import 'package:flutter3d_shaders/flutter3d_shaders.dart' show dielectricF0;
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
  test('one minus the constant is the 0.96 the formulas used to write', () {
    // What keeps the pictures bit for bit: Schlick's `F0 + (1 − F0)·x` with
    // the constant is the `0.04 + 0.96·x` it replaced, to the last bit.
    expect(1.0 - dielectricF0, 0.96);
  });

  test('no CPU stage writes the dielectric F0 as a literal of its own', () {
    // The plain stage's F0, the coat's Fresnel, lobe and ambient, the
    // iridescence's starting Fresnel and the reflections' Schlick term.
    // Mutation: put `0.04 + 0.96` back in any of them and it is named here.
    final literal = RegExp(r'(?<![\w.])0\.(04|96)(?!\d)');
    final found = <String>[
      for (final path in <String>[
        'lib/src/cpu_shaders_lit.dart',
        'lib/src/cpu_shaders_reflections.dart',
      ])
        for (final (index, line) in _code(
          File(path).readAsStringSync(),
        ).split('\n').indexed)
          if (literal.hasMatch(line)) '$path:${index + 1}: ${line.trim()}',
    ];
    expect(found, isEmpty);
  });
}
