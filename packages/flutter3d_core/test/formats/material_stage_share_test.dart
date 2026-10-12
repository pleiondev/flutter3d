/// The room a lighting model of a plugin's own has, as a number held for
/// all of 1.x, and the refusal of a material past the budget on every
/// backend's path.
///
///     dart test test/formats/material_stage_share_test.dart
library;

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:flutter3d_shaders/compile.dart' show loadShaders;
import 'package:flutter3d_shaders/translate.dart' show resolveIncludes;
import 'package:test/test.dart';

/// A lit material with every feature the language has that adds engine
/// bindings: its own light block with the directional light left out, an
/// ambient and a composite block, the engine's maps, and the scene behind a
/// translucent surface.
const String _everything = '''
f3dmat 3
material Everything {
  texture base = base_color_texture;
  texture bumps = normal_texture;
  state { blend alpha; directional off; }
  light { return albedo * nDotL; }
  ambient { return albedo * lightmap; }
  composite { return direct + indirect; }
  fragment {
    let behind = sceneDepth - viewDepth;
    return vec4(lit + sample(base, uv).rgb * sample(bumps, uv).r +
        vec3(behind * 0.0), alpha);
  }
}
''';

String _fur(int textures) =>
    '''
f3dmat 3
material Fur {
${[for (var i = 0; i < textures; i++) '  texture fur$i;'].join('\n')}
  light { return albedo * nDotL; }
  fragment {
    return vec4(lit${[for (var i = 0; i < textures; i++) ' + sample(fur$i, uv).rgb'].join()}, alpha);
  }
}
''';

void main() {
  final sources = loadShaders().sources;

  test("the engine's bindings in a lit stage leave a plugin model its "
      'share', () {
    final program = parseMaterial(_everything);
    final glsl = resolveIncludes(
      emitMaterialFragment(
        specializeMaterial(program, const MaterialVariant('Everything')),
      ),
      sources,
      from: 'everything.f3dmat',
    );
    final (:textures, :uniformBlocks) = countGlslBindings(glsl);
    // Mutation: add a texture to the lit headers that packs into nothing
    // and the engine takes a plugin model's room in a minor.
    expect(
      textures,
      lessThanOrEqualTo(
        MaterialStageBudget.textures - MaterialStageBudget.materialTextures,
      ),
    );
    expect(
      uniformBlocks,
      lessThanOrEqualTo(
        MaterialStageBudget.uniformBlocks -
            MaterialStageBudget.materialUniformBlocks,
      ),
    );
  });

  test('a material within its share builds; one past the budget is refused '
      'on WebGL2 too', () {
    Object build(int textures) => runtimeMaterialBundle(
      _fur(textures),
      backend: 'webgl',
      from: 'fur.f3dmat',
      engineSources: sources,
    );
    expect(() => build(MaterialStageBudget.materialTextures), returnsNormally);
    // Mutation: drop the count from `runtimeMaterialBundle` and WebGL2 makes
    // a bundle that fails to link at the first draw on a phone.
    expect(
      () => build(8),
      throwsA(
        isA<RuntimeShadersException>().having(
          (RuntimeShadersException e) => e.message,
          'message',
          contains('textures'),
        ),
      ),
    );
  });
}
