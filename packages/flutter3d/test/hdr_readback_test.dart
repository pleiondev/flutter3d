/// `CpuDevice.readHdrPixels` — the raw floats [readPixels] clamps away.
///
///     flutter test test/hdr_readback_test.dart
///
/// Built for `par-02`'s diagnostic MCP: a depth in world metres does not fit
/// in `readPixels`'s 8-bit `0..1`, and `NaN.clamp(0.0, 1.0)` answers `1.0`
/// on this SDK — an ordinary channel value with nothing about it to say a
/// shader went wrong. Pinned here so a future change to either method is
/// caught by a number, not by a diagnostic tool quietly going blind.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 32;
const int _height = 32;

void main() {
  test(
    'the surface buffer\'s depth survives readHdrPixels and drowns in readPixels',
    () async {
      final it = cpuTestDevice(width: _width, height: _height);
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(
              it.device,
              const PlaneShape(width: 4.0, depth: 4.0).build(),
            ),
            Material(name: 'floor', baseColor: Vector4(0.6, 0.6, 0.6, 1.0)),
          ),
        );
      // Ten metres out, looking straight down the axis: the surface buffer's
      // alpha (view depth) should read close to ten, far past readPixels's
      // `0..1` ceiling.
      final camera = CameraNode(
        projection: const PerspectiveProjection(
          fovYRadians: 1.0,
          near: 0.05,
          far: 50.0,
        ),
      )..setPositionFrom(Vector3(0.0, 10.0, 0.0));
      camera.lookAt(Vector3.zero());
      scene.add(camera);

      final renderer = Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      );
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: const RenderSettings(
          surfaceBuffer: true,
          showSurfaceBuffer: true,
        ),
      );

      final raw = it.device.readHdrPixels(result.frame);
      final centre = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
      final depth = raw[centre + 3];
      expect(
        depth,
        closeTo(10.0, 0.5),
        reason: 'the surface buffer\'s alpha is view depth in world metres',
      );

      final clamped = await it.device.readPixels(result.frame);
      final bytes = clamped!.buffer.asUint8List();
      expect(
        bytes[centre + 3],
        255,
        reason:
            'readPixels clamps the same ten metres to 1.0 — the exact loss '
            'readHdrPixels exists to avoid',
      );
    },
  );
}
