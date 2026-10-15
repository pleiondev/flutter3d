/// Whether a device's capability report is true — in both directions.
///
/// **The check the 1.0 contract rests on.** `GraphicsDevice.features` is one
/// set of answers a caller branches on, and the contract makes two promises
/// about each: a feature the device lists works, and a feature it does not
/// list refuses every call it gates with `UnsupportedCapabilityException` — before
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
/// "no" was never a refusal (alpha-to-coverage is ignored, a second
/// attachment's blend falls back to the first) and which have checks of
/// their own.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor, UnsupportedCapabilityException;
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

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
  'alpha-to-coverage': 'a device without it ignores the call, by contract',
  'stencil': 'held by "a stencil test keeps what it should"',
  'gpu-timestamps': 'reported through onGpuTimings, never refused',
  'independent-blend': 'a device without it sets attachment zero, by contract',
  'reversed-depth':
      'no call of its own: it describes the depth range and the depth '
      'format, and a device without it draws a reversed projection all the '
      'same, without the precision',
  'viewport-beyond-target':
      'no call refuses: a device without it is never handed such a '
      'viewport, and the renderer draws a window of a larger frame through '
      'a crop there; held with pixels by photo_capture_test.dart in '
      'flutter3d_cpu',
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

/// The features whose probe binds to a stage, [_anyStage]: a device with no
/// stages yet cannot be asked about them, and the check says so rather than
/// blame its feature report.
const Set<DeviceFeature> _stageBound = <DeviceFeature>{
  DeviceFeature.renderStageStorage,
  DeviceFeature.samplerCompare,
  DeviceFeature.samplerLodClamp,
  DeviceFeature.samplerBorderColor,
  DeviceFeature.uniformBytes,
  DeviceFeature.uniformBuffers,
};

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
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) => p.setBlendColor(LinearColor.transparent),
    ),
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
      final buffer = d.createBuffer(
        BufferDescriptor(
          lengthInBytes: _sixteen.lengthInBytes,
          usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
        ),
        contents: _sixteen,
      );
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
  DeviceFeature.texture1D: (
    needs: const <DeviceFeature>[DeviceFeature.textureWrites],
    refusalOnly: false,
    run: (GraphicsDevice d) async => d.releaseTexture(
      _created(
        d,
        TextureDescriptor(
          width: 4,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
          dimension: TextureDimension.d1,
          // A 1D texture is never an attachment, on WebGPU or anywhere.
          usage: TextureUsage.sampled | TextureUsage.copyDestination,
        ),
      ),
    ),
  ),
  // The pixels of a cube, which a device without cubes refuses by name
  // since 1.0 (it answered null before); what a face holds is "a cube map
  // answers the face a direction points at".
  DeviceFeature.cubeTextures: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => d.releaseTexture(
      d.createCubeTextureFromPixels(
        size: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        faces: <ByteData>[for (var i = 0; i < 6; i++) ByteData(4)],
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
      final buffer = d.createBuffer(
        BufferDescriptor(
          lengthInBytes: values.lengthInBytes,
          usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
        ),
        contents: values,
      );
      final arguments = d.createBuffer(
        const BufferDescriptor(lengthInBytes: 12, usage: BufferUsage.indirect),
        contents: dispatchIndirectArguments(1),
      );
      d.beginComputePass()
        ..bindPipeline(
          d.createComputePipelineFrom(
            ComputePipelineDescriptor(shader: stage!),
          ),
        )
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
  DeviceFeature.depthBiasClamp: (
    needs: const <DeviceFeature>[DeviceFeature.depthBias],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) =>
          p.setDepthBias(const DepthBias(constant: 1, clamp: 0.01)),
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
  // Since 1.0.0-rc.1+2: the capabilities every backend was assumed to have,
  // asked for the way a caller asks, from the call that names them.
  DeviceFeature.blendConstantAlpha: (
    needs: const <DeviceFeature>[DeviceFeature.blendConstant],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) => p.setBlend(
        const BlendState(sourceColorFactor: BlendFactor.blendAlpha),
      ),
    ),
  ),
  DeviceFeature.primitiveStrips: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) => p
        ..setPrimitiveType(PrimitiveType.triangleStrip)
        ..setPrimitiveType(PrimitiveType.lineStrip),
    ),
  ),
  DeviceFeature.pointPrimitives: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) => p.setPrimitiveType(PrimitiveType.point),
    ),
  ),
  DeviceFeature.indexUint32: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) => p.bindIndexData(ByteData(12), IndexType.int32, 3),
    ),
  ),
  DeviceFeature.fractionalViewport: (
    needs: const <DeviceFeature>[],
    refusalOnly: false,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) =>
          p.setViewport(const PassViewport(x: 0.5, width: 2.5, height: 3)),
    ),
  ),
  // No backend binds a buffer range as a block yet; the default refuses,
  // and a backend that overrides it is held to its refusal until it lists
  // the feature.
  DeviceFeature.uniformBuffers: (
    needs: const <DeviceFeature>[DeviceFeature.buffers],
    refusalOnly: true,
    run: (GraphicsDevice d) async => _inPass(
      d,
      (CommandEncoder p) => p.bindUniformBuffer(
        _anyStage(d),
        'Flutter3dNoSuchBlock',
        _foreignBuffer(),
        0,
        16,
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
    // An axis clamped to the border: a colour no axis uses needs nothing.
    run: (GraphicsDevice d) async => _sampledBy(
      d,
      const SamplerDescriptor(
        widthAddressMode: SamplerAddressMode.clampToBorder,
        borderColor: SamplerBorderColor.opaqueWhite,
      ),
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
        throw UnsupportedCapabilityException(
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
  // 1.0. A pass naming two views, into the layers of an array target:
  // refused by `checkFeatures` on a device without it, drawn on one with.
  DeviceFeature.multiview: (
    needs: const <DeviceFeature>[
      DeviceFeature.textureArrays,
      DeviceFeature.renderToArrayLayer,
    ],
    refusalOnly: false,
    run: (GraphicsDevice d) async {
      final views = d.createTexture(
        const TextureDescriptor(
          width: 4,
          height: 4,
          format: TextureFormat.r8g8b8a8UNormInt,
          dimension: TextureDimension.d2Array,
          depthOrArrayLayers: 2,
          usage: TextureUsage.renderTarget,
        ),
      );
      d
          .beginRenderPass(
            RenderPassDescriptor(
              colors: <ColorTarget>[ColorTarget(texture: views)],
              viewMask: 0x3,
            ),
          )
          .submit();
    },
  ),
  // The sharing calls' positive halves need a second device or a native
  // handle to share with, which this check has neither of; their refusals
  // are what every backend here gives, and what is asked.
  DeviceFeature.sharedTextures: (
    needs: const <DeviceFeature>[],
    refusalOnly: true,
    run: (GraphicsDevice d) async =>
        d.exportTexture(_target(d), kind: NativeHandleKind.metalTexture),
  ),
  DeviceFeature.sharedBuffers: (
    needs: const <DeviceFeature>[],
    refusalOnly: true,
    run: (GraphicsDevice d) async => d.exportBuffer(_foreignBuffer()),
  ),
  DeviceFeature.sharedFences: (
    needs: const <DeviceFeature>[],
    refusalOnly: true,
    run: (GraphicsDevice d) async => d.createFence(),
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
/// with `UnsupportedCapabilityException`, a reserved one must never be listed.
///
/// **Shader-free, as its tier promises.** The few probes that bind to a
/// stage (`_stageBound`) are skipped on a device whose library has no
/// `DebugLine` yet; every other feature is still walked, a wrong answer
/// still fails, and only when everything else is right does the check
/// decline, naming the features it could not ask about.
Future<void> checkCapabilitiesAreHonest(GraphicsDevice device) async {
  final features = device.features;
  final wrong = <String>[];
  final hasStage = device.shaders['DebugLine'] != null;
  final unasked = <String>[];
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
    if (probe == null) continue; // in unprobedFeatures
    if (!hasStage && _stageBound.contains(feature)) {
      unasked.add(feature.name);
      continue;
    }
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
    } on UnsupportedCapabilityException catch (refusal) {
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
        'than UnsupportedCapabilityException naming it',
      );
    }
  }
  // A preference for samples the device cannot allocate is a target the
  // renderer makes and the backend refuses.
  if (device.preferredSampleCount > 1 &&
      !features.has(DeviceFeature.offscreenMultisample)) {
    wrong.add(
      'preferredSampleCount is ${device.preferredSampleCount} without '
      '${DeviceFeature.offscreenMultisample.name}',
    );
  }
  require(
    wrong.isEmpty,
    'the capability report is not honest:\n  ${wrong.join('\n  ')}',
  );
  if (unasked.isNotEmpty) {
    decline(
      device,
      'has no DebugLine stage yet, so ${unasked.join(', ')} could not be '
      'asked; every other feature answered honestly',
    );
  }
}

/// Every backend runs these. The honesty check declines only on a device
/// with no stages yet, for the probes that need one.
List<ConformanceCheck> get capabilityChecks => <ConformanceCheck>[
  ConformanceCheck(
    name: 'every capability a device reports is honest',
    run: checkCapabilitiesAreHonest,
  ),
];
