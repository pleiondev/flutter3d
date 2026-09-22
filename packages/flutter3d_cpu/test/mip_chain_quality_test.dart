/// `ap-08` in `doc/asset-pipeline-plan.md`'s own acceptance, read literally:
/// a distant surface (a huge screen-space footprint, the same `du`/`dv` this
/// backend already differentiates for `mip_sampling_test.dart`) samples
/// close to the texture's true average when it has `ap-08`'s Kaiser-filtered
/// chain, and a plain base-level read — what a texture with no chain at all
/// falls back to, per `mip_sampling_test.dart`'s own "ignores the derivative
/// entirely" case — does not, because a single random texel is not the
/// average of the whole image.
///
/// Random rather than a checkerboard: a checkerboard averages to the same
/// half whichever texel a point sample happens to land on, which would pass
/// this test with no chain built at all and prove nothing about the filter.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart' show Rgba8Image, buildMipChain;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

const _size = 32;

Rgba8Image _noiseImage() {
  final random = Random(42);
  final pixels = Uint8List(_size * _size * 4);
  for (var i = 0; i < _size * _size; i++) {
    pixels[i * 4] = random.nextInt(256);
    pixels[i * 4 + 1] = random.nextInt(256);
    pixels[i * 4 + 2] = random.nextInt(256);
    pixels[i * 4 + 3] = 255;
  }
  return Rgba8Image(width: _size, height: _size, pixels: pixels);
}

(double, double, double) _trueAverage(Rgba8Image image) {
  var r = 0, g = 0, b = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      r += image.red(x, y);
      g += image.green(x, y);
      b += image.blue(x, y);
    }
  }
  final count = image.width * image.height;
  return (r / count, g / count, b / count);
}

void main() {
  late CpuDevice device;

  setUp(() {
    device = CpuDevice(
      width: 8,
      height: 8,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
  });

  test(
    'a distant sample through ap-08\'s chain lands near the texture\'s true average',
    () {
      final source = _noiseImage();
      final (trueR, trueG, trueB) = _trueAverage(source);
      final baseBytes = ByteData.sublistView(source.pixels);

      final chain = buildMipChain(source);
      final mipLevels = chain
          .skip(1)
          .map((level) => ByteData.sublistView(level.pixels))
          .toList();

      final withChain = BoundTexture(
        device
                .createTextureFromPixels(
                  width: _size,
                  height: _size,
                  format: TextureFormat.r8g8b8a8UNormInt,
                  pixels: baseBytes,
                  mipLevels: mipLevels,
                )!
                .backend
            as CpuTexture,
        SamplerOptions.trilinearRepeat,
      );
      final withoutChain = BoundTexture(
        device
                .createTextureFromPixels(
                  width: _size,
                  height: _size,
                  format: TextureFormat.r8g8b8a8UNormInt,
                  pixels: baseBytes,
                )!
                .backend
            as CpuTexture,
        SamplerOptions.trilinearRepeat,
      );

      // The whole texture in one pixel — as distant as a footprint gets, the
      // same value `mip_sampling_test.dart` uses for "reads a small level".
      const noiseThreshold = 12.0; // out of 255
      final distant = withChain.sample(0.5, 0.5, du: 1.0, dv: 1.0);
      expect(
        (distant.x * 255 - trueR).abs(),
        lessThan(noiseThreshold),
        reason: 'red',
      );
      expect(
        (distant.y * 255 - trueG).abs(),
        lessThan(noiseThreshold),
        reason: 'green',
      );
      expect(
        (distant.z * 255 - trueB).abs(),
        lessThan(noiseThreshold),
        reason: 'blue',
      );

      // The point this chain exists to fix: without one, a distant sample is
      // whichever texel (or bilinear blend of four) sits under this UV, not
      // the image's average — and for random noise that is usually far from
      // it, well past the same threshold the chain stays inside of.
      final noChain = withoutChain.sample(0.5, 0.5, du: 1.0, dv: 1.0);
      final noChainError = [
        (noChain.x * 255 - trueR).abs(),
        (noChain.y * 255 - trueG).abs(),
        (noChain.z * 255 - trueB).abs(),
      ].reduce(max);
      expect(
        noChainError,
        greaterThan(noiseThreshold),
        reason:
            'a base-level read this far from the average is exactly what a '
            'chain is for — if this ever fails, the fixture stopped being '
            'noisy enough to tell the two apart',
      );
    },
  );
}
