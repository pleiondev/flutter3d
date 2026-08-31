/// A camera standing on a floor bigger than it can see.
///
///     flutter test test/near_plane_test.dart
///
/// One brush a hundred and twenty metres across is one pair of triangles, and a
/// camera three metres above the middle of it has both of them straddling the
/// eye. The clipper handles that — it was written for exactly this and says so
/// — but the vertex it cuts is stored in float32, and interpolating its `w`
/// rounds. Sometimes to a hair below the plane, which is survivable, and
/// sometimes to exactly zero, which is not: `x / 0` is infinity, and the
/// bounding box's `ceil()` throws `Unsupported operation: Infinity or NaN
/// toInt` from four frames inside a rasteriser.
///
/// Every frame drawn from inside a level crashed this way, and the parity
/// fixtures never noticed because none of them has geometry that big.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

({CpuDevice device, Renderer renderer}) _engine() {
  final it = cpuTestDevice(width: _width, height: _height);
  return (
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
  );
}

void main() {
  test('a floor that reaches behind the camera is still drawn', () async {
    // Mutation: drop `cutVertex.w = _nearEpsilon` from `_rasterise`, which
    // leaves the cut vertex wherever float32 rounding put it. This throws.
    final it = _engine();
    final scene = Scene();

    // Four brushes off the platformer's shipped level, to the metre: the first
    // floor and the three walls around it. The *size* is the test — the long
    // walls are two hundred and seventy-four metres of triangle, and it is
    // their cut vertex that rounds onto zero. A tidy little floor rounds to a
    // survivable `w` and proves nothing, which is what the first draft of this
    // test did.
    for (final List<double> brush in <List<double>>[
      <double>[0.0, -0.5, -2.5, 120.0, 1.0, 55.0],
      <double>[-60.5, 4.0, 105.0, 1.0, 8.0, 274.0],
      <double>[60.5, 4.0, 105.0, 1.0, 8.0, 274.0],
      <double>[0.0, 4.0, -30.5, 122.0, 8.0, 1.0],
    ]) {
      scene.add(
        MeshNode(
          DeviceMesh.upload(
            it.device,
            CuboidShape(size: Vector3(brush[3], brush[4], brush[5])).build(),
          ),
          Material(
            name: 'brush',
            baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
            lighting: LightingModel.pbr,
          ),
          name: 'brush',
        )..setPosition(brush[0], brush[1], brush[2]),
      );
    }
    scene.add(
      LightNode(type: LightType.point, intensity: 40.0, range: 80.0, name: 'sun')
        ..setPosition(0.0, 8.0, -16.0),
    );

    // Where the game's camera stood when this was found: inside the level, just
    // above the floor, looking a little down at a coin three metres ahead.
    final camera = CameraNode()
      ..setPosition(0.0, 1.4, -19.0)
      ..lookAt(Vector3(0.0, 0.8, -16.0));

    // The assertion is that this returns at all: before the fix it threw from
    // inside `_rasteriseTriangle`, which no caller could have caught usefully.
    final frame = it.renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: const RenderSettings(),
    );

    final pixels = await it.device.readPixels(frame.frame);
    expect(pixels, isNotNull);

    // And that it drew the floor rather than merely surviving: the bottom of
    // the frame is the floor near the camera, and it is lit.
    final rgba = pixels!.buffer.asUint8List();
    var lit = 0;
    for (var y = _height ~/ 2; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        if (rgba[(y * _width + x) * 4] > 20) lit++;
      }
    }
    expect(lit, greaterThan(_width * _height ~/ 8),
        reason: 'the near half of the floor is missing, not merely dim');
  });
}
