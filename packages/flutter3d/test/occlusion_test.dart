/// Occlusion leaves out what is hidden and changes no pixel — `C2`, `C3`.
///
///     flutter test test/occlusion_test.dart
///
/// Metamorphic: each scene is drawn with occlusion off and on through the
/// software rasteriser, and the two frames must be the same bytes while the
/// one with occlusion on draws less. Every mesh is marked an occluder, which
/// is the hardest case for the claim — every surface in the frame is then
/// allowed to hide every other — and not what a game would do.
///
/// `occlusion-city` is the plan's golden scene, held here as a property
/// rather than a picture: its references are recorded on a device, and this
/// is what has to be true of whatever gets recorded.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// The pyramid's own size, so each cell is one pixel of the frame.
const int _width = 256;
const int _height = 128;

/// A street: a row of blocks across the view with gaps between them, a
/// floor, and thirty small things behind the row, some seen through the gaps
/// and most not. One block is mirrored and one wall is a double-sided plane,
/// so both windings are in the frame.
({Scene scene, CameraNode camera}) _city(GraphicsDevice device) {
  final scene = Scene()
    ..add(
      LightNode(intensity: 5.0, castsShadow: true)
        ..setPosition(6.0, 10.0, 8.0)
        ..lookAt(Vector3.zero()),
    );
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(40, 0.2, 40)).build(),
      ),
      Material(name: 'floor', baseColor: Vector4(0.7, 0.7, 0.7, 1.0)),
    )..setPosition(0.0, -0.1, 0.0),
  );
  final block = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(3.0, 6.0, 1.0)).build(),
  );
  for (var i = 0; i < 5; i++) {
    final node = scene.add(
      MeshNode(
        block,
        Material(name: 'block $i', baseColor: Vector4(0.8, 0.5, 0.3, 1.0)),
      )..setPosition(-8.0 + i * 4.0, 3.0, 3.0),
    );
    // Mirrored in x: the same box, its triangles turned over on screen.
    if (i == 1) node.setScale(-1.0, 1.0, 1.0);
  }
  scene.add(
    MeshNode(
        DeviceMesh.upload(
          device,
          const PlaneShape(width: 3.0, depth: 6.0).build(),
        ),
        Material(name: 'sheet', doubleSided: true),
      )
      ..setPosition(9.5, 3.0, 3.0)
      ..setRotation(
        Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), 1.5707963267948966),
      ),
  );
  final thing = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3.all(0.6)).build(),
  );
  for (var i = 0; i < 30; i++) {
    scene.add(
      MeshNode(
        thing,
        Material(baseColor: Vector4(0.3, 0.6, 0.9, 1.0)),
        name: 'thing $i',
      )..setPosition(-9.0 + (i % 10) * 2.0, 0.3, -1.0 - (i ~/ 10) * 3.0),
    );
  }
  final camera = scene.add(CameraNode())
    ..setPosition(0.0, 1.6, 12.0)
    ..lookAt(Vector3(0.0, 1.6, 0.0));
  return (scene: scene, camera: camera);
}

void _markAll(Scene scene) {
  for (final node in scene.meshes) {
    node.occluder = true;
  }
}

const RenderSettings _settings = RenderSettings(
  shadows: ShadowSettings(enabled: true),
  bloom: BloomSettings(enabled: false),
);

void main() {
  test('occlusion-city', () async {
    Future<({Uint8List pixels, int culled})> draw(OcclusionMode mode) async {
      final it = cpuTestDevice(width: _width, height: _height);
      final renderer = Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      );
      final (:scene, :camera) = _city(it.device);
      _markAll(scene);
      final frame = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: _settings.copyWith(occlusion: mode),
      );
      final pixels = await it.device.readPixels(frame.frame);
      return (pixels: pixels!.buffer.asUint8List(), culled: frame.culled);
    }

    final off = await draw(OcclusionMode.none);
    final on = await draw(OcclusionMode.software);
    // Mutation: flip the per-pixel comparison in
    // `OcclusionBuffer.mayBeVisible` — what is hidden is kept and what is
    // seen is left out, and the frames part.
    expect(on.culled, greaterThan(off.culled + 10));
    expect(on.pixels, off.pixels);
  });

  test(
    'hi-Z hides nothing before its first reading and the same after',
    () async {
      final it = cpuTestDevice(width: _width, height: _height);
      final renderer = Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      );
      final (:scene, :camera) = _city(it.device);
      final views = <RenderView>[RenderView(camera: camera)];

      Future<({Uint8List pixels, int culled})> draw(OcclusionMode mode) async {
        final frame = renderer.render(
          width: _width,
          height: _height,
          scene: scene,
          views: views,
          settings: _settings.copyWith(occlusion: mode),
        );
        final pixels = await it.device.readPixels(frame.frame);
        return (pixels: pixels!.buffer.asUint8List(), culled: frame.culled);
      }

      final off = await draw(OcclusionMode.none);
      final first = await draw(OcclusionMode.hiZ);
      expect(first.culled, off.culled, reason: 'no reading yet');
      await pumpEventQueue();
      expect(renderer.debugHiZ!.readings, 1);

      // A still camera: the reading is this frame's depth, carried nowhere.
      // Mutation: scale the decoded depth in `HiZOcclusion.accept` by 0.3, so
      // the reading sits in front of surfaces that are there — 765 bytes of
      // the frame change and this goes red. (By 0.8 it does not: every box
      // in this street reaches past an edge onto something farther.)
      final second = await draw(OcclusionMode.hiZ);
      expect(second.culled, greaterThan(off.culled + 10));
      expect(second.pixels, off.pixels);

      // Switched off, the reading goes with it: the next frame with hi-Z on
      // again starts from nothing rather than from a stale scene.
      await draw(OcclusionMode.none);
      final again = await draw(OcclusionMode.hiZ);
      expect(again.culled, off.culled);
    },
  );
}
