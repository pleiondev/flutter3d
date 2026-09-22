/// `DebugDrawOptions.normals`, drawn rather than assembled.
///
///     flutter test test/debug_normals_test.dart
///
/// **The one overlay nothing turned on.** `addNormals` has unit tests of its
/// own in `flutter3d/test/debug_draw_test.dart`, and `buildForScene` is reached
/// by the goldens and by `steady_frame_test.dart` — but every caller that sets
/// options sets some subset of `bounds`, `axes` and `lightGizmos`, so the
/// branch between the flag and the segments had never run, on this backend or
/// on either other one.
///
/// The branch is not a pass-through. It reads `node.mesh.source`, which is null
/// for a mesh uploaded with `keepSourceData: false` — and no backend here can
/// read a buffer back, so a dropped source is not a slow path but no normals at
/// all. Both halves are pinned below, because the second one is silent: the
/// overlay draws the bounding boxes it was also asked for and looks like it
/// worked.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

/// One cube in front of the camera, uploaded with or without its triangles.
({CpuDevice device, Scene scene, CameraNode camera}) _cube({
  required bool keepSource,
}) {
  final it = cpuTestDevice(width: _width, height: _height);
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          it.device,
          CuboidShape(size: Vector3(2.0, 2.0, 2.0)).build(),
          keepSourceData: keepSource,
        ),
        Material(
          name: 'cube',
          baseColor: Vector4(0.5, 0.5, 0.5, 1.0),
          lighting: LightingModel.lambert,
        ),
        name: 'cube',
      ),
    );
  final camera = CameraNode()
    ..setPosition(3.0, 2.5, -4.0)
    ..lookAt(Vector3.zero());
  scene.add(camera);
  return (device: it.device, scene: scene, camera: camera);
}

/// The frame and how many debug segments went into it.
Future<({List<int> pixels, int lines})> _draw(
  ({CpuDevice device, Scene scene, CameraNode camera}) it,
  DebugDrawOptions debug,
) async {
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: cpuTestDevice(width: 4, height: 4).albedo,
    fallbackNormal: cpuTestDevice(width: 4, height: 4).normal,
  );
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[RenderView(camera: it.camera)],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      debug: debug,
    ),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return (pixels: pixels!.buffer.asUint8List(), lines: result.debugLines);
}

void main() {
  test('the normals overlay puts segments in the frame', () async {
    // Mutation: change `if (options.bounds || options.normals)` in
    // `debug_draw_gizmos.dart` to `if (options.bounds)` — the flag then reaches
    // `buildForScene` and stops there, `debugLines` comes back zero and the two
    // frames are identical, which is what this backend drew before.
    final it = _cube(keepSource: true);
    final off = await _draw(it, const DebugDrawOptions());
    final on = await _draw(it, const DebugDrawOptions(normals: true));

    expect(off.lines, 0, reason: 'nothing was asked for');
    expect(
      on.lines,
      greaterThan(0),
      reason: 'the flag reached the overlay but no segment came out of it',
    );
    expect(
      on.pixels,
      isNot(equals(off.pixels)),
      reason:
          'the segments were built and never rasterised, which is the half of '
          'this that a count cannot see',
    );
  });

  test('a mesh that dropped its triangles draws none, and says so', () async {
    // The documented consequence of `keepSourceData: false`, stated on
    // `MeshGeometry.source` — "normals cannot be drawn" — and worth a check
    // because the overlay stays on and the frame stays plausible. A reader who
    // sees the bounding boxes appear has no reason to doubt the normals.
    //
    // Mutation: drop the `if (source != null)` guard in `buildForScene` — the
    // null goes into `addNormals` and this fails with a type error rather than
    // with a count, which is the other way the same branch can be wrong.
    final it = _cube(keepSource: false);
    final on = await _draw(
      it,
      const DebugDrawOptions(normals: true, bounds: true),
    );
    final bounds = await _draw(it, const DebugDrawOptions(bounds: true));

    expect(
      on.lines,
      bounds.lines,
      reason:
          'a mesh with no source data has no normals to draw, so asking for '
          'them must add nothing to what the bounding box already drew',
    );
    expect(on.lines, greaterThan(0), reason: 'the box itself is still drawn');
  });
}
