/// Version 2 of the material language — item 9 of
/// `tasks/1.0-scope-additions.md`: the vertex block, the ambient and
/// composite hooks, the state block and its switches, the scene behind a
/// translucent surface, and the full-screen and compute kinds.
///
///     dart test test/formats/material_language_v2_test.dart
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

MaterialProgram _parse(String source) => parseMaterial(source);

Matcher _refused(String fragment) => throwsA(
  isA<MaterialSyntaxException>().having(
    (MaterialSyntaxException e) => e.message,
    'message',
    contains(fragment),
  ),
);

MaterialSurfaceValues _surface(Map<String, List<double>> inputs) =>
    MaterialSurfaceValues(
      inputs: inputs,
      sample: (_, _, _) => const <double>[1, 1, 1, 1],
    );

void main() {
  test('the version 2 fixture reads every construct it holds', () {
    final program = _parse(
      File('test/fixtures/v2/rim_glow.f3dmat').readAsStringSync(),
    );

    // Mutation: drop any one block from `MaterialProgram` and its field is
    // null here.
    expect(program.languageVersion, 2);
    expect(program.kind, MaterialStageKind.surface);
    expect(program.vertex, isNotNull);
    expect(program.ambient, isNotNull);
    expect(program.composite, isNotNull);
    expect(program.light, isNotNull);
    expect(program.state.blend, MaterialBlend.additive);
    expect(program.state.depthWrite, isFalse);
    expect(program.state.depthLayer, 1);
    expect(program.state.directional, isFalse);
    expect(program.state.environment, isTrue);
    expect(program.readsSceneDepth, isTrue);
    expect(program.vertexStageName, 'RimGlowVertex');
  });

  test('a version 1 file keeps every name version 2 took', () {
    // Mutation: make the version 2 inputs visible to every version and the
    // sea floor's `let depth` — and this `let sceneDepth` — stop compiling.
    final program = _parse('''
material Old {
  fragment {
    let sceneDepth = 1.0;
    let viewDepth = sceneDepth * 2.0;
    return vec4(albedo * viewDepth, 1.0);
  }
}''');
    expect(program.languageVersion, 1);
  });

  test('a version 2 construct in a version 1 file names the version', () {
    for (final source in <String>[
      'material A { state { blend alpha; } fragment { return vec4(1.0); } }',
      'material A { vertex { out world = world; } fragment { return x; } }',
      'fullscreen A { fragment { return sample(scene, uv); } }',
      'material A { fragment { return vec4(sceneDepth); } }',
    ]) {
      expect(() => _parse(source), _refused('f3dmat 2'), reason: source);
    }
  });

  group('refusals', () {
    test('the scene behind is read by a translucent surface only', () {
      expect(
        () => _parse('''
f3dmat 2
material A {
  fragment { return vec4(albedo, sceneDepth); }
}'''),
        _refused('translucent'),
      );
    });

    test('a hook needs a light block to shape', () {
      expect(
        () => _parse('''
f3dmat 2
material A {
  ambient { return albedo; }
  fragment { return vec4(albedo, 1.0); }
}'''),
        _refused('"light" block'),
      );
    });

    test('a vertex block writes position or world, not both', () {
      expect(
        () => _parse('''
f3dmat 2
material A {
  vertex {
    out position = position;
    out world = world;
  }
  fragment { return vec4(albedo, 1.0); }
}'''),
        _refused('not both'),
      );
    });

    test('a vertex block cannot sample', () {
      expect(
        () => _parse('''
f3dmat 2
material A {
  texture base = base_color_texture;
  vertex { out world = world + sample(base, uv).xyz; }
  fragment { return vec4(albedo, 1.0); }
}'''),
        _refused('cannot sample'),
      );
    });

    test('a cutoff and coverage belong to a masked blend', () {
      expect(
        () => _parse('''
f3dmat 2
material A {
  state { blend alpha; cutoff 0.5; }
  fragment { return vec4(albedo, 1.0); }
}'''),
        _refused('not masked'),
      );
    });

    test('a switch needs a light block', () {
      expect(
        () => _parse('''
f3dmat 2
material A {
  state { environment off; }
  fragment { return vec4(albedo, 1.0); }
}'''),
        _refused('"light"'),
      );
    });

    test('a full-screen stage reads the picture it draws over', () {
      expect(
        () => _parse('''
f3dmat 2
fullscreen A {
  fragment { return vec4(uv, 0.0, 1.0); }
}'''),
        _refused('sample(scene, uv)'),
      );
    });

    test('a kernel samples every texture it declares', () {
      expect(
        () => _parse('''
f3dmat 2
compute A {
  texture noise = noise_texture;
  kernel { return vec4(uv, 0.0, 1.0); }
}'''),
        _refused('never sampled'),
      );
    });

    test('a workgroup stays within 256 invocations', () {
      expect(
        () => _parse('''
f3dmat 2
compute A {
  workgroup 32 16;
  kernel { return vec4(uv, 0.0, 1.0); }
}'''),
        _refused('256'),
      );
    });
  });

  group('evaluation', () {
    final lit = specializeMaterial(
      _parse('''
f3dmat 2
material Lit {
  light { return albedo; }
  fragment { return vec4(lit, 1.0); }
}'''),
      const MaterialVariant('Lit'),
    );
    final inputs = <String, List<double>>{
      'albedo': <double>[0.5, 0.5, 0.5],
      'ambient': <double>[0.2, 0.2, 0.2],
      'occlusion': <double>[0.5],
      'emissive': <double>[0.1, 0.0, 0.0],
    };

    test('without hooks, lit adds up as version 1 does', () {
      // Mutation: drop the occlusion over the indirect light and this is
      // 0.4 rather than 0.3 in green.
      final value = composeMaterialLit(
        lit,
        _surface(inputs),
        direct: const <double>[0.4, 0.4, 0.4],
        lightmap: const <double>[0.0, 0.0, 0.0],
      );
      expect(value[0], closeTo((0.4 + 0.1) * 0.5 + 0.1, 1e-9));
      expect(value[1], closeTo((0.4 + 0.1) * 0.5, 1e-9));
    });

    test('environment off leaves the indirect light out', () {
      final dark = specializeMaterial(
        _parse('''
f3dmat 2
material Dark {
  state { environment off; }
  light { return albedo; }
  fragment { return vec4(lit, 1.0); }
}'''),
        const MaterialVariant('Dark'),
      );
      final value = composeMaterialLit(
        dark,
        _surface(inputs),
        direct: const <double>[0.4, 0.4, 0.4],
        lightmap: const <double>[1.0, 1.0, 1.0],
      );
      expect(value[1], closeTo(0.4 * 0.5, 1e-9));
    });

    test('the composite block is lit', () {
      final hooked = specializeMaterial(
        _parse('''
f3dmat 2
material Hooked {
  light { return albedo; }
  ambient { return lightmap; }
  composite { return direct * 2.0 + indirect; }
  fragment { return vec4(lit, 1.0); }
}'''),
        const MaterialVariant('Hooked'),
      );
      final value = composeMaterialLit(
        hooked,
        _surface(inputs),
        direct: const <double>[0.1, 0.1, 0.1],
        lightmap: const <double>[0.3, 0.3, 0.3],
      );
      expect(value[0], closeTo(0.5, 1e-9));
    });

    test('a vertex block writes what it names and nothing else', () {
      final moved = specializeMaterial(
        _parse('''
f3dmat 2
material Moved {
  uniform float lift = 2.0;
  vertex { out world = world + vec3(0.0, lift, 0.0); }
  fragment { return vec4(albedo, 1.0); }
}'''),
        const MaterialVariant('Moved'),
      );
      final written = evaluateMaterialVertex(
        moved,
        _surface(<String, List<double>>{
          'world': <double>[1.0, 2.0, 3.0],
        }),
      );
      expect(written.keys, <String>['world']);
      expect(written['world'], <double>[1.0, 4.0, 3.0]);
    });
  });

  group('emission', () {
    test('a version 1 material emits no version 2 code', () {
      final glsl = emitMaterialFragment(
        specializeMaterial(
          _parse(File('test/fixtures/v1/rim_glow.f3dmat').readAsStringSync()),
          const MaterialVariant('RimGlow'),
        ),
      );
      // Mutation: route every lit material through the hooked path and
      // every bundle built before it changes.
      expect(glsl, isNot(contains('f3d_')));
    });

    test('a block that writes world is projected through its own block', () {
      final program = specializeMaterial(
        _parse(File('test/fixtures/v2/rim_glow.f3dmat').readAsStringSync()),
        const MaterialVariant('RimGlow'),
      );
      expect(emitMaterialVertex(program), contains('MaterialVertexInfo'));
      expect(
        emitMaterialVertex(program, skinned: true),
        contains('SkinMatrix'),
      );
      expect(emitMaterialFragment(program), contains('MaterialLights'));
      expect(emitMaterialFragment(program), contains('scene_depth_texture'));
    });

    test('premultiplied leaves the colour as returned', () {
      final glsl = emitMaterialFragment(
        specializeMaterial(
          _parse('''
f3dmat 2
material Pre {
  state { blend premultiplied; }
  fragment { return vec4(albedo * alpha, alpha); }
}'''),
          const MaterialVariant('Pre'),
        ),
      );
      expect(glsl, contains('g_premultiply = false;'));
    });

    test('a full-screen stage declares the picture and the surface', () {
      final glsl = emitMaterialFragment(
        specializeMaterial(
          _parse('''
f3dmat 2
fullscreen Fog {
  uniform vec3 colour = vec3(0.5);
  fragment {
    let c = sample(scene, uv);
    let t = clamp(sceneDepth * 0.01, 0.0, 1.0);
    return vec4(mix(c.rgb, colour, t), c.a);
  }
}'''),
          const MaterialVariant('Fog'),
        ),
      );
      expect(glsl, contains('uniform sampler2D scene_texture;'));
      expect(glsl, contains('uniform sampler2D surface_texture;'));
      expect(glsl, contains('frag_color ='));
    });
  });

  test('the bindings carry the scene depth and the vertex stage', () {
    final bindings = describeMaterial(
      _parse(File('test/fixtures/v2/rim_glow.f3dmat').readAsStringSync()),
    );
    final model = bindings.lightingModel(label: 'Rim', shaderName: 'RimGlow');

    // Mutation: build the model without the two flags and the renderer
    // neither binds the scene's depth nor casts the moved shadow.
    expect(model.usesSceneDepth, isTrue);
    expect(model.vertexShaderName, 'RimGlowVertex');
    expect(model.vertexStageInDepthPasses, isTrue);
    expect(bindings.state.depthLayer, 1);
  });
}
