/// `MeshOverlay.ribbon`'s own width, drawn at two different depths —
/// `pro-eng-07`'s own acceptance: a screen-space expansion, so the same
/// pixel width whatever the ribbon's own distance from the eye.
///
///     flutter test test/overlay_ribbon_width_test.dart
///
/// `mesh_overlay_test.dart` already proves the geometry — the quad `ribbon`
/// emits is exactly [width] logical pixels across, and `point`'s own "twice
/// as far away is twice as wide in the world" test already exercises the
/// same `worldSize` a ribbon's width comes from — but neither ever reads a
/// pixel back. This is the one place a change to `worldSize`, or to how the
/// software rasteriser turns a wide quad into a scanline, would actually be
/// checked against a rendered picture rather than against the vertices that
/// went in.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 240;
const int _height = 160;
const double _fovYRadians = 0.9;

/// How many pixels in [row] read as [colour], scanning outward from
/// [aroundColumn] — the ribbon's own measured width, in pixels, wherever it
/// landed.
int _spanWidth(Uint8List rgba, int row, int aroundColumn, {required int r, required int g, required int b}) {
  bool isRibbon(int column) {
    if (column < 0 || column >= _width) return false;
    final at = (row * _width + column) * 4;
    return (rgba[at] - r).abs() < 20 &&
        (rgba[at + 1] - g).abs() < 20 &&
        (rgba[at + 2] - b).abs() < 20;
  }

  if (!isRibbon(aroundColumn)) return 0;
  var low = aroundColumn;
  while (isRibbon(low - 1)) {
    low--;
  }
  var high = aroundColumn;
  while (isRibbon(high + 1)) {
    high++;
  }
  return high - low + 1;
}

void main() {
  test('a ribbon of the same width reads the same pixels wide at two depths', () async {
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final overlay = renderer.addContributor(
      MeshOverlay(
        vertexShader: renderer.debugLineVertexShader,
        fragmentShader: renderer.debugLineFragmentShader,
      ),
    );

    // Looking down -Z from the origin — the plainest camera this file could
    // set up without an application's own staging behind it.
    final pixel = 2.0 * math.tan(_fovYRadians * 0.5) / _height;
    overlay.lookFrom(
      eye: Vector3.zero(),
      right: Vector3(1, 0, 0),
      up: Vector3(0, 1, 0),
      pixel: pixel,
    );

    // Two ribbons, side by side in x so neither's own span reaches the
    // other, one twice as far from the eye as the other — the exact case
    // `worldSize` exists to correct for.
    const near = -4.0;
    const far = -8.0;
    const requestedWidth = 8.0;
    overlay.ribbon(
      Vector3(-1.0, -0.6, near),
      Vector3(-1.0, 0.6, near),
      Vector4(1, 0, 0, 1),
      width: requestedWidth,
    );
    overlay.ribbon(
      Vector3(1.0, -0.6, far),
      Vector3(1.0, 0.6, far),
      Vector4(0, 1, 0, 1),
      width: requestedWidth,
    );

    final camera = CameraNode(
      projection: const PerspectiveProjection(fovYRadians: _fovYRadians),
    );
    final scene = Scene()..add(camera);
    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      // Exact colours matter here — this test reads them back to find a
      // ribbon's own edges — and tonemapping exists to make a picture look
      // right, not to preserve the byte a caller asked for.
      settings: const RenderSettings(tonemap: false, exposure: 1.0),
    );
    final pixels = await device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');
    final rgba = pixels!.buffer.asUint8List();

    // Columns are found by where each ribbon's own colour first appears in
    // the middle row, rather than assumed from the world positions above —
    // a projection bug that moved a ribbon sideways should not also move
    // this test's own idea of where to look.
    int firstColumnOf({required int r, required int g, required int b}) {
      for (var c = 0; c < _width; c++) {
        final at = (_height ~/ 2 * _width + c) * 4;
        if ((rgba[at] - r).abs() < 20 &&
            (rgba[at + 1] - g).abs() < 20 &&
            (rgba[at + 2] - b).abs() < 20) {
          return c;
        }
      }
      return -1;
    }

    final redColumn = firstColumnOf(r: 255, g: 0, b: 0);
    final greenColumn = firstColumnOf(r: 0, g: 255, b: 0);
    expect(redColumn, greaterThanOrEqualTo(0), reason: 'the near ribbon did not draw');
    expect(greenColumn, greaterThanOrEqualTo(0), reason: 'the far ribbon did not draw');

    final nearWidth = _spanWidth(rgba, _height ~/ 2, redColumn + 1, r: 255, g: 0, b: 0);
    final farWidth = _spanWidth(rgba, _height ~/ 2, greenColumn + 1, r: 0, g: 255, b: 0);

    // Mutation: drop the `_depth(at)` factor from `worldSize`, and a ribbon
    // twice as far away reads about half as many pixels wide instead of the
    // same number — perspective shrinks it exactly as much as the missing
    // compensation was meant to cancel out.
    expect(
      farWidth,
      closeTo(nearWidth.toDouble(), 1.0),
      reason:
          'near ribbon read $nearWidth px wide, far ribbon read $farWidth px '
          'wide — a screen-space width should not care which one is farther',
    );
    expect(nearWidth, greaterThan(2), reason: 'too thin a span to be measuring anything');
  });
}
