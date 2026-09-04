/// Lines on the software rasteriser, and the triangle arithmetic that got in.
///
///     flutter test test/line_draw_test.dart
///
/// `PrimitiveType.line` draws this engine's debug geometry — bounds, axes,
/// light gizmos — and it has its own path here because a line has no
/// barycentric coordinates. The path was written by copying the triangle's and
/// cutting it down, and one block survived the cut: the screen-space gradient
/// solve, which reads a third window position. There is no third endpoint. It
/// ran only behind `_hasMippedTexture()`, which asks whether *any* bound
/// texture carries a chain rather than whether this draw samples one, so the
/// crash waited for a caller that bound a mipped texture and then drew a line.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 16;

/// Two endpoints across the middle of the frame, in clip space.
final Float32List _line = Float32List.fromList(<double>[
  -0.9, 0, 0.5, //
  0.9, 0, 0.5,
]);

/// One colour per endpoint, both white, so a drawn line is unmistakable.
final Float32List _colours = Float32List.fromList(<double>[
  1, 1, 1, 1, //
  1, 1, 1, 1,
]);

const VertexLayoutSpec _layout = VertexLayoutSpec(<BufferLayout>[
  BufferLayout(
    strideInBytes: 12,
    attributes: <InputAttribute>[
      InputAttribute(name: 'position', format: VertexFormat.float32x3),
    ],
  ),
  BufferLayout(
    strideInBytes: 16,
    attributes: <InputAttribute>[
      InputAttribute(name: 'color', format: VertexFormat.float32x4),
    ],
  ),
]);

/// A 4x4 texture with a chain, which is all the rasteriser looks at.
TextureHandle _mipped(CpuDevice device) {
  final base = Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 255);
  final bytes = ByteData.sublistView(base);
  return device.createTextureFromPixels(
    width: 4,
    height: 4,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: bytes,
    mipLevels: MipChain.build(bytes, 4, 4),
  )!;
}

/// Draws the line, optionally with a mipped texture bound, and reports the
/// pixels.
Float32List _draw({required bool withChain}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final colour = device.createTexture(
    const RenderTargetSpec(
      width: _size,
      height: _size,
      format: TextureFormat.r16g16b16a16Float,
    ),
  );

  final vertex = device.shaders['DebugLineVertex']!;
  final fragment = device.shaders['DebugLine']!;
  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: colour,
          loadAction: LoadAction.clear,
          clearValue: Vector4.zero(),
        ),
      ],
    ),
  );
  pass
    ..bindPipeline(device.createPipeline(vertex, fragment, layout: _layout))
    ..setPrimitiveType(PrimitiveType.line)
    ..setCullMode(CullMode.none)
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    });
  if (withChain) {
    // Any slot: the rasteriser asks the bound set whether *anything* has
    // levels, not whether this stage samples it. That is the whole of the
    // trigger, and it is why no scene ever hit it.
    pass.bindTexture(fragment, 'base_color_texture', _mipped(device));
  }
  pass
    ..bindVertexData(ByteData.sublistView(_line), 2)
    ..bindVertexData(ByteData.sublistView(_colours), 2, slot: 1)
    ..draw()
    ..submit();

  return (colour.backend as CpuTexture).pixels;
}

void main() {
  test('a line draws while a mipped texture is bound', () {
    // Mutation: put the triangle path's gradient solve back at the top of
    // `_rasteriseLine` — this throws `RangeError (length): Invalid value: Not
    // in inclusive range 0..1: 2` out of the rasteriser, which is the failure
    // that was waiting there.
    final lit = _draw(withChain: true);
    final at = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
    expect(lit[at], closeTo(1.0, 1e-6), reason: 'the line is white');
  });

  test('and draws the same line as when nothing carries a chain', () {
    // A line has no area, so no chain can change what it samples: the two
    // frames are the same picture. Mutation: give the line path a gradient of
    // its own from the run direction — the pixels stay equal here, which is
    // the point, but the first test stops proving anything, so this one is
    // what says the fix was to delete rather than to compute.
    expect(_draw(withChain: true), equals(_draw(withChain: false)));
  });
}
