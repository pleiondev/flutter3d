/// `gfx-24n`: ordered dither before the 8-bit encode.
///
///     flutter test test/dither_test.dart
///
/// **A controlled ramp, which took two goes to get to.** The first version of
/// this file measured a rendered sphere instead, on the grounds that
/// `overwriteTexture` refuses anything but the two eight-bit readback layouts
/// and so an HDR ramp could not be seeded. That refusal is real and it is not
/// the only door: `createTextureFromPixels` takes a format and raw bytes, and
/// the software rasteriser accepts every uncompressed one — including
/// `r32g32b32a32Float`, which it copies through as it stands. So the frame
/// under test can be exactly a linear ramp rather than whatever a light
/// happens to leave on a sphere, and the numbers below are about banding
/// rather than about one scene.
///
/// Worth writing down because the first version reasoned from "the backend
/// cannot do this" when what was true was "this one entry point refuses it",
/// and those are the same sentence only if nobody looks.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [width]x1 float texture holding a linear ramp from 0 to [top].
TextureHandle _ramp(CpuDevice device, {required int width, double top = 0.02}) {
  final pixels = Float32List(width * 4);
  for (var x = 0; x < width; x++) {
    final value = top * x / (width - 1);
    pixels[x * 4 + 0] = value;
    pixels[x * 4 + 1] = value;
    pixels[x * 4 + 2] = value;
    pixels[x * 4 + 3] = 1.0;
  }
  final texture = device.createTextureFromPixels(
    width: width,
    height: 1,
    // Full floats rather than the engine's own half-float HDR format: the
    // point is a ramp with no quantisation of its own, and this backend
    // copies these through without a decode step to argue with.
    format: TextureFormat.r32g32b32a32Float,
    pixels: pixels.buffer.asByteData(),
  );
  if (texture == null) {
    throw StateError('the ramp was refused; the byte count must be exact');
  }
  return texture;
}

/// The red channel of the composited ramp, one byte per pixel.
Future<List<int>> _composited(double dither, {int width = 512}) async {
  final device = CpuDevice(
    width: width,
    height: 1,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final result = renderer.renderPost(
    hdr: _ramp(device, width: width),
    settings: RenderSettings(
      // Tone mapping off and exposure at one: the curve is its own
      // compression and would decide the answer. What is under test is the
      // encode and the noise that goes in before it.
      tonemap: false,
      exposure: 1.0,
      bloom: const BloomSettings(enabled: false),
      look: LookSettings(dither: dither),
    ),
  );

  final bytes = await device.readPixels(result.frame);
  return <int>[for (var x = 0; x < width; x++) bytes!.getUint8(x * 4)];
}

/// How many times the value changes along the row.
///
/// The count of *distinct* values would be the obvious measure and is the
/// wrong one: a dithered ramp and a banded ramp can hold the same set of
/// values and differ entirely in how they are laid out. What banding looks
/// like is long runs with a step between them, so the thing to count is the
/// steps.
int _transitions(List<int> row) {
  var count = 0;
  for (var i = 1; i < row.length; i++) {
    if (row[i] != row[i - 1]) count++;
  }
  return count;
}

/// The longest run of one value along the row.
///
/// The measure banding actually has: a banded ramp is long flat runs with a
/// step between them, and a dithered one holds the same values with no run
/// left to see. Counting distinct values instead would score the two the
/// same, which is how the first version of this test came to assert
/// something false.
int _longestRun(List<int> row) {
  var longest = 0;
  var run = 0;
  for (var i = 0; i < row.length; i++) {
    run = i > 0 && row[i] == row[i - 1] ? run + 1 : 1;
    if (run > longest) longest = run;
  }
  return longest;
}

void main() {
  test(
    'a dark ramp bands at 8 bits, and one step of dither breaks it up',
    () async {
      final without = await _composited(0.0);
      final with1 = await _composited(1.0 / 255.0);

      // **Three thresholds were written here before the numbers were
      // measured, and all three were wrong.** "At most six distinct values",
      // then "fewer than sixteen transitions", then "the longest flat run
      // halves". Measured over these 512 pixels: 39 transitions without and
      // 255 with, longest run 23 and 14.
      //
      // The arithmetic behind 39: a 0-to-0.02 linear ramp leaves the sRGB
      // encode at `1.055 * 0.02^(1/2.4) - 0.055`, about 0.152, which is 39 of
      // the 256 output values — so the ramp arrives as 39 runs of about
      // thirteen pixels, and that is what banding is here.
      //
      // The longest run is the wrong measure and the numbers say why: this
      // image is one pixel tall, so a 4x4 Bayer cell varies only along x with
      // a period of four. Inside a thirteen-pixel band it has four thresholds
      // to work with and cannot break every run — 23 to 14 rather than to 1.
      // What it does do is replace a flat band with a pattern, which is
      // transitions: 39 to 255, one step short of every pixel differing from
      // its neighbour.
      printOnFailure(
        'over ${without.length} pixels: without=${_transitions(without)} '
        'transitions, with=${_transitions(with1)}; longest flat run '
        'without=${_longestRun(without)}, with=${_longestRun(with1)}',
      );

      expect(
        _transitions(without),
        lessThan(60),
        reason:
            'a short dark ramp should arrive as a few dozen flat runs; if it '
            'does not, this is not measuring banding',
      );
      expect(
        _transitions(with1),
        greaterThan(_transitions(without) * 4),
        reason:
            'one output step of ordered noise should replace each flat band '
            'with a pattern, which is far more transitions',
      );
    },
  );

  test(
    'the ends of the ramp are untouched, so dither is noise and not a lift',
    () async {
      // A dither that shifted the picture would be a grade wearing a disguise.
      // Both ends are clamped by the encode, so they are where a lift would
      // show first and where the ordered cell must average out.
      final without = await _composited(0.0);
      final with1 = await _composited(1.0 / 255.0);

      double mean(List<int> row) =>
          row.fold<int>(0, (int a, int b) => a + b) / row.length;

      expect(
        (mean(with1) - mean(without)).abs(),
        lessThan(1.0),
        reason:
            'the Bayer cell is centred on zero, so the average level must '
            'not move by as much as one output step',
      );
    },
  );

  test('dither at zero leaves the frame byte for byte', () async {
    // The promise every golden in the repository depends on, and the reason
    // the shader skips the branch at zero rather than adding a noise that
    // rounds away: "rounds away" is a claim about the target's bit depth
    // rather than about the arithmetic.
    expect(const LookSettings().dither, 0.0);
    expect(await _composited(0.0), await _composited(0.0));
  });

  test('the noise is fixed to the pixel, so a golden stays recorded', () async {
    // The constraint `LookSettings.grain` documents from the other side: an
    // ordered cell is a function of screen position and of nothing else. A
    // dither that read a frame counter would be a dither no reference image
    // could describe, which is why this is ordered rather than animated.
    expect(await _composited(1.0 / 255.0), await _composited(1.0 / 255.0));
  });

  test(
    'the amount reaches the shader, and is zero when nobody asked',
    () async {
      // The plumbing half, on a backend that records what was bound: a fifth
      // uniform block is exactly the kind of thing that compiles everywhere and
      // is never written, and the frame would still look right, because zero is
      // also what "never written" produces.
      final device = FakeBackend();
      final renderer = Renderer.create(device: device);
      final scene = Scene()..add(CameraNode());

      List<double> outputEncode(RenderSettings settings) {
        renderer.render(
          width: 32,
          height: 32,
          scene: scene,
          views: <RenderView>[RenderView(camera: scene.cameras.single)],
          settings: settings,
        );
        return device.passes.last
            .recordedOf<RecordedUniformBlock>()
            .firstWhere((RecordedUniformBlock b) => b.block == 'CompositeInfo')
            .members['output_encode']!;
      }

      expect(outputEncode(const RenderSettings()), <double>[
        0.0,
        0.0,
        0.0,
        0.0,
      ]);
      expect(
        outputEncode(
          const RenderSettings(look: LookSettings(dither: 4.0 / 255.0)),
        )[0],
        closeTo(4.0 / 255.0, 1e-9),
      );
    },
  );
}
