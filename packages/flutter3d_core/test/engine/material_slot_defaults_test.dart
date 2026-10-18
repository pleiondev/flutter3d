/// A plugin's lit model drawn by a material that sets none of its own
/// blocks or textures: each block is bound at the defaults its source
/// declares, and each texture of its own to a stand-in, so no backend meets
/// a slot the stage declares with nothing bound (D21).
///
///     dart test test/engine/material_slot_defaults_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show MaterialParameters;
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show ShaderHandle;
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const String _hair = '''
f3dmat 2
material acme_hair_Hair {
  uniform float gloss = 0.5;
  uniform(Strands) vec3 tint = vec3(0.4, 0.3, 0.2);
  uniform(Strands) float shift = 0.1;
  texture fur;

  light { return albedo * tint * nDotL; }
  fragment {
    let strands = sample(fur, uv).rgb;
    return vec4(lit * strands * (gloss + shift), alpha);
  }
}
''';

final LightingModel _model = describeMaterial(
  parseMaterial(_hair),
).lightingModel(label: 'Hair', shaderName: 'acme_hair_Hair');

/// Draws one plane with [material] and answers what the fragment stage of
/// the plugin's model was handed.
({List<RecordedUniformBlock> blocks, List<RecordedTexture> textures}) _draw(
  RenderMaterial material,
) {
  final device = FakeBackend();
  final camera = CameraNode()..setPosition(0.0, 3.0, 0.0);
  camera.lookAt(Vector3.zero());
  final scene = Scene()
    ..add(
      MeshNode(DeviceMesh.upload(device, const PlaneShape().build()), material),
    )
    ..add(camera);
  Renderer.create(device: device).render(
    width: 16,
    height: 16,
    scene: scene,
    views: <CameraView>[CameraView(camera: camera)],
  );
  final commands = <Recorded>[
    for (final pass in device.passes) ...pass.commands,
  ];
  bool ours(ShaderHandle? shader) =>
      shader?.name.startsWith('acme_hair_Hair') ?? false;
  return (
    blocks: <RecordedUniformBlock>[
      for (final block in commands.whereType<RecordedUniformBlock>())
        if (ours(block.shader)) block,
    ],
    textures: <RecordedTexture>[
      for (final texture in commands.whereType<RecordedTexture>())
        if (ours(texture.shader)) texture,
    ],
  );
}

void main() {
  test('a block nobody set is bound at the defaults the source declares', () {
    // Mutation: bind a block only when the material sets one of its
    // members. WebGPU then meets `MaterialParams` and `Strands` declared
    // with nothing bound, and the draw is refused.
    final drawn = _draw(RenderMaterial(lighting: _model));
    final byName = <String, Map<String, Float32List>>{
      for (final block in drawn.blocks) block.block: block.members,
    };
    expect(byName.keys, containsAll(<String>['MaterialParams', 'Strands']));
    expect(byName['MaterialParams']!['gloss'], <double>[0.5]);
    expect(byName['Strands']!['shift'], <Matcher>[closeTo(0.1, 1e-7)]);
    expect(byName['Strands']!['tint'], <Matcher>[
      closeTo(0.4, 1e-7),
      closeTo(0.3, 1e-7),
      closeTo(0.2, 1e-7),
    ]);
    // Mutation: leave the texture of its own unbound when the material
    // names none.
    expect(drawn.textures.map((t) => t.slot), contains('material_fur'));
  });

  test('a member the material sets wins over its default, the rest keep '
      'theirs', () {
    final drawn = _draw(
      RenderMaterial(
        lighting: _model,
        parameters: MaterialParameters.over(<String, Float32List>{
          'shift': Float32List.fromList(<double>[0.25]),
        }),
      ),
    );
    final strands = drawn.blocks.lastWhere((b) => b.block == 'Strands');
    expect(strands.members['shift'], <double>[0.25]);
    expect(strands.members['tint'], hasLength(3));
    expect(
      drawn.blocks.lastWhere((b) => b.block == 'MaterialParams').members,
      contains('gloss'),
    );
  });
}
