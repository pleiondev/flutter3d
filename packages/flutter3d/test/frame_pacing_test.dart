/// Frame pacing — `A1.4`–`A1.7` — and the physical camera — `B6.22`.
///
/// A renderer whose GPU is behind by every frame in flight presents the
/// previous picture rather than queue another; a sliced warm-up yields between slices and
/// links what the whole one links; a pipeline build over the threshold is
/// reported with its material and geometry. And the default camera exposes
/// exactly as the multiplier did.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

({Renderer renderer, FakeBackend device, Scene scene, CameraNode camera})
_stage() {
  final device = FakeBackend();
  final texel = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData(4),
  );
  final renderer = Renderer.create(
    device: device,
    fallbackAlbedo: texel,
    fallbackNormal: texel,
  );
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape().build()),
        RenderMaterial(lighting: LightingModel.lambert),
      )..setPosition(0.0, 0.0, -4.0),
    )
    ..add(LightNode(intensity: 2.0 * Photometric.legacyUnit));
  final camera = scene.add(CameraNode());
  return (renderer: renderer, device: device, scene: scene, camera: camera);
}

FrameResult _draw(
  ({Renderer renderer, FakeBackend device, Scene scene, CameraNode camera}) it,
) => it.renderer.render(
  width: 16,
  height: 16,
  scene: it.scene,
  views: <RenderView>[RenderView(camera: it.camera)],
);

void main() {
  test('a GPU behind by every frame in flight holds the frame', () {
    final it = _stage();
    it.device.completesImmediately = false;
    final heard = <FrameResult>[];
    it.renderer.listener = RenderListener(held: heard.add);
    final first = _draw(it);
    final second = _draw(it);
    final third = _draw(it);
    expect(<bool>[first.held, second.held, third.held], everyElement(isFalse));
    expect(it.renderer.unfinishedFrames, 3);
    // Frames one and two unfinished before the third: a fourth would share
    // the first's slot of every ring.
    final fourth = _draw(it);
    expect(fourth.held, isTrue);
    expect(identical(fourth.frame, third.frame), isTrue);
    expect(it.renderer.heldFrames, 1);
    expect(heard, hasLength(1));
    // Mutation: hold on the count of every unfinished frame, the latest
    // included. Finishing the oldest is then not enough to draw again.
    it.device.finishOldestFrame();
    expect(_draw(it).held, isFalse);
  });

  test('a backend that finishes as it goes never holds', () {
    final it = _stage();
    for (var i = 0; i < 10; i++) {
      expect(_draw(it).held, isFalse);
    }
    expect(it.renderer.heldFrames, 0);
  });

  test('holding off draws however far behind the GPU is', () {
    final it = _stage();
    it.device.completesImmediately = false;
    it.renderer.pacing = const FramePacing(holdWhenBehind: false);
    for (var i = 0; i < 6; i++) {
      expect(_draw(it).held, isFalse);
    }
  });

  test('a pipeline build over the threshold names its material', () {
    final it = _stage();
    it.renderer.pacing = const FramePacing(stallThreshold: Duration.zero);
    final stalls = <PipelineStall>[];
    it.renderer.listener = RenderListener(stalled: stalls.add);
    final frame = _draw(it);
    expect(frame.pipelineStalls, isNotEmpty);
    expect(
      frame.pipelineStalls.map((s) => s.material),
      contains(LightingModel.lambert.shaderName),
    );
    expect(frame.pipelineStalls.first.geometry, PipelineGeometry.plain);
    expect(stalls, frame.pipelineStalls);
    // Built once: the next frame has nothing to report.
    expect(_draw(it).pipelineStalls, isEmpty);
  });

  test('builds inside a warm-up are not stalls', () {
    final it = _stage();
    it.renderer
      ..pacing = const FramePacing(stallThreshold: Duration.zero)
      ..warmUp(
        width: 16,
        height: 16,
        scene: it.scene,
        views: <RenderView>[RenderView(camera: it.camera)],
      );
    expect(it.renderer.pipelineStalls, isEmpty);
  });

  test('a sliced warm-up links what the whole one does', () async {
    final whole = _stage();
    whole.renderer.warmUp(
      width: 16,
      height: 16,
      scene: whole.scene,
      views: <RenderView>[RenderView(camera: whole.camera)],
    );
    final sliced = _stage();
    final progress = <double>[];
    await sliced.renderer.warmUpInSlices(
      width: 16,
      height: 16,
      scene: sliced.scene,
      views: <RenderView>[RenderView(camera: sliced.camera)],
      slice: Duration.zero,
      onProgress: progress.add,
    );
    expect(
      sliced.device.linkedPipelines.length,
      whole.device.linkedPipelines.length,
    );
    expect(sliced.renderer.frameIndex, whole.renderer.frameIndex);
    expect(progress.last, 1.0);
  });

  test('the default camera exposes exactly as the multiplier did', () {
    const settings = RenderSettings();
    expect(settings.physicalCamera, isTrue);
    expect(settings.cameraExposure, RenderSettings.defaultExposure);
    expect(const RenderSettings(exposure: 2.5).cameraExposure, 2.5);
    expect(const PhysicalCamera().exposureScale, 1.0);
    // One stop slower is twice the light; off, the camera is not read.
    const slow = PhysicalCamera(shutter: 1.0 / 30.0);
    expect(
      const RenderSettings(camera: slow).cameraExposure,
      closeTo(2.0 * RenderSettings.defaultExposure, 1e-9),
    );
    expect(
      const RenderSettings(camera: slow, physicalCamera: false).cameraExposure,
      RenderSettings.defaultExposure,
    );
  });

  test('the camera states its exposure in EV100', () {
    expect(const PhysicalCamera().ev100, closeTo(9.907, 1e-3));
    // Sunny sixteen: f/16 at 1/100 s, ISO 100.
    expect(
      const PhysicalCamera(aperture: 16.0, shutter: 0.01).ev100,
      closeTo(14.644, 1e-3),
    );
    // The reference camera draws white at 1.6 × 1.2 × 2^EV100 nits, the
    // number `Photometric.legacyNits` names.
    expect(
      PhysicalCamera.referenceExposure *
          1.2 *
          math.pow(2.0, PhysicalCamera.referenceEv100),
      closeTo(Photometric.legacyNits, 1e-6),
    );
    expect(
      PhysicalCamera.ev100ForExposure(RenderSettings.defaultExposure),
      closeTo(PhysicalCamera.referenceEv100, 1e-12),
    );
    final metered = PhysicalCamera.atEv100(12.0, aperture: 8.0);
    expect(metered.ev100, closeTo(12.0, 1e-9));
  });

  test('the physical sky at noon meters near a sunny day', () {
    const sky = PhysicalSky();
    final noon = sky.illuminanceLux(Vector3(0.0, 1.0, 0.0));
    expect(noon, inInclusiveRange(5.0e4, 1.5e5));
    final dusk = sky.illuminanceLux(Vector3(1.0, 0.02, 0.0));
    expect(dusk, lessThan(noon / 10.0));
    final camera = PhysicalCamera.forSky(sky, Vector3(0.0, 1.0, 0.0));
    expect(camera.ev100, inInclusiveRange(14.0, 16.0));
  });

  test('clustered lights are on by default', () {
    expect(const RenderSettings().clusteredLights, isTrue);
  });
}
