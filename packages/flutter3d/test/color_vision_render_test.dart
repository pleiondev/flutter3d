/// Colour vision in the composite: the table `ColorVision` bakes, read by the
/// software renderer where the frame is graded.
///
///     flutter test test/color_vision_render_test.dart
///
/// The table is the whole of the effect — no shader of its own — so what is
/// left to show is that the frame drawn through it is the frame `ColorVision`
/// says, pixel by pixel, to within the table's own interpolation.
///
/// Drawn undithered throughout, so a difference is the table's and not the
/// noise's.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 48;
const int _height = 36;

/// Red, green, blue and yellow swatches, unlit.
Scene _colors(CpuDevice device) {
  final scene = Scene();
  const swatches = <List<double>>[
    <double>[0.8, 0.2, 0.2],
    <double>[0.2, 0.7, 0.3],
    <double>[0.2, 0.3, 0.9],
    <double>[0.7, 0.7, 0.2],
  ];
  for (var i = 0; i < swatches.length; i++) {
    final rgb = swatches[i];
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(0.8, 0.8, 0.8)).build(),
        ),
        RenderMaterial(
          name: 'swatch$i',
          baseColor: LinearColor.fromSrgb(rgb[0], rgb[1], rgb[2], 1.0),
          lighting: LightingModel.unlit,
        ),
      )..setPosition((i - 1.5) * 1.0, 0.0, 0.0),
    );
  }
  return scene;
}

Future<Uint8List> _draw(LookSettings Function(CpuDevice device) look) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: _colors(device),
    views: <RenderView>[
      RenderView(camera: CameraNode()..setPosition(0.0, 0.0, 5.0)),
    ],
    settings: RenderSettings(look: look(device)),
  );
  return (await device.readback(frame.frame)).buffer.asUint8List();
}

void main() {
  test('the frame through the table is the frame ColorVision says', () async {
    final plain = await _draw((_) => const LookSettings(dither: 0));
    for (final vision in <ColorVision>[
      const ColorVision.simulate(ColorVisionDeficiency.deutan),
      const ColorVision.correct(ColorVisionDeficiency.protan),
      const ColorVision.simulate(ColorVisionDeficiency.tritan),
    ]) {
      final seen = await _draw(
        (device) => LookSettings(lut: vision.upload(device), dither: 0),
      );
      var worst = 0;
      var moved = 0;
      for (var at = 0; at < plain.length; at += 4) {
        final (r, g, b) = vision.applyEncoded(
          plain[at] / 255,
          plain[at + 1] / 255,
          plain[at + 2] / 255,
        );
        final want = <int>[
          (r * 255).round(),
          (g * 255).round(),
          (b * 255).round(),
        ];
        for (var c = 0; c < 3; c++) {
          final off = (seen[at + c] - want[c]).abs();
          if (off > worst) worst = off;
          if (seen[at + c] != plain[at + c]) moved++;
        }
      }
      // Within what 33 entries a channel interpolate to, and the frame did
      // change. Mutation: a table written in linear light where the
      // composite indexes in sRGB moves every swatch by tens of levels.
      expect(worst, lessThanOrEqualTo(6), reason: '$vision');
      expect(moved, greaterThan(100), reason: '$vision');
    }
  });

  test('at no severity the frame is the frame without a table', () async {
    // Undithered, for the reason `lut_grading_test.dart` gives: half a step
    // of the table and half a step of dither together cross a rounding edge
    // that neither crosses alone.
    final plain = await _draw((_) => const LookSettings(dither: 0));
    final none = await _draw(
      (device) => LookSettings(
        lut: const ColorVision.simulate(
          ColorVisionDeficiency.deutan,
          severity: 0.0,
        ).upload(device),
        dither: 0,
      ),
    );
    expect(none, plain);
  });
}
