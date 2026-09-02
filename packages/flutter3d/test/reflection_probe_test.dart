/// What a reflection probe draws, when, and what a material gets from it —
/// asserted against a device that records.
///
///     flutter test test/reflection_probe_test.dart
///
/// A probe is six captures and a chain of filter passes, scheduled two ways
/// and read by the nearest material. Every one of those is a decision that
/// draws a plausible picture when wrong: a kept probe that redraws every
/// frame costs thirty-six passes nobody notices, a rolling one that never
/// drew its first six faces reflects the allocation, and a material that
/// picks the wrong probe reflects a room it is not in. None of it needs a
/// GPU to check.
library;

import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/lighting_model.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/mesh_node.dart';
import 'package:flutter3d/src/engine/scene/reflection_probe_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Stage {
  _Stage({FakeBackend? device}) : device = device ?? FakeBackend() {
    renderer = Renderer.create(device: this.device);
    scene = Scene();
    camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
    scene.add(camera);
    ball = MeshNode(
      DeviceMesh.upload(
        this.device,
        const SphereShape(radius: 1.0, segments: 8, rings: 4).build(),
      ),
      Material(metallic: 1.0, roughness: 0.1, lighting: LightingModel.pbr),
      name: 'ball',
    );
    scene.add(ball);
  }

  final FakeBackend device;
  late final Renderer renderer;
  late final Scene scene;
  late final CameraNode camera;
  late final MeshNode ball;

  void frame() {
    device.passes.clear();
    renderer.render(
      width: 64,
      height: 48,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
    );
  }

  /// Passes drawn into a cube face at the base level: the captures.
  List<FakePass> get captures => <FakePass>[
    for (final pass in device.passes)
      if (pass.descriptor.colors.length == 1 &&
          pass.color.texture.type == TextureType.textureCube &&
          pass.descriptor.depth != null)
        pass,
  ];

  /// Passes drawn into a cube with no depth: the filter.
  List<FakePass> get filters => <FakePass>[
    for (final pass in device.passes)
      if (pass.descriptor.colors.length == 1 &&
          pass.color.texture.type == TextureType.textureCube &&
          pass.descriptor.depth == null)
        pass,
  ];

  /// The pass that draws the world: the one with the HDR colour and depth.
  FakePass get scenePass => device.passes.lastWhere(
    (pass) =>
        pass.descriptor.depth != null &&
        pass.descriptor.colors.first.texture.type == TextureType.texture2D,
  );

  /// What the ball's draw bound to the environment slot in the scene pass.
  RecordedTexture get environment => scenePass
      .recordedOf<RecordedTexture>()
      .lastWhere((it) => it.slot == 'environment_texture');

  /// The level count the ball's draw told the shader.
  double get environmentLevels => scenePass
      .recordedOf<RecordedUniformBlock>()
      .lastWhere((it) => it.block == 'FragInfo')
      .members['frame_params']![3];
}

void main() {
  group('a kept probe', () {
    test('captures six faces and filters every level once, then keeps', () {
      // The first frame it is seen. Mutation: forget to mark the state whole
      // — every frame re-captures, and a dungeon pays six views of the room
      // a frame for a picture it already has.
      final stage = _Stage();
      final probe = stage.scene.add(ReflectionProbeNode(levels: 3));

      stage.frame();

      expect(stage.captures.map((p) => p.color.face).toList(), <int>[
        0,
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(
        stage.captures.every((p) => p.color.mipLevel == 0),
        isTrue,
        reason: 'a capture goes into the base level of the capture cube',
      );
      // Four levels — the base and three below — times six faces.
      expect(stage.filters.length, 4 * 6);
      expect(stage.filters.map((p) => p.color.mipLevel).toSet(), <int>{
        0,
        1,
        2,
        3,
      });
      expect(stage.filters.every((p) => p.submitted), isTrue);
      expect(stage.captures.every((p) => p.submitted), isTrue);
      // The chain is allocated with every level the shader is told about.
      expect(stage.device.createdCubeRenderTargets.last.mipLevels, 4);

      stage.frame();
      expect(stage.captures, isEmpty, reason: 'a kept probe is not redrawn');
      expect(stage.filters, isEmpty);

      probe.invalidate();
      stage.frame();
      expect(stage.captures.length, 6, reason: 'invalidate redraws the six');
      expect(stage.filters.length, 4 * 6);
    });

    test('the mesh nearest it reflects it, with its level count', () {
      // The material's side. Mutation: bind `scene.environment` regardless of
      // the probe — the ball reflects the sky through a wall.
      final stage = _Stage();
      stage.scene.add(ReflectionProbeNode(levels: 3));
      stage.frame();

      final filtered = stage.device.passes
          .where((p) => p.color.texture.type == TextureType.textureCube)
          .where((p) => p.descriptor.depth == null)
          .first
          .color
          .texture;
      expect(identical(stage.environment.texture, filtered), isTrue);
      expect(stage.environmentLevels, 3.0);
      expect(
        stage.environment.sampler?.mipFilter,
        MipFilter.linear,
        reason: 'a roughness chain is read between its levels',
      );
    });

    test('a probe out of reach leaves the scene environment in place', () {
      // Radius is the reach. Mutation: ignore it in `_SceneProbes.nearest` —
      // a probe in the next room lights this one.
      final stage = _Stage();
      stage.scene.add(
        ReflectionProbeNode(radius: 1.0)..setPosition(10.0, 0.0, 0.0),
      );
      stage.frame();

      expect(stage.environmentLevels, 0.0);
      expect(
        stage.environment.texture.width,
        1,
        reason: 'the one-texel fallback cube, not the probe',
      );
    });

    test('the nearest of two wins', () {
      final stage = _Stage();
      final near = stage.scene.add(
        ReflectionProbeNode(levels: 2)..setPosition(0.5, 0.0, 0.0),
      );
      stage.scene.add(
        ReflectionProbeNode(levels: 4)..setPosition(3.0, 0.0, 0.0),
      );
      stage.frame();

      // Told apart by their level counts, which is what the shader is told.
      expect(stage.environmentLevels, 2.0, reason: 'the nearer probe');
      expect(near.levels, 2);
    });
  });

  group('a rolling probe', () {
    test('draws all six the first time and then one a frame', () {
      // Mutation: start rolling from frame one — five faces of the first
      // cube are whatever the allocation held, and a car reflects noise for
      // five frames after every level load.
      final stage = _Stage();
      stage.scene.add(ReflectionProbeNode(refreshFaceEveryFrame: true));

      stage.frame();
      expect(stage.captures.length, 6);

      stage.frame();
      expect(stage.captures.map((p) => p.color.face).toList(), <int>[0]);
      expect(stage.filters, isNotEmpty, reason: 'a drawn face refilters');

      stage.frame();
      expect(stage.captures.map((p) => p.color.face).toList(), <int>[1]);
    });
  });

  group('the capture', () {
    test('leaves out what the probe excludes', () {
      // A mirror ball must not reflect itself. Mutation: drop the exclusion
      // — the ball is in every face of its own probe.
      final stage = _Stage();
      final probe = stage.scene.add(ReflectionProbeNode());
      stage.frame();
      expect(stage.captures.first.drawCount, 1, reason: 'the ball is drawn');

      probe
        ..excluded.add(stage.ball)
        ..invalidate();
      stage.frame();
      expect(stage.captures.first.drawCount, 0);
    });

    test('winds the other way, because the view is a mirror', () {
      // `probeFaceViewProjection` mirrors x, which reverses every triangle's
      // orientation on screen; the winding set per node has to flip with it
      // or backface culling discards the faces meant to be seen. Mutation:
      // ignore `mirrored` in the encoder — every face of every probe shows
      // the inside of every object.
      final stage = _Stage();
      stage.scene.add(ReflectionProbeNode());
      stage.frame();

      expect(
        stage.captures.first.windingOrder,
        WindingOrder.clockwise,
        reason: 'a mirrored view of an unmirrored node',
      );
      expect(
        stage.scenePass.windingOrder,
        WindingOrder.counterClockwise,
        reason: 'the world is drawn as it always was',
      );
    });

    test('binds no probe to what it draws', () {
      // A probe drawn into a probe would sample a cube that may not have been
      // filled yet. The capture hands down no probes, so its draws bind the
      // fallback environment.
      final stage = _Stage();
      stage.scene.add(ReflectionProbeNode());
      stage.frame();

      final bound = stage.captures.first
          .recordedOf<RecordedTexture>()
          .firstWhere((it) => it.slot == 'environment_texture');
      expect(bound.texture.width, 1);
    });
  });

  group('a device that cannot render into a mip', () {
    test('gets no probe, and the material reads what it read before', () {
      // flutter_gpu on OpenGL ES. Mutation: gate on `supportsCubeTextures`
      // alone — the chain is requested, refused at the attachment, and the
      // frame throws out of a pass.
      final stage = _Stage(device: FakeBackend(supportsRenderToMip: false));
      stage.scene.add(ReflectionProbeNode());
      stage.frame();

      expect(stage.captures, isEmpty);
      expect(stage.filters, isEmpty);
      expect(stage.environmentLevels, 0.0);
    });
  });

  test('a probe that left the scene gives its cubes back', () {
    // Two cubes per probe, on a backend where dropping a handle frees
    // nothing. Released through the frames-in-flight ring, so it takes the
    // ring's length of frames to see.
    final stage = _Stage();
    final probe = stage.scene.add(ReflectionProbeNode());
    stage.frame();
    final cubes = stage.device.releasedTextures.length;

    stage.scene.remove(probe);
    for (var i = 0; i < 4; i++) {
      stage.frame();
    }
    expect(
      stage.device.releasedTextures
          .skip(cubes)
          .where((t) => t.type == TextureType.textureCube)
          .length,
      2,
    );
  });
}
