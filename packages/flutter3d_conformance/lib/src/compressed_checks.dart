/// A block-compressed texture the backend says it samples comes back as the
/// colour that was encoded into it.
///
/// **The check `supportsTextureFormat` needs beside it.** A backend is
/// entitled to answer no for every compressed family — the software
/// rasteriser does — and that is not what this catches. What it catches is a
/// yes that is not one: a format the capability table names, the allocation
/// accepts, and the sampler then reads as noise or black, which is what
/// a mapped-but-unverified enum value looks like on a real driver. The
/// Impeller side of the compressed formats had exactly that status until this
/// ran: every number checked against flutter_gpu's, and not one block ever
/// drawn.
///
/// One block per family, assembled by hand from the format's own bit layout
/// rather than taken from an encoder, so the expected colour is arithmetic:
/// BC1 stores two 565 endpoints and 2-bit picks between them, so equal
/// endpoints and zero picks are the endpoint colour; ETC2's individual mode
/// stores a 4-bit base per channel and a 2-bit modifier per pixel, and the
/// all-zero modifier under table 0 is +2; ASTC has a block that is nothing but
/// a colour — the void extent — which is why the family with the most
/// complicated encoder is the one whose block here is the simplest.
///
/// **All three families, because two of them was an arbitrary line.** ASTC has
/// a mapping on every backend and had never had a block drawn through it, which
/// is exactly the status this check exists to end: a format the capability
/// table names, the allocation accepts, and nothing has ever sampled.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

const int _r = 136;
const int _g = 68;
const int _b = 204;

/// One 4×4 BC1 block of a single colour: both endpoints the same 565 value,
/// every pick 0.
Uint8List _bc1Solid() {
  final c = ((_r >> 3) << 11) | ((_g >> 2) << 5) | (_b >> 3);
  return Uint8List.fromList(<int>[
    c & 0xFF,
    c >> 8,
    c & 0xFF,
    c >> 8,
    0,
    0,
    0,
    0,
  ]);
}

/// One 4×4 ETC2 RGB8 block in ETC1 individual mode: 4-bit base colours for
/// both halves, modifier table 0 for both, no differential bit, no flip, and
/// every pixel's 2-bit modifier index 0, which table 0 reads as +2.
Uint8List _etc2Solid() {
  int both(int v) => ((v >> 4) << 4) | (v >> 4);
  return Uint8List.fromList(<int>[both(_r), both(_g), both(_b), 0, 0, 0, 0, 0]);
}

/// One 4×4 ASTC LDR block as a *void extent*: the block layout whose whole
/// content is one colour and no weights at all.
///
/// Bits 0–8 are the void-extent marker `111111100`, bit 9 says LDR, bits 10 and
/// 11 are reserved and must be one, and bits 12–63 are the extent's four
/// texture coordinates — all ones, which is the encoding for "this block is a
/// constant colour and names no extent". The last eight bytes are RGBA as
/// UNORM16, and a UNORM16 whose two bytes are equal is exactly its own top
/// byte, so the colour that comes back is the colour that went in with no
/// rounding to allow for.
Uint8List _astc4x4Solid() {
  int wide(int v) => (v << 8) | v;
  return Uint8List.fromList(<int>[
    0xFC, 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, //
    for (final channel in <int>[_r, _g, _b, 255]) ...<int>[
      wide(channel) & 0xFF,
      wide(channel) >> 8,
    ],
  ]);
}

Future<void> checkCompressedTextureSamples(GraphicsDevice device) async {
  final candidates = <(TextureFormat, Uint8List)>[
    (TextureFormat.bc1RGBAUNormInt, _bc1Solid()),
    (TextureFormat.etc2RGB8UNormInt, _etc2Solid()),
    (TextureFormat.astc4x4LDR, _astc4x4Solid()),
  ];

  for (final (format, block) in candidates) {
    // Not a failure: the interface says to ask, and a backend that answers
    // false is entitled to. A backend with neither family — the software
    // rasteriser — runs nothing here, and that is the honest outcome.
    if (!device.supportsTextureFormat(format)) continue;

    final texture = device.createTextureFromPixels(
      width: 4,
      height: 4,
      format: format,
      pixels: ByteData.sublistView(block),
    );
    require(
      texture != null,
      '${format.name} is reported as sampled, but a one-block texture in it '
      'could not be created',
    );

    final centre = await _sampleCentre(device, texture!);
    for (final (channel, got, want) in <(String, int, int)>[
      ('red', centre[0], _r),
      ('green', centre[1], _g),
      ('blue', centre[2], _b),
    ]) {
      require(
        (got - want).abs() <= 8,
        '${format.name} sampled $channel as $got where $want was encoded — '
        'the format is reported as supported, the block was accepted, and the '
        'sampler read something else',
      );
    }
  }
}

/// Draws [texture] over an 8×8 target at u = v = 0.5 and reads the centre.
///
/// The same textured-particle pair the null-sampler check draws with, for
/// the same reason: it is the one stage pair in the bundle whose fragment
/// reads a texture and does nothing else to it.
Future<List<int>> _sampleCentre(
  GraphicsDevice device,
  TextureHandle texture,
) async {
  const size = 8;
  final vertex = device.shaders['ParticleVertex'];
  final fragment = device.shaders['ParticleTextured'];
  require(
    vertex != null && fragment != null,
    'the textured particle stages are missing, so nothing here samples',
  );

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final triangle = Float32List.fromList(<double>[
    -1, -1, 0.5, 1, 1, 1, 1, 0.5, 0.5, //
    3, -1, 0.5, 1, 1, 1, 1, 0.5, 0.5,
    -1, 3, 0.5, 1, 1, 1, 1, 0.5, 0.5,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4.zero(),
        ),
      ],
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(device.createPipeline(vertex!, fragment!))
    ..bindUniformBlock(vertex, 'ParticleInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindUniformBlock(fragment, 'FogInfo', <String, Float32List>{
      'fog': Float32List(4),
      'eye': Float32List(4),
    })
    ..bindTexture(fragment, 'particle_texture', texture)
    ..bindVertexData(ByteData.sublistView(triangle), 3)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
    ..draw();
  pass.submit();

  final read = await device.readPixels(target);
  require(read != null, 'the target could not be read back');
  final bytes = read!.buffer.asUint8List();
  final at = ((size ~/ 2) * size + size ~/ 2) * 4;
  return <int>[bytes[at], bytes[at + 1], bytes[at + 2]];
}
