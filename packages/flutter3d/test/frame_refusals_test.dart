/// The two fields of `FrameResult` whose whole job is to explain a missing
/// picture.
///
///     flutter test test/frame_refusals_test.dart
///
/// `wireframeDeclined` and `shadowsDenied` are the engine's answer to "I asked
/// for this and did not get it", and both were written, documented and shipped
/// with nothing asserting either. A field like that is worse than absent: an
/// author reads the doc comment, believes the frame will say so, and takes
/// silence as "it worked".
///
/// Recorded through the fake device rather than drawn, because what is being
/// pinned is a refusal — there is by definition no picture of it. The device
/// that cannot draw lines is `FakeBackend(supportsWireframe: false)`, which is
/// what the WebGL and software backends both answer.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/light_node.dart';
import 'package:flutter3d/src/engine/scene/mesh_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A renderer over a fake device, and a room with one cube in it.
///
/// [pointCasters] point lights are hung around the cube, each asking for a
/// cube shadow, so a count above `Renderer.kShadowedLights` is a scene where
/// the allocator has to turn somebody away.
({FakeBackend device, Renderer renderer, Scene scene, CameraNode camera})
_build({bool supportsWireframe = true, int pointCasters = 0}) {
  final device = FakeBackend(supportsWireframe: supportsWireframe);
  final texel = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData(4),
  )!;
  final renderer = Renderer.create(
    device: device,
    fallbackAlbedo: texel,
    fallbackNormal: texel,
  );
  final scene = Scene(name: 'refusals');
  final camera = CameraNode(name: 'eye')..setPosition(0.0, 0.0, 4.0);
  scene.root.add(camera);
  scene.root.add(
    MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build()),
      Material(name: 'cube'),
      name: 'cube',
    ),
  );
  for (var i = 0; i < pointCasters; i++) {
    final angle = i * 2.0 * math.pi / pointCasters;
    scene.root.add(
      LightNode(name: 'torch $i', type: LightType.point)
        ..intensity = 5.0
        ..range = 12.0
        ..castsShadow = true
        // Spread around the cube rather than stacked, so relevance has
        // something to rank and every one of them is in view.
        ..setPosition(2.0 * math.cos(angle), 0.5, 2.0 * math.sin(angle)),
    );
  }
  return (device: device, renderer: renderer, scene: scene, camera: camera);
}

FrameResult _render(
  ({FakeBackend device, Renderer renderer, Scene scene, CameraNode camera})
  frame, {
  required RenderSettings settings,
}) => frame.renderer.render(
  width: 64,
  height: 48,
  scene: frame.scene,
  views: <RenderView>[RenderView(camera: frame.camera)],
  settings: settings,
);

/// Wireframe with everything else that costs a pass switched off.
RenderSettings _plain({bool wireframe = false, bool shadows = false}) =>
    RenderSettings(
      wireframe: wireframe,
      bloom: const BloomSettings(enabled: false),
      shadows: ShadowSettings(enabled: shadows),
    );

void main() {
  group('wireframeDeclined', () {
    test('a device with no line primitives says so, and draws filled', () {
      // The whole failure this field exists for: the backends refuse a polygon
      // mode they have no line primitives for, and the engine was swallowing
      // the refusal — a solid model, no exception, and no word anywhere.
      //
      // Mutation: dropping `&& !device.supportsWireframe` from
      // `renderer.dart` leaves the flag false here and the test fails;
      // dropping `&& device.supportsWireframe` from `renderer_scene_pass.dart`
      // sends `PolygonMode.line` to a device that refuses it, and the second
      // expectation fails.
      final frame = _build(supportsWireframe: false);
      final result = _render(frame, settings: _plain(wireframe: true));

      expect(result.wireframeDeclined, isTrue);
      expect(
        frame.device.passes.first.recordedOf<RecordedPolygonMode>().map(
          (RecordedPolygonMode m) => m.mode,
        ),
        everyElement(PolygonMode.fill),
        reason: 'the request must not reach a backend that would refuse it',
      );
    });

    test('a device that can draw lines is not declined, and gets them', () {
      final frame = _build();
      final result = _render(frame, settings: _plain(wireframe: true));

      expect(result.wireframeDeclined, isFalse);
      expect(
        frame.device.passes.first.recordedOf<RecordedPolygonMode>().map(
          (RecordedPolygonMode m) => m.mode,
        ),
        contains(PolygonMode.line),
      );
    });

    test('a setting nobody asked for is not a refusal', () {
      // The field says "asked for and could not be given", not "cannot be
      // given" — a device with no wireframe drawing a scene that wanted none
      // has refused nothing.
      final result = _render(
        _build(supportsWireframe: false),
        settings: _plain(),
      );
      expect(result.wireframeDeclined, isFalse);
    });
  });

  group('shadowsDenied', () {
    test('more casters than the atlas has rows leaves a count behind', () {
      // Eight is `LightBuffer.maxLights`, so this is the most crowded room the
      // engine can be handed: every light is shaded and two of them cannot be
      // shadowed.
      //
      // Mutation: `_shadowsDenied = 0` in place of
      // `assignment.denied.length` — the field the renderer writes and nothing
      // read — fails both expectations below.
      const casters = 8;
      final result = _render(
        _build(pointCasters: casters),
        settings: _plain(shadows: true),
      );

      expect(
        result.shadowsDenied,
        greaterThan(0),
        reason: 'a `castsShadow` that did nothing has to say so',
      );
      expect(
        result.shadowsDenied,
        casters - Renderer.kShadowedLights,
        reason: 'every light past the atlas rows shades unshadowed',
      );
    });

    test('a scene inside the atlas denies nobody', () {
      final result = _render(
        _build(pointCasters: Renderer.kShadowedLights),
        settings: _plain(shadows: true),
      );
      expect(result.shadowsDenied, 0);
    });
  });
}
