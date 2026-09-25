/// A splat's footprint is the perspective one and at least a pixel wide,
/// drawn through the software rasteriser.
///
///     dart test test/splat_ewa_test.dart
///
/// Two scenes the quads used to get wrong, each with one white splat on a
/// black ground. `splat-edge-on`: a flat disc seen exactly along its own
/// plane, which without the screen's low-pass filter is a zero-width quad
/// and draws nothing at all. `splat-grazing`: a splat long along the view
/// ray, off to the side of the frame, which the perspective Jacobian turns
/// into a streak across the screen and the camera's right and up alone
/// leave as a dot.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 128;
const int _height = 96;

/// One white, opaque-cored splat of [scale] at [centre], unrotated.
SplatCloud _one(Vector3 centre, Vector3 scale) => SplatCloud(
  centres: Float32List.fromList(<double>[centre.x, centre.y, centre.z]),
  colours: Float32List.fromList(<double>[1.0, 1.0, 1.0, 1.0]),
  scales: Float32List.fromList(<double>[scale.x, scale.y, scale.z]),
  rotations: Float32List.fromList(<double>[0.0, 0.0, 0.0, 1.0]),
);

/// The HDR frame of [cloud] seen from the origin down −Z, and the pixel its
/// centre lands on.
(Float32List, int, int) _draw(SplatCloud cloud) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode();
  final scene = Scene()
    ..ambientIntensity = 0.0
    ..add(camera);
  final renderer = Renderer.create(device: device)
    ..addContributor(SplatContributor(cloud));
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: const RenderSettings(
      tonemap: false,
      bloom: BloomSettings(enabled: false),
    ),
  );
  final clip = camera
      .viewProjection(_width / _height)
      .transformed(
        Vector4(cloud.centres[0], cloud.centres[1], cloud.centres[2], 1.0),
      );
  return (
    device.readHdrPixels(result.frame),
    ((clip.x / clip.w * 0.5 + 0.5) * _width).floor(),
    ((0.5 - clip.y / clip.w * 0.5) * _height).floor(),
  );
}

/// How many pixels of row [y] carry more than a trace of the splat.
int _litInRow(Float32List frame, int y) => <int>[
  for (var x = 0; x < _width; x++)
    if (frame[(y * _width + x) * 4] > 0.05) x,
].length;

void main() {
  test('splat-edge-on', () {
    // A disc half a metre across in the XZ plane, level with the eye: seen
    // along its plane it has no height at all. The low-pass filter gives it
    // √0.3 px of standard deviation up the screen, so its row is lit across
    // the disc's width. Mutation: drop the dilation in `SplatQuads.build` and
    // the quad has no height, so no pixel is lit.
    final (frame, _, y) = _draw(
      _one(Vector3(0.0, 0.0, -6.0), Vector3(0.5, 0.0, 0.5)),
    );
    expect(_litInRow(frame, y), greaterThan(8));
  });

  test('splat-grazing', () {
    // Two centimetres across and a metre long along the view ray, 2.5 m to
    // the right at 5 m deep: the Jacobian's lean spreads the long axis over
    // about half a metre in the splat's plane, tens of pixels. Taken from
    // right and up alone it would be the 2 cm, a pixel or two. Mutation: drop
    // the lean and the row is lit across a handful of pixels.
    final (frame, x, y) = _draw(
      _one(Vector3(2.5, 0.0, -5.0), Vector3(0.02, 0.02, 1.0)),
    );
    expect(x, lessThan(_width));
    final lit = _litInRow(frame, y);
    expect(lit, greaterThan(20), reason: 'lit across $lit pixels');
    // And only across: its height stays the narrow axes'.
    final column = <int>[
      for (var row = 0; row < _height; row++)
        if (frame[(row * _width + x) * 4] > 0.05) row,
    ].length;
    expect(column, lessThan(lit ~/ 3), reason: '$column pixels tall');
  });
}
