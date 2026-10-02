/// What the lens does to a picture — `P2`: it bends it, and it throws a
/// bright light's reflections across the middle of the frame.
///
///     dart test test/lens_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

/// A card of [colour] at ([x], [y]) on black, through [settings].
Float32List _render(
  RenderSettings settings, {
  double x = 0.0,
  double y = 0.0,
  double size = 0.6,
  double colour = 1.0,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final card =
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          Material(
            lighting: LightingModel.unlit,
            baseColor: Vector4(colour, colour, colour, 1.0),
          ),
        )
        ..setPosition(x, y, -3.0)
        ..setScale(size, size, 0.05);
  final camera = CameraNode();
  final result = Renderer.create(device: device).render(
    width: _width,
    height: _height,
    scene: Scene()
      ..add(card)
      ..add(camera),
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: settings,
  );
  return Float32List.fromList(device.readHdrPixels(result.frame));
}

/// How many pixels are mostly lit.
int _lit(Float32List frame) {
  var count = 0;
  for (var i = 0; i < frame.length; i += 4) {
    if (frame[i] > 0.5) count++;
  }
  return count;
}

/// The red at pixel ([x], [y]).
double _at(Float32List frame, int x, int y) => frame[(y * _width + x) * 4];

const RenderSettings _plain = RenderSettings(
  bloom: BloomSettings(enabled: false),
  look: LookSettings(dither: 0.0),
);

void main() {
  group('distortion', () {
    test('nought is the picture as it was', () {
      expect(
        _render(_plain.copyWith(look: _plain.look.copyWith(distortion: 0.0))),
        _render(_plain),
      );
    });

    test('a barrel magnifies the middle and a pincushion shrinks it', () {
      // Mutation: turn the sign of `k` in `Distort`, and the two swap.
      // A card big enough that a pixel's worth of quantisation at its edge
      // does not hide the bend.
      int lit(double k) => _lit(
        _render(
          _plain.copyWith(look: _plain.look.copyWith(distortion: k)),
          size: 1.2,
        ),
      );
      final straight = lit(0.0);
      final barrel = lit(0.5);
      final pincushion = lit(-0.5);
      // ignore: avoid_print
      print('lit: pincushion $pincushion, straight $straight, barrel $barrel');
      expect(barrel, greaterThan(straight * 1.15));
      expect(pincushion, lessThan(straight * 0.9));
    });
  });

  group('flare', () {
    // A small bright card up and to the left, well over the bloom
    // threshold: its reflections land down and to the right.
    RenderSettings flaring({bool flare = true, bool bloom = true}) =>
        _plain.copyWith(
          // A tight glow: the flare is as soft as the glow it is drawn
          // from, and the default five full levels throw a skirt half the
          // frame wide.
          bloom: BloomSettings(
            enabled: bloom,
            intensity: 0.02,
            levels: 3,
            scatter: 0.4,
            lensFlare: LensFlareSettings(enabled: flare, intensity: 6.0),
          ),
        );
    Float32List light(RenderSettings settings) =>
        _render(settings, x: -0.9, y: 0.45, size: 0.15, colour: 6.0);

    /// What [after] adds over [before] in the quarter of the frame from
    /// column [x0] and row [y0].
    double added(Float32List before, Float32List after, int x0, int y0) {
      var sum = 0.0;
      for (var y = y0; y < y0 + _height ~/ 2; y++) {
        for (var x = x0; x < x0 + _width ~/ 2; x++) {
          sum += _at(after, x, y) - _at(before, x, y);
        }
      }
      return sum;
    }

    test('throws light across the middle from a bright one', () {
      // The light is in the top left quarter; its reflections land in the
      // bottom right one, across the middle, and not beside it in the top
      // right. Mutation: drop the flip in `lens_flare.frag`, and the light
      // lands on itself instead.
      final without = light(flaring(flare: false));
      final withFlare = light(flaring());
      final across = added(without, withFlare, _width ~/ 2, _height ~/ 2);
      final beside = added(without, withFlare, _width ~/ 2, 0);
      // ignore: avoid_print
      print('flare added: $across across the middle, $beside beside');
      expect(across, greaterThan(1.0));
      expect(across, greaterThan(beside * 4.0));
    });

    test('is nothing with the bloom off', () {
      expect(light(flaring(bloom: false)), light(_plain));
    });

    test('is nothing when nothing blooms', () {
      // A card well under the bloom's knee: no glow, so no reflection of
      // one.
      Float32List dim({required bool flare}) => _render(
        _plain.copyWith(
          bloom: BloomSettings(
            lensFlare: LensFlareSettings(enabled: flare, intensity: 6.0),
          ),
        ),
        size: 0.15,
        colour: 0.2,
      );
      expect(dim(flare: true), dim(flare: false));
    });
  });
}
