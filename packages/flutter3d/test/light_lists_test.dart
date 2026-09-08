/// The per-object light list as the encoder actually hands it over.
///
///     flutter test test/light_lists_test.dart
///
/// `light_selection_test.dart` pins what [LightBuffer.gatherNear] chooses.
/// This pins that a frame *uses* it: that the block bound for a draw carries
/// the lights near that draw rather than the frame's first eight, and that a
/// lamp which never reached the frame's own eight can still own an atlas row
/// and have it found again.
///
/// Off a device, because both are decisions the encoder makes. The fake backend
/// records the arrays it was handed by reference, and the per-draw buffer is
/// one buffer refilled per draw — so a frame here draws one lit mesh and the
/// recorded block is that mesh's. Two frames rather than two meshes, for the
/// same reason.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/geometry/device_mesh.dart';
import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/light_buffer.dart';
import 'package:flutter3d/src/engine/scene/light_node.dart';
import 'package:flutter3d/src/engine/scene/mesh_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

TextureHandle _texel(FakeBackend device) => device.createTexture(
  const RenderTargetSpec(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
  ),
);

Renderer _renderer(FakeBackend device) => Renderer.create(
  device: device,
  fallbackAlbedo: _texel(device),
  fallbackNormal: _texel(device),
);

/// A room with a lamp for every slot at one end and one lamp at the other.
///
/// The eight at `x = -40` are written down first, so the frame's own packing —
/// first come, first served — hands every draw exactly those eight and drops
/// the ninth. Their range is short enough that they reach nothing at the far
/// end, which is what makes the two answers tell each other apart: whichever
/// end the mesh stands at, only the lamps beside it score above zero.
({Scene scene, CameraNode camera}) _room(
  FakeBackend device, {
  required double meshAt,
}) {
  final scene = Scene(name: 'two ends');

  scene.add(
    MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build()),
      Material(name: 'block'),
      name: 'block',
    )..setPosition(meshAt, 0.0, 0.0),
  );

  for (var i = 0; i < LightBuffer.maxLights; i++) {
    scene.add(
      LightNode(name: 'west$i', type: LightType.point)
        ..intensity = 5.0
        ..range = 6.0
        ..setPosition(-40.0 + i * 0.25, 2.0, 0.0),
    );
  }
  scene.add(
    LightNode(name: 'east', type: LightType.point)
      ..intensity = 5.0
      ..range = 6.0
      ..setPosition(0.0, 2.0, 0.0),
  );

  final camera = CameraNode(name: 'eye')
    ..setPosition(meshAt, 1.0, 6.0)
    ..lookAt(Vector3(meshAt, 0.0, 0.0));
  scene.add(camera);

  return (scene: scene, camera: camera);
}

/// The last `FragInfo` block bound in the frame, which is the block the one lit
/// mesh was drawn with.
({Float32List positions, double count}) _fragInfo(FakeBackend device) {
  final blocks = <RecordedUniformBlock>[
    for (final pass in device.passes)
      ...pass.recordedOf<RecordedUniformBlock>().where(
        (b) => b.block == 'FragInfo',
      ),
  ];
  expect(blocks, isNotEmpty, reason: 'nothing in the frame was lit');
  final last = blocks.last;
  return (
    positions: last.members['light_position']!,
    count: last.members['frame_params']![1],
  );
}

/// Draws the room once and reports the block the lit mesh was drawn with.
({Float32List positions, double count}) _draw({required double meshAt}) {
  final device = FakeBackend();
  final built = _room(device, meshAt: meshAt);
  _renderer(device).render(
    width: 128,
    height: 96,
    scene: built.scene,
    views: <RenderView>[RenderView(camera: built.camera)],
  );
  return _fragInfo(device);
}

void main() {
  test('a draw is lit by the lamps that reach it, not by the first eight', () {
    // MUTATION: return `(lights: frameLights, shadowSlots: frameShadowSlots)`
    // unconditionally from `_drawLightsFor`. The eastern block is then handed
    // the eight western lamps — count eight, every position forty metres away —
    // and this goes red on both halves. That is the state the renderer was in:
    // a block standing under a lamp, lit by eight lamps at the other end of the
    // room and not by the one over its head.
    final east = _draw(meshAt: 0.0);
    expect(east.count, 1.0, reason: 'one lamp reaches the eastern end');
    expect(east.positions[0], closeTo(0.0, 1e-5));
    expect(east.positions[1], closeTo(2.0, 1e-5));

    // The other end of the same room, where the eight are the right answer.
    final west = _draw(meshAt: -40.0);
    expect(west.count, LightBuffer.maxLights.toDouble());
    for (var i = 0; i < LightBuffer.maxLights; i++) {
      expect(west.positions[i * 4], lessThan(-30.0));
    }
  });

  test('a lamp outside the frame-wide eight still owns its atlas row', () {
    // The shadow atlas ranks casters by relevance and the frame's own buffer
    // takes the first eight it is written; when a scene overflows those two
    // disagree, and the disagreement used to end the row's description early.
    // The row was allocated, its cube data never written, and the pass that
    // draws the atlas concluded no row was in use — a shadowing lamp standing
    // over the camera casting nothing, in a level whose only fault was holding
    // nine lights.
    //
    // MUTATION: put `final index = lights.packed.indexOf(owner); if (index < 0)
    // continue;` back at the top of the row loop in `render`. The atlas pass
    // disappears from the frame and this goes red.
    final device = FakeBackend();
    final built = _room(device, meshAt: 0.0);
    // The ninth light, and the only caster.
    built.scene.lights.firstWhere((light) => light.name == 'east').castsShadow =
        true;

    _renderer(device).render(
      width: 128,
      height: 96,
      scene: built.scene,
      views: <RenderView>[RenderView(camera: built.camera)],
    );

    // `ShadowDistance` is only ever paired in the cube atlas pass, so a
    // pipeline whose name ends in it identifies the pass without this test
    // having to know how many passes a frame opens.
    final atlas = device.passes.where(
      (pass) => pass.recordedOf<RecordedPipeline>().any(
        (p) => p.pipeline.name.endsWith('+ShadowDistance'),
      ),
    );
    expect(atlas, isNotEmpty, reason: 'the ninth lamp cast nothing');

    // And the draw that lamp lights reads the row it was given, rather than
    // the −1 that means "no shadow here".
    final slots = <RecordedUniformBlock>[
      for (final pass in device.passes)
        ...pass.recordedOf<RecordedUniformBlock>().where(
          (b) => b.block == 'PointShadow',
        ),
    ];
    expect(slots, isNotEmpty, reason: 'no draw was handed a slot table');
    expect(slots.last.members['slots']![0], 0.0);
  });
}
