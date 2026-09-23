/// A material written as source — `gfx-84n`.
///
///     dart test test/formats/material_language_test.dart
///
/// **What this file checks and what `material_generators_test.dart` checks.**
/// Here: that the parser reads the language, refuses what a material must not
/// be allowed to do with a sentence attached, folds a variant's parameters
/// into constants, and that the emitter and the evaluator agree about what the
/// tree means. There: that the GLSL the emitter writes goes through the two
/// generators the WebGL and WebGPU backends already use, which is the half of
/// the row's acceptance that no amount of testing in this package can stand in
/// for.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

const String _rimLight = '''
material RimLight {
  // A rim that brightens towards the silhouette.
  param float rimPower = 2.0;
  param vec3 rimColor = vec3(0.2, 0.6, 1.0);
  texture base = base_color_texture;

  fragment {
    let facing = clamp(nDotV, 0.0, 1.0);
    let rim = pow(1.0 - facing, rimPower);
    let texel = sample(base, uv);
    return vec4(albedo * texel.rgb + rimColor * rim, alpha);
  }
}
''';

/// A surface with every input answered, so a test can evaluate a body without
/// a renderer.
MaterialSurfaceValues _surface({
  List<double> albedo = const <double>[0.5, 0.5, 0.5],
  double nDotV = 1.0,
  List<double> texel = const <double>[1, 1, 1, 1],
}) => MaterialSurfaceValues(
  inputs: <String, List<double>>{
    'albedo': albedo,
    'alpha': const <double>[1],
    'normal': const <double>[0, 0, 1],
    'view': const <double>[0, 0, 1],
    'nDotV': <double>[nDotV],
    'metallic': const <double>[0],
    'roughness': const <double>[0.5],
    'occlusion': const <double>[1],
    'emissive': const <double>[0, 0, 0],
    'ambient': const <double>[0, 0, 0],
    'uv': const <double>[0.25, 0.75],
    'world': const <double>[0, 0, 0],
  },
  sample: (slot, u, v) => texel,
);

void main() {
  test('a material parses into what it declares', () {
    final program = parseMaterial(_rimLight);

    expect(program.name, 'RimLight');
    expect(program.parameters.map((p) => p.name), <String>[
      'rimPower',
      'rimColor',
    ]);
    expect(program.parameters.last.defaultValue, <double>[0.2, 0.6, 1.0]);
    expect(program.textures.single.bindingName, 'base_color_texture');
    // The binding metadata the row asks the toolchain to generate: read off
    // the tree rather than declared by whoever wrote the material.
    expect(program.inputsUsed, <String>{'nDotV', 'uv', 'albedo', 'alpha'});
  });

  test('a variant is the same tree with its numbers in it', () {
    final program = parseMaterial(_rimLight);
    final sharp = specialiseMaterial(
      program,
      const MaterialVariant('RimSharp'),
    );
    final soft = specialiseMaterial(
      program,
      const MaterialVariant('RimSoft', <String, List<double>>{
        'rimPower': <double>[8],
        'rimColor': <double>[1, 0, 0],
      }),
    );

    expect(sharp.name, 'RimSharp');
    expect(emitMaterialFragment(sharp), contains('pow((1.0 - facing), 2.0)'));
    expect(emitMaterialFragment(soft), contains('pow((1.0 - facing), 8.0)'));
    expect(
      emitMaterialFragment(soft),
      contains('vec3(1.0, 0.0, 0.0)'),
      reason: 'the variant\'s colour did not reach the shader',
    );
  });

  test('the evaluator answers what the numbers say', () {
    // Straight on: nDotV is one, so the rim term is pow(0, 2) = 0 and the
    // result is the albedo alone. Hand-computed rather than compared against
    // the evaluator's own earlier answer, which would only say it has not
    // changed.
    final program = specialiseMaterial(
      parseMaterial(_rimLight),
      const MaterialVariant('Rim'),
    );
    expect(
      evaluateMaterial(program, _surface(albedo: <double>[0.4, 0.5, 0.6])),
      <double>[0.4, 0.5, 0.6, 1.0],
    );

    // Edge on: nDotV is zero, pow(1, 2) is one, so the whole rim colour is
    // added.
    final edge = evaluateMaterial(
      program,
      _surface(albedo: <double>[0.4, 0.5, 0.6], nDotV: 0),
    );
    expect(edge[0], closeTo(0.6, 1e-9));
    expect(edge[1], closeTo(1.1, 1e-9));
    expect(edge[2], closeTo(1.6, 1e-9));
  });

  test('a texture multiplies where the source says it does', () {
    final program = specialiseMaterial(
      parseMaterial(_rimLight),
      const MaterialVariant('Rim'),
    );
    final result = evaluateMaterial(
      program,
      _surface(
        albedo: <double>[1, 1, 1],
        texel: const <double>[0.25, 0.5, 0.75, 1],
      ),
    );
    expect(result.sublist(0, 3), <double>[0.25, 0.5, 0.75]);
  });

  group('what the language refuses, and the message says which', () {
    void refuses(String source, String contains) {
      expect(
        () => parseMaterial(source),
        throwsA(
          isA<MaterialSyntaxError>().having(
            (e) => e.message,
            'message',
            stringContainsInOrder(<String>[contains]),
          ),
        ),
        reason: source,
      );
    }

    test('a texture the engine does not bind', () {
      refuses(
        'material M { texture t = my_texture; fragment { return vec4(1.0); } }',
        'is not a texture this engine binds',
      );
    });

    test('a body that does not return a vec4', () {
      refuses('material M { fragment { return albedo; } }', 'returns a vec3');
    });

    test('a vec3 built from the wrong number of components', () {
      refuses(
        'material M { fragment { return vec4(albedo, alpha, alpha); } }',
        'add up to 5',
      );
    });

    test('a swizzle the type has not got', () {
      refuses(
        'material M { fragment { return vec4(uv.z, 0.0, 0.0, 1.0); } }',
        'has no "z"',
      );
    });

    test('a swizzle mixing the two naming sets', () {
      refuses(
        'material M { fragment { return vec4(albedo.rx, 0.0, 0.0, 1.0); } }',
        'mixes xyzw with rgba',
      );
    });

    test('a name that shadows a surface input', () {
      refuses(
        'material M { param float albedo = 1.0; fragment { '
            'return vec4(1.0); } }',
        'is one of the surface inputs',
      );
    });

    test('a builtin called with the wrong number of arguments', () {
      refuses(
        'material M { fragment { return vec4(pow(alpha), 0.0, 0.0, 1.0); } }',
        'takes 2 arguments and was given 1',
      );
    });

    test('a vec3 divided by a vec2', () {
      refuses(
        'material M { fragment { return vec4(albedo / uv, 1.0); } }',
        'cannot be combined',
      );
    });

    test('a name nothing bound', () {
      refuses(
        'material M { fragment { return vec4(wind, 0.0, 0.0, 1.0); } }',
        '"wind" is not bound here',
      );
    });

    test('a texture read as if it were a colour', () {
      refuses(
        'material M { texture base = base_color_texture; fragment { '
            'return vec4(base, 1.0); } }',
        'it is read with sample(base, uv)',
      );
    });

    test('a body with no return', () {
      refuses('material M { fragment { let x = alpha; } }', 'has no "return"');
    });

    test('a variant that sets a parameter the material has not got', () {
      expect(
        () => specialiseMaterial(
          parseMaterial(_rimLight),
          const MaterialVariant('Typo', <String, List<double>>{
            'rimPowr': <double>[4],
          }),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the error says where', () {
      try {
        parseMaterial('material M {\n  fragment {\n    return wind;\n  }\n}');
        fail('parsed');
      } on MaterialSyntaxError catch (error) {
        expect(error.line, 3);
        expect(error.column, 12);
      }
    });
  });

  test('the emitter writes whole numbers with a decimal point', () {
    // `pow(x, 2)` does not compile in GLSL: the overload takes floats, and an
    // integer literal is the classic way a generated shader stops building.
    final program = specialiseMaterial(
      parseMaterial(
        'material M { fragment { return vec4(albedo * 2.0, 1.0); } }',
      ),
      const MaterialVariant('M'),
    );
    final glsl = emitMaterialFragment(program);
    expect(glsl, contains('2.0'));
    expect(glsl, isNot(matches(RegExp(r'[^.\d]2[^.\d]'))));
  });

  test('binding metadata comes off the tree', () {
    final plain = describeMaterial(
      parseMaterial('material M { fragment { return vec4(albedo, alpha); } }'),
    );
    expect(plain.usesAlbedoTexture, isFalse);
    expect(plain.usesMaterialMaps, isFalse);
    expect(plain.usesMetallic, isFalse);

    final full = describeMaterial(
      parseMaterial(
        'material M { texture base = base_color_texture; '
        'texture mr = metallic_roughness_texture; fragment { '
        'let t = sample(mr, uv); '
        'return vec4(sample(base, uv).rgb * metallic + t.rgb, alpha); } }',
      ),
    );
    expect(full.usesAlbedoTexture, isTrue);
    expect(full.usesMaterialMaps, isTrue);
    expect(full.usesMetallicRoughnessMap, isTrue);
    expect(full.usesMetallic, isTrue);
  });

  test('a material gathers no lights, so it declares and binds no list', () {
    // Maps and all, it still returns the light its surface emits. Declaring
    // the list and binding it would be the phantom Metal crashes on; one
    // without the other is a dropped draw on WebGL. Both halves, then.
    //
    // Mutation: drop the `#define F3D_NO_LIGHT_LIST` line from the emitter.
    final program = parseMaterial(
      'material M { texture n = normal_texture; fragment { '
      'return vec4(sample(n, uv).rgb, alpha); } }',
    );
    expect(describeMaterial(program).usesMaterialMaps, isTrue);
    expect(describeMaterial(program).usesLightList, isFalse);
    expect(
      emitMaterialFragment(program),
      contains('#define F3D_NO_LIGHT_LIST'),
    );
  });

  test('a program nothing specialised refuses to emit rather than guess', () {
    // The default is *a* value, and using it here would mean the GPU's shader
    // and this package disagreeing about what a variant that set the parameter
    // meant.
    expect(
      () => emitMaterialFragment(parseMaterial(_rimLight)),
      throwsA(isA<StateError>()),
    );
  });
}
