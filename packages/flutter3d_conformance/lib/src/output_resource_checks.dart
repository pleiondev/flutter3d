/// The 1.0 features of buffers, textures and samplers, each held by the bytes
/// or pixels it hands back: buffers written, copied and mapped, textures
/// written and copied in every shape a readback can reach, the samplers'
/// clamps, the float and packed formats as targets, zero-copy sharing, an
/// indirect dispatch — and the promises every device makes whatever it
/// lists: its own dispose told on `lost`, a second dispose harmless, sRGB
/// decoded on the way in and encoded on the way out.
///
/// As in `output_draw_checks.dart`, a check declines on a device without its
/// feature (the refusal is the honesty check's half) and otherwise compares
/// what came back against arithmetic the software rasteriser agrees with.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart' show SynchronousBufferReadback;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// Sixteen bytes no two of which are alike.
ByteData _sixteen() => ByteData.sublistView(
  Uint8List.fromList(<int>[for (var i = 0; i < 16; i++) i * 13 + 7]),
);

void _needs(GraphicsDevice device, List<DeviceFeature> features, String why) {
  final missing = features.where((DeviceFeature f) => !device.features.has(f));
  if (missing.isNotEmpty) {
    decline(
      device,
      'has no ${missing.map((f) => f.name).join(' or ')}, so $why',
    );
  }
}

/// Holds [got] to [want] byte for byte, from [from] in [got].
void _same(ByteData got, ByteData want, String what, {int from = 0}) {
  require(
    got.lengthInBytes >= from + want.lengthInBytes,
    '$what came back ${got.lengthInBytes} bytes long, too short for '
    '${want.lengthInBytes} from byte $from',
  );
  for (var i = 0; i < want.lengthInBytes; i++) {
    require(
      got.getUint8(from + i) == want.getUint8(i),
      '$what: byte ${from + i} is ${got.getUint8(from + i)} where '
      '${want.getUint8(i)} belongs',
    );
  }
}

// --------------------------------------------------------------- buffers

/// A buffer made with contents reads them back, and a write at an offset
/// lands exactly there.
Future<void> checkBufferWritesLand(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[DeviceFeature.buffers], 'no buffer is made');
  final buffer = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: 16,
      usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
    ),
    contents: _sixteen(),
  );
  _same(await device.readBuffer(buffer), _sixteen(), 'a created buffer');
  device.writeBuffer(
    buffer,
    4,
    ByteData.sublistView(Uint8List.fromList(<int>[1, 2, 3, 4])),
  );
  final written = await device.readBuffer(buffer);
  _same(
    written,
    ByteData.sublistView(Uint8List.fromList(<int>[1, 2, 3, 4])),
    'a write at offset 4',
    from: 4,
  );
  _same(
    ByteData.sublistView(written, 8, 16),
    ByteData.sublistView(_sixteen(), 8, 16),
    'the bytes after a write at offset 4',
  );
  device.releaseStorageBuffer(buffer);
}

/// `clearBuffer` zeroes, and `copyBufferToBuffer` moves the bytes it names
/// to where it names.
Future<void> checkBufferCopyLands(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.buffers,
    DeviceFeature.bufferCopy,
  ], 'no buffer is copied');
  final source = device.createBuffer(
    const BufferDescriptor(lengthInBytes: 16, usage: BufferUsage.copySource),
    contents: _sixteen(),
  );
  final destination = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: 16,
      usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
    ),
    contents: _sixteen(),
  );
  device.beginTransferPass()
    ..clearBuffer(destination)
    ..copyBufferToBuffer(source, 4, destination, 8, 8)
    ..submit();
  final got = await device.readBuffer(destination);
  _same(got, ByteData(8), 'the cleared half of a buffer');
  _same(
    ByteData.sublistView(got, 8, 16),
    ByteData.sublistView(_sixteen(), 4, 12),
    'eight bytes copied from offset 4 to offset 8',
  );
}

/// Bytes copied into a texture read back as its pixels, and the pixels
/// copied out of it land in a buffer as the same bytes.
Future<void> checkBufferTextureCopyRoundTrips(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.buffers,
    DeviceFeature.bufferTextureCopy,
  ], 'no texture is copied to or from a buffer');
  final texture = device.createTexture(
    const RenderTargetDescriptor(
      width: 4,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final rows = ByteData(256)
    ..buffer.asUint8List().setAll(0, Uint8List.sublistView(_sixteen()));
  final source = device.createBuffer(
    const BufferDescriptor(lengthInBytes: 256, usage: BufferUsage.copySource),
    contents: rows,
  );
  final out = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: 256,
      usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
    ),
  );
  device.beginTransferPass()
    ..copyBufferToTexture(
      source,
      const BufferTextureLayout(bytesPerRow: 256),
      TextureCopyLocation(texture),
      width: 4,
      height: 1,
    )
    ..submit();
  _same(await device.readback(texture), _sixteen(), 'a buffer-to-texture copy');
  device.beginTransferPass()
    ..copyTextureToBuffer(
      TextureCopyLocation(texture),
      out,
      const BufferTextureLayout(bytesPerRow: 256),
      width: 4,
      height: 1,
    )
    ..submit();
  _same(await device.readBuffer(out), _sixteen(), 'a texture-to-buffer copy');
}

/// A mapped buffer hands back its bytes, and bytes written through a map
/// are what a copy then carries.
Future<void> checkMappedBuffersCarryBytes(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.buffers,
    DeviceFeature.mappedBuffers,
  ], 'no buffer is mapped');
  final readable = device.createBuffer(
    const BufferDescriptor(lengthInBytes: 16, usage: BufferUsage.hostReadable),
    contents: _sixteen(),
  );
  final read = await device.mapBuffer(readable, MapMode.read);
  _same(read.bytes, _sixteen(), 'a buffer mapped for reading');
  read.unmap();
  // WebGPU maps a buffer for writing only beside `copySource`, so what was
  // written comes back through a copy, where the device copies.
  if (device.features.has(DeviceFeature.bufferCopy)) {
    await _mappedWriteLands(device);
  }
}

/// Bytes written through a map, copied into a readable buffer, read back.
Future<void> _mappedWriteLands(GraphicsDevice device) async {
  final writable = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: 16,
      usage: BufferUsage.hostWritable | BufferUsage.copySource,
    ),
  );
  final written = await device.mapBuffer(writable, MapMode.write);
  written.bytes.buffer
      .asUint8List(written.bytes.offsetInBytes, 16)
      .setAll(0, Uint8List.sublistView(_sixteen()));
  written.unmap();
  final landed = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: 16,
      usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
    ),
  );
  device.beginTransferPass()
    ..copyBufferToBuffer(writable, 0, landed, 0, 16)
    ..submit();
  _same(await device.readBuffer(landed), _sixteen(), 'bytes written by a map');
}

/// `readBufferSync` hands back the bytes a write left, at once.
Future<void> checkSynchronousReadbackReads(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.buffers,
    DeviceFeature.synchronousReadback,
  ], 'no buffer is read synchronously');
  require(
    device is SynchronousBufferReadback,
    'lists synchronous-readback and does not mix in SynchronousBufferReadback',
  );
  final buffer = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: 16,
      usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
    ),
    contents: ByteData(16),
  );
  device.writeBuffer(buffer, 0, _sixteen());
  _same(
    (device as SynchronousBufferReadback).readBufferSync(buffer),
    _sixteen(),
    'a synchronous readback after a write',
  );
}

/// An indirect dispatch of one workgroup scans the buffer as a direct one
/// would: 1024 ones become 1, 2, … 1024.
Future<void> checkIndirectDispatchRuns(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.compute,
    DeviceFeature.buffers,
    DeviceFeature.indirectDispatch,
  ], 'no dispatch reads its size from a buffer');
  final stage = device.shaders['PrefixSum'];
  require(stage != null, 'the PrefixSum compute stage is missing');
  final values = ByteData(1024 * 4);
  for (var i = 0; i < 1024; i++) {
    values.setUint32(i * 4, 1, Endian.little);
  }
  final buffer = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: values.lengthInBytes,
      usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
    ),
    contents: values,
  );
  final arguments = device.createBuffer(
    const BufferDescriptor(lengthInBytes: 12, usage: BufferUsage.indirect),
    contents: dispatchIndirectArguments(1),
  );
  device.beginComputePass()
    ..bindPipeline(
      device.createComputePipelineFrom(
        ComputePipelineDescriptor(shader: stage!),
      ),
    )
    ..bindStorageBuffer(stage, 'Values', buffer)
    ..dispatchIndirect(arguments)
    ..submit();
  final out = await device.readBuffer(buffer);
  for (final i in <int>[0, 511, 1023]) {
    require(
      out.getUint32(i * 4, Endian.little) == i + 1,
      'an indirect dispatch of one workgroup left ${out.getUint32(i * 4, Endian.little)} '
      'at element $i of a prefix sum over ones, not ${i + 1}',
    );
  }
}

// -------------------------------------------------------------- textures

/// Four by four texels, each a different colour.
Uint8List _texels(int width, int height, int seed) => Uint8List.fromList(<int>[
  for (var i = 0; i < width * height; i++) ...<int>[
    (i * 17 + seed) & 0xFF,
    (i * 29 + seed * 3) & 0xFF,
    (i * 41 + seed * 7) & 0xFF,
    255,
  ],
]);

/// A texture written whole and then in a region reads back with the region
/// in place and the rest as first written.
Future<void> checkTextureWritesLand(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.textureWrites,
  ], 'no texture is written after it is made');
  final texture = device.createTexture(
    const TextureDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final first = _texels(4, 4, 1);
  final patch = _texels(2, 2, 90);
  device
    ..writeTexture(texture, ByteData.sublistView(first))
    ..writeTexture(
      texture,
      ByteData.sublistView(patch),
      region: const TextureRegion(x: 1, y: 1, width: 2, height: 2),
      bytesPerRow: 8,
    );
  final got = (await device.readback(texture)).buffer.asUint8List();
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      final inside = x >= 1 && x < 3 && y >= 1 && y < 3;
      final want = inside
          ? patch.sublist(((y - 1) * 2 + (x - 1)) * 4, ((y - 1) * 2 + x) * 4)
          : first.sublist((y * 4 + x) * 4, (y * 4 + x + 1) * 4);
      final at = (y * 4 + x) * 4;
      require(
        <int>[0, 1, 2, 3].every((int c) => got[at + c] == want[c]),
        'texel ($x, $y) after a whole write and a 2x2 write at (1, 1) is '
        '${got.sublist(at, at + 4)}, not $want',
      );
    }
  }
}

/// Layer [layer] of [texture], copied into a 2D texture and read back.
Future<Uint8List> _layer(
  GraphicsDevice device,
  TextureHandle texture,
  int layer,
) async {
  final flat = device.createTexture(
    const RenderTargetDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  device.beginTransferPass()
    ..copyTextureToTexture(
      TextureCopyLocation(texture, z: layer),
      TextureCopyLocation(flat),
      width: 4,
      height: 4,
    )
    ..submit();
  return (await device.readback(flat)).buffer.asUint8List();
}

/// A cube array keeps what is written to a face of its second cube, and its
/// other faces apart.
Future<void> checkCubeArrayKeepsItsFaces(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.cubeArrayTextures,
    DeviceFeature.textureWrites,
    DeviceFeature.textureCopy,
  ], 'no face of a cube array reaches a readback');
  final cubes = device.createTexture(
    const TextureDescriptor(
      width: 4,
      height: 4,
      depthOrArrayLayers: 12,
      format: TextureFormat.r8g8b8a8UNormInt,
      dimension: TextureDimension.cubeArray,
    ),
  );
  final face = _texels(4, 4, 33);
  device.writeTexture(
    cubes,
    ByteData.sublistView(face),
    region: const TextureRegion(z: 7, width: 4, height: 4),
  );
  final got = await _layer(device, cubes, 7);
  require(
    <int>[
      for (var i = 0; i < face.length; i++) i,
    ].every((int i) => got[i] == face[i]),
    'face 1 of the second cube came back ${got.sublist(0, 8)}… after '
    '${face.sublist(0, 8)}… was written to layer 7',
  );
  final other = await _layer(device, cubes, 6);
  require(
    !<int>[
      for (var i = 0; i < face.length; i++) i,
    ].every((int i) => other[i] == face[i]),
    'layer 6 of a cube array holds what was written to layer 7',
  );
}

/// A 3D texture keeps each slice written to it, as a copy of one slice out
/// shows, and its slices apart.
Future<void> checkTexture3DKeepsItsSlices(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.texture3D,
    DeviceFeature.textureWrites,
    DeviceFeature.textureCopy,
  ], 'no slice of a 3D texture reaches a readback');
  final volume = device.createTexture(
    const TextureDescriptor(
      width: 4,
      height: 4,
      depthOrArrayLayers: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
      dimension: TextureDimension.d3,
    ),
  );
  final slices = <Uint8List>[for (var z = 0; z < 4; z++) _texels(4, 4, z * 50)];
  device.writeTexture(
    volume,
    ByteData.sublistView(
      Uint8List.fromList(<int>[for (final slice in slices) ...slice]),
    ),
    region: const TextureRegion(width: 4, height: 4, depthOrArrayLayers: 4),
  );
  for (final z in <int>[1, 2]) {
    final got = await _layer(device, volume, z);
    require(
      <int>[
        for (var i = 0; i < 64; i++) i,
      ].every((int i) => got[i] == slices[z][i]),
      'slice $z of a 3D texture came back ${got.sublist(0, 8)}… where '
      '${slices[z].sublist(0, 8)}… was written',
    );
  }
}

/// A 1D texture keeps the texels written to it, as a copy out shows.
Future<void> checkTexture1DKeepsItsTexels(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.texture1D,
    DeviceFeature.textureWrites,
    DeviceFeature.buffers,
    DeviceFeature.bufferTextureCopy,
  ], 'no 1D texture reaches a readback');
  final line = device.createTexture(
    TextureDescriptor(
      width: 4,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      dimension: TextureDimension.d1,
      usage:
          TextureUsage.sampled |
          TextureUsage.copyDestination |
          TextureUsage.copySource,
    ),
  );
  device.writeTexture(line, _sixteen());
  final out = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: 256,
      usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
    ),
  );
  device.beginTransferPass()
    ..copyTextureToBuffer(
      TextureCopyLocation(line),
      out,
      const BufferTextureLayout(bytesPerRow: 256),
      width: 4,
      height: 1,
    )
    ..submit();
  _same(await device.readBuffer(out), _sixteen(), 'a 1D texture copied out');
}

// -------------------------------------------------------------- samplers

/// [texture] sampled at ([u], [v]) over an 8x8 target, the centre's RGBA.
///
/// The textured-particle pair, as the null-sampler check draws it: the one
/// stage pair in the bundle whose fragment reads a texture and does nothing
/// else to it. A constant coordinate has no derivative, so the level is the
/// base level unless a clamp says otherwise.
Future<List<int>> _sampled(
  GraphicsDevice device,
  TextureHandle texture, {
  required double u,
  required double v,
  SamplerDescriptor? sampler,
}) async {
  final vertex = device.shaders['ParticleVertex'];
  final fragment = device.shaders['ParticleTextured'];
  if (vertex == null || fragment == null) {
    decline(
      device,
      'has no textured particle stages yet, so nothing here samples',
    );
  }
  final target = device.createTexture(
    const RenderTargetDescriptor(
      width: 8,
      height: 8,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final triangle = Float32List.fromList(<double>[
    -1, -1, 0.5, 1, 1, 1, 1, u, v, //
    3, -1, 0.5, 1, 1, 1, 1, u, v,
    -1, 3, 0.5, 1, 1, 1, 1, u, v,
  ]);
  device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: target, clearValue: ClearColor.transparentBlack),
        ],
      ),
    )
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(
      device.createPipelineFrom(
        PipelineDescriptor(vertex: vertex, fragment: fragment),
      ),
    )
    ..bindUniformBlock(vertex, 'ParticleInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindUniformBlock(fragment, 'FogInfo', <String, Float32List>{
      'fog': Float32List(4),
      'eye': Float32List(4),
    })
    ..bindTexture(fragment, 'particle_texture', texture, sampler: sampler)
    ..bindVertexData(ByteData.sublistView(triangle), 3)
    ..bindIndexData(
      ByteData.sublistView(Uint16List.fromList(<int>[0, 1, 2])),
      IndexType.int16,
      3,
    )
    ..draw()
    ..submit();
  final bytes = (await device.readback(target)).buffer.asUint8List();
  const at = (4 * 8 + 4) * 4;
  return bytes.sublist(at, at + 4);
}

ByteData _solid(int texels, int value) => ByteData.sublistView(
  Uint8List.fromList(<int>[
    for (var i = 0; i < texels; i++) ...<int>[value, value, value, 255],
  ]),
);

/// A minimum level clamp of one samples the first smaller level even where
/// the base level would be read: white at level 0, black at level 1.
Future<void> checkSamplerLodClampPicksTheLevel(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.samplerLodClamp,
    DeviceFeature.manualMipmaps,
  ], 'no level is clamped');
  final chain = device.createTextureFromPixels(
    width: 2,
    height: 2,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: _solid(4, 255),
    mipLevels: <ByteData>[_solid(1, 0)],
  );
  final base = await _sampled(
    device,
    chain,
    u: 0.5,
    v: 0.5,
    sampler: const SamplerDescriptor(),
  );
  require(
    base[0] > 240,
    'a two-level texture sampled with no clamp came back $base, not the '
    'white of its base level',
  );
  final clamped = await _sampled(
    device,
    chain,
    u: 0.5,
    v: 0.5,
    sampler: const SamplerDescriptor(lodMinClamp: 1),
  );
  require(
    clamped[0] < 16,
    'a two-level texture sampled with lodMinClamp: 1 came back $clamped, '
    'not the black of level 1: the clamp was ignored',
  );
}

/// A coordinate past the edge with a border address mode reads the border
/// colour; with the default clamp it reads the edge texel.
Future<void> checkSamplerBorderColorIsRead(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.samplerBorderColor,
  ], 'no border colour is read');
  final black = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: _solid(1, 0),
  );
  final border = await _sampled(
    device,
    black,
    u: 1.5,
    v: 1.5,
    sampler: const SamplerDescriptor(
      widthAddressMode: SamplerAddressMode.clampToBorder,
      heightAddressMode: SamplerAddressMode.clampToBorder,
      borderColor: SamplerBorderColor.opaqueWhite,
    ),
  );
  require(
    border[0] > 240 && border[1] > 240 && border[2] > 240,
    'a black texture sampled past its edge with an opaque white border came '
    'back $border: the border colour was not read',
  );
  final edge = await _sampled(
    device,
    black,
    u: 1.5,
    v: 1.5,
    sampler: const SamplerDescriptor(),
  );
  require(
    edge[0] < 16,
    'a black texture sampled past its edge with clampToEdge came back $edge',
  );
}

// --------------------------------------------------------------- formats

/// A full-target triangle in [colour] drawn into [target], with [blend].
void _fill(
  GraphicsDevice device,
  TextureHandle target,
  List<double> colour, {
  ClearColor clear = ClearColor.transparentBlack,
  BlendState? blend,
}) {
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  if (vertex == null || fragment == null) {
    decline(device, 'has no debug-line stages yet, so nothing here can draw');
  }
  final pass =
      device.beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(texture: target, clearValue: clear),
            ],
          ),
        )
        ..setPrimitiveType(PrimitiveType.triangle)
        ..setCullMode(CullMode.none)
        ..bindPipeline(
          device.createPipelineFrom(
            PipelineDescriptor(vertex: vertex, fragment: fragment),
          ),
        );
  if (blend != null) pass.setBlend(blend);
  pass
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(
      ByteData.sublistView(
        Float32List.fromList(<double>[
          -1, -1, 0.5, ...colour, //
          3, -1, 0.5, ...colour,
          -1, 3, 0.5, ...colour,
        ]),
      ),
      3,
    )
    ..bindIndexData(
      ByteData.sublistView(Uint16List.fromList(<int>[0, 1, 2])),
      IndexType.int16,
      3,
    )
    ..draw()
    ..submit();
}

Future<List<int>> _centre(GraphicsDevice device, TextureHandle target) async {
  final bytes = (await device.readback(target)).buffer.asUint8List();
  final at = ((target.height ~/ 2) * target.width + target.width ~/ 2) * 4;
  return bytes.sublist(at, at + 4);
}

/// A 32-bit float target blends: 0.5 added over a clear of 0.25 is 0.75.
Future<void> checkFloat32TargetBlends(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.float32Renderable,
    DeviceFeature.float32Blendable,
  ], 'no 32-bit float target is blended');
  final target = device.createTexture(
    const RenderTargetDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.r32Float,
    ),
  );
  _fill(
    device,
    target,
    const <double>[0.5, 0, 0, 1],
    clear: const ClearColor(0.25, 0, 0, 1),
    blend: BlendState.additive,
  );
  final centre = await _centre(device, target);
  require(
    (centre[0] - 191).abs() <= 4,
    '0.5 added over an r32Float target cleared to 0.25 read back as '
    '${centre[0] / 255}, not 0.75: the blend did not run, or replaced',
  );
}

/// The packed float format takes a draw: (0.5, 0.25, 0.75) comes back.
Future<void> checkPackedFloatTargetRenders(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.rg11b10Renderable,
  ], 'nothing is drawn into r11g11b10UFloat');
  final target = device.createTexture(
    const RenderTargetDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.r11g11b10UFloat,
    ),
  );
  _fill(device, target, const <double>[0.5, 0.25, 0.75, 1]);
  final centre = await _centre(device, target);
  require(
    (centre[0] - 128).abs() <= 4 &&
        (centre[1] - 64).abs() <= 4 &&
        (centre[2] - 191).abs() <= 4,
    '(0.5, 0.25, 0.75) drawn into r11g11b10UFloat read back as $centre',
  );
}

// --------------------------------------------------------------- sharing

/// A texture shared with zero copy carries the producer's pixels, here with
/// the device on both ends.
Future<void> checkZeroCopyTextureCarries(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.sharedTextures,
    DeviceFeature.sharedFences,
  ], 'no texture is shared without a copy');
  final shared = SharedTexture.create(
    producer: device,
    consumer: device,
    descriptor: const TextureDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
    demand: SharingMode.zeroCopy,
  );
  try {
    final texels = _texels(4, 4, 5);
    await device.overwriteTexture(
      shared.producerTexture,
      ByteData.sublistView(texels),
    );
    await shared.publish();
    final got = (await device.readback(
      shared.consumerTexture,
    )).buffer.asUint8List();
    require(
      <int>[
        for (var i = 0; i < texels.length; i++) i,
      ].every((int i) => got[i] == texels[i]),
      'a zero-copy share handed the consumer ${got.sublist(0, 8)}… where '
      'the producer wrote ${texels.sublist(0, 8)}…',
    );
  } finally {
    shared.dispose();
  }
}

/// A buffer shared with zero copy carries the producer's bytes.
Future<void> checkZeroCopyBufferCarries(GraphicsDevice device) async {
  _needs(device, <DeviceFeature>[
    DeviceFeature.buffers,
    DeviceFeature.sharedBuffers,
    DeviceFeature.sharedFences,
  ], 'no buffer is shared without a copy');
  final shared = SharedBuffer.create(
    producer: device,
    consumer: device,
    descriptor: BufferDescriptor(
      lengthInBytes: 16,
      usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
    ),
    demand: SharingMode.zeroCopy,
  );
  try {
    device.writeBuffer(shared.producerBuffer, 0, _sixteen());
    await shared.publish();
    _same(
      await device.readBuffer(shared.consumerBuffer),
      _sixteen(),
      'a zero-copy buffer share',
    );
  } finally {
    shared.dispose();
  }
}

// -------------------------------------------------------------- lifetime

/// The device's own dispose is told on `lost`, as
/// `DeviceLossReason.destroyed`, and `isLost` answers true after it.
///
/// **Every backend owes it**, whatever it lists: a caller listens once on
/// whatever it opened. The null example the backend template copies did
/// not, so every backend started from it began in breach.
Future<void> checkDisposeIsToldOnLost(GraphicsDevice device) async {
  final told = device.lost.first.timeout(
    const Duration(seconds: 5),
    onTimeout: () => throw const ConformanceFailureException(
      'dispose was not told on lost within five seconds: every backend '
      'reports its own dispose as DeviceLossReason.destroyed',
    ),
  );
  device.dispose();
  final loss = await told;
  require(
    loss.reason == DeviceLossReason.destroyed,
    'dispose was told on lost as ${loss.reason.name}, not destroyed',
  );
  require(device.isLost, 'isLost answers false after dispose');
}

/// A second dispose throws nothing and tells no second loss: a renderer and
/// its owner can both let go of a device.
Future<void> checkSecondDisposeDoesNothing(GraphicsDevice device) async {
  var losses = 0;
  final listening = device.lost.listen((DeviceLoss _) => losses++);
  try {
    device
      ..dispose()
      ..dispose();
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(
      ConformanceFailureException(
        'a second dispose threw $error: letting go twice is harmless',
      ),
      stackTrace,
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await listening.cancel();
  require(
    losses <= 1,
    'two disposes told $losses losses on lost; the second is no loss',
  );
}

/// sRGB is decoded when sampled and encoded when drawn.
///
/// 188 in an sRGB texture is 0.50 linear, so sampled into a linear target it
/// is 128; 0.5 linear drawn into an sRGB target is stored as 188, which a
/// copy into the plain layout shows byte for byte. A backend that stored or
/// sampled the bytes as they are draws everything a shade too light or too
/// dark, and no error says so.
Future<void> checkSrgbIsDecodedAndEncoded(GraphicsDevice device) async {
  const srgb = TextureFormat.r8g8b8a8UNormIntSRGB;
  final support = device.textureFormatSupport(srgb);
  if (!support.sampled) {
    decline(device, 'does not sample ${srgb.name}');
  }
  final stored = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: srgb,
    pixels: _solid(1, 188),
  );
  final decoded = await _sampled(device, stored, u: 0.5, v: 0.5);
  require(
    (decoded[0] - 128).abs() <= 4,
    'an sRGB texel of 188 sampled into a linear target came back '
    '${decoded[0]}, not 128: the sampler did not decode it',
  );
  if (support.renderable) await _srgbDrawEncodes(device);
}

/// 0.5 drawn into an sRGB target samples back as 0.5 and, copied into the
/// plain layout where the device copies, is the byte 188.
Future<void> _srgbDrawEncodes(GraphicsDevice device) async {
  const srgb = TextureFormat.r8g8b8a8UNormIntSRGB;
  final drawn = device.createTexture(
    const RenderTargetDescriptor(width: 4, height: 4, format: srgb),
  );
  _fill(device, drawn, const <double>[0.5, 0.5, 0.5, 1]);
  final roundTrip = await _sampled(device, drawn, u: 0.5, v: 0.5);
  require(
    (roundTrip[0] - 128).abs() <= 4,
    '0.5 drawn into an sRGB target and sampled back came back '
    '${roundTrip[0]}, not 128',
  );
  if (device.features.has(DeviceFeature.textureCopy)) {
    await _srgbBytesAre188(device, drawn);
  }
}

/// [drawn], copied into the plain layout and read back, holds 188.
Future<void> _srgbBytesAre188(
  GraphicsDevice device,
  TextureHandle drawn,
) async {
  final plain = device.createTexture(
    const RenderTargetDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  device.beginTransferPass()
    ..copyTextureToTexture(
      TextureCopyLocation(drawn),
      TextureCopyLocation(plain),
      width: 4,
      height: 4,
    )
    ..submit();
  final bytes = await _centre(device, plain);
  require(
    (bytes[0] - 188).abs() <= 2,
    '0.5 drawn into an sRGB target is stored as ${bytes[0]}, not 188: the '
    'draw did not encode it',
  );
}

/// The checks above that need no stage: buffers, copies, writes, sharing
/// and the device's lifetime — the shader-free tier.
List<ConformanceCheck> get resourceOutputChecks => <ConformanceCheck>[
  ConformanceCheck(
    name: 'a buffer reads back what it was made with and written',
    run: checkBufferWritesLand,
  ),
  ConformanceCheck(
    name: 'a buffer copy moves the bytes it names',
    run: checkBufferCopyLands,
  ),
  ConformanceCheck(
    name: 'a copy between a buffer and a texture keeps the bytes',
    run: checkBufferTextureCopyRoundTrips,
  ),
  ConformanceCheck(
    name: 'a mapped buffer carries its bytes both ways',
    run: checkMappedBuffersCarryBytes,
  ),
  ConformanceCheck(
    name: 'a synchronous readback reads what was written',
    run: checkSynchronousReadbackReads,
  ),
  ConformanceCheck(
    name: 'an indirect dispatch runs the workgroups it names',
    run: checkIndirectDispatchRuns,
  ),
  ConformanceCheck(
    name: 'a texture write lands where it was aimed',
    run: checkTextureWritesLand,
  ),
  ConformanceCheck(
    name: 'a cube array keeps its faces apart',
    run: checkCubeArrayKeepsItsFaces,
  ),
  ConformanceCheck(
    name: 'a 3D texture keeps its slices apart',
    run: checkTexture3DKeepsItsSlices,
  ),
  ConformanceCheck(
    name: 'a 1D texture keeps its texels',
    run: checkTexture1DKeepsItsTexels,
  ),
  ConformanceCheck(
    name: 'a zero-copy texture share carries the pixels',
    run: checkZeroCopyTextureCarries,
  ),
  ConformanceCheck(
    name: 'a zero-copy buffer share carries the bytes',
    run: checkZeroCopyBufferCarries,
  ),
  ConformanceCheck(
    name: 'a dispose is told on lost as destroyed',
    run: checkDisposeIsToldOnLost,
  ),
  ConformanceCheck(
    name: 'a second dispose does nothing',
    run: checkSecondDisposeDoesNothing,
  ),
];

/// The checks above that sample or draw: the samplers' clamps, the float
/// and packed targets, and sRGB — the shader tier.
List<ConformanceCheck> get sampledOutputChecks => <ConformanceCheck>[
  ConformanceCheck(
    name: 'a minimum level clamp picks the level',
    run: checkSamplerLodClampPicksTheLevel,
  ),
  ConformanceCheck(
    name: 'a border address mode reads the border colour',
    run: checkSamplerBorderColorIsRead,
  ),
  ConformanceCheck(
    name: 'a 32-bit float target blends',
    run: checkFloat32TargetBlends,
  ),
  ConformanceCheck(
    name: 'the packed float format takes a draw',
    run: checkPackedFloatTargetRenders,
  ),
  ConformanceCheck(
    name: 'an sRGB texture is decoded when sampled and encoded when drawn',
    run: checkSrgbIsDecodedAndEncoded,
  ),
];
