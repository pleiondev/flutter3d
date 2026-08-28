/// Mirrored wrapping, which this backend refused for as long as it existed.
///
/// The refusal read as a deliberate gap — the enum has a mode nothing binds —
/// and it was not one: `samplerOptionsFor` maps glTF's `MIRRORED_REPEAT`
/// straight onto it, so an ordinary model authored with mirrored wrapping
/// reached the throw. It threw from inside the per-texel path, so the failure
/// was a dead frame rather than a wrong pixel, and it happened only off a
/// device — on the backend that CI, `flutter3d_testing` and the software
/// fallback all run, while the two hardware backends drew the model fine.
///
/// Each test was written by breaking the thing it covers. The mutation is
/// named in the test.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// A two-texel-wide texture: black on the left, white on the right.
///
/// Two texels is the smallest thing that can tell the three wrapping modes
/// apart, because each answers with a different column past the edge.
TextureHandle _blackThenWhite(CpuDevice device) {
  final pixels = Uint8List(2 * 2 * 4);
  for (var y = 0; y < 2; y++) {
    for (var x = 0; x < 2; x++) {
      final value = x == 0 ? 0 : 255;
      final at = (y * 2 + x) * 4;
      pixels[at] = value;
      pixels[at + 1] = value;
      pixels[at + 2] = value;
      pixels[at + 3] = 255;
    }
  }
  return device.createTextureFromPixels(
    width: 2,
    height: 2,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(pixels),
  )!;
}

BoundTexture _bound(CpuDevice device, SamplerAddressMode mode) => BoundTexture(
  _blackThenWhite(device).backend as CpuTexture,
  SamplerOptions(widthAddressMode: mode, heightAddressMode: mode),
);

void main() {
  late CpuDevice device;

  setUp(() {
    device = CpuDevice(
      width: 8,
      height: 8,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
  });

  test('a mirrored coordinate is sampled rather than refused', () {
    // Mutation: restore the `throw UnsupportedError` in `_address`. This fails
    // with the throw, which is what every glTF carrying MIRRORED_REPEAT met.
    final bound = _bound(device, SamplerAddressMode.mirror);

    expect(() => bound.sample(1.25, 0.25), returnsNormally);
  });

  test('the second period walks the texture backwards', () {
    // Inside [0,1) mirroring and repeating agree, so the assertion that means
    // something is the one past the edge: at u=1.25 a repeat comes back to the
    // first texel and a mirror reflects onto the last.
    //
    // Mutation: return `m` instead of `period - 1 - m` in `_mirror`. The two
    // expectations below swap, which is a mirror that does not mirror.
    final bound = _bound(device, SamplerAddressMode.mirror);

    expect(bound.sample(0.25, 0.25).x, 0.0, reason: 'the left texel is black');
    expect(bound.sample(0.75, 0.25).x, 1.0, reason: 'the right texel is white');
    expect(
      bound.sample(1.25, 0.25).x,
      1.0,
      reason: 'reflected back onto the right texel, not wrapped to the left',
    );
    expect(bound.sample(1.75, 0.25).x, 0.0);
  });

  test('and it differs from a repeat, which is the whole point', () {
    // A mirror that quietly behaved like a repeat would pass every test above
    // except this one. The two modes are asked the same question and must
    // disagree.
    final mirrored = _bound(device, SamplerAddressMode.mirror);
    final repeated = _bound(device, SamplerAddressMode.repeat);

    expect(mirrored.sample(1.25, 0.25).x, isNot(repeated.sample(1.25, 0.25).x));
  });

  test('a coordinate below zero reflects too', () {
    // The negative side is a separate arm — Dart's `%` is already non-negative
    // for a positive divisor, so an implementation that forgot the guard still
    // passes, and one that wrote `i.abs()` does not.
    //
    // Mutation: replace the body with `i.abs() % size`. This fails, because
    // u=-0.25 lands on texel 0 and not on texel 1.
    final bound = _bound(device, SamplerAddressMode.mirror);

    expect(bound.sample(-0.25, 0.25).x, 0.0);
    expect(bound.sample(-0.75, 0.25).x, 1.0);
  });
}
