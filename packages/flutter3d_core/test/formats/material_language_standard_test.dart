/// Version 3 of the material language's injection points into the
/// engine's standard model: `lighting standard;`, a `surface` block, a
/// `light` block reading `standard`, and a plugin's light type in the
/// model's loop.
///
///     dart test test/formats/material_language_standard_test.dart
///
/// What the GPU draws is `lighting/pbr.frag` with the hooks defined; that a
/// material with no injection is the engine's PBR to the pixel is held on
/// the software backend in `flutter3d_testing`'s
/// `material_language_frame_test.dart`. Each test names the mutation that
/// would defeat it.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

const String _sheen = '''
f3dmat 3
material Sheen {
  lighting standard;
  uniform vec3 sheen = vec3(0.3);
  lighttype tube = acme.tube;

  surface {
    let worn = 0.5;
    out roughness = mix(roughness, 1.0, worn);
    out normal = normal + vec3(0.0, 0.1, 0.0);
  }

  light {
    return standard * (1.0 + tube) + sheen * pow(1.0 - nDotV, 5.0);
  }
}
''';

Matcher _refused(String saying) => throwsA(
  isA<MaterialSyntaxException>().having(
    (e) => e.message,
    'message',
    contains(saying),
  ),
);

void main() {
  group('the source', () {
    test('reads its model, its surface block and its light block', () {
      // Mutation: drop `lighting` from the program. The emitter would write
      // a material lighting itself with no fragment body.
      final program = parseMaterial(_sheen);
      expect(program.isStandard, isTrue);
      expect(program.lighting, materialStandardLighting);
      expect(program.surface, hasLength(3));
      expect(program.body, isEmpty);
      expect(program.inputsUsed, contains('standard'));
      expect(program.isLit, isTrue);
    });

    test('a material lit by the standard model has no fragment body', () {
      // Mutation: accept one. Its colour would be written over nothing the
      // model drew, and the two backends would each guess which wins.
      expect(
        () => parseMaterial('''
f3dmat 3
material A { lighting standard; fragment { return vec4(albedo, 1.0); } }
'''),
        _refused('no fragment body'),
      );
      expect(
        () => parseMaterial('''
f3dmat 3
material A { lighting standard; ambient { return albedo; } }
'''),
        _refused('no ambient block'),
      );
    });

    test('the words are version 3, and come before the blocks', () {
      // Mutation: read `lighting` in a version 2 file. A build of version 2
      // would refuse it by an unknown word rather than by its version.
      expect(
        () => parseMaterial('f3dmat 2\nmaterial A { lighting standard; }'),
        _refused('version 3'),
      );
      expect(
        () => parseMaterial('f3dmat 3\nmaterial A { lighting toon; }'),
        _refused('"toon" is not a model'),
      );
      expect(
        () => parseMaterial(
          'f3dmat 3\nmaterial A { light { return albedo; } '
          'lighting standard; }',
        ),
        _refused('comes before them'),
      );
    });

    test('a surface block is the standard model\'s, and writes its '
        'outputs only', () {
      // Mutation: let a surface block into a material lighting itself. Its
      // outputs would be written to a surface nothing then lights.
      expect(
        () => parseMaterial(
          'f3dmat 3\nmaterial A { surface { out albedo = albedo; } '
          'fragment { return vec4(albedo, 1.0); } }',
        ),
        _refused('declare "lighting standard;" first'),
      );
      expect(
        () => parseMaterial(
          'f3dmat 3\nmaterial A { lighting standard; '
          'surface { out lit = albedo; } }',
        ),
        _refused('"lit" is not an output'),
      );
      expect(
        () => parseMaterial(
          'f3dmat 3\nmaterial A { lighting standard; surface { let x = 1.0; } }',
        ),
        _refused('writes nothing'),
      );
    });

    test('`standard` is read only in the standard model\'s light block', () {
      // Mutation: offer `standard` to every light block. A material lighting
      // itself would read a model it never ran.
      expect(
        () => parseMaterial(
          'f3dmat 3\nmaterial A { light { return standard; } '
          'fragment { return vec4(lit, 1.0); } }',
        ),
        _refused('"standard" is not bound here'),
      );
      expect(
        () => parseMaterial(
          'f3dmat 3\nmaterial A { lighting standard; '
          'light { let StandardLight = 1.0; return standard; } }',
        ),
        _refused('already uses'),
      );
    });
  });

  group('the stage', () {
    test('is pbr.frag with the material\'s hooks switched on', () {
      // Mutation: write the hook functions without their defines. The model
      // would compile, and never call them.
      final glsl = emitMaterialFragment(
        specializeMaterial(
          parseMaterial(_sheen),
          const MaterialVariant('Sheen'),
        ),
      );
      expect(
        glsl,
        allOf(<Matcher>[
          contains('#define F3D_SURFACE_HOOK'),
          contains('#define F3D_LIGHT_HOOK'),
          contains('#define F3D_LIGHT_TYPE_HOOK'),
          contains('#include <lib/pbr.glsl>'),
          contains('void ShadeSurfaceHook(inout Surface s)'),
          contains(
            'vec3 ShadeLightHook(Surface s, LightSample light, '
            'vec3 f3d_standard)',
          ),
          contains('bool F3dLightTypeHook(float code, vec4 params)'),
          contains('s.n = normalize(f3d_out_normal);'),
          isNot(contains('void main()')),
        ]),
      );
      // Read against the surface as it came, then written: a later output
      // never reads an earlier one.
      expect(
        glsl.indexOf('s.roughness = f3d_out_roughness;'),
        greaterThan(glsl.indexOf('vec3 f3d_out_normal')),
      );
    });

    test('a material with no injection still switches nothing on', () {
      // Mutation: define every hook whatever the source has. A light hook
      // with no body is a link error on every backend.
      final glsl = emitMaterialFragment(
        parseMaterial('f3dmat 3\nmaterial Plain { lighting standard; }'),
      );
      expect(glsl, isNot(contains('#define F3D_')));
      expect(glsl, contains('#include <lib/pbr.glsl>'));
    });

    test('binds what the standard model binds', () {
      // Mutation: describe it as a material lighting itself. The renderer
      // would leave the environment and the metallic-roughness map unbound,
      // a refused draw on WebGL2 and a crash on Metal.
      final model = describeMaterial(
        parseMaterial(_sheen),
      ).lightingModel(label: 'Sheen', shaderName: 'Sheen');
      expect(model.usesEnvironment, LightingModel.pbr.usesEnvironment);
      expect(
        model.usesMetallicRoughnessMap,
        LightingModel.pbr.usesMetallicRoughnessMap,
      );
      expect(model.usesMetallic, isTrue);
      expect(model.usesLightList, isTrue);
      expect(model.lightTypeMembers, <String, String>{
        'f3d_lighttype_tube': 'acme.tube',
      });
    });

    test('the software backend writes what the surface block writes', () {
      // Mutation: write the outputs into the inputs as they are evaluated.
      // The second output would read the first one's answer, where the
      // emitted stage reads the surface as it came.
      final written = evaluateMaterialSurface(
        parseMaterial(
          'f3dmat 3\nmaterial A { lighting standard; '
          'surface { out roughness = 1.0; out metallic = roughness; } }',
        ),
        MaterialSurfaceValues(
          inputs: <String, List<double>>{
            for (final input in materialInputs)
              input.name: List<double>.filled(input.type.components, 0.25),
          },
          sample: (slot, u, v) => const <double>[1, 1, 1, 1],
        ),
      );
      expect(written, <String, List<double>>{
        'roughness': <double>[1],
        'metallic': <double>[0.25],
      });
    });
  });
}
