/// A far sprite marks the mask through its mip chain.
///
///     dart test test/reactive_sprite_mip_test.dart
///
/// `reactive_sprite.frag` reads the sprite's alpha with `texture()`, which
/// picks a level from the screen derivatives, so a sprite a few pixels across
/// is read from a small level of its chain. The mirror has to be handed the
/// same footprint, or it reads the base level and marks the mask sharper than
/// the GPU does.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

const int _size = 16;

/// A sprite whose alpha is a checkerboard, with the chain built from it: the
/// base answers zero or one, every small level about a half.
BoundTexture _checkerSprite(CpuDevice device) {
  final base = Uint8List(_size * _size * 4);
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      final at = (y * _size + x) * 4;
      base
        ..fillRange(at, at + 3, 255)
        ..[at + 3] = (x + y).isEven ? 255 : 0;
    }
  }
  final bytes = ByteData.sublistView(base);
  final handle = device.createTextureFromPixels(
    width: _size,
    height: _size,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: bytes,
    mipLevels: MipChain.build(bytes, _size, _size),
  )!;
  return BoundTexture(
    handle.backend as CpuTexture,
    SamplerOptions.trilinearRepeat,
  );
}

/// The blue the stage writes at texel (0,0) — white alpha on the base —
/// with one pixel spanning [footprint] of the sprite's coordinate.
double _mark(CpuDevice device, double? footprint) {
  final bindings = ShaderBindings(
    <String, Map<String, Float32List>>{
      'ReactiveInfo': <String, Float32List>{
        // Full strength, the sprite shape.
        'params': Float32List.fromList(<double>[1.0, 2.0, 0.0, 0.0]),
      },
    },
    <String, BoundTexture>{'sprite_texture': _checkerSprite(device)},
  );
  final varyings = Float32List(9)
    ..[3] = 1.0
    ..[4] = 0.5 / _size
    ..[5] = 0.5 / _size;
  final context = FragmentContext();
  if (footprint != null) {
    context
      ..ddx = (Float32List(9)..[4] = footprint)
      ..ddy = (Float32List(9)..[5] = footprint);
  }
  return const ReactiveSpriteShader().run(varyings, bindings, context)?.z ??
      0.0;
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

  test('a sprite smaller than its texels is read from a small level', () {
    // One pixel covers the whole sprite: the chain's last level, a half.
    // Mutation: drop the derivatives from the `sample` call and this reads
    // the base texel, a one.
    expect(_mark(device, 1.0), closeTo(0.5, 0.02));
  });

  test('a magnified sprite, or no derivative at all, reads the base', () {
    expect(_mark(device, 1.0 / 256.0), closeTo(1.0, 1e-6));
    expect(_mark(device, null), closeTo(1.0, 1e-6));
  });
}
