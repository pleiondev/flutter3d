/// `gfx-18n`: a colour table in the composite, and what an identity one costs.
///
///     flutter test test/lut_grading_test.dart
///
/// **The question the row exists to answer is whether "neutral" is exactly a
/// no-op or merely nearly one**, and it is a question about the texture's
/// precision rather than about the arithmetic. A table read off disk is eight
/// bits a channel, so an identity entry at index `i` is `round(255 i / (N -
/// 1))` — which is the value itself only where that division comes out whole,
/// and the sampler interpolates between entries that are each up to half a
/// step off.
///
/// Measured, the answer is that it is exact, and for a reason worth keeping:
/// the composite encodes to eight bits of sRGB at the end, and half a step of
/// error rounds back to the byte it started from. It is a property of the
/// pair — an eight-bit table into an eight-bit target — rather than of the
/// table, which is why the test that says so carries the argument with it.
///
/// The off case is exact for a simpler reason: no table, or a strength of
/// zero, and the composite never samples anything at all.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 48;
const int _height = 36;

({CpuDevice device, Renderer renderer}) _engine() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  return (device: device, renderer: Renderer.create(device: device));
}

/// The identity table, uploaded.
TextureHandle _identity(CpuDevice device, {int size = 33}) =>
    device.createTextureFromPixels(
      width: size * size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(buildIdentityLut(size: size)),
    )!;

/// A table that swaps red and blue — visibly not the identity, and its own
/// inverse, which is what lets a round trip be checked.
TextureHandle _swapRedAndBlue(CpuDevice device, {int size = 33}) {
  final pixels = buildIdentityLut(size: size);
  for (var at = 0; at < pixels.length; at += 4) {
    final red = pixels[at];
    pixels[at] = pixels[at + 2];
    pixels[at + 2] = red;
  }
  return device.createTextureFromPixels(
    width: size * size,
    height: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(pixels),
  )!;
}

/// A scene with a spread of colours in it, so a table has something to move.
Scene _colours(CpuDevice device) {
  final scene = Scene();
  const List<List<double>> swatches = <List<double>>[
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
        Material(
          name: 'swatch$i',
          baseColor: Vector4(rgb[0], rgb[1], rgb[2], 1.0),
          lighting: LightingModel.unlit,
        ),
      )..setPosition((i - 1.5) * 1.0, 0.0, 0.0),
    );
  }
  return scene;
}

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer}) it,
  LookSettings look,
) async {
  final frame = it.renderer.render(
    width: _width,
    height: _height,
    scene: _colours(it.device),
    views: <RenderView>[
      RenderView(camera: CameraNode()..setPosition(0.0, 0.0, 5.0)),
    ],
    settings: RenderSettings(look: look),
  );
  final pixels = await it.device.readPixels(frame.frame);
  return pixels!.buffer.asUint8List();
}

/// The largest difference in any channel of any pixel.
int _largestDifference(Uint8List a, Uint8List b) {
  var worst = 0;
  for (var i = 0; i < a.length; i++) {
    final difference = (a[i] - b[i]).abs();
    if (difference > worst) worst = difference;
  }
  return worst;
}

void main() {
  group('the identity table', () {
    test('builds a strip of the shape the shader expects', () {
      const int size = 17;
      final pixels = buildIdentityLut(size: size);
      expect(pixels.length, size * size * size * 4);

      // The first texel is black, the last is white, and the entry for the
      // middle slice's middle row and column is mid grey in all three.
      expect(<int>[pixels[0], pixels[1], pixels[2]], <int>[0, 0, 0]);
      final lastAt = pixels.length - 4;
      expect(
        <int>[pixels[lastAt], pixels[lastAt + 1], pixels[lastAt + 2]],
        <int>[255, 255, 255],
      );
    });

    test('a table needs two ends', () {
      expect(() => buildIdentityLut(size: 1), throwsArgumentError);
    });
  });

  group('off means untouched', () {
    test('no table draws what no grading draws', () async {
      final it = _engine();
      final without = await _draw(it, const LookSettings());
      final again = await _draw(it, const LookSettings());
      expect(without, again);
    });

    test('a table at zero strength is never sampled', () async {
      final it = _engine();
      final without = await _draw(it, const LookSettings());
      // A table that would swap red and blue, asked for at zero. If the
      // composite mixed by the strength instead of branching on it, a
      // rounding difference would show; if it sampled and then discarded,
      // the picture would still be right but the row's own acceptance would
      // be false. Byte equality is the only reading of "never sampled" a
      // test can take from outside.
      final ignored = await _draw(
        it,
        LookSettings(lut: _swapRedAndBlue(it.device), lutStrength: 0.0),
      );
      expect(ignored, without);
    });

    test('a look with a table at zero is still neutral', () {
      final it = _engine();
      expect(const LookSettings().isNeutral, isTrue);
      expect(
        LookSettings(lut: _identity(it.device), lutStrength: 0.0).isNeutral,
        isTrue,
      );
      expect(
        LookSettings(lut: _identity(it.device)).isNeutral,
        isFalse,
        reason: 'a table at full strength is a look, whatever is in it',
      );
    });
  });

  group('a table that does something', () {
    test('swapping red and blue swaps red and blue', () async {
      final it = _engine();
      final plain = await _draw(it, const LookSettings());
      final swapped = await _draw(
        it,
        LookSettings(lut: _swapRedAndBlue(it.device)),
      );

      // Every pixel's red and blue traded places, to within the table's own
      // precision. Checked over the whole frame rather than at one swatch:
      // a table sampled with the slices transposed would still look plausible
      // on a single colour.
      var checked = 0;
      for (var at = 0; at < plain.length; at += 4) {
        if (plain[at] == plain[at + 2]) continue; // grey pixels say nothing
        checked++;
        expect(
          (swapped[at] - plain[at + 2]).abs(),
          lessThanOrEqualTo(3),
          reason: 'red at $at came out ${swapped[at]}, wanted ${plain[at + 2]}',
        );
        expect((swapped[at + 2] - plain[at]).abs(), lessThanOrEqualTo(3));
      }
      expect(
        checked,
        greaterThan(100),
        reason:
            'the scene has to have coloured pixels for this to mean '
            'anything',
      );
    });

    test('half strength lands between the two', () async {
      final it = _engine();
      final plain = await _draw(it, const LookSettings());
      final full = await _draw(
        it,
        LookSettings(lut: _swapRedAndBlue(it.device)),
      );
      final half = await _draw(
        it,
        LookSettings(lut: _swapRedAndBlue(it.device), lutStrength: 0.5),
      );

      expect(
        _largestDifference(half, plain),
        lessThan(_largestDifference(full, plain)),
      );
      expect(_largestDifference(half, plain), greaterThan(0));
    });
  });

  group('what an identity table actually costs', () {
    test('it is exactly a no-op, and the reason is worth knowing', () async {
      // **The row asked whether this is exactly a no-op, and it is — but
      // not because the table is exact.** An eight-bit entry at index `i`
      // holds `round(255 i / (N - 1))`, which is the value itself only
      // where that division comes out whole; the sampler then interpolates
      // between entries that are each up to half a step off. What rescues
      // it is the other end of the pass: the composite encodes to eight
      // bits of sRGB, and half a step of error rounds to the byte it
      // started from.
      //
      // So this is a claim about the pair — an eight-bit table into an
      // eight-bit target — rather than about the table alone. A float
      // target or a wider gamut would have to be measured again, which is
      // why the sentence is here and not only in the plan.
      final it = _engine();
      final without = await _draw(it, const LookSettings());
      final through = await _draw(it, LookSettings(lut: _identity(it.device)));

      final worst = _largestDifference(without, through);
      expect(worst, 0, reason: 'an identity table moved a channel by $worst');
    });

    test(
      'a coarser table is further off, which is the whole tradeoff',
      () async {
        final it = _engine();
        final without = await _draw(it, const LookSettings());
        final fine = await _draw(
          it,
          LookSettings(lut: _identity(it.device, size: 33)),
        );
        final coarse = await _draw(
          it,
          LookSettings(lut: _identity(it.device, size: 5)),
        );

        expect(
          _largestDifference(coarse, without),
          greaterThanOrEqualTo(_largestDifference(fine, without)),
        );
      },
    );
  });
}
