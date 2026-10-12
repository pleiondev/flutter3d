/// The binding budget counted from GLSL, which every backend's path has,
/// rather than only from the WebGPU section a machine with glslang and naga
/// writes.
///
///     dart test test/glsl_binding_count_test.dart
library;

import 'package:flutter3d_shaders/backend.dart';
import 'package:test/test.dart';

void main() {
  test('a declaration a conditional switches off is not counted', () {
    const glsl = '''
#ifndef GUARD_
#define GUARD_
uniform sampler2D always_texture;
#ifdef F3D_NO_FOG
uniform sampler2D fogless_texture;
#else
uniform FogInfo { vec4 fog; } fog_info;
#endif
#endif  // GUARD_
// uniform sampler2D commented_texture;
uniform highp samplerCube cube_texture;
uniform FragInfo
{
  vec4 a;
} frag_info;
''';
    // Mutation: ignore `#else` and both branches are counted.
    expect(countGlslBindings(glsl), (textures: 2, uniformBlocks: 2));
    expect(countGlslBindings(glsl, defines: <String>{'F3D_NO_FOG'}), (
      textures: 3,
      uniformBlocks: 1,
    ));
  });

  test('a stage over the budget is refused, naming it and the count', () {
    final over = <String>[
      for (var i = 0; i <= MaterialStageBudget.textures; i++)
        'uniform sampler2D t$i;',
    ].join('\n');
    // Mutation: compare with `>=` and a stage of exactly sixteen is refused.
    expect(
      MaterialStageBudget.problemOfGlsl(
        'Fur',
        over.split('\n').skip(1).join('\n'),
      ),
      isNull,
    );
    expect(
      MaterialStageBudget.problemOfGlsl('Fur', over),
      allOf(contains('"Fur"'), contains('17 textures')),
    );
  });
}
