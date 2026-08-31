/// Choosing a mip level, which is the half of mipmapping this backend had to
/// write for itself.
///
/// Storage is easy and was never the problem. Selection needs the screen-space
/// derivative of a texture coordinate, and a hardware rasteriser gets that for
/// free by differencing a quad of neighbouring fragments. This one has no
/// neighbours to difference and no idea which of its varyings is a UV, so the
/// derivative is computed per triangle and passed in by the shader — see
/// `BoundTexture.sample`.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// A texture whose base level is a checkerboard and whose every smaller level
/// is the flat average of it.
///
/// The point of the shape: the base averages to 0.5 over any region larger than
/// a texel, so a sample that reaches for a small level answers a half while a
/// sample of the base answers zero or one depending on where it lands. One
/// number tells which level was read.
TextureHandle _checkerWithChain(CpuDevice device, int size) {
  final base = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final on = (x + y).isEven ? 255 : 0;
      final at = (y * size + x) * 4;
      base[at] = on;
      base[at + 1] = on;
      base[at + 2] = on;
      base[at + 3] = 255;
    }
  }
  final bytes = ByteData.sublistView(base);
  return device.createTextureFromPixels(
    width: size,
    height: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: bytes,
    mipLevels: MipChain.build(bytes, size, size),
  )!;
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

  test('the backend says it can hold a chain, and holds one', () {
    expect(device.supportsMipmaps, isTrue);
    final handle = _checkerWithChain(device, 16);
    final texture = handle.backend as CpuTexture;
    expect(texture.levels, hasLength(MipChain.levelsFor(16, 16)));
    expect(texture.levels!.first.width, 8);
    expect(texture.levels!.last.width, 1);
  });

  test('a coordinate that barely moves reads the base level', () {
    final bound = BoundTexture(
      _checkerWithChain(device, 16).backend as CpuTexture,
      SamplerOptions.trilinearRepeat,
    );
    // One pixel covers a sixteenth of a texel: a magnifying view, where the
    // base is the only right answer.
    final sample = bound.sample(0.03125, 0.03125, du: 1 / 256, dv: 1 / 256);
    expect(sample.x, closeTo(1.0, 1e-6),
        reason: 'texel (0,0) of the checkerboard is white');
  });

  test('a coordinate racing across the texture reads a small level', () {
    final bound = BoundTexture(
      _checkerWithChain(device, 16).backend as CpuTexture,
      SamplerOptions.trilinearRepeat,
    );
    // One pixel covers the whole texture, which is past the end of the chain.
    // The last level is one texel, and a checkerboard averaged down to one
    // texel is a half.
    final sample = bound.sample(0.5, 0.5, du: 1.0, dv: 1.0);
    expect(sample.x, closeTo(0.5, 0.02),
        reason: 'the base level here would answer 0 or 1, not a half');
  });

  test('no derivative means the base level, which is what every old call does',
      () {
    final bound = BoundTexture(
      _checkerWithChain(device, 16).backend as CpuTexture,
      SamplerOptions.trilinearRepeat,
    );
    // Zero is the default, and it is what the twenty-odd scenes with no chain
    // pass without knowing this parameter exists.
    final without = bound.sample(0.03125, 0.03125);
    expect(without.x, closeTo(1.0, 1e-6));
  });

  test('a nearest mip filter picks one level rather than blending two', () {
    final chain = _checkerWithChain(device, 16).backend as CpuTexture;
    const nearest = SamplerOptions(
      minFilter: MinMagFilter.linear,
      magFilter: MinMagFilter.linear,
      widthAddressMode: SamplerAddressMode.repeat,
      heightAddressMode: SamplerAddressMode.repeat,
    );
    // Between the base and the first level, which is the only step where the
    // two say different things: this checkerboard averages to a half at every
    // level below the base, so any pair further down would agree whatever the
    // filter did — and a test that could not tell them apart would pass with
    // `mipFilter` ignored. The first version of this test did exactly that.
    //
    // A footprint of 1.5 texels is lod 0.585. At the centre of texel (0, 0) the
    // base says white and the level below says a half.
    const at = 0.03125;
    final blended = BoundTexture(chain, SamplerOptions.trilinearRepeat)
        .sample(at, at, du: 1.5 / 16, dv: 1.5 / 16);
    final picked =
        BoundTexture(chain, nearest).sample(at, at, du: 1.5 / 16, dv: 1.5 / 16);
    expect(picked.x, closeTo(1.0, 1e-6),
        reason: 'nearest must read the base level whole');
    expect(blended.x, closeTo(1.0 + (0.5 - 1.0) * 0.585, 0.02),
        reason: 'linear must land between the two levels');
  });

  test('a texture with no chain ignores the derivative entirely', () {
    final plain = device.createTextureFromPixels(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List(4 * 4 * 4)..fillRange(0, 64, 255)),
    )!;
    final bound = BoundTexture(
      plain.backend as CpuTexture,
      SamplerOptions.trilinearRepeat,
    );
    // A huge footprint on a texture with one level must not walk off the end
    // of a chain that is not there.
    expect(bound.sample(0.5, 0.5, du: 4.0, dv: 4.0).x, closeTo(1.0, 1e-6));
  });
}
