/// Whether a device's capability report is true — in both directions.
///
/// **The check the 1.0 contract rests on.** `GraphicsDevice.features` is one
/// set of answers a caller branches on, and the contract makes two promises
/// about each: a feature the device lists works, and a feature it does not
/// list refuses every call it gates with `UnsupportedCapability` — before
/// anything reaches a driver, and naming itself. A backend that listed a
/// feature it could not deliver would send callers down a path that fails
/// somewhere else; one that left a feature out and quietly did something
/// anyway would be a device whose report nobody could trust. This walks
/// every `DeviceFeature` and asks each its question.
///
/// **Minimal on purpose.** A probe proves the call works at all — a buffer
/// written comes back, a copy lands, a query set resolves to the right
/// length, a pass state is accepted — and leaves pixel-level behaviour to
/// the dedicated checks beside it. Three kinds of feature have no probe here
/// and are named in [unprobedFeatures] with the reason: the shader-language
/// ones (refused by `loadShaders`, which needs a bundle compiled with them),
/// the draw-shaped ones whose positive half needs a pipeline built for the
/// purpose (their refusal half *is* probed), and the pre-1.0 ones whose
/// "no" was never a refusal (alpha-to-coverage is ignored, a cube target is
/// null) and which have checks of their own.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import '../flutter3d_conformance.dart';

/// One feature's probe: what else it needs, and the call that exercises it.
typedef _Probe = ({
  List<DeviceFeature> needs,

  /// True when only the refusal half is probed: the call is made on a
  /// device without the feature, and skipped on one with it.
  bool refusalOnly,
  Future<void> Function(GraphicsDevice device) run,
});

/// Features this check cannot ask about, and why.
const Map<String, String> unprobedFeatures = <String, String>{
  'shader-f16': 'a shader-language feature: refused by loadShaders',
  'subgroups': 'a shader-language feature: refused by loadShaders',
  'clip-distances': 'a shader-language feature: refused by loadShaders',
  'indirect-first-instance':
      'no call of its own; a draw with a first instance reads it',
  'read-write-storage-textures':
      'bound only through a compute stage that declares one',
  'offscreen-multisample': 'held by "a multisample resolve resolves"',
  'manual-mipmaps': 'held by "a cube takes the mip chain it is handed"',
  'cube-textures':
      'held by "a cube map answers the face a direction points '
      'at"; a device without it answers null, not a refusal',
  'alpha-to-coverage': 'a device without it ignores the call, by contract',
  'stencil': 'held by "a stencil test keeps what it should"',
  'gpu-timestamps': 'reported through onGpuTimings, never refused',
  'independent-blend': 'a device without it sets attachment zero, by contract',
  'reversed-depth':
      'no call of its own: it describes the depth range and the depth '
      'format, and a device without it draws a reversed projection all the '
      'same, without the precision',
};

final ByteData _sixteen = ByteData.sublistView(
  Uint8List.fromList(List<int>.generate(16, (int i) => i * 7 + 1)),
);

TextureHandle _target(GraphicsDevice device) => device.createTexture(
  const RenderTargetDescriptor(
    width: 4,
    height: 4,
    format: TextureFormat.r8g8b8a8UNormInt,
  ),
);

/// Opens a pass over a fresh target, runs [body] in it, submits.
void _inPass(GraphicsDevice device, void Function(CommandEncoder pass) body) {
  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[ColorTarget(texture: _target(device))],
    ),
  );
  try {
    body(pass);
  } finally {
    pass.submit();
  }
}

/// A buffer handle no backend made, for a refusal that must come before
/// the backend looks at the buffer.
StorageBuffer _foreignBuffer() =>
    wrapStorageBuffer(backend: Object(), lengthInBytes: 16);

StorageBuffer _buffer(GraphicsDevice device, BufferUsage usage) =>
    device.createBuffer(
      BufferDescriptor(lengthInBytes: 16, usage: usage),
      contents: _sixteen,
    );

void _sameBytes(ByteData got, ByteData want, String what) {
  require(
    got.lengthInBytes >= want.lengthInBytes,
    '$what came back ${got.lengthInBytes} bytes long, not '
    '${want.lengthInBytes}',
  );
  for (var i = 0; i < want.lengthInBytes; i++) {
    require(
      got.getUint8(i) == want.getUint8(i),
      '$what: byte $i is ${got.getUint8(i)} where ${want.getUint8(i)} '
      'belongs',
    );
  }
}

ShaderHandle _anyStage(GraphicsDevice device) {
  final stage = device.shaders['DebugLine'];
  require(stage != null, 'the DebugLine stage is missing');
  return stage!;
}

TextureHandle _created(GraphicsDevice device, TextureDescriptor descriptor) {
  final texture = device.createTexture(descriptor);
  require(
    texture.width == descriptor.width &&
        texture.dimension == descriptor.dimension &&
        texture.depthOrArrayLayers == descriptor.depthOrArrayLayers,
    'createTexture answered $texture for $descriptor',
  );
  return texture;
}

/// Binds a texture with [sampler] to a slot no stage declares: a device
/// without the sampler's feature refuses before it looks for the slot.
void _sampledBy(GraphicsDevice device, SamplerDescriptor sampler) {
  final texture = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData(4),
  );
  _inPass(device, (CommandEncoder pass) {
    pass.bindTexture(
      _anyStage(device),
      'flutter3dNoSuchSlot',
      texture,
      sampler: sampler,
    );
  });
}

/// The probe for each feature this check can ask about, by name.
final Map<DeviceFeature, _Probe> _probes = <DeviceFeature, _Probe>{
  DeviceFeature.blendConstant: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async =>
        _inPass(d, (CommandEncoder p) => p.setBlendColor(Vector4.zero())),
  ),
  DeviceFeature.wireframe: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async =>
        _inPass(d, (CommandEncoder p) => p.setPolygonMode(PolygonMode.line)),
  ),
  DeviceFeature.renderToMipLevel: (
    needs: const <DeviceFeature>[DeviceFeature.textureWrites],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final texture = d.features.has(DeviceFeature.textureWrites)
          ? _created(
              d,
              const TextureDescriptor(
                width: 4,
                height: 4,
                format: TextureFormat.r8g8b8a8UNormInt,
                mipLevelCount: 2,
              ),
            )
          : _target(d);
      d
          .beginRenderPass(
            RenderPassDescriptor(
              colors: <ColorTarget>[ColorTarget(texture: texture, mipLevel: 1)],
            ),
          )
          .submit();
    },
  ),
  DeviceFeature.compute: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final buffer = d.createStorageBuffer(_sixteen, hostReadable: true);
      _sameBytes(await d.readBuffer(buffer), _sixteen, 'a storage buffer');
      d.releaseStorageBuffer(buffer);
    },
  ),
  DeviceFeature.textureArrays: (
    needs: const <DeviceFeature>[DeviceFeature.textureWrites],
    refusalOnly: false,
    run: (GraphicsDevice d) async => d.releaseTexture(
      _created(
        d,
        const TextureDescriptor(
          width: 4,
          height: 4,
          depthOrArrayLayers: 3,
          format: TextureFormat.r8g8b8a8UNormInt,
          dimension: TextureDimension.d2Array,
        ),
      ),
    ),
  ),
  DeviceFeature.texture3D: (
    needs: const <DeviceFeature>[DeviceFeature.textureWrites],
    refusalOnly: false,
    run: (GraphicsDevice d) async => d.releaseTexture(
      _created(
        d,
        const TextureDescriptor(
          width: 4,
          height: 4,
          depthOrArrayLayers: 4,
          format: TextureFormat.r8g8b8a8UNormInt,
          dimension: TextureDimension.d3,
        ),
      ),
    ),
  ),
  DeviceFeature.cubeArrayTextures: (
    needs: const <DeviceFeature>[
      DeviceFeature.textureWrites,
      DeviceFeature.cubeTextures,
    ],
    refusalOnly: false,
    run: (GraphicsDevice d) async => d.releaseTexture(
      _created(
        d,
        const TextureDescriptor(
          width: 4,
          height: 4,
          depthOrArrayLayers: 12,
          format: TextureFormat.r8g8b8a8UNormInt,
          dimension: TextureDimension.cubeArray,
        ),
      ),
    ),
  ),
  DeviceFeature.renderToArrayLayer: (
    needs: const <DeviceFeature>[
      DeviceFeature.textureWrites,
      DeviceFeature.textureArrays,
    ],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final texture =
          d.features.has(DeviceFeature.textureArrays) &&
              d.features.has(DeviceFeature.textureWrites)
          ? _created(
              d,
              const TextureDescriptor(
                width: 4,
                height: 4,
                depthOrArrayLayers: 2,
                format: TextureFormat.r8g8b8a8UNormInt,
                dimension: TextureDimension.d2Array,
              ),
            )
          : _target(d);
      d
          .beginRenderPass(
            RenderPassDescriptor(
              colors: <ColorTarget>[ColorTarget(texture: texture, layer: 1)],
            ),
          )
          .submit();
    },
  ),
  DeviceFeature.textureWrites: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final texture = _created(
        d,
        const TextureDescriptor(
          width: 2,
          height: 2,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      );
      final pixels = ByteData.sublistView(
        Uint8List.fromList(<int>[
          255, 0, 0, 255, 0, 255, 0, 255, //
          0, 0, 255, 255, 255, 255, 255, 255,
        ]),
      );
      d.writeTexture(texture, pixels);
      _sameBytes(await d.readback(texture), pixels, 'a written texture');
    },
  ),
  DeviceFeature.buffers: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final buffer = _buffer(
        d,
        BufferUsage.copyDestination | BufferUsage.hostReadable,
      );
      _sameBytes(await d.readBuffer(buffer), _sixteen, 'a created buffer');
      d.writeBuffer(buffer, 4, ByteData(4));
      final written = await d.readBuffer(buffer);
      require(
        written.getUint32(4) == 0 &&
            written.getUint8(8) == _sixteen.getUint8(8),
        'writeBuffer at offset 4 did not land exactly there',
      );
      d.releaseStorageBuffer(buffer);
    },
  ),
  DeviceFeature.bufferCopy: (
    needs: const <DeviceFeature>[DeviceFeature.buffers],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final source = d.features.has(DeviceFeature.buffers)
          ? _buffer(d, BufferUsage.copySource)
          : _foreignBuffer();
      final destination = d.features.has(DeviceFeature.buffers)
          ? _buffer(d, BufferUsage.copyDestination | BufferUsage.hostReadable)
          : _foreignBuffer();
      d.beginTransferPass()
        ..clearBuffer(destination)
        ..copyBufferToBuffer(source, 0, destination, 8, 8)
        ..submit();
      final got = await d.readBuffer(destination);
      require(
        got.getUint32(0) == 0 && got.getUint32(4) == 0,
        'clearBuffer left bytes behind',
      );
      _sameBytes(
        ByteData.sublistView(got, 8, 16),
        ByteData.sublistView(_sixteen, 0, 8),
        'a buffer copy',
      );
    },
  ),
  DeviceFeature.textureCopy: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final pixels = ByteData.sublistView(
        Uint8List.fromList(<int>[10, 20, 30, 255]),
      );
      final source = d.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: pixels,
      );
      final destination = d.createTexture(
        const RenderTargetDescriptor(
          width: 1,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      );
      d.beginTransferPass()
        ..copyTextureToTexture(
          TextureCopyLocation(source),
          TextureCopyLocation(destination),
          width: 1,
          height: 1,
        )
        ..submit();
      _sameBytes(await d.readback(destination), pixels, 'a texture copy');
    },
  ),
  DeviceFeature.bufferTextureCopy: (
    needs: const <DeviceFeature>[DeviceFeature.buffers],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final texture = d.createTexture(
        const RenderTargetDescriptor(
          width: 4,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      );
      final source = d.features.has(DeviceFeature.buffers)
          ? d.createBuffer(
              const BufferDescriptor(
                lengthInBytes: 256,
                usage: BufferUsage.copySource,
              ),
              contents: ByteData(256)
                ..buffer.asUint8List().setAll(
                  0,
                  Uint8List.sublistView(_sixteen),
                ),
            )
          : _foreignBuffer();
      d.beginTransferPass()
        ..copyBufferToTexture(
          source,
          const BufferTextureLayout(bytesPerRow: 256),
          TextureCopyLocation(texture),
          width: 4,
          height: 1,
        )
        ..submit();
      _sameBytes(
        await d.readback(texture),
        _sixteen,
        'a buffer-to-texture copy',
      );
    },
  ),
  DeviceFeature.storageTextures: (
    needs: const <DeviceFeature>[DeviceFeature.textureWrites],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final format = TextureFormat.values.firstWhere(
        (TextureFormat f) => d.textureFormatSupport(f).storage,
        orElse: () => TextureFormat.r32Float,
      );
      d.releaseTexture(
        _created(
          d,
          TextureDescriptor(
            width: 4,
            height: 4,
            format: format,
            usage: TextureUsage.storage | TextureUsage.copySource,
          ),
        ),
      );
    },
  ),
  DeviceFeature.renderStageStorage: (
    needs: const <DeviceFeature>[DeviceFeature.buffers],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final buffer = d.features.has(DeviceFeature.buffers)
          ? _buffer(d, BufferUsage.storage)
          : _foreignBuffer();
      _inPass(d, (CommandEncoder p) {
        require(
          !p.bindStorageBuffer(_anyStage(d), 'flutter3dNoSuchBuffer', buffer),
          'a storage binding the stage does not declare answered true',
        );
      });
    },
  ),
  DeviceFeature.indirectDraw: (
    needs: const <DeviceFeature>[],
    refusalOnly: true,
    run: (GraphicsDevice d) async =>
        _inPass(d, (CommandEncoder p) => p.drawIndirect(_foreignBuffer())),
  ),
  DeviceFeature.multiDrawIndirect: (
    needs: const <DeviceFeature>[],
    refusalOnly: true,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) => p.multiDrawIndirect(_foreignBuffer(), 1),
    ),
  ),
  DeviceFeature.multiDraw: (
    needs: const <DeviceFeature>[],
    refusalOnly: true,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) =>
          p.multiDraw(const <IndexedDraw>[IndexedDraw(indexCount: 3)]),
    ),
  ),
  DeviceFeature.nonIndexedDraw: (
    needs: const <DeviceFeature>[],
    refusalOnly: true,
    run: (GraphicsDevice d) async =>
        _inPass(d, (CommandEncoder p) => p.drawNonIndexed(vertexCount: 3)),
  ),
  DeviceFeature.baseVertexBaseInstance: (
    needs: const <DeviceFeature>[],
    refusalOnly: true,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) =>
          p.drawIndexed(const IndexedDraw(indexCount: 3, baseVertex: 1)),
    ),
  ),
  DeviceFeature.indirectDispatch: (
    needs: const <DeviceFeature>[DeviceFeature.compute],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      if (!d.features.has(DeviceFeature.indirectDispatch)) {
        d.beginComputePass()
          ..dispatchIndirect(_foreignBuffer())
          ..submit();
        return;
      }
      require(
        d.features.has(DeviceFeature.buffers),
        'indirect dispatch is reported without buffers, so no argument '
        'buffer can be made for it',
      );
      final stage = d.shaders['PrefixSum'];
      require(stage != null, 'the PrefixSum compute stage is missing');
      final values = ByteData(1024 * 4);
      for (var i = 0; i < 1024; i++) {
        values.setUint32(i * 4, 1, Endian.little);
      }
      final buffer = d.createStorageBuffer(values, hostReadable: true);
      final arguments = d.createBuffer(
        const BufferDescriptor(lengthInBytes: 12, usage: BufferUsage.indirect),
        contents: dispatchIndirectArguments(1),
      );
      d.beginComputePass()
        ..bindPipeline(d.createComputePipeline(stage!))
        ..bindStorageBuffer(stage, 'Values', buffer)
        ..dispatchIndirect(arguments)
        ..submit();
      final out = await d.readBuffer(buffer);
      require(
        out.getUint32(1023 * 4, Endian.little) == 1024,
        'an indirect dispatch of one workgroup did not scan the buffer',
      );
    },
  ),
  DeviceFeature.depthBias: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) => p.setDepthBias(const DepthBias(constant: 1)),
    ),
  ),
  DeviceFeature.colorWriteMask: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) => p.setColorWriteMask(ColorWriteMask.red),
    ),
  ),
  DeviceFeature.depthClamp: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async =>
        _inPass(d, (CommandEncoder p) => p.setDepthClamp(enabled: true)),
  ),
  DeviceFeature.minMaxBlend: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) =>
          p.setBlend(const BlendState(colorOperation: BlendOperation.max)),
    ),
  ),
  DeviceFeature.dualSourceBlending: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) => p.setBlend(
        const BlendState(destinationColorFactor: BlendFactor.source1Color),
      ),
    ),
  ),
  DeviceFeature.samplerCompare: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async =>
        _sampledBy(d, const SamplerDescriptor(compare: CompareFunction.less)),
  ),
  DeviceFeature.samplerLodClamp: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async =>
        _sampledBy(d, const SamplerDescriptor(lodMaxClamp: 1)),
  ),
  DeviceFeature.samplerBorderColor: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _sampledBy(
      d,
      const SamplerDescriptor(borderColor: SamplerBorderColor.opaqueWhite),
    ),
  ),
  DeviceFeature.uniformBytes: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(d, (CommandEncoder p) {
      require(
        !p.bindUniformBytes(_anyStage(d), 'Flutter3dNoSuchBlock', ByteData(16)),
        'a uniform block the stage does not declare answered true',
      );
    }),
  ),
  DeviceFeature.occlusionQuery: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final set = d.createQuerySet(QueryType.occlusion, 2);
      final pass =
          d.beginRenderPass(
              RenderPassDescriptor(
                colors: <ColorTarget>[ColorTarget(texture: _target(d))],
                occlusionQuerySet: set,
              ),
            )
            ..beginOcclusionQuery(0)
            ..endOcclusionQuery();
      pass.submit();
      final results = await d.readQueryResults(set);
      require(
        results.length == 2 && results[0] == 0,
        'an occlusion query around no draws answered $results',
      );
      d.releaseQuerySet(set);
    },
  ),
  DeviceFeature.timestampQuery: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final set = d.createQuerySet(QueryType.timestamp, 2);
      d
          .beginRenderPass(
            RenderPassDescriptor(
              colors: <ColorTarget>[ColorTarget(texture: _target(d))],
              timestampWrites: PassTimestampWrites(
                querySet: set,
                beginningOfPassIndex: 0,
                endOfPassIndex: 1,
              ),
            ),
          )
          .submit();
      final results = await d.readQueryResults(set);
      require(
        results.length == 2 && results[1] >= results[0],
        'a pass\'s timestamps answered $results',
      );
      d.releaseQuerySet(set);
    },
  ),
  DeviceFeature.pipelineStatisticsQuery: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final set = d.createQuerySet(QueryType.pipelineStatistics, 1);
      _inPass(d, (CommandEncoder p) {
        p
          ..beginPipelineStatisticsQuery(set, 0)
          ..endPipelineStatisticsQuery();
      });
      final results = await d.readQueryResults(set);
      require(
        results.length == PipelineStatistic.values.length,
        'a pipeline statistics query answered ${results.length} counters, '
        'not ${PipelineStatistic.values.length}',
      );
      d.releaseQuerySet(set);
    },
  ),
  DeviceFeature.mappedBuffers: (
    needs: const <DeviceFeature>[DeviceFeature.buffers],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final buffer = d.features.has(DeviceFeature.buffers)
          ? _buffer(d, BufferUsage.hostReadable)
          : _foreignBuffer();
      final mapped = await d.mapBuffer(buffer, MapMode.read);
      _sameBytes(mapped.bytes, _sixteen, 'a mapped buffer');
      mapped.unmap();
    },
  ),
  DeviceFeature.synchronousReadback: (
    needs: const <DeviceFeature>[DeviceFeature.buffers],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final buffer = d.features.has(DeviceFeature.buffers)
          ? _buffer(d, BufferUsage.hostReadable)
          : _foreignBuffer();
      // A capability a device opts into (`SynchronousBufferReadback`); one
      // that has not is refused exactly as a gated call refuses.
      if (d is! SynchronousBufferReadback) {
        throw UnsupportedCapability(
          DeviceFeature.synchronousReadback,
          backend: d.backendName,
        );
      }
      _sameBytes(d.readBufferSync(buffer), _sixteen, 'a synchronous readback');
    },
  ),
  DeviceFeature.renderBundles: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final bundle = d
          .createRenderBundleEncoder(
            const RenderBundleDescriptor(
              colorFormats: <TextureFormat>[TextureFormat.r8g8b8a8UNormInt],
            ),
          )
          .finish(label: 'empty');
      _inPass(
        d,
        (CommandEncoder p) => p.executeBundles(<RenderBundle>[bundle]),
      );
    },
  ),
};

/// Format-table features: the family answer has to match the per-format
/// table, both ways.
final Map<DeviceFeature, bool Function(GraphicsDevice device)> _tables =
    <DeviceFeature, bool Function(GraphicsDevice device)>{
      // The whole family, as WebGPU's `texture-compression-bc` means it:
      // every BC format the enum names, sRGB variants included.
      DeviceFeature.textureCompressionBC: (GraphicsDevice d) => <TextureFormat>[
        TextureFormat.bc1RGBAUNormInt,
        TextureFormat.bc1RGBAUNormIntSRGB,
        TextureFormat.bc3RGBAUNormInt,
        TextureFormat.bc3RGBAUNormIntSRGB,
        TextureFormat.bc5RGUNormInt,
        TextureFormat.bc7RGBAUNormInt,
        TextureFormat.bc7RGBAUNormIntSRGB,
      ].every((TextureFormat f) => d.textureFormatSupport(f).sampled),
      DeviceFeature.textureCompressionETC2: (GraphicsDevice d) =>
          d.textureFormatSupport(TextureFormat.etc2RGBA8UNormInt).sampled,
      DeviceFeature.textureCompressionASTC: (GraphicsDevice d) =>
          d.textureFormatSupport(TextureFormat.astc4x4LDR).sampled,
      DeviceFeature.textureCompressionASTCHdr: (GraphicsDevice d) =>
          d.textureFormatSupport(TextureFormat.astc4x4HDR).sampled,
      DeviceFeature.float32Filterable: (GraphicsDevice d) =>
          d.textureFormatSupport(TextureFormat.r32Float).filterable,
      DeviceFeature.float32Renderable: (GraphicsDevice d) =>
          d.textureFormatSupport(TextureFormat.r32Float).renderable,
      DeviceFeature.float32Blendable: (GraphicsDevice d) =>
          d.textureFormatSupport(TextureFormat.r32Float).blendable,
      DeviceFeature.rg11b10Renderable: (GraphicsDevice d) =>
          d.textureFormatSupport(TextureFormat.r11g11b10UFloat).renderable,
    };

/// Walks every feature: a listed one must work, an unlisted one must refuse
/// with `UnsupportedCapability`, a reserved one must never be listed.
Future<void> checkCapabilitiesAreHonest(GraphicsDevice device) async {
  final features = device.features;
  final wrong = <String>[];
  for (final feature in DeviceFeature.values) {
    final has = features.has(feature);
    if (feature.stability == FeatureStability.reserved) {
      if (has) wrong.add('${feature.name} is reserved and reported');
      continue;
    }
    if (_tables[feature] case final table?) {
      final answer = table(device);
      if (answer != has) {
        wrong.add(
          '${feature.name} is ${has ? '' : 'not '}reported, but '
          'textureFormatSupport says ${answer ? 'yes' : 'no'}',
        );
      }
      continue;
    }
    final probe = _probes[feature];
    if (probe == null) continue; // in unprobedFeatures, or a stage-bound one
    final missing = probe.needs.where((DeviceFeature n) => !features.has(n));
    if (has) {
      if (probe.refusalOnly || missing.isNotEmpty) continue;
      try {
        await probe.run(device);
      } on ConformanceFailureException catch (failure) {
        wrong.add('${feature.name} is reported and ${failure.message}');
      } on Object catch (error) {
        wrong.add('${feature.name} is reported, and its call threw $error');
      }
      continue;
    }
    try {
      await probe.run(device);
      wrong.add(
        '${feature.name} is not reported, and its call succeeded anyway — '
        'a backend that can do it should say so',
      );
    } on UnsupportedCapability catch (refusal) {
      final acceptable =
          refusal.feature == feature || missing.contains(refusal.feature);
      if (!acceptable) {
        wrong.add(
          '${feature.name} is not reported, and its call was refused as '
          '${refusal.feature.name} instead',
        );
      }
    } on Object catch (error) {
      wrong.add(
        '${feature.name} is not reported, and its call threw $error rather '
        'than UnsupportedCapability naming it',
      );
    }
  }
  require(
    wrong.isEmpty,
    'the capability report is not honest:\n  ${wrong.join('\n  ')}',
  );
}

/// The pre-1.0 getters answer what the feature set and limits say.
Future<void> checkLegacyGettersForward(GraphicsDevice device) async {
  final f = device.features;
  final pairs = <String, (bool, bool)>{
    'supportsOffscreenMsaa': (
      device.features.has(DeviceFeature.offscreenMultisample),
      f.has(DeviceFeature.offscreenMultisample),
    ),
    'supportsBlendColor': (
      device.features.has(DeviceFeature.blendConstant),
      f.has(DeviceFeature.blendConstant),
    ),
    'supportsMipmaps': (
      device.features.has(DeviceFeature.manualMipmaps),
      f.has(DeviceFeature.manualMipmaps),
    ),
    'supportsCubeTextures': (
      device.features.has(DeviceFeature.cubeTextures),
      f.has(DeviceFeature.cubeTextures),
    ),
    'supportsRenderToMip': (
      device.features.has(DeviceFeature.renderToMipLevel),
      f.has(DeviceFeature.renderToMipLevel),
    ),
    'supportsWireframe': (
      device.features.has(DeviceFeature.wireframe),
      f.has(DeviceFeature.wireframe),
    ),
    'supportsAlphaToCoverage': (
      device.features.has(DeviceFeature.alphaToCoverage),
      f.has(DeviceFeature.alphaToCoverage),
    ),
    'supportsStencil': (
      device.features.has(DeviceFeature.stencil),
      f.has(DeviceFeature.stencil),
    ),
    'supportsGpuTimestamps': (
      device.features.has(DeviceFeature.gpuTimestamps),
      f.has(DeviceFeature.gpuTimestamps),
    ),
    'supportsCompute': (
      device.features.has(DeviceFeature.compute),
      f.has(DeviceFeature.compute),
    ),
    'supportsFloat32Filtering': (
      device.features.has(DeviceFeature.float32Filterable) &&
          device.features.has(DeviceFeature.float32Renderable),
      f.has(DeviceFeature.float32Filterable) &&
          f.has(DeviceFeature.float32Renderable),
    ),
    'supportsIndependentBlend': (
      device.features.has(DeviceFeature.independentBlend),
      f.has(DeviceFeature.independentBlend),
    ),
  };
  final wrong = <String>[
    for (final MapEntry(key: name, value: (old, now)) in pairs.entries)
      if (old != now) '$name answers $old where features say $now',
    if (device.limits.maxSamplerAnisotropy !=
        device.limits.maxSamplerAnisotropy)
      'maxAnisotropy is ${device.limits.maxSamplerAnisotropy}, limits say ${device.limits.maxSamplerAnisotropy}',
    if (device.limits.maxColorAttachments != device.limits.maxColorAttachments)
      'maxColorAttachments is ${device.limits.maxColorAttachments}, limits say ${device.limits.maxColorAttachments}',
    for (final format in TextureFormat.values)
      if (device.textureFormatSupport(format).sampled !=
          device.textureFormatSupport(format).sampled)
        'supportsTextureFormat(${format.name}) disagrees with textureFormatSupport',
  ];
  require(
    wrong.isEmpty,
    'the pre-1.0 capability getters disagree with features:\n  '
    '${wrong.join('\n  ')}',
  );
}

/// Every backend runs these; neither declines.
List<ConformanceCheck> get capabilityChecks => <ConformanceCheck>[
  (
    name: 'every capability a device reports is honest',
    run: checkCapabilitiesAreHonest,
  ),
  (
    name: 'the pre-1.0 capability getters agree with features',
    run: checkLegacyGettersForward,
  ),
];
