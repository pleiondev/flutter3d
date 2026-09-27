/// A renderer warmed up on a loading screen links nothing during play — `N3`.
///
/// A camera turns round a scene whose materials it cannot all see at first;
/// every material it comes to is one the warm-up linked, so three hundred
/// frames of play link nothing. Without the warm-up the frame that first
/// sees each new material is the one that links it, which is the hitch.
///
/// And it leaves nothing else to the first frames: the pacing run found
/// them at over a hundred milliseconds each after a warm-up that linked
/// everything, because the level's reflection probes were still being
/// captured one a frame and the pool had no targets to lend yet.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

({Renderer renderer, FakeBackend device, Scene scene, CameraNode camera})
_stage({int probes = 0}) {
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
  // One per room of a level, which is how many a first frame used to leave
  // for the frames after it.
  for (var i = 0; i < probes; i++) {
    scene.add(ReflectionProbeNode()..setPosition(4.0 * i, 0.0, 0.0));
  }
  final camera = scene.add(CameraNode());
  return (renderer: renderer, device: device, scene: scene, camera: camera);
}

/// What the pacing run draws the crypt with: bloom by default, and a metered
/// exposure, whose luminance target is pooled too.
const RenderSettings _settings = RenderSettings(
  autoExposure: AutoExposureSettings(enabled: true),
);

void _play(
  ({Renderer renderer, FakeBackend device, Scene scene, CameraNode camera}) it,
  int frames, {
  RenderSettings settings = const RenderSettings(),
}) {
  for (var f = 0; f < frames; f++) {
    final angle = f / frames * 2.0 * math.pi;
    it.camera.lookAt(Vector3(math.sin(angle), 0.0, -math.cos(angle)));
    it.renderer.render(
      width: 16,
      height: 16,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
      settings: settings,
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

  test('warmed up, every reflection probe is captured before play', () {
    final it = _stage(probes: 4);
    it.camera.lookAt(Vector3(0.0, 0.0, -1.0));
    it.renderer.warmUp(
      width: 16,
      height: 16,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
      settings: _settings,
    );
    // Mutation: keep the one-a-frame ration while warming up. A probe
    // stands for each frame the warm-up draws, and the fourth waits for the
    // first frame of play.
    expect(
      <bool>[for (final p in it.scene.probes) p.isCaptured],
      <bool>[true, true, true, true],
    );
  });

  test('warmed up, the first frames of play make no textures', () {
    final it = _stage(probes: 4);
    it.camera.lookAt(Vector3(0.0, 0.0, -1.0));
    it.renderer.warmUp(
      width: 16,
      height: 16,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
      settings: _settings,
    );
    final made = it.device.createdTextures.length;
    _play(it, 8, settings: _settings);
    // Mutation: draw one frame in `warmUp` rather than one per frame in
    // flight. The two frames after it each make a bloom chain and a
    // luminance target, because the warm-up's are still held back.
    expect(it.device.createdTextures.skip(made), isEmpty);
  });
}
