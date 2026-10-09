/// Typed material accessors — item 22 of `tasks/1.0-scope-additions.md`.
///
///     dart test test/material_accessors_test.dart
library;

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

void main() {
  final program = parseMaterial('''
f3dmat 2
material Sea {
  param float headOn = 0.02;
  uniform float time = 0.0;
  uniform vec3 eye = vec3(0.0, 10.0, 0.0);
  uniform vec4 tint = vec4(1.0);
  uniform vec2 parameters = vec2(0.5, 2.0);
  fragment { return vec4(albedo * tint.rgb + eye * time * headOn, 1.0); }
}''');

  test('a class per material, a member per uniform, typed by width', () {
    final dart = generateMaterialAccessors(<MaterialProgram>[program]);

    // Mutation: emit a `param` as a member and a folded constant reads as
    // something a game could set.
    expect(dart, contains('extension type SeaParams('));
    expect(dart, contains('double get time'));
    expect(dart, contains('Vector3 get eye'));
    expect(dart, contains('Vector4 get tint'));
    expect(dart, isNot(contains('headOn')));
  });

  test('a uniform named as the accessor already is takes a suffix', () {
    final dart = generateMaterialAccessors(<MaterialProgram>[program]);

    // Mutation: write the member under its own name and the extension type
    // does not compile, being two things called `parameters`.
    expect(dart, contains('Vector2 get parametersValue'));
    expect(dart, contains("_at('parameters', 2)"));
  });

  test('a material without uniforms gets no class', () {
    final plain = parseMaterial(
      'material Plain { fragment { return vec4(albedo, 1.0); } }',
    );
    expect(
      generateMaterialAccessors(<MaterialProgram>[plain]),
      isNot(contains('extension type')),
    );
  });
}
