/// A `vertex` block drawn on instanced and lightmapped draws too: grass
/// that sways in the block sways when it is instanced, from version 3.
///
///     dart test test/formats/material_vertex_variants_test.dart
library;

import 'package:flutter3d_core/data_plugins.dart' show runtimeMaterialBundle;
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_shaders/compile.dart' show loadShaders;
import 'package:flutter3d_shaders/translate.dart' show resolveIncludes;
import 'package:test/test.dart';

String _grass(int version) =>
    '''
f3dmat $version
material Grass {
  uniform float sway = 0.2;
  vertex {
    out world = world + vec3(sway * instance.x, 0.0, 0.0);
  }
  fragment { return vec4(albedo, alpha); }
}
''';

String _grassV2() => '''
f3dmat 2
material Grass {
  uniform float sway = 0.2;
  vertex {
    let i_data = sway;
    out world = world + vec3(i_data, 0.0, 0.0);
  }
  fragment { return vec4(albedo, alpha); }
}
''';

/// The `in` declarations of [glsl] after its includes, in order.
List<String> _inputs(String glsl) {
  final resolved = resolveIncludes(
    glsl,
    loadShaders().sources,
    from: 'stage.vert',
  );
  return <String>[
    for (final m in RegExp(
      r'^\s*in\s+(\w+)\s+(\w+)\s*;',
      multiLine: true,
    ).allMatches(resolved))
      '${m.group(1)} ${m.group(2)}',
  ];
}

void main() {
  final program = specializeMaterial(
    parseMaterial(_grass(3)),
    const MaterialVariant('Grass'),
  );

  test('a version 3 vertex block has an instanced and a lightmapped half', () {
    final stages = emitMaterialVertexStages(program);
    // Mutation: emit only the plain and the skinned half and an instanced
    // draw goes through the engine's stage, the block dropped.
    expect(stages.keys, <String>[
      'GrassVertex',
      'GrassVertexSkinned',
      'GrassVertexInstanced',
      'GrassVertexLightmapped',
    ]);
    final model = describeMaterial(
      program,
    ).lightingModel(label: 'Grass', shaderName: 'Grass');
    expect(model.vertexVariants, <VertexStageVariant>{
      VertexStageVariant.instanced,
      VertexStageVariant.lightmapped,
    });
  });

  test("the instanced half reads the engine's instanced layout, in order", () {
    // Mutation: declare `i_data` before `i_color` and every instance reads
    // its colour as its four numbers on a backend that numbers by order.
    final engine = loadShaders().sources['mesh_instanced.vert']!;
    expect(
      _inputs(emitMaterialVertex(program, instanced: true)),
      _inputs(engine),
    );
    final instanced = emitMaterialVertex(program, instanced: true);
    expect(instanced, contains('vec4 f3d_instance = i_data;'));
    expect(instanced, contains('v_color = color * i_color;'));
    final lightmapped = emitMaterialVertex(program, lightmapped: true);
    expect(lightmapped, contains('v_lightmap_uv = color.xy;'));
    expect(lightmapped, contains('vec4 f3d_color = vec4(1.0);'));
    expect(
      _inputs(lightmapped),
      _inputs(loadShaders().sources['mesh_lightmapped.vert']!),
    );
  });

  test(
    'a version 2 source keeps the engine for those draws, and its names',
    () {
      final older = parseMaterial(_grassV2());
      // Mutation: emit the halves for a version 2 source and its `let i_data`
      // collides with the instanced stage's input.
      expect(emitMaterialVertexStages(older).keys, <String>[
        'GrassVertex',
        'GrassVertexSkinned',
      ]);
      expect(describeMaterial(older).vertexVariants, isEmpty);
      expect(
        () => parseMaterial(_grassV2().replaceFirst('f3dmat 2', 'f3dmat 3')),
        throwsA(isA<MaterialSyntaxException>()),
      );
      expect(
        () => parseMaterial(_grass(2)),
        throwsA(isA<MaterialSyntaxException>()),
        reason: '`instance` is a version 3 input of the vertex block',
      );
    },
  );

  test('a bundle lists only the halves it carries', () {
    final bundle = runtimeMaterialBundle(
      _grass(3),
      backend: 'cpu',
      from: 'grass.f3dmat',
    );
    expect(
      bundle.names,
      containsAll(<String>['GrassVertexInstanced', 'GrassVertexLightmapped']),
    );
    expect(
      BundledMaterials.read(bundle.encode())['Grass'].vertexVariants,
      hasLength(2),
    );
  });
}
