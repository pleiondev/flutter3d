/// A plugin's lit model with blocks and textures of its own: the slot table
/// the source declares, the GLSL that declares it, and the lighting model
/// that carries it to the renderer (D21).
///
///     dart test test/formats/material_slots_test.dart
///
/// Mutation: lay a `vec3` out at 12 rather than 16 in `std140` and the
/// offsets test fails; have the emitter read every uniform through
/// `material_params` and the GLSL test finds no `f3d_block_Hair`.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

const String _hair = '''
f3dmat 2
material AcmeHair {
  uniform float gloss = 0.5;
  uniform(Hair) float shift = 0.1;
  uniform(Hair) vec3 tint = vec3(0.4, 0.3, 0.2);
  texture fur;
  texture base = base_color_texture;

  light { return albedo * tint * nDotL; }
  fragment {
    let strands = sample(fur, uv).rgb;
    return vec4(lit * strands * (gloss + shift), alpha);
  }
}
''';

void main() {
  test(
    'the table lists the blocks and the textures of the material\'s own',
    () {
      final table = MaterialSlotTable.of(parseMaterial(_hair));
      expect(table.blocks.map((b) => b.name), <String>[
        'MaterialParams',
        'Hair',
      ]);
      expect(table.block('MaterialParams')!.members.single.name, 'gloss');
      expect(table.textures.single.name, 'fur');
      expect(table.textures.single.binding, 'material_fur');
      expect(table.isEmpty, isFalse);
    },
  );

  test('a block of its own is laid out as std140 lays it', () {
    final hair = MaterialSlotTable.of(parseMaterial(_hair)).block('Hair')!;
    expect(
      <String, int>{for (final m in hair.members) m.name: m.offset},
      <String, int>{'shift': 0, 'tint': 16},
    );
    expect(hair.size, 32);
    expect(hair.toJson()['size'], 32);
  });

  test('the emitted stage declares each block and its own sampler', () {
    final program = specializeMaterial(
      parseMaterial(_hair),
      const MaterialVariant('AcmeHair'),
    );
    final glsl = emitMaterialFragment(program);
    expect(glsl, contains('uniform Hair {'));
    expect(glsl, contains('f3d_block_Hair;'));
    expect(glsl, contains('f3d_block_Hair.tint'));
    expect(glsl, contains('material_params.gloss'));
    expect(glsl, contains('uniform sampler2D material_fur;'));
  });

  test('the lighting model carries the table to the renderer', () {
    final model = describeMaterial(
      parseMaterial(_hair),
    ).lightingModel(label: 'Hair', shaderName: 'acme_hair_Hair');
    expect(model.slots.blocks.map((b) => b.name), <String>[
      'MaterialParams',
      'Hair',
    ]);
    expect(model.slots.textures.single.binding, 'material_fur');
    expect(LightingModel.pbr.slots.isEmpty, isTrue);
  });

  test('the software evaluator reads a block of its own by member', () {
    final program = parseMaterial(_hair);
    final values = MaterialSurfaceValues(
      inputs: <String, List<double>>{
        'albedo': const <double>[1, 1, 1],
        'nDotL': const <double>[1],
      },
      uniforms: const <String, List<double>>{
        'tint': <double>[0.5, 0.25, 1.0],
      },
      sample: (slot, u, v) => const <double>[1, 1, 1, 1],
    );
    expect(evaluateMaterialLight(program, values), <double>[0.5, 0.25, 1.0]);
  });

  test('version 1 and the engine\'s block names are refused, by name', () {
    expect(
      () => parseMaterial(
        'material Old { texture fur; fragment { return vec4(albedo, 1.0); } }',
      ),
      throwsA(
        isA<MaterialSyntaxException>().having(
          (e) => e.message,
          'message',
          contains('version 2'),
        ),
      ),
    );
    expect(
      () => parseMaterial(
        'f3dmat 2\nmaterial Bad { uniform(FrameInfo) float x = 1.0; '
        'fragment { return vec4(albedo * x, 1.0); } }',
      ),
      throwsA(
        isA<MaterialSyntaxException>().having(
          (e) => e.message,
          'message',
          contains('"FrameInfo"'),
        ),
      ),
    );
  });
}
