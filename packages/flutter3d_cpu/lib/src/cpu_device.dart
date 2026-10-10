/// A `GraphicsDevice` with no GPU behind it.
///
/// The third implementation, and the reason for it: two backends that agree
/// prove less than they seem to when both are hardware rasterisers driven by a
/// C API. This one shares nothing with either — no driver, no shading language,
/// no command buffer — so whatever the interface still assumes about graphics
/// hardware has to show up here.
///
/// It is also useful rather than only instructive. Rendering on this backend
/// needs no device, so the engine's frames can be checked under a plain
/// `dart test` on the VM, in seconds, where the golden suite currently
/// drives an application for twelve minutes.
///
/// Split across a few files by cohesive concern, all re-exported from here:
/// [CpuShaderLibrary] and `CpuPipeline` are `cpu_shader_library.dart`;
/// [CpuEncoder] — the pass that records state and rasterises on `draw` — is
/// `cpu_encoder.dart`; and the per-vertex attribute assembly instancing needs
/// is `cpu_vertex_fetch.dart`. `CpuFrame`, the widget `presentFrame` in
/// `flutter3d_app` returns for this backend, moved there with it (mcp-02n) —
/// this package is flat, and a Flutter-facing widget file could not stay.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_compute_encoder.dart';
import 'cpu_encoder.dart';
import 'cpu_render_bundle.dart';
import 'cpu_resources.dart';
import 'cpu_shader.dart';
import 'cpu_shader_library.dart';
import 'cpu_texel_codec.dart';
import 'cpu_transfer_encoder.dart';

export 'cpu_encoder.dart';
export 'cpu_render_bundle.dart' show CpuRenderBundleEncoder;
export 'cpu_shader_library.dart';
export 'cpu_vertex_fetch.dart';

/// The software backend.
final class CpuDevice extends GraphicsDevice with SynchronousBufferReadback {
  @override
  String get backendName => 'the software rasteriser';

  // Debug groups, labels and loss: the inherited defaults are the truth
  // here. There is no debugger to show a group to, a label is kept for
  // `labelOf`, nothing can take a CPU away, and a pipeline links in the
  // calling turn either way.

  CpuDevice({
    required this.width,
    required this.height,
    required this.shaders,
    int maxColorAttachments = 3,
    this.hdrOutputFormats = const <TextureFormat>[],
    bool supportsIndependentBlend = true,
    Iterable<DeviceFeature> withhold = const <DeviceFeature>[],
    this.materialCompiler,
  }) : features = DeviceFeatures(<DeviceFeature>[
         ..._implemented,
         if (supportsIndependentBlend) DeviceFeature.independentBlend,
       ]).without(withhold),
       limits = DeviceLimits(
         maxColorAttachments: maxColorAttachments,
         maxColorAttachmentBytesPerSample: maxColorAttachments * 16,
         maxSampleCount: 1,
         maxSamplerAnisotropy: 16,
         minStorageBufferOffsetAlignment: 4,
       );

  /// Everything this rasteriser really does, whatever a test withholds.
  ///
  /// **What is not here, and why**, decided once rather than per getter:
  ///
  ///  * `offscreenMultisample`, `alphaToCoverage` — one sample a pixel, so
  ///    nothing to resolve and no coverage to spread (`P7`). Answering one
  ///    for `preferredSampleCount` rather than four is the difference between
  ///    a backend that says what it does and one whose pictures quietly
  ///    differ.
  ///  * `wireframe` — see `wireframeRefusal`.
  ///  * `gpuTimestamps` — a pass here is timed where it is encoded, on the
  ///    CPU, and there is no frame of GPU timings to report;
  ///    `timestampQuery` is the honest form of the same clock.
  ///  * the four compression families — this backend samples raw texels and
  ///    has no decoder for a block, by design.
  ///  * `rg11b10Renderable` — the packed format is sampled, and the
  ///    rasteriser's writes do not round to its eleven bits.
  ///  * `shaderF16`, `subgroups`, `clipDistances` — shader-language features,
  ///    and a Dart stage has no shader language to have them in.
  ///  * `uniformBytes` — see `uniformBytesRefusal`.
  ///
  /// `independentBlend` is a constructor argument, and `withhold` takes any
  /// of these away: a device that refuses something is the only place the
  /// refusal is exercised with real pixels behind it.
  static const List<DeviceFeature> _implemented = <DeviceFeature>[
    // `A2.8`: clip depth in `[0, 1]` and a depth buffer of floats, so a
    // reversed projection keeps its precision here as on a GPU — and the
    // rasteriser's comparisons are the eight the contract names, whichever
    // way round they are asked.
    DeviceFeature.reversedDepth,
    // A field on the pass and four arms in the blend equation, which is the
    // whole of what a blend constant is when the blending is arithmetic this
    // backend does itself.
    DeviceFeature.blendConstant,
    // Both halves are here: the chain is stored as whole textures and the
    // level is chosen from a per-triangle derivative. See
    // `BoundTexture.sample` for why the derivative is a parameter rather than
    // a property of the fragment, which is the one place this backend cannot
    // imitate hardware.
    DeviceFeature.manualMipmaps,
    // Nothing to probe: a cube here is six arrays of floats and a table
    // saying which of them a direction lands on.
    DeviceFeature.cubeTextures,
    // A level is an array like any other, and the rasteriser writes into
    // whichever one the attachment names — see `CpuTexture.subresource`.
    DeviceFeature.renderToMipLevel,
    // A byte per pixel beside the depth, tested and written the way the
    // specification says, every operation of the eight. See `CpuEncoder`.
    DeviceFeature.stencil,
    // `H6`: a stage is a `CpuComputeShader`, a storage buffer is its bytes,
    // and a dispatch runs its workgroups before it returns, which is as
    // synchronous as every draw on this backend.
    DeviceFeature.compute,
    // Every texture here is four 32-bit floats a texel whatever its format
    // says, and the sampler filters them the same way it filters anything —
    // `S2`'s moments atlas is no special case for this backend. Rendered
    // into and blended the same way.
    DeviceFeature.float32Filterable,
    DeviceFeature.float32Renderable,
    DeviceFeature.float32Blendable,
    // Layers, slices and cubes of cubes are lists of the same arrays a 2D
    // texture is; `CpuTexture.plane` addresses all of them.
    DeviceFeature.textureArrays,
    DeviceFeature.texture3D,
    DeviceFeature.cubeArrayTextures,
    DeviceFeature.renderToArrayLayer,
    DeviceFeature.textureWrites,
    DeviceFeature.buffers,
    DeviceFeature.bufferCopy,
    DeviceFeature.textureCopy,
    DeviceFeature.bufferTextureCopy,
    // A Dart stage is handed `CpuStorageTexture`s and storage bytes by name,
    // in a compute pass and a render pass alike.
    DeviceFeature.storageTextures,
    DeviceFeature.readWriteStorageTextures,
    DeviceFeature.renderStageStorage,
    // Indirect arguments are read off the buffer when the call is made: the
    // pass that wrote them ran to its end before this one opened.
    DeviceFeature.indirectDraw,
    DeviceFeature.indirectDispatch,
    DeviceFeature.indirectFirstInstance,
    DeviceFeature.nonIndexedDraw,
    DeviceFeature.multiDraw,
    DeviceFeature.multiDrawIndirect,
    DeviceFeature.baseVertexBaseInstance,
    DeviceFeature.depthBias,
    DeviceFeature.colorWriteMask,
    DeviceFeature.depthClamp,
    DeviceFeature.minMaxBlend,
    // `FragmentContext.source1` is the second output.
    DeviceFeature.dualSourceBlending,
    DeviceFeature.samplerCompare,
    DeviceFeature.samplerLodClamp,
    DeviceFeature.samplerBorderColor,
    DeviceFeature.occlusionQuery,
    // Read off `CpuClock` — see it for the one way it is not a GPU's clock.
    DeviceFeature.timestampQuery,
    DeviceFeature.pipelineStatisticsQuery,
    DeviceFeature.mappedBuffers,
    // A buffer here is host memory, so reading it in the calling turn
    // stalls on nothing.
    DeviceFeature.synchronousReadback,
    // Recorded calls, replayed — see `CpuRenderBundleEncoder`.
    DeviceFeature.renderBundles,
  ];

  @override
  final DeviceFeatures features;

  /// WebGPU's guaranteed numbers, except where this rasteriser says
  /// otherwise: the colour attachments the constructor was given (three by
  /// default — `gfx-50n`, `L5`), one sample, sixteen taps of anisotropy, and
  /// storage ranges on any four-byte boundary.
  ///
  /// The texture sizes are WebGPU's on purpose. The rasteriser could hold
  /// anything memory allows, and a reference that could do more than the
  /// thing it is a reference for would record pictures no shipping backend
  /// can reproduce — the same argument that keeps the attachments at three.
  @override
  final DeviceLimits limits;

  final CpuClock _clock = CpuClock();

  /// What [format] can be used for here.
  ///
  /// Everything but a compressed format and a 32-bit integer one is stored
  /// as four floats a texel, so "sampled" is true for all the rest — the
  /// pre-1.0 answer, `!format.isCompressed`, kept exactly, `unknown`
  /// included. The integer formats are sampled and stored to but never
  /// filtered, blended or rendered: the rasteriser's colour writes keep
  /// floats and do not round to an integer. The 32-bit integer formats are
  /// refused: a 32-bit float cannot hold every 32-bit integer.
  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) {
    // TODO(cpu): block-compressed formats — this backend samples raw texels
    // and has no decoder for a block, by design (ARCHITECTURE.md §15); a
    // decoder per family at upload is what would unblock it.
    if (format.isCompressed) return TextureFormatSupport.none;
    final storable = features.has(DeviceFeature.storageTextures);
    final readWrite = features.has(DeviceFeature.readWriteStorageTextures);
    final float32Renders = features.has(DeviceFeature.float32Renderable);
    return switch (format) {
      TextureFormat.unknown => const TextureFormatSupport(sampled: true),
      // TODO(cpu): 32-bit integer formats — the texel store is 32-bit
      // floats, which hold integers exactly only to 2²⁴; an integer plane
      // beside `CpuTexture.pixels` would unblock them.
      TextureFormat.r32UInt ||
      TextureFormat.r32SInt ||
      TextureFormat.r32g32UInt ||
      TextureFormat.r32g32SInt ||
      TextureFormat.r32g32b32a32UInt ||
      TextureFormat.r32g32b32a32SInt => TextureFormatSupport.none,
      TextureFormat.s8UInt ||
      TextureFormat.d24UnormS8Uint ||
      TextureFormat.d32FloatS8UInt ||
      TextureFormat.d16UNormInt ||
      TextureFormat.d32Float => const TextureFormatSupport(
        sampled: true,
        depthStencil: true,
      ),
      TextureFormat.r32Float ||
      TextureFormat.r32g32Float ||
      TextureFormat.r32g32b32a32Float => TextureFormatSupport(
        sampled: true,
        filterable: features.has(DeviceFeature.float32Filterable),
        renderable: float32Renders,
        blendable:
            float32Renders && features.has(DeviceFeature.float32Blendable),
        storage: storable,
        storageReadWrite: readWrite,
      ),
      TextureFormat.r8g8b8a8UInt ||
      TextureFormat.r8g8b8a8SInt ||
      TextureFormat.r16g16b16a16UInt ||
      TextureFormat.r16g16b16a16SInt => TextureFormatSupport(
        sampled: true,
        storage: storable,
        storageReadWrite: readWrite,
      ),
      TextureFormat.r8g8b8a8SNormInt => TextureFormatSupport(
        sampled: true,
        filterable: true,
        storage: storable,
        storageReadWrite: readWrite,
      ),
      TextureFormat.r10g10b10a2UNormInt ||
      TextureFormat.r11g11b10UFloat ||
      TextureFormat.r9g9b9e5UFloat => const TextureFormatSupport(
        sampled: true,
        filterable: true,
      ),
      // sRGB is encoded bytes, which a storage store does not encode — as
      // WebGPU refuses them for storage, so does this.
      TextureFormat.r8g8b8a8UNormIntSRGB ||
      TextureFormat.b8g8r8a8UNormIntSRGB => const TextureFormatSupport(
        sampled: true,
        filterable: true,
        renderable: true,
        blendable: true,
      ),
      _ => TextureFormatSupport(
        sampled: true,
        filterable: true,
        renderable: true,
        blendable: true,
        storage: storable,
        storageReadWrite: readWrite,
      ),
    };
  }

  // The 0.8 cycle's half of the contract, declared in 0.8.0 and not built
  // here yet — see the end of `GraphicsDevice`. Each answer is the one that
  // makes a caller take its fallback.

  /// Never called: `gpuTimestamps` is not among [features] — a pass here is
  /// timed where it is encoded.
  @override
  void onGpuTimings(void Function(GpuFrameTimings timings)? listener) {}

  @override
  StorageBuffer createStorageBuffer(
    ByteData bytes, {
    bool hostReadable = false,
    bool bindableAsIndices = false,
  }) {
    features.require(DeviceFeature.compute, backend: cpuBackendName);
    final copy = ByteData.sublistView(
      Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    return wrapStorageBuffer(
      owner: this,
      backend: copy,
      lengthInBytes: bytes.lengthInBytes,
      hostReadable: hostReadable,
      // The same bytes in the shape [uploadGeometry] gives a draw, so what a
      // dispatch writes is what the next draw reads, with no copy between.
      asIndices: bindableAsIndices
          ? wrapGeometry(
              backend: (bytes: copy, usage: GeometryUsage.indices),
              offsetInBytes: 0,
              lengthInBytes: bytes.lengthInBytes,
            )
          : null,
    );
  }

  @override
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) {
    features.require(DeviceFeature.compute, backend: cpuBackendName);
    final stage = shader.backend;
    if (stage is! CpuStage || stage.compute == null) {
      throw ArgumentError.value(
        shader.name,
        'shader',
        'is not a compute stage on this device',
      );
    }
    return wrapComputePipeline(
      owner: this,
      backend: stage.compute!,
      shader: shader,
    );
  }

  @override
  ComputeEncoder beginComputePass({
    String? label,
    PassTimestampWrites? timestampWrites,
  }) {
    features.require(DeviceFeature.compute, backend: cpuBackendName);
    return CpuComputeEncoder(
      features: features,
      support: textureFormatSupport,
      clock: _clock,
      timestampWrites: timestampWrites,
    );
  }

  /// A copy of [buffer]'s bytes, which are host memory here: the passes that
  /// wrote them ran to their end before this was called.
  @override
  Future<ByteData> readBuffer(StorageBuffer buffer) async {
    if (!features.has(DeviceFeature.compute)) {
      features.require(
        DeviceFeature.buffers,
        backend: cpuBackendName,
        reason: 'readBuffer needs compute or buffers',
      );
    }
    _requireReadable(buffer);
    checkUnmapped(buffer);
    return _copyOf(rangeOf(buffer));
  }

  @override
  void releaseStorageBuffer(StorageBuffer buffer) {}

  // `independentBlend` comes from the constructor: the pass keeps a blend
  // state for each of its first two attachments — `R8`. A third, the albedo
  // buffer, is written unblended whatever is set, as it always was. A
  // constructor argument, like the attachment count, so the fallback a device
  // without it takes — weighted blended transparency drawing its list once
  // per target — can be drawn here and compared with the path it stands in
  // for.

  /// None unless a test hands some in — `R9`: there is no display here to
  /// be HDR, and the extended output is exercised by asking for one.
  @override
  final List<TextureFormat> hdrOutputFormats;

  final int width;
  final int height;

  @override
  final CpuShaderLibrary shaders;

  /// What makes a Dart stage of a material written in the engine's language,
  /// for a bundle that carries one — `P8`. Null, the default, refuses such a
  /// bundle by name, as it refuses any stage [shaders] does not have.
  final CpuMaterialCompiler? materialCompiler;

  /// The bundle's names, answered with this device's own Dart stages; a name
  /// it has no Dart for is a refusal naming the bundle and the stage. See
  /// [CpuLoadedShaderLibrary]. Nothing is compiled, so nothing is waited for.
  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async =>
      CpuLoadedShaderLibrary.load(shaders, bytes, compiler: materialCompiler);

  @override
  // The engine's own convention, and here it is a choice rather than a
  // constraint — nothing underneath has an opinion. Choosing the engine's
  // saves a matrix multiply per frame and, more to the point, means this
  // backend does not quietly become a second test of `toDepthRange`.
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  // Row zero is the top, because that is where this backend puts it. There is
  // no framebuffer here to disagree with.
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d32FloatS8UInt;

  @override
  // Float everywhere internally, so this costs nothing and is not a lie: the
  // values really are kept beyond one.
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  // No multisampling. Answering one rather than four is the difference between
  // a backend that says what it does and one whose pictures quietly differ.
  int get preferredSampleCount => 1;

  // `limits.maxSamplerAnisotropy`, sixteen: one tap along one axis from one
  // level, chosen per triangle — see `BoundTexture.sample`, which takes the
  // taps since `gfx-02n`: a sampler asking for eight gets eight, spread along
  // the long axis of its footprint, each at the level the short axis asks
  // for. This answered one until then, and `anisotropic-floor` is the scene
  // whose cross-backend budget was the measured size of that difference — a
  // budget now describing a smaller gap than it was written for, since the
  // remaining difference is the weighting of the taps rather than their
  // absence. Sixteen because that is what the hardware backends report and
  // what a sampler is clamped against; the cost here is linear in the taps
  // and paid only by a sampler that asked.
  //
  // `limits.maxColorAttachments`, three by default and settable — `gfx-50n`,
  // `L5`. The rasteriser could write into any number of arrays, so the three
  // is a choice rather than a limit: it answers what the hardware backends
  // answer where they work — the colour, the surface buffer and the albedo
  // buffer, which is all any pass here opens. **Settable for the harder
  // reason.** The device this stands in for is Impeller on OpenGL ES, which
  // aborts rather than refusing, so the no-MRT path cannot be run on the
  // hardware that has it — there is no way to see what the engine does there
  // except to build a device that says one. A rasteriser that can be that
  // device is the only place the path is exercised with real pixels at the
  // end of it.

  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) {
    // The same shape `createCubeTextureFromPixels` builds, so
    // `BoundTexture.sampleCube` reads a rendered cube exactly as it reads an
    // uploaded one: six faces hanging off face zero, a chain per face. The
    // chain reaches one by one and no further, which is where the upload's
    // arithmetic stops too.
    final faces = List<CpuTexture>.generate(
      6,
      (_) => CpuTexture(size, size, format),
    );
    if (mipLevels > 1) {
      for (final face in faces) {
        final chain = <CpuTexture>[];
        var side = size;
        for (var level = 1; level < mipLevels && side > 1; level++) {
          side = side >> 1;
          chain.add(CpuTexture(side, side, format));
        }
        face.levels = chain;
      }
    }
    final cube = faces[0]..faces = faces;
    return wrapTexture(
      owner: this,
      backend: cube,
      width: size,
      height: size,
      format: format,
      type: TextureType.textureCube,
    );
  }

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) {
    if (format.isCompressed) {
      throw UnsupportedError(
        'The software rasteriser samples raw RGBA texels — '
        'TextureFormat.${format.name} is block-compressed and has no decode '
        'path here, by design (see ARCHITECTURE.md §15).',
      );
    }
    if (faces.length != 6) {
      throw refuseResource(
        'createCubeTextureFromPixels',
        'a cube has six faces and ${faces.length} were given',
      );
    }

    CpuTexture read(ByteData source, int side) {
      final need = side * side * 4;
      // **Exactly, not "at least".** The interface refuses a face that is not
      // the size its description says, and the other two backends enforce it —
      // WebGL because `texSubImage2D` would read past the level, Impeller
      // because `overwrite` throws. This one accepted a longer buffer and used
      // its prefix, which turns a chain built with the wrong arithmetic into a
      // cube that loads and reflects noise.
      if (source.lengthInBytes != need) {
        throw refuseResource(
          'createCubeTextureFromPixels',
          'a ${side}x$side face is $need bytes and '
              '${source.lengthInBytes} were given',
        );
      }
      final texture = CpuTexture(side, side, format);
      final bytes = source.buffer.asUint8List(source.offsetInBytes, need);
      for (var i = 0; i < need; i++) {
        texture.pixels[i] = bytes[i] / 255.0;
      }
      return texture;
    }

    final built = <CpuTexture>[];
    for (final face in faces) {
      built.add(read(face, size));
    }

    // **A chain per face, not one chain for the cube.** Each face is sampled as
    // its own square, so the levels have to hang off the face that owns them;
    // hanging them off face zero would give five faces a chain belonging to the
    // sixth, which reads as a seam that moves with the roughness.
    if (mipLevels != null && mipLevels.isNotEmpty) {
      final chains = List<List<CpuTexture>>.generate(6, (_) => <CpuTexture>[]);
      var side = size;
      for (final level in mipLevels) {
        if (level.length != 6) {
          throw refuseResource(
            'createCubeTextureFromPixels',
            'a mip level of a cube has six faces and ${level.length} were '
                'given',
          );
        }
        side = side > 1 ? side >> 1 : 1;
        for (var face = 0; face < 6; face++) {
          chains[face].add(read(level[face], side));
        }
      }
      for (var face = 0; face < 6; face++) {
        built[face].levels = chains[face];
      }
    }

    // The handle's own texture is face zero, so anything that samples this as
    // an ordinary 2D texture gets +X rather than nothing. The six live beside
    // it, and `BoundTexture.sampleCube` is what reaches them.
    final cube = built[0]..faces = built;
    return wrapTexture(
      owner: this,
      backend: cube,
      width: size,
      height: size,
      format: format,
      type: TextureType.textureCube,
    );
  }

  TextureHandle _createTarget(RenderTargetDescriptor spec) => wrapTexture(
    owner: this,
    backend: CpuTexture(spec.width, spec.height, spec.format),
    width: spec.width,
    height: spec.height,
    format: spec.format,
    sampleCount: 1,
    storageMode: spec.storageMode,
  );

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    if (format.isCompressed) {
      throw UnsupportedError(
        'The software rasteriser samples raw RGBA texels — '
        'TextureFormat.${format.name} is block-compressed and has no decode '
        'path here, by design (see ARCHITECTURE.md §15).',
      );
    }
    // **Exactly, not "at least"** — the same rule the cube path above spells
    // out, and for the same reason. `GraphicsDevice.createTextureFromPixels`
    // refuses a buffer that is not the size the description asks for;
    // Impeller refuses on `!=` because `overwrite` would throw, WebGL on `!=`
    // because `texSubImage2D` reads exactly that many bytes. This one took the
    // prefix of anything longer, so a decoder that disagreed with the engine
    // about the dimensions was refused on two backends and silently drew
    // something else on the third.
    final expected = width * height * _texelBytes(format);
    if (pixels.lengthInBytes != expected) {
      throw refuseResource(
        'createTextureFromPixels',
        'a ${width}x$height ${format.name} texture is $expected bytes and '
            '${pixels.lengthInBytes} were given',
      );
    }
    final texture = CpuTexture(width, height, format);
    _decodeInto(texture.pixels, pixels, format, width * height);
    if (mipLevels != null && mipLevels.isNotEmpty) {
      final chain = <CpuTexture>[];
      var w = width;
      var h = height;
      for (final level in mipLevels) {
        w = w > 1 ? w >> 1 : 1;
        h = h > 1 ? h >> 1 : 1;
        final small = CpuTexture(w, h, format);
        final need = w * h * _texelBytes(format);
        // Exactly, as above. A chain built with the wrong arithmetic is the
        // case this catches, and it is the one that looks like a filtering bug
        // rather than like a bad upload.
        if (level.lengthInBytes != need) {
          throw refuseResource(
            'createTextureFromPixels',
            'a ${w}x$h mip level is $need bytes and ${level.lengthInBytes} '
                'were given',
          );
        }
        _decodeInto(small.pixels, level, format, w * h);
        chain.add(small);
      }
      texture.levels = chain;
    }
    return wrapTexture(
      owner: this,
      backend: texture,
      width: width,
      height: height,
      format: format,
      sampleCount: 1,
      storageMode: StorageMode.devicePrivate,
    );
  }

  @override
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  }) async {
    if (!readbackFormats.contains(target.format)) {
      throw UnsupportedError(
        'overwriteTexture: TextureFormat.${target.format.name} is not one '
        'of readbackFormats — the two this call, like readback, insists on.',
      );
    }
    if (mipLevel != 0) {
      throw UnsupportedError(
        'overwriteTexture: mip level $mipLevel is refused; only the base '
        'level (0) may be overwritten.',
      );
    }
    final rect =
        region ?? ScreenRect(width: target.width, height: target.height);
    if (rect.x < 0 ||
        rect.y < 0 ||
        rect.x + rect.width > target.width ||
        rect.y + rect.height > target.height) {
      throw ArgumentError(
        'overwriteTexture: $rect does not fit inside a '
        '${target.width}x${target.height} texture',
      );
    }
    if (rgba.lengthInBytes != rect.width * rect.height * 4) {
      throw ArgumentError(
        'overwriteTexture: ${rgba.lengthInBytes} bytes does not match '
        '${rect.width}x${rect.height} RGBA8',
      );
    }

    final texture = target.backend as CpuTexture;
    for (var y = 0; y < rect.height; y++) {
      for (var x = 0; x < rect.width; x++) {
        final src = (y * rect.width + x) * 4;
        final dstTexel = ((rect.y + y) * target.width + (rect.x + x)) * 4;
        for (var c = 0; c < 4; c++) {
          texture.pixels[dstTexel + c] = rgba.getUint8(src + c) / 255.0;
        }
      }
    }
  }

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    // The usage is recorded rather than acted on: nothing here binds a buffer
    // to anything for life. Recorded anyway, because a backend that forgets
    // which it was told would pass the conformance check for the wrong reason.
    final copy = Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    return wrapGeometry(
      backend: (bytes: ByteData.sublistView(copy), usage: usage),
      offsetInBytes: 0,
      lengthInBytes: bytes.lengthInBytes,
      release: releaseGeometry,
    );
  }

  /// Writes straight into the `Uint8List` [uploadGeometry] copied the
  /// original bytes into — there is no separate device-side copy to keep in
  /// step, which is the one respect in which this backend's write is simpler
  /// than the other three's.
  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) {
    final backend = target.backend as ({ByteData bytes, GeometryUsage usage});
    if (offsetInBytes < 0 ||
        offsetInBytes + bytes.lengthInBytes > target.lengthInBytes) {
      throw ArgumentError(
        'overwriteGeometry: $offsetInBytes + ${bytes.lengthInBytes} does not '
        'fit inside a ${target.lengthInBytes}-byte buffer',
      );
    }
    final at = target.offsetInBytes + offsetInBytes;
    backend.bytes.buffer
        .asUint8List(backend.bytes.offsetInBytes + at, bytes.lengthInBytes)
        .setAll(
          0,
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
  }

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) {
    // Every format this backend can read is floats. The integer ones exist in
    // the vocabulary because flutter_gpu has them; a stage here receives one
    // `Float32List`, so a `uint32` attribute would have to be reinterpreted,
    // and reinterpreting it silently is how a joint index becomes 1.4e-45.
    if (layout != null) {
      for (final buffer in layout.buffers) {
        for (final attribute in buffer.attributes) {
          if (!attribute.format.name.startsWith('float')) {
            throw UnsupportedError(
              'attribute "${attribute.name}" is ${attribute.format.name}. This '
              'backend hands a vertex stage a list of floats, so it reads only '
              'the float formats.',
            );
          }
        }
      }
    }
    final v = (vertex.backend as CpuStage).vertex;
    final f = (fragment.backend as CpuStage).fragment;
    if (v == null || f == null) {
      throw StateError(
        'createPipeline("${vertex.name}", "${fragment.name}"): the stages are '
        'the wrong way round, or one of them is not the kind it is being used '
        'as.',
      );
    }
    return wrapPipeline(
      owner: this,
      backend: CpuPipeline(v, f, layout),
      name: '${vertex.name}+${fragment.name}',
    );
  }

  @override
  void beginFrame() {
    // Nothing rotates here. Implemented as nothing, which is the answer the
    // contract asks for rather than the absence of one.
  }

  @override
  void onFrameComplete(void Function() whenDone) {
    // Straight away, and honestly: this backend rasterises on the calling
    // thread, so by the time anybody could ask, the frame is finished.
    whenDone();
  }

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    // `gfx-50n`. Nothing here would abort — the rasteriser writes into
    // whichever lists it is handed — and it refuses all the same, because a
    // reference implementation that accepted a pass the shipping backends
    // would not is a reference for the wrong thing.
    descriptor
      ..checkAttachmentLimit(
        limits.maxColorAttachments,
        backend: cpuBackendName,
      )
      ..checkFeatures(features, backend: cpuBackendName);
    // Every colour format this backend gained in 1.0 is checked against what
    // it says of the format; the pre-1.0 ones are drawn into as they always
    // were.
    for (final color in descriptor.colors) {
      final format = color.texture.format;
      if (!format.isMirrored && !textureFormatSupport(format).renderable) {
        throw ArgumentError.value(
          format,
          'colors',
          'is not renderable on $cpuBackendName',
        );
      }
    }
    return CpuEncoder(
      descriptor,
      features: features,
      support: textureFormatSupport,
      clock: _clock,
    );
  }

  // ------------------------------------------------------------------ 1.0

  /// Every shape the contract names: a 2D texture (a 1D one is a 2D texture
  /// one row high), a 2D array, a 3D texture, a cube and a cube array, each
  /// with its chain — see [CpuTexture.layers] and [CpuTexture.slices] for
  /// how they hang together. Contents start at nought.
  ///
  /// A [RenderTargetDescriptor] is the pool's 2D target, made as it always
  /// was; any other descriptor is the general form, `textureWrites`.
  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    if (descriptor is RenderTargetDescriptor) return _createTarget(descriptor);
    features.require(DeviceFeature.textureWrites, backend: cpuBackendName);
    final d = descriptor;
    final format = d.format;
    switch (d.dimension) {
      case TextureDimension.d2Array:
        features.require(DeviceFeature.textureArrays, backend: cpuBackendName);
      case TextureDimension.d3:
        features.require(DeviceFeature.texture3D, backend: cpuBackendName);
      case TextureDimension.cube:
        features.require(DeviceFeature.cubeTextures, backend: cpuBackendName);
      case TextureDimension.cubeArray:
        features.require(
          DeviceFeature.cubeArrayTextures,
          backend: cpuBackendName,
        );
      case TextureDimension.d1 || TextureDimension.d2:
        break;
    }
    if (d.sampleCount > 1) {
      features.require(
        DeviceFeature.offscreenMultisample,
        backend: cpuBackendName,
        reason: 'it draws one sample a pixel',
      );
    }
    if (format.isCompressed) {
      features.require(
        _compressionFamily(format),
        backend: cpuBackendName,
        reason: 'it samples raw texels and has no decoder for a block',
      );
    }
    final support = textureFormatSupport(format);
    if (support == TextureFormatSupport.none) {
      throw ArgumentError.value(
        format,
        'descriptor.format',
        'cannot be held by $cpuBackendName',
      );
    }
    if (d.usage.contains(TextureUsage.storage)) {
      features.require(DeviceFeature.storageTextures, backend: cpuBackendName);
      if (!support.storage) {
        throw ArgumentError.value(
          format,
          'descriptor.format',
          'cannot be a storage texture here',
        );
      }
    }
    _checkShape(d);

    final levels = d.mipLevelCount;
    CpuTexture flat(int w, int h) {
      final base = CpuTexture(w, h, format);
      if (levels > 1) {
        base.levels = <CpuTexture>[
          for (var level = 1; level < levels; level++)
            CpuTexture(_down(w, level), _down(h, level), format),
        ];
      }
      return base;
    }

    CpuTexture cube() {
      final faces = List<CpuTexture>.generate(
        6,
        (_) => flat(d.width, d.height),
      );
      return faces[0]..faces = faces;
    }

    CpuTexture volumeLevel(int level) {
      final slices = List<CpuTexture>.generate(
        _down(d.depthOrArrayLayers, level),
        (_) =>
            CpuTexture(_down(d.width, level), _down(d.height, level), format),
      );
      return slices[0]..slices = slices;
    }

    final CpuTexture texture = switch (d.dimension) {
      TextureDimension.d1 || TextureDimension.d2 => flat(d.width, d.height),
      TextureDimension.d2Array => () {
        final layers = List<CpuTexture>.generate(
          d.depthOrArrayLayers,
          (_) => flat(d.width, d.height),
        );
        return layers[0]..layers = layers;
      }(),
      TextureDimension.cube => cube(),
      TextureDimension.cubeArray => () {
        final cubes = List<CpuTexture>.generate(
          d.depthOrArrayLayers ~/ 6,
          (_) => cube(),
        );
        return cubes[0]..layers = cubes;
      }(),
      TextureDimension.d3 => () {
        final base = volumeLevel(0);
        if (levels > 1) {
          base.levels = <CpuTexture>[
            for (var level = 1; level < levels; level++) volumeLevel(level),
          ];
        }
        return base;
      }(),
    };
    final isCube =
        d.dimension == TextureDimension.cube ||
        d.dimension == TextureDimension.cubeArray;
    return wrapTexture(
      owner: this,
      backend: texture,
      width: d.width,
      height: d.height,
      format: format,
      storageMode: d.storageMode,
      type: isCube ? TextureType.textureCube : TextureType.texture2D,
      dimension: d.dimension,
      depthOrArrayLayers: d.depthOrArrayLayers,
      mipLevelCount: d.mipLevelCount,
      usage: d.usage,
    );
  }

  void _checkShape(TextureDescriptor d) {
    final l = limits;
    final (int maxSide, int maxDepth) = switch (d.dimension) {
      TextureDimension.d1 => (l.maxTextureDimension1D, 1),
      TextureDimension.d3 => (l.maxTextureDimension3D, l.maxTextureDimension3D),
      TextureDimension.d2Array || TextureDimension.cubeArray => (
        l.maxTextureDimension2D,
        l.maxTextureArrayLayers,
      ),
      TextureDimension.cube => (l.maxTextureDimension2D, 6),
      TextureDimension.d2 => (l.maxTextureDimension2D, 1),
    };
    final problem = switch (d.dimension) {
      _ when d.width > maxSide || d.height > maxSide =>
        'is larger than $maxSide on a side',
      _ when d.depthOrArrayLayers > maxDepth =>
        'has more than $maxDepth layers or slices',
      TextureDimension.d1 when d.height != 1 => 'is 1D and more than one row',
      TextureDimension.cube when d.depthOrArrayLayers != 6 =>
        'is a cube with ${d.depthOrArrayLayers} faces rather than six',
      TextureDimension.cubeArray when d.depthOrArrayLayers % 6 != 0 =>
        'is a cube array of ${d.depthOrArrayLayers} faces, not a multiple '
            'of six',
      TextureDimension.cube || TextureDimension.cubeArray
          when d.width != d.height =>
        'is a cube whose faces are not square',
      _ when d.sampleCount > 1 && d.mipLevelCount > 1 =>
        'is multisampled with a chain',
      _ when d.mipLevelCount > _fullChain(d) =>
        'asks for ${d.mipLevelCount} levels where ${_fullChain(d)} reach one '
            'texel',
      _ => null,
    };
    if (problem != null) {
      throw ArgumentError.value(d, 'descriptor', problem);
    }
  }

  /// Levels from the base down to one texel, the largest side deciding.
  static int _fullChain(TextureDescriptor d) {
    final largest = [
      d.width,
      d.height,
      if (d.dimension == TextureDimension.d3) d.depthOrArrayLayers,
    ].reduce((a, b) => a > b ? a : b);
    return largest.bitLength;
  }

  static int _down(int size, int level) {
    final side = size >> level;
    return side < 1 ? 1 : side;
  }

  static DeviceFeature _compressionFamily(TextureFormat format) =>
      switch (format) {
        TextureFormat.etc2RGB8UNormInt ||
        TextureFormat.etc2RGB8UNormIntSRGB ||
        TextureFormat.etc2RGBA8UNormInt ||
        TextureFormat.etc2RGBA8UNormIntSRGB =>
          DeviceFeature.textureCompressionETC2,
        TextureFormat.astc4x4HDR ||
        TextureFormat.astc8x8HDR => DeviceFeature.textureCompressionASTCHdr,
        TextureFormat.astc4x4LDR ||
        TextureFormat.astc4x4LDRSRGB ||
        TextureFormat.astc8x8LDR ||
        TextureFormat.astc8x8LDRSRGB => DeviceFeature.textureCompressionASTC,
        _ => DeviceFeature.textureCompressionBC,
      };

  /// Decodes [data] into the planes of [region] at [mipLevel], in
  /// [target]'s own format — see `writeTexels` for where depth and stencil
  /// land. Written at once: there is no queue here for it to wait in.
  @override
  void writeTexture(
    TextureHandle target,
    ByteData data, {
    TextureRegion? region,
    int mipLevel = 0,
    int? bytesPerRow,
  }) {
    features.require(DeviceFeature.textureWrites, backend: cpuBackendName);
    final format = target.format;
    if (format.isCompressed) {
      features.require(
        _compressionFamily(format),
        backend: cpuBackendName,
        reason: 'it samples raw texels and has no decoder for a block',
      );
    }
    if (!target.usage.contains(TextureUsage.copyDestination)) {
      throw ArgumentError.value(
        target.usage,
        'target.usage',
        'lacks TextureUsage.copyDestination, which a write needs',
      );
    }
    final texture = target.backend as CpuTexture;
    final level = texture.plane(mipLevel: mipLevel);
    final box =
        region ??
        TextureRegion(
          width: level.width,
          height: level.height,
          depthOrArrayLayers: texture.planeCount(mipLevel),
        );
    if (box.x < 0 ||
        box.y < 0 ||
        box.z < 0 ||
        box.x + box.width > level.width ||
        box.y + box.height > level.height ||
        box.z + box.depthOrArrayLayers > texture.planeCount(mipLevel)) {
      throw RangeError('$box does not fit in level $mipLevel of $target');
    }
    final row = bytesPerRow ?? box.width * format.bytesPerTexel;
    final image = row * box.height;
    final needed = box.depthOrArrayLayers == 0 || box.height == 0
        ? 0
        : (box.depthOrArrayLayers - 1) * image +
              (box.height - 1) * row +
              box.width * format.bytesPerTexel;
    if (row < box.width * format.bytesPerTexel || data.lengthInBytes < needed) {
      throw ArgumentError.value(
        data.lengthInBytes,
        'data',
        'is too short for $box of ${format.name} with rows $row bytes apart',
      );
    }
    for (var z = 0; z < box.depthOrArrayLayers; z++) {
      writeTexels(
        texture.plane(mipLevel: mipLevel, z: box.z + z),
        format,
        data,
        z * image,
        x: box.x,
        y: box.y,
        width: box.width,
        height: box.height,
        bytesPerRow: row,
      );
    }
  }

  /// Host memory, like every buffer here: [StorageBuffer.backend] is the
  /// bytes, and a draw binding [StorageBuffer.asVertices] or
  /// [StorageBuffer.asIndices] reads the same bytes a dispatch wrote.
  @override
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) {
    features.require(DeviceFeature.buffers, backend: cpuBackendName);
    final usage = descriptor.usage;
    if (usage.contains(BufferUsage.storage) &&
        !features.has(DeviceFeature.renderStageStorage)) {
      features.require(
        DeviceFeature.compute,
        backend: cpuBackendName,
        reason: 'a storage buffer needs compute or render-stage storage',
      );
    }
    if (usage.contains(BufferUsage.indirect) &&
        !features.has(DeviceFeature.indirectDispatch)) {
      features.require(
        DeviceFeature.indirectDraw,
        backend: cpuBackendName,
        reason: 'an indirect buffer needs indirect draws or dispatches',
      );
    }
    if (descriptor.lengthInBytes > limits.maxBufferSize) {
      throw ArgumentError.value(
        descriptor.lengthInBytes,
        'lengthInBytes',
        'is past maxBufferSize, ${limits.maxBufferSize}',
      );
    }
    if (contents != null && contents.lengthInBytes > descriptor.lengthInBytes) {
      throw ArgumentError.value(
        contents.lengthInBytes,
        'contents',
        'is longer than the ${descriptor.lengthInBytes}-byte buffer',
      );
    }
    final bytes = Uint8List(descriptor.lengthInBytes);
    if (contents != null) {
      bytes.setAll(
        0,
        contents.buffer.asUint8List(
          contents.offsetInBytes,
          contents.lengthInBytes,
        ),
      );
    }
    final data = ByteData.sublistView(bytes);
    GeometryBuffer? as(BufferUsage wanted, GeometryUsage geometry) =>
        usage.contains(wanted)
        ? wrapGeometry(
            backend: (bytes: data, usage: geometry),
            offsetInBytes: 0,
            lengthInBytes: descriptor.lengthInBytes,
          )
        : null;
    return wrapStorageBuffer(
      owner: this,
      backend: data,
      lengthInBytes: descriptor.lengthInBytes,
      hostReadable: usage.contains(BufferUsage.hostReadable),
      asVertices: as(BufferUsage.vertex, GeometryUsage.vertices),
      asIndices: as(BufferUsage.index, GeometryUsage.indices),
      usage: usage,
    );
  }

  @override
  void writeBuffer(StorageBuffer target, int offsetInBytes, ByteData bytes) {
    if (!features.has(DeviceFeature.compute)) {
      features.require(
        DeviceFeature.buffers,
        backend: cpuBackendName,
        reason: 'writeBuffer needs compute or buffers',
      );
    }
    requireBufferUsage(target, BufferUsage.copyDestination, 'a write');
    if (offsetInBytes < 0 ||
        offsetInBytes + bytes.lengthInBytes > target.lengthInBytes) {
      throw ArgumentError(
        'writeBuffer: $offsetInBytes + ${bytes.lengthInBytes} does not fit '
        'inside a ${target.lengthInBytes}-byte buffer',
      );
    }
    checkUnmapped(target);
    final into = bytesOf(target);
    into.buffer
        .asUint8List(into.offsetInBytes + offsetInBytes, bytes.lengthInBytes)
        .setAll(
          0,
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
  }

  @override
  QuerySet createQuerySet(QueryType type, int count) {
    features.require(type.feature, backend: cpuBackendName);
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'must be at least one');
    }
    return wrapQuerySet(
      owner: this,
      backend: CpuQueryResults(type, count),
      type: type,
      count: count,
    );
  }

  /// The results as the passes left them — they ran to their end before
  /// this was called. A pipeline-statistics query is five results, in
  /// `PipelineStatistic` order, so [count] of them are `5 × count` numbers.
  @override
  Future<List<int>> readQueryResults(
    QuerySet querySet, {
    int first = 0,
    int? count,
  }) async {
    final results = querySet.backend as CpuQueryResults;
    final n = count ?? querySet.count - first;
    if (first < 0 || n < 0 || first + n > querySet.count) {
      throw RangeError('$n queries from $first of a set of ${querySet.count}');
    }
    final per = querySet.type == QueryType.pipelineStatistics
        ? PipelineStatistic.values.length
        : 1;
    return List<int>.of(
      results.values.getRange(first * per, (first + n) * per),
    );
  }

  @override
  void releaseQuerySet(QuerySet querySet) {}

  @override
  TransferEncoder beginTransferPass({String? label}) =>
      CpuTransferEncoder(features);

  /// The range itself, not a copy: a buffer here is host memory, so the
  /// mapping is the buffer's own bytes, and no pass may use the buffer until
  /// [MappedBuffer.unmap] — the rule that makes handing out the memory
  /// itself safe. Mapped at once: every pass before this has finished.
  @override
  Future<MappedBuffer> mapBuffer(
    StorageBuffer buffer,
    MapMode mode, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) async {
    features.require(DeviceFeature.mappedBuffers, backend: cpuBackendName);
    switch (mode) {
      case MapMode.read:
        _requireReadable(buffer);
      case MapMode.write:
        requireBufferUsage(buffer, BufferUsage.hostWritable, 'a write mapping');
    }
    if (mappedBuffers[buffer] != null) {
      throw StateError('the buffer is already mapped');
    }
    final range = rangeOf(
      buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
      alignment: 8,
    );
    if (range.lengthInBytes % 4 != 0) {
      throw ArgumentError.value(
        range.lengthInBytes,
        'sizeInBytes',
        'must be a multiple of four',
      );
    }
    mappedBuffers[buffer] = mode;
    return _CpuMappedBuffer(buffer, range);
  }

  @override
  ByteData readBufferSync(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    features.require(
      DeviceFeature.synchronousReadback,
      backend: cpuBackendName,
    );
    _requireReadable(buffer);
    checkUnmapped(buffer);
    return _copyOf(
      rangeOf(buffer, offsetInBytes: offsetInBytes, sizeInBytes: sizeInBytes),
    );
  }

  @override
  RenderBundleEncoder createRenderBundleEncoder(
    RenderBundleDescriptor descriptor,
  ) {
    features.require(DeviceFeature.renderBundles, backend: cpuBackendName);
    return CpuRenderBundleEncoder(
      descriptor,
      features: features,
      support: textureFormatSupport,
    );
  }

  /// Readable by the host: made `hostReadable` the pre-1.0 way, or with
  /// [BufferUsage.hostReadable].
  static void _requireReadable(StorageBuffer buffer) {
    if (buffer.hostReadable ||
        buffer.usage.contains(BufferUsage.hostReadable)) {
      return;
    }
    throw ArgumentError.value(
      buffer,
      'buffer',
      'was not created hostReadable, so it cannot be read back',
    );
  }

  static ByteData _copyOf(ByteData bytes) => ByteData.sublistView(
    Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    ),
  );

  /// [texture]'s own RGBA floats, unclamped and unconverted — what
  /// [readback] throws away on the way to an 8-bit picture.
  ///
  /// **Only this backend can answer this, and only this backend needs to.**
  /// A hardware texture's bytes live on the GPU in whatever layout the driver
  /// chose; reading them back as linear floats is the round trip
  /// `GraphicsDevice.readback` already declines for anything but its two
  /// 8-bit formats. This backend's own texture already *is* a `Float32List`
  /// — see `CpuTexture` — so there is nothing to convert and nothing to ask
  /// a driver for.
  ///
  /// A diagnostic wants exactly what a picture cannot show: a depth of forty
  /// metres does not fit in `0..1`, and a `double.nan` a broken shader wrote
  /// clamps to `1.0` before it ever reaches [readback] — silently, since
  /// `1.0` is a perfectly ordinary channel value. Reading the texture as it
  /// actually stands is the only way to tell a NaN or an out-of-range value
  /// apart from the picture it happens to resemble once rounded.
  Float32List readHdrPixels(TextureHandle texture) {
    final backend = texture.backend as CpuTexture;
    return Float32List.fromList(backend.pixels);
  }

  /// The region, converted on the spot — every format alike, since a
  /// texture here is floats whatever it claims to be, so the whole of a float
  /// target ([readbackConverts]) is the same clamp-and-round.
  ///
  /// Nothing here is in flight: the pass that wrote these floats ran to the
  /// end before `submit` returned, so "the texture as the passes before this
  /// call left it" is simply the texture. The future is already complete when
  /// it is handed back, which is the honest answer and also what makes the
  /// engine's own tests of the callers run in a plain `flutter test`.
  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) {
    final rect = readbackConverts(texture, region: region)
        ? ScreenRect.of(texture)
        : readbackRegionOf(texture, region);
    final backend = texture.backend as CpuTexture;
    final out = Uint8List(rect.width * rect.height * 4);
    final source = backend.pixels;
    for (var y = 0; y < rect.height; y++) {
      final from = ((rect.y + y) * backend.width + rect.x) * 4;
      final to = y * rect.width * 4;
      for (var i = 0; i < rect.width * 4; i++) {
        out[to + i] = (source[from + i].clamp(0.0, 1.0) * 255.0).round();
      }
    }
    return Future<ByteData>.value(ByteData.sublistView(out));
  }

  /// Releases nothing, and honestly so: every texture and buffer this backend
  /// hands out is a plain Dart object — a [CpuTexture] wrapping a
  /// `Float32List`, a record wrapping a `ByteData` — with nothing external to
  /// release. The garbage collector already does the whole of what this
  /// method would do on a backend with a driver underneath it.
  ///
  /// What it does do is report the loss: the first call marks the device
  /// [isLost] and sends one `DeviceLossReason.destroyed` on [lost], then
  /// closes it. A second call is a teardown run twice and says nothing.
  @override
  void dispose() {
    if (_isLost) return;
    _isLost = true;
    _lost
      ..add(
        const DeviceLoss(
          reason: DeviceLossReason.destroyed,
          message: 'the software device was disposed',
        ),
      )
      ..close();
  }

  /// [GraphicsDevice.lost]: nothing outside this process can take a software
  /// device away, so the one loss it has is its own [dispose]. Reported all
  /// the same, so that a caller listening on whatever it opened learns of a
  /// teardown here as it would on a hardware backend.
  @override
  Stream<DeviceLoss> get lost => _lost.stream;

  @override
  bool get isLost => _isLost;
  bool _isLost = false;

  final StreamController<DeviceLoss> _lost =
      StreamController<DeviceLoss>.broadcast();

  /// Nothing to free, for the same reason [dispose] has nothing to free: a
  /// texture here is a Dart list, and dropping the handle is already the whole
  /// of releasing it. Written out rather than left to a default so that a
  /// backend which grows a driver underneath it has to say so.
  @override
  void releaseTexture(TextureHandle texture) {}

  @override
  void releaseGeometry(GeometryBuffer geometry) {}
}

/// How many bytes one texel of [format] occupies in an upload.
///
/// **This used to be four for everything.** Every texture the engine uploaded
/// was eight-bit RGBA, so a constant was right by accident until the morph
/// deltas arrived as `r32g32b32a32Float`: sixteen bytes a texel, refused by the
/// size check, and a model that quietly drew its base shape on this backend
/// while the other two morphed. A format the sampler cannot describe is not a
/// format this rasteriser should guess at, so anything unlisted keeps the old
/// four and is refused by the size check if that is wrong — which is a null
/// upload and a warning rather than a texture full of misread bytes.
int _texelBytes(TextureFormat format) => switch (format) {
  // Since 1.0 the new formats say their own size; the old ones keep the
  // answer they always had.
  _ when !format.isMirrored => format.bytesPerTexel,
  TextureFormat.r32g32b32a32Float => 16,
  TextureFormat.r16g16b16a16Float => 8,
  TextureFormat.r32Float => 4,
  TextureFormat.r8UNormInt || TextureFormat.a8UNormInt => 1,
  TextureFormat.r8g8UNormInt => 2,
  _ => 4,
};

/// Reads [count] texels out of [pixels] into a [CpuTexture]'s four-float
/// storage.
///
/// The float formats are copied as they are; everything else is the eight-bit
/// unorm decode this backend has always done. A single-channel float lands in
/// red with the rest at nought and alpha at one, which is what sampling one of
/// these means everywhere else.
void _decodeInto(
  Float32List into,
  ByteData pixels,
  TextureFormat format,
  int count,
) {
  switch (format) {
    case TextureFormat.r32g32b32a32Float:
      for (var i = 0; i < count * 4; i++) {
        into[i] = pixels.getFloat32(i * 4, Endian.little);
      }
    case TextureFormat.r16g16b16a16Float:
      // Read through a Float32List rather than by hand: `dart:typed_data` has
      // no half-float view, and the conversion belongs in one place.
      for (var i = 0; i < count * 4; i++) {
        into[i] = halfToDouble(pixels.getUint16(i * 2, Endian.little));
      }
    case TextureFormat.r32Float:
      for (var i = 0; i < count; i++) {
        into[i * 4] = pixels.getFloat32(i * 4, Endian.little);
        into[i * 4 + 1] = 0.0;
        into[i * 4 + 2] = 0.0;
        into[i * 4 + 3] = 1.0;
      }
    // The narrow unorm formats, one and two bytes a texel, as every other
    // backend samples them: the channels there are, nought for the rest, and
    // alpha at one — except for alpha-only, whose one channel is alpha. The
    // engine's blue noise is the first table to arrive in one — `G1`.
    case TextureFormat.r8UNormInt:
      for (var i = 0; i < count; i++) {
        into[i * 4] = pixels.getUint8(i) / 255.0;
        into[i * 4 + 1] = 0.0;
        into[i * 4 + 2] = 0.0;
        into[i * 4 + 3] = 1.0;
      }
    case TextureFormat.a8UNormInt:
      for (var i = 0; i < count; i++) {
        into[i * 4] = 0.0;
        into[i * 4 + 1] = 0.0;
        into[i * 4 + 2] = 0.0;
        into[i * 4 + 3] = pixels.getUint8(i) / 255.0;
      }
    case TextureFormat.r8g8UNormInt:
      for (var i = 0; i < count; i++) {
        into[i * 4] = pixels.getUint8(i * 2) / 255.0;
        into[i * 4 + 1] = pixels.getUint8(i * 2 + 1) / 255.0;
        into[i * 4 + 2] = 0.0;
        into[i * 4 + 3] = 1.0;
      }
    // The formats 1.0 added, through the one codec `writeTexture` uses, so
    // an upload and a write of the same bytes store the same floats.
    case _ when !format.isMirrored && hasColourLayout(format):
      final size = format.bytesPerTexel;
      for (var i = 0; i < count; i++) {
        decodeTexel(format, pixels, i * size, into, i * 4);
      }
    default:
      for (var i = 0; i < count * 4; i++) {
        into[i] = pixels.getUint8(i) / 255.0;
      }
  }
}

/// A mapping on this backend: the buffer's own bytes, handed back by
/// [unmap].
final class _CpuMappedBuffer extends MappedBuffer {
  _CpuMappedBuffer(this._buffer, this.bytes);

  final StorageBuffer _buffer;

  @override
  final ByteData bytes;

  @override
  void unmap() {
    if (mappedBuffers[_buffer] == null) {
      throw StateError('a buffer unmapped twice');
    }
    mappedBuffers[_buffer] = null;
  }
}
