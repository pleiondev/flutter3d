/// A renderer warmed up on a loading screen links nothing during play — `N3`.
///
/// A camera turns round a scene whose materials it cannot all see at first;
/// every material it comes to is one the warm-up linked, so three hundred
/// frames of play link nothing. Without the warm-up the frame that first
/// sees each new material is the one that links it, which is the hitch.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

({Renderer renderer, FakeBackend device, Scene scene, CameraNode camera})
_stage() {
  final device = FakeBackend();
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
  final box = CuboidShape().build();
  final scene = Scene();
  // Four boxes round the camera, each lit a different way, so the view that
  // starts on one of them has three it has not linked for yet.
  final models = <LightingModel>[
    LightingModel.pbr,
    LightingModel.lambert,
    LightingModel.blinnPhong,
    LightingModel.toon,
  ];
  for (var i = 0; i < models.length; i++) {
    final angle = i * math.pi / 2.0;
    scene.add(
      MeshNode(DeviceMesh.upload(device, box), Material(lighting: models[i]))
        ..setPosition(4.0 * math.sin(angle), 0.0, -4.0 * math.cos(angle)),
    );
  }
  scene.add(LightNode(intensity: 2.0)..setRotationYawPitchRoll(0.3, -0.6, 0.0));
  final camera = scene.add(CameraNode());
  return (renderer: renderer, device: device, scene: scene, camera: camera);
}

void _play(
  ({Renderer renderer, FakeBackend device, Scene scene, CameraNode camera}) it,
  int frames,
) {
  for (var f = 0; f < frames; f++) {
    final angle = f / frames * 2.0 * math.pi;
    it.camera.lookAt(Vector3(math.sin(angle), 0.0, -math.cos(angle)));
    it.renderer.render(
      width: 16,
      height: 16,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
    );
  }
}

void main() {
  test('warmed up, three hundred frames of play link nothing', () {
    final it = _stage();
    it.camera.lookAt(Vector3(0.0, 0.0, -1.0));
    it.renderer.warmUp(
      width: 16,
      height: 16,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
    );
    final linked = it.device.linkedPipelines.length;
    _play(it, 300);
    expect(it.device.linkedPipelines.length, linked);
  });

  test('cold, the frames that turn to a new material link it', () {
    final it = _stage();
    it.camera.lookAt(Vector3(0.0, 0.0, -1.0));
    it.renderer.render(
      width: 16,
      height: 16,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
    );
    final linked = it.device.linkedPipelines.length;
    _play(it, 300);
    // Mutation: link nothing but the one frame in `warmUp`. The first test
    // links in play just as this one does.
    expect(it.device.linkedPipelines.length, greaterThan(linked));
  });
}
