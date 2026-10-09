/// WebGPU as an implementation of [GraphicsDevice].
///
/// The fourth backend, and the first one whose API disagrees with the contract
/// about *when* a pipeline exists. Where the two models differ the difference
/// is written down at the line where it bites; the largest of them is
/// `webgpu_encoder.dart`, and the second largest is the buffer lifetime scheme
/// at the top of `webgpu_resources.dart`.
///
/// Split by cohesive concern, the way `webgl_device.dart` is: [WebGpuTexture]
/// and [WebGpuGeometry] are the value types a handle carries
/// (`webgpu_types.dart`); [WebGpuShader], [WebGpuPipeline] and the libraries
/// over them are `webgpu_shaders.dart` and `webgpu_loaded_shaders.dart`;
/// allocation and teardown are `webgpu_resources.dart`;
/// [WebGpuPipelineSignature] and the map behind it are
/// `webgpu_pipeline_cache.dart`; [WebGpuEncoder] — one pass, accumulated and
/// resolved at the draw — is `webgpu_encoder.dart`.
///
/// **This device is itself the shader libraries' compiler.** They are written
/// without a browser binding so that name resolution, the vertex layout
/// arithmetic and every refusal can be asserted on the VM; the one thing they
/// cannot do without a device is turn WGSL into a module, and they reach it
/// through [WgslModuleCompiler], which this class implements over
/// `GPUDevice.createShaderModule`. Both libraries — the engine's own stages and
/// one loaded from a bundle — are handed this same seam, which is why
/// [loadShaders] is four lines.
///
/// **A few lines of DOM binding live here rather than in
/// `webgpu_interop.dart`.** This package depends on neither `package:web` nor
/// anything else that would hand it an element, and what presenting needs is
/// exactly three things: make a canvas, size it, and set five CSS properties on
/// it. They are private because nothing outside this file has any business
/// making the canvas a device draws into.
@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../engine_shaders.dart';
import 'webgpu_bundle_section.dart';
import 'webgpu_compute.dart';
import 'webgpu_compute_stage.dart';
import 'webgpu_encoder.dart';
import 'webgpu_formats.dart';
import 'webgpu_image_decode.dart';
import 'webgpu_interop.dart';
import 'webgpu_loaded_shaders.dart';
import 'webgpu_pipeline_cache.dart';
import 'webgpu_resources.dart';
import 'webgpu_shaders.dart';
import 'webgpu_timer.dart';
import 'webgpu_transfer.dart';
import 'webgpu_types.dart';

/// What this backend calls itself in a refusal.
const String _backend = 'WebGPU';

@JS('document')
external _Document get _document;

/// `window.matchMedia`, for whether the display reports a high dynamic range
/// — `R9`.
@JS('matchMedia')
external _MediaQueryList _matchMedia(String query);

extension type _MediaQueryList._(JSObject _) implements JSObject {
  external bool get matches;
}

extension type _Document._(JSObject _) implements JSObject {
  external JSObject createElement(String tag);
}

extension type _Canvas._(JSObject _) implements JSObject {
  external set width(int value);
  external set height(int value);
  // Read as well as written, because assigning either one resets the drawing
  // buffer: presenting compares before it resizes, and a frame the same size
  // as the last leaves the canvas alone.
  external int get width;
  external int get height;
  external _Style get style;
  external void remove();
}

extension type _Style._(JSObject _) implements JSObject {
  external set width(String value);
  external set height(String value);
  external set pointerEvents(String value);
  external set objectFit(String value);
  external set imageRendering(String value);
}

/// The one thing between the platform view registry and the canvas.
///
/// **The registry has no unregister and never will**, so the factory closure it
/// is handed lives for as long as the application does. What that closure holds
/// is this cell rather than the element, so `dispose` has somewhere to put a
/// null: the pin the platform keeps is then a pin on an empty box, and the
/// canvas — with the WebGPU context configured on it — is free.
///
/// The WebGL2 backend cannot do this half. Its canvas *is* the drawing surface,
/// so a factory that stopped handing it over would be a device that had already
/// stopped presenting; here the canvas only receives a copy of a finished
/// frame, and a disposed device has no frames to copy.
final class _CanvasSlot {
  _CanvasSlot(this.element);
  JSObject? element;
}

/// A bind group by what is in it, so two draws binding the same things get the
/// same group.
///
/// Identity throughout, and that is the point: a `GPUTextureView`, a
/// `GPUSampler` and a `GPUBuffer` have no value equality and want none — two
/// views of one texture are two objects a bind group tells apart. It works
/// because the things put in here are themselves cached: a texture makes its
/// view once, a sampler is one object per distinct `SamplerDescriptor`, and a
/// uniform block names the frame arena rather than a slice of it.
final class _BindGroupKey {
  _BindGroupKey(this.layout, this.resources);

  final GPUBindGroupLayout layout;
  final List<Object> resources;

  /// Whether [resource] is one of [resources], by identity.
  bool holds(Object resource) =>
      resources.any((Object held) => identical(held, resource));

  @override
  bool operator ==(Object other) {
    if (other is! _BindGroupKey) return false;
    if (!identical(other.layout, layout)) return false;
    if (other.resources.length != resources.length) return false;
    for (var i = 0; i < resources.length; i++) {
      if (!identical(other.resources[i], resources[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    identityHashCode(layout),
    Object.hashAll(resources.map(identityHashCode)),
  );
}

/// A stage pair by the identity of its two compiled modules.
final class _StagePairKey {
  const _StagePairKey(this.vertex, this.fragment);

  final Object vertex;
  final Object fragment;

  @override
  bool operator ==(Object other) =>
      other is _StagePairKey &&
      identical(other.vertex, vertex) &&
      identical(other.fragment, fragment);

  @override
  int get hashCode =>
      Object.hash(identityHashCode(vertex), identityHashCode(fragment));
}

/// WebGPU as a [GraphicsDevice], and as the compiler its shader libraries reach
/// a browser through.
final class WebGpuDevice extends GraphicsDevice
    with WgslModuleCompiler, EncodedImageUpload {
  // ------------------------------------------------------- what it can do

  /// Every capability, decided once from what the device was granted — see
  /// `webgpuDeviceFeatures`, which is where each answer and each absence is
  /// explained, and which runs on the VM.
  ///
  /// The answers the `supportsX` getters gave before 1.0 are these, read
  /// through `DeviceCapabilityForwarders`, and none of them moved:
  ///
  ///  * **`gpu-timestamps` and `timestamp-query`** where the adapter granted
  ///    `timestamp-query` — `H2`, written per labelled pass and read back a
  ///    frame or two later.
  ///  * **`compute`** always — `H6`: storage buffers, _pipelines built from the
  ///    generated compute table, passes encoded as they go, and a readback
  ///    through a mappable staging buffer.
  ///  * **`float32-filterable`** where the adapter granted it, which [open]
  ///    asks for whenever it is offered; `float32-renderable` is core, so
  ///    `supportsFloat32Filtering` answers exactly what it did.
  ///  * **`independent-blend`** always: every colour target in a WebGPU
  ///    pipeline carries its own equation, and the pipeline signature keys on
  ///    the list of them, so the index has always been honoured here — `R8`
  ///    only asked.
  ///  * **`offscreen-multisample`, `stencil`, `manual-mipmaps`** always.
  ///  * **`blend-constant` never, and the absence is a finding rather than a
  ///    limitation.** See `WebGpuEncoder.setBlendColor`, which is the refusal
  ///    it promises.
  ///  * **`wireframe` never**: WebGPU has no polygon fill mode at all. A
  ///    wireframe here is line primitives and an index buffer built for them,
  ///    which is the renderer's decision — the same answer WebGL2 gives for the
  ///    same reason.
  ///  * **`alpha-to-coverage`** always — `P7`: a pipeline's
  ///    `alphaToCoverageEnabled`, wherever the pass multisamples, which the
  ///    scene pass does at four.
  ///  * **`cube-textures`** always: a cube is a six-layer texture with a
  ///    `"cube"` view over it, and the sky pass needs one.
  ///  * **`render-to-mip-level`** always, and what it turns on is reflection
  ///    probes.
  ///
  /// **The false `render-to-mip-level` used to be was honest when it was
  /// written and had stopped being so.** It was written beside a
  /// [createCubeRenderTarget] that answered null: a probe needs a cube to draw
  /// six views into *and* a chain to convolve them down,
  /// `ReflectionProbeNode.supportedOn` asks for both, and answering yes to the
  /// second while the first was missing would have handed the renderer a probe
  /// and got a crash where a skip belonged. The cube arrived later — the
  /// conformance suite would not let `supportsCubeTextures` promise a face a
  /// pass could name and then hand back nothing — and the answer stayed false,
  /// which by then described no missing work at all. A refusal that outlives
  /// its reason is worse than the gap it once guarded, because nobody goes
  /// looking behind it.
  ///
  /// **There was nothing left to build.** The chain a probe wants is not a
  /// `generateMipmap` — this API has none, and the engine never asks a device
  /// for one. `Renderer._prefilterProbe` writes every level itself, as an
  /// ordinary full-screen pass whose colour target names a face and a level,
  /// and on this backend both of those are one mechanism: `baseArrayLayer`
  /// picks the face and `baseMipLevel` picks the level on a plain 2D view,
  /// which `WebGpuTexture.attachmentView` has always made. The pass's initial
  /// viewport covers the *level* rather than the texture, because WebGPU takes
  /// it from the view's own size, so §7.2's last rule needs no arithmetic here
  /// either.
  ///
  /// What said so is the picture rather than the reading: `probe-car` records
  /// through this backend and lands on Impeller's reference at nought of a
  /// hundred and seventy-two thousand eight hundred pixels, worst channel zero.
  /// `test/reflection_probe_test.dart` asks the question the capability
  /// actually promises: that a mirror ball between a red wall and a blue one
  /// shows each on its own side.
  @override
  late final DeviceFeatures features = webgpuDeviceFeatures(
    granted: _gpuDevice.features.has,
  );

  /// The device's own limits, as granted — [open] asks for no raised ones,
  /// so these are what the adapter gives every device by default — with
  /// three answers of this backend's own:
  ///
  ///  * **`maxColorAttachments` is four — `gfx-50n`.** The specification's
  ///    guaranteed floor, which no device may report below. A constant rather
  ///    than the device's number, because here the floor is the promise and
  ///    it is what `maxColorAttachments` has always answered: a WebGPU device
  ///    that offered fewer would not be a WebGPU device.
  ///  * **`maxSamplerAnisotropy` is sixteen**, which is what this API's
  ///    `maxAnisotropy` tops out at. A sampler asking for more is clamped by
  ///    [_samplerFor] rather than refused.
  ///  * **`maxSampleCount` is four**, the only count above one WebGPU offers.
  @override
  late final DeviceLimits limits = () {
    final l = _gpuDevice.limits;
    return DeviceLimits(
      maxTextureDimension1D: l.maxTextureDimension1D,
      maxTextureDimension2D: l.maxTextureDimension2D,
      maxTextureDimension3D: l.maxTextureDimension3D,
      maxTextureArrayLayers: l.maxTextureArrayLayers,
      maxColorAttachments: 4,
      maxColorAttachmentBytesPerSample: l.maxColorAttachmentBytesPerSample,
      maxSampleCount: 4,
      maxSamplerAnisotropy: 16,
      maxBindGroups: l.maxBindGroups,
      maxSampledTexturesPerShaderStage: l.maxSampledTexturesPerShaderStage,
      maxSamplersPerShaderStage: l.maxSamplersPerShaderStage,
      maxStorageBuffersPerShaderStage: l.maxStorageBuffersPerShaderStage,
      maxStorageTexturesPerShaderStage: l.maxStorageTexturesPerShaderStage,
      maxUniformBuffersPerShaderStage: l.maxUniformBuffersPerShaderStage,
      maxUniformBufferBindingSize: l.maxUniformBufferBindingSize,
      maxStorageBufferBindingSize: l.maxStorageBufferBindingSize,
      maxBufferSize: l.maxBufferSize,
      minUniformBufferOffsetAlignment: l.minUniformBufferOffsetAlignment,
      minStorageBufferOffsetAlignment: l.minStorageBufferOffsetAlignment,
      maxVertexBuffers: l.maxVertexBuffers,
      maxVertexAttributes: l.maxVertexAttributes,
      maxVertexBufferArrayStride: l.maxVertexBufferArrayStride,
      maxInterStageShaderVariables: l.maxInterStageShaderVariables,
      maxComputeWorkgroupStorageSize: l.maxComputeWorkgroupStorageSize,
      maxComputeInvocationsPerWorkgroup: l.maxComputeInvocationsPerWorkgroup,
      maxComputeWorkgroupSizeX: l.maxComputeWorkgroupSizeX,
      maxComputeWorkgroupSizeY: l.maxComputeWorkgroupSizeY,
      maxComputeWorkgroupSizeZ: l.maxComputeWorkgroupSizeZ,
      maxComputeWorkgroupsPerDimension: l.maxComputeWorkgroupsPerDimension,
    );
  }();

  /// What [format] can be used for on what this device was granted — see
  /// `webgpuTextureFormatSupport`. Its `sampled` is what
  /// `supportsTextureFormat` answers.
  ///
  /// **Two questions, and the second is asked of the device rather than of a
  /// table.** A spelling is not permission: `bc7-rgba-unorm` is a name the
  /// specification defines and a device that did not request
  /// `texture-compression-bc` refuses it at allocation and at sampling alike.
  /// [open] asks the adapter which of the three families it carries and
  /// requests exactly those, so what came back is what this reads —
  /// `_gpuDevice.features`, not the list of wants. A device may be granted less
  /// than it asked for, and a capability answering from a wish is how a loader
  /// is told to upload a texture the browser will not take.
  ///
  /// Three formats answer none whatever any adapter carries —
  /// [TextureFormat.a8UNormInt] and the two HDR ASTC layouts — because WebGPU
  /// has no spelling for them at all. See [gpuTextureFormat], which is where
  /// that is written down.
  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      _formatSupport[format] ??= webgpuTextureFormatSupport(
        format,
        granted: _gpuDevice.features.has,
      );

  final Map<TextureFormat, TextureFormatSupport> _formatSupport =
      <TextureFormat, TextureFormatSupport>{};

  void Function(GpuFrameTimings timings)? _timingListener;
  late final WebGpuTimer _timer = WebGpuTimer(_gpuDevice);

  @override
  void onGpuTimings(void Function(GpuFrameTimings timings)? listener) =>
      _timingListener = features.has(DeviceFeature.gpuTimestamps)
      ? listener
      : null;

  @override
  StorageBuffer createStorageBuffer(
    ByteData bytes, {
    bool hostReadable = false,
    bool bindableAsIndices = false,
  }) => _guard(
    'a ${bytes.lengthInBytes}-byte storage buffer',
    () => webgpuCreateStorageBuffer(
      _gpuDevice,
      bytes,
      hostReadable: hostReadable,
      bindableAsIndices: bindableAsIndices,
    ),
  );

  @override
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) {
    final stage = shader.backend;
    if (stage is! WebGpuComputeShader) {
      throw ArgumentError.value(
        shader.name,
        'shader',
        'is not a compute stage on this device',
      );
    }
    return wrapComputePipeline(
      owner: this,
      backend: _guard(
        'the compute pipeline for ${shader.name}',
        () => webgpuCreateComputePipeline(_gpuDevice, stage),
      ),
      shader: shader,
    );
  }

  /// [createComputePipeline] through `createComputePipelineAsync`: a compute
  /// pipeline has no draw state, so the whole of it is realised here, off
  /// the calling turn, and a pipeline the browser refuses completes the
  /// future with the error rather than surfacing later at
  /// [debugDrainErrors].
  @override
  Future<ComputePipelineHandle> createComputePipelineAsync(
    ShaderHandle shader,
  ) async {
    final stage = shader.backend;
    if (stage is! WebGpuComputeShader) {
      throw ArgumentError.value(
        shader.name,
        'shader',
        'is not a compute stage on this device',
      );
    }
    final pipeline = await webgpuCreateComputePipelineAsync(_gpuDevice, stage);
    return wrapComputePipeline(owner: this, backend: pipeline, shader: shader);
  }

  @override
  ComputeEncoder beginComputePass({
    String? label,
    PassTimestampWrites? timestampWrites,
  }) {
    if (timestampWrites != null) {
      features.require(DeviceFeature.timestampQuery, backend: _backend);
    }
    return WebGpuComputeEncoder(
      _gpuDevice,
      features: features,
      samplerFor: _samplerFor,
      label: label,
      timestampWrites: _timestampWritesOf(timestampWrites),
      storageAlignment: limits.minStorageBufferOffsetAlignment,
    );
  }

  /// The caller's [writes] as the API takes them, after the set is checked
  /// to count time.
  GPURenderPassTimestampWrites? _timestampWritesOf(
    PassTimestampWrites? writes,
  ) {
    if (writes == null) return null;
    final set = writes.querySet;
    if (set.type != QueryType.timestamp) {
      throw ArgumentError.value(
        set,
        'timestampWrites',
        'names a ${set.type.name} query set; timestamps go in a timestamp one',
      );
    }
    return gpuTimestampWrites(
      (set.backend as WebGpuQueries).set,
      writes.beginningOfPassIndex,
      writes.endOfPassIndex,
    );
  }

  @override
  Future<ByteData> readBuffer(StorageBuffer buffer) =>
      webgpuReadBuffer(_gpuDevice, buffer);

  @override
  void releaseStorageBuffer(StorageBuffer buffer) =>
      (buffer.backend as WebGpuStorage).buffer.destroy();

  /// `rgba16float` on a display the browser says has a high dynamic range —
  /// `R9` — asked once, when the device is made. A frame in it is presented
  /// through a canvas configured for extended tone mapping; see
  /// [copyToCanvas].
  @override
  List<TextureFormat> get hdrOutputFormats => _hdrDisplay
      ? const <TextureFormat>[TextureFormat.r16g16b16a16Float]
      : const <TextureFormat>[];

  late final bool _hdrDisplay = () {
    try {
      return _matchMedia('(dynamic-range: high)').matches;
    } on Object {
      return false;
    }
  }();

  /// The format the canvas is configured for now: the frame's, since
  /// presenting is a copy and a copy needs the two to match.
  TextureFormat _canvasFormat = TextureFormat.r8g8b8a8UNormInt;

  WebGpuDevice._(this._gpuDevice, this._canvas, this._context, this._stages)
    : _slot = _CanvasSlot(_canvas),
      _uniformArena = WebGpuFrameArena(
        _gpuDevice,
        usage: GpuBufferUsage.uniform,
        // Every implementation so far reports 256 for
        // `minUniformBufferOffsetAlignment`, and a dynamic offset that is not a
        // multiple of it is refused. Stated as a constant rather than read from
        // `limits` because a device that reported less would still accept 256,
        // and one that reported more is a device this arena would have to be
        // rebuilt for anyway.
        alignment: 256,
        label: 'flutter3d uniforms',
      ),
      _vertexArena = WebGpuFrameArena(
        _gpuDevice,
        usage: GpuBufferUsage.vertex,
        alignment: 4,
        label: 'flutter3d vertices',
      ),
      _indexArena = WebGpuFrameArena(
        _gpuDevice,
        usage: GpuBufferUsage.index,
        alignment: 4,
        label: 'flutter3d indices',
      ) {
    _zeroBlock = _gpuDevice.createBuffer(
      GPUBufferDescriptor(
        // 64 KiB is `maxUniformBufferBindingSize`'s guaranteed floor, so no
        // block a shader can declare is larger than this and one buffer covers
        // every unbound one. A WebGPU buffer starts zeroed, which is what makes
        // the fallback read like GL's: a block nobody filled is zeros rather
        // than whatever the last draw left in the arena.
        size: 1 << 16,
        usage: GpuBufferUsage.uniform | GpuBufferUsage.copyDst,
        label: 'flutter3d unbound block',
      ),
    );
  }

  /// Turns [wgsl] into a `GPUShaderModule`, and asks the browser what it
  /// thought of it.
  ///
  /// **Nothing is thrown for text that does not compile, and nothing can be.**
  /// A module is created whether or not the code was valid, the same way a
  /// pipeline is created whether or not the descriptor was — and a bad shader
  /// is not an error scope's business at all: `createShaderModule` succeeds,
  /// and the complaint arrives at the first pipeline built from it as
  /// `[Invalid ShaderModule "X"] is invalid due to a previous error`, naming
  /// neither the line nor what was wrong with it. `getCompilationInfo` has the
  /// line and the column and is a promise, so the verdict cannot reach a caller
  /// standing here. It reaches [debugDrainErrors] instead, which is where a
  /// test — and `open_test.dart`, which is the only thing in this repository
  /// that has ever asked a browser what it makes of the generated WGSL — goes
  /// looking. The WGSL a translator produced is WGSL nobody typed.
  ///
  /// Every module this backend ever compiles goes through here, the engine's
  /// stages and a loaded bundle's alike, so a stage that arrives broken at half
  /// past a reload is reported in the same words as one that shipped broken.
  @override
  Object compileModule(String name, String wgsl) {
    final module = _gpuDevice.createShaderModule(
      GPUShaderModuleDescriptor(code: wgsl, label: name),
    );
    _pending.add(
      module.getCompilationInfo().toDart.then((GPUCompilationInfo info) {
        for (final message in info.messages.toDart) {
          if (message.type != 'error') continue;
          _errors.add(
            'the WGSL of "$name" at line ${message.lineNum}, '
            'column ${message.linePos}: ${message.message}',
          );
        }
      }),
    );
    return module;
  }

  /// Opens a device over a canvas of [width] by [height], with the engine's
  /// own [stages] unless others are given — WGSL translated from
  /// `flutter3d_shaders` by `tool/generate_shaders.dart`, beside the
  /// reflection a `GPUShaderModule` cannot be asked for.
  ///
  /// **Asynchronous, and it is the one place the fourth backend costs anything
  /// outside itself.** `requestAdapter` and `requestDevice` are both promises,
  /// so a WebGPU device cannot be built by a constructor the way the other
  /// three are. Nothing in `flutter3d_hardware` says how a device is made — the
  /// contract starts once one exists — so this costs the contract nothing and
  /// costs whatever chooses a backend an `await`.
  ///
  /// **Throws a [DeviceUnavailableException]** for a browser with no
  /// `navigator.gpu`, for one that hands back no adapter — a machine whose GPU
  /// is blocklisted, which is the common case on an old driver and looks
  /// identical from Dart — and for a canvas that will not give a `webgpu`
  /// context. It answered null before 1.0, and `openWebGpu` turned the null
  /// into this sentence; a caller's move is still to pick another backend,
  /// which `DeviceRegistry.open` does with it.
  ///
  /// **The features are asked for rather than assumed, and only the ones this
  /// adapter admits to having.** A WebGPU device gets exactly what it requested:
  /// sampling a BC7 texture on a device that did not ask for
  /// `texture-compression-bc` is a validation error, not a slow path. The other
  /// half of that rule is the trap — `requestDevice` asked for a feature the
  /// adapter does not carry **rejects the promise** rather than handing back a
  /// device without it, so a list of wants written as a constant is a game that
  /// does not start on the first machine that lacks one of them. The adapter is
  /// asked, the intersection is requested, and [textureFormatSupport] then
  /// answers from `_gpuDevice.features` — what was granted — rather than from
  /// this list, because the two are not the same thing.
  ///
  /// `GpuFeature.requested` is the list: filtering of 32-bit float textures,
  /// the full-precision depth-stencil format, the three block-compression
  /// families a KTX2 asset arrives in, timestamps, and since 1.0 everything
  /// `webgpuDeviceFeatures` reports behind an adapter feature — unclipped
  /// depth, indirect first instance, dual-source and float32 blending,
  /// `rg11b10ufloat` targets, `f16`, subgroups, clip distances and
  /// multi-draw-indirect.
  static Future<WebGpuDevice> open({
    required int width,
    required int height,
    WebGpuSectionStages? stages,
  }) async {
    const unavailable = DeviceUnavailableException(
      'WebGPU is not available in this browser. The engine needs '
      'navigator.gpu and an adapter it will hand out — a browser without '
      'WebGPU, and a machine whose GPU the browser has blocklisted, fail '
      'here the same way.',
      backend: _backend,
    );
    final gpu = gpuNavigator.gpu;
    if (gpu == null) throw unavailable;
    final adapter = await gpu
        .requestAdapter(
          GPURequestAdapterOptions(powerPreference: 'high-performance'),
        )
        .toDart;
    if (adapter == null) throw unavailable;
    final wanted = <String>[
      for (final feature in GpuFeature.requested)
        if (adapter.features.has(feature)) feature,
    ];
    final created = await adapter
        .requestDevice(
          GPUDeviceDescriptor(
            label: 'flutter3d',
            requiredFeatures: gpuStrings(wanted),
          ),
        )
        .toDart;

    final canvas = _document.createElement('canvas') as _Canvas
      ..width = width
      ..height = height;
    final context = GpuCanvas(canvas).getContext('webgpu');
    if (context == null) {
      created.destroy();
      throw const DeviceUnavailableException(
        'WebGPU gave no `webgpu` context for the canvas.',
        backend: _backend,
      );
    }
    context.configure(
      GPUCanvasConfiguration(
        device: created,
        // **Not `getPreferredCanvasFormat`**, and that is a decision rather
        // than an oversight. Presenting here is a texture-to-texture copy, and
        // a copy demands the two formats match; the engine's frame is
        // [defaultColorFormat], so a canvas configured as the machine's
        // preferred `bgra8unorm` would need a whole blit pass to reach. The
        // browser converts on composite instead, once, off the frame's path.
        format: gpuTextureFormat(TextureFormat.r8g8b8a8UNormInt)!,
        // `COPY_DST` and not `RENDER_ATTACHMENT`, for the same reason.
        usage: GpuTextureUsage.copyDst,
        alphaMode: 'opaque',
      ),
    );
    return WebGpuDevice._(
      created,
      canvas,
      context,
      stages ?? webGpuEngineShaders,
    );
  }

  /// The browser's device. The encoder beside this one records into it,
  /// through [WebGpuDeviceInternals].
  final GPUDevice _gpuDevice;

  final _Canvas _canvas;
  final GPUCanvasContext _context;
  final _CanvasSlot _slot;

  final WebGpuSectionStages _stages;

  /// The engine's own stages, compiled on first use.
  ///
  /// **Lazy, where the first version of this file compiled all thirty-nine at
  /// `create`.** A scene binds a handful of them, and compiling the rest is a
  /// pause the frame pays for shaders it never draws with. `late final` rather
  /// than an initialiser because the library is handed `this` as its compiler,
  /// and `this` does not exist yet in an initialiser list.
  late final WebGpuShaderLibrary _library = WebGpuShaderLibrary(this, _stages);

  /// Where a uniform block written this frame lands. See
  /// `webgpu_resources.dart` for why one arena reset per frame is safe.
  final WebGpuFrameArena _uniformArena;

  /// Where `PassEncoder.bindVertexData`'s bytes land.
  final WebGpuFrameArena _vertexArena;

  /// Where `PassEncoder.bindIndexData`'s bytes land.
  final WebGpuFrameArena _indexArena;

  /// Real _pipelines, by the signature that produced each. Shared across passes:
  /// the signature already carries the attachment formats and the sample count.
  final WebGpuPipelineCache<GPURenderPipeline> _pipelines =
      WebGpuPipelineCache<GPURenderPipeline>();

  final Map<_StagePairKey, WebGpuBindingLayouts> _bindingLayouts =
      <_StagePairKey, WebGpuBindingLayouts>{};
  final Map<SamplerDescriptor, GPUSampler> _samplers =
      <SamplerDescriptor, GPUSampler>{};
  final Map<_BindGroupKey, GPUBindGroup> _bindGroups =
      <_BindGroupKey, GPUBindGroup>{};

  final List<WebGpuTexture> _textures = <WebGpuTexture>[];

  /// The mip pass for browser-decoded images, made on the first one.
  late final WebGpuMipBuilder _mips = WebGpuMipBuilder(_gpuDevice);
  final List<GPUBuffer> _buffers = <GPUBuffer>[];

  late final GPUBuffer _zeroBlock;

  bool _disposed = false;

  // -------------------------------------------------------- error scopes

  final List<Future<void>> _pending = <Future<void>>[];
  final List<String> _errors = <String>[];

  /// Runs [body] with a validation scope open, recording whatever the browser
  /// says into [debugDrainErrors].
  ///
  /// **Without this pair nothing WebGPU rejects can ever be seen from Dart.**
  /// The API validates asynchronously: `createRenderPipeline` hands back a
  /// pipeline object whether or not the descriptor was legal, and the complaint
  /// arrives later, on the console, where no Dart program will meet it. A
  /// backend that means to report a refusal has to bracket the call.
  ///
  /// Synchronous in and synchronous out, so the object can be handed on while
  /// the verdict settles behind it — which is what makes this affordable at
  /// all. It is used on the calls that are rare and expensive: making a
  /// texture, a buffer, a pipeline, a bind group, and submitting a pass.
  /// Wrapping a per-draw call would add a promise per draw.
  T _guard<T>(String what, T Function() body) {
    _gpuDevice.pushErrorScope(GpuErrorFilter.validation);
    final T result;
    try {
      result = body();
    } catch (_) {
      // Popped either way: an unbalanced scope makes the *next* pop answer for
      // this call's errors, which reports the mistake against whatever ran
      // afterwards.
      _pending.add(_gpuDevice.popErrorScope().toDart.then((GPUError? _) {}));
      rethrow;
    }
    _pending.add(
      _gpuDevice.popErrorScope().toDart.then((GPUError? error) {
        if (error != null) _errors.add('$what: ${error.message}');
      }),
    );
    return result;
  }

  /// Everything the browser complained about since the last drain, or null when
  /// it complained about nothing.
  ///
  /// Asynchronous because the verdicts are: every scope [_guard] opened is a
  /// promise, and this waits for the ones outstanding before answering. A test
  /// that draws and then asks gets the truth; a caller that never asks pays for
  /// the scopes and nothing else.
  Future<String?> debugDrainErrors([String where = '']) async {
    final outstanding = List<Future<void>>.of(_pending);
    _pending.clear();
    await Future.wait(outstanding);
    if (_errors.isEmpty) return null;
    final said = _errors.join('; ');
    _errors.clear();
    return where.isEmpty ? said : '$where: $said';
  }

  // -------------------------------------------------------- the caches

  /// The bind group layouts [pipeline]'s stage pair needs, made once.
  ///
  /// Keyed on the pair's compiled modules rather than on the pipeline object,
  /// because the layouts come out of the two stages' reflection and nothing
  /// else: two _pipelines over one pair with different vertex layouts are two
  /// _pipelines and one set of bind group layouts.
  ///
  /// **Not on the pair's name.** A reload replaces the code *and* the
  /// reflection behind a name, and a layered library answers a name the
  /// engine's library also answers; a name-keyed cache handed either of those
  /// the layouts of whichever pair was drawn first.
  WebGpuBindingLayouts _bindingsFor(WebGpuPipeline pipeline) =>
      _bindingLayouts[_StagePairKey(
        pipeline.vertexModule,
        pipeline.fragmentModule,
      )] ??= _guard(
        'the bind group layouts of ${pipeline.name}',
        () => WebGpuBindingLayouts.of(_gpuDevice, pipeline),
      );

  /// The sampler object for [options], made once per distinct description.
  ///
  /// **This is where all of the WebGL2 backend's sampler trouble disappears.**
  /// In GL the filter and the wrap modes are properties of the *texture*, so
  /// that backend sets four `texParameteri` on every bind and one image bound
  /// twice with two descriptions keeps whichever came last. WebGPU has real
  /// sampler objects compared by value, `SamplerDescriptor` already is a value,
  /// and so a map is the whole of it.
  ///
  /// [SamplerDescriptor.anisotropy] is clamped to `limits.maxSamplerAnisotropy` rather than
  /// refused, which is the contract's own rule: a caller may ask for sixteen
  /// without asking first.
  ///
  /// Since 1.0 every field reaches the descriptor: the third axis is
  /// [SamplerDescriptor.depthAddressMode] (a 2D or cube texture ignores it, so
  /// no existing sampler samples differently), the level clamps are the
  /// options' own — their defaults are the whole chain the constants here
  /// always asked for — and a compare function makes a comparison sampler,
  /// which is a different kind of object in this API. A border colour is
  /// refused, by [webgpuCheckSampler], before anything is made.
  GPUSampler _samplerFor(SamplerDescriptor options) {
    final cached = _samplers[options];
    if (cached != null) return cached;
    webgpuCheckSampler(features, options);
    final anisotropy = options.anisotropy > limits.maxSamplerAnisotropy
        ? limits.maxSamplerAnisotropy
        : options.anisotropy;
    final compare = options.compare;
    return _samplers[options] = _gpuDevice.createSampler(
      compare == null
          ? GPUSamplerDescriptor(
              addressModeU: gpuAddressMode(options.widthAddressMode),
              addressModeV: gpuAddressMode(options.heightAddressMode),
              addressModeW: gpuAddressMode(options.depthAddressMode),
              magFilter: gpuFilterMode(options.magFilter),
              minFilter: gpuFilterMode(options.minFilter),
              mipmapFilter: gpuMipmapFilterMode(options.mipFilter),
              lodMinClamp: options.lodMinClamp,
              lodMaxClamp: options.lodMaxClamp,
              maxAnisotropy: anisotropy,
              label: options.toString(),
            )
          : GPUSamplerDescriptor.comparison(
              addressModeU: gpuAddressMode(options.widthAddressMode),
              addressModeV: gpuAddressMode(options.heightAddressMode),
              addressModeW: gpuAddressMode(options.depthAddressMode),
              magFilter: gpuFilterMode(options.magFilter),
              minFilter: gpuFilterMode(options.minFilter),
              mipmapFilter: gpuMipmapFilterMode(options.mipFilter),
              compare: gpuCompareFunction(compare),
              lodMinClamp: options.lodMinClamp,
              lodMaxClamp: options.lodMaxClamp,
              maxAnisotropy: anisotropy,
              label: options.toString(),
            ),
    );
  }

  /// The bind group for one `@group` of [layouts], assembled from what the pass
  /// has bound and cached by what went into it.
  ///
  /// A binding the pass never filled gets a neutral resource rather than being
  /// left out: WebGPU refuses an incomplete group outright. An unfilled block
  /// reads the zeroed buffer and an unfilled sampler a white texel.
  ///
  /// **And says so, into [debugDrainErrors].** The contract makes a declared
  /// slot left unbound the caller's mistake, and this is the one backend that
  /// sees every stage's declarations at the draw. It used to fill the hole in
  /// silence, which made it the backend that drew cleanly through the 0.7.2
  /// regression that Metal failed on natively.
  GPUBindGroup _bindGroupFor(
    WebGpuBindingLayouts layouts,
    int group,
    Map<int, WebGpuSlice>? blocks,
    Map<int, GPUTextureView>? views,
    Map<int, GPUSampler>? samplers,
  ) {
    final shape = layouts.shapes[group];
    final resources = <Object>[];
    final entries = <GPUBindGroupEntry>[];
    for (final bound in shape.blocks) {
      final block = bound.block;
      final filled = blocks?[block.binding]?.buffer;
      if (filled == null && bound.bindable) {
        _unbound('uniform block "${block.name}"');
      }
      final buffer = filled ?? _zeroBlock;
      resources.add(buffer);
      entries.add(
        GPUBindGroupEntry.buffer(
          binding: block.binding,
          // Offset zero and the block's own size: the offset a draw actually
          // wants rides on `setBindGroup` instead, which is what
          // `hasDynamicOffset` bought.
          resource: GPUBufferBinding(
            buffer: buffer,
            offset: 0,
            size: block.sizeInBytes,
          ),
        ),
      );
    }
    for (final bound in shape.samplers) {
      final sampler = bound.sampler;
      final filledView = views?[sampler.textureBinding];
      if (filledView == null && bound.bindable) {
        _unbound('sampler "${sampler.name}"');
      }
      final view =
          filledView ??
          _blankView(sampler.dimension, depth: sampler.comparison);
      final object =
          samplers?[sampler.samplerBinding] ??
          _samplerFor(
            sampler.comparison
                ? _blankComparison
                : SamplerDescriptor.linearRepeat,
          );
      resources
        ..add(view)
        ..add(object);
      entries
        ..add(
          GPUBindGroupEntry.textureView(
            binding: sampler.textureBinding,
            resource: view,
          ),
        )
        ..add(
          GPUBindGroupEntry.sampler(
            binding: sampler.samplerBinding,
            resource: object,
          ),
        );
    }
    return _bindGroups[_BindGroupKey(
      layouts.groups[group],
      resources,
    )] ??= _guard(
      'a bind group for group $group',
      () => _gpuDevice.createBindGroup(
        GPUBindGroupDescriptor(
          layout: layouts.groups[group],
          entries: entries.toJS,
          label: 'group $group',
        ),
      ),
    );
  }

  /// Reports a declared slot a draw left unbound, once per slot per device, so
  /// a mistake repeated every frame is one line and not a flood.
  void _unbound(String what) {
    if (_reportedUnbound.add(what)) {
      _errors.add('$what is declared and nothing was bound to it');
    }
  }

  final Set<String> _reportedUnbound = <String>{};

  /// One white texel — or one zero depth, for a comparison slot — in the
  /// shape a slot with nothing bound to it wants.
  ///
  /// Made on first need rather than at startup, because a bundle whose stages
  /// declare no sampler never asks — and because a device that allocated for a
  /// case that never happens is a device counting resources it did not need.
  GPUTextureView _blankView(
    WebGpuTextureDimension dimension, {
    bool depth = false,
  }) => (_blanks[(dimension, depth)] ??= webgpuCreateBlank(
    _gpuDevice,
    _textures,
    dimension,
    depth: depth,
  )).sampledView;

  final Map<(WebGpuTextureDimension, bool), WebGpuTexture> _blanks =
      <(WebGpuTextureDimension, bool), WebGpuTexture>{};

  /// What an unbound comparison slot samples with: a comparison slot takes a
  /// comparison sampler, whatever is behind it.
  static const SamplerDescriptor _blankComparison = SamplerDescriptor(
    compare: CompareFunction.lessEqual,
  );

  /// Every GPU object this device owns and would have to release: the textures
  /// and geometry it handed out, the frame arenas and fallbacks it made for
  /// itself, and the modules, layouts, samplers, bind groups and _pipelines it
  /// cached.
  ///
  /// **Not zero on a fresh device**, unlike the WebGL2 backend's count of the
  /// same name, and the difference is a fact about the two APIs rather than
  /// about the two implementations: this one allocates three arena buffers and
  /// a zeroed block before it is asked for anything. What it is for is the same
  /// — a leak is a number that climbs while a frame repeats — and it falls to
  /// zero after [dispose] just the same.
  /// How many distinct sampler objects this device has made.
  ///
  /// Diagnostic, and the number that says whether [_samplerFor] is doing its
  /// job: a frame binding a hundred textures with `SamplerDescriptor.linearRepeat`
  /// should leave this at one. Read by `webgpu_draw_test.dart`, which is the
  /// only way to tell a cache hit from an allocation that happened to look the
  /// same.
  int get debugSamplerCount => _samplers.length;

  /// How many distinct bind groups this device has assembled. Diagnostic, for
  /// the reason [debugSamplerCount] is: the dynamic offset on a uniform block
  /// exists to keep this number small, and nothing else would notice if it
  /// stopped working.
  int get debugBindGroupCount => _bindGroups.length;

  int get debugTrackedResourceCount =>
      _textures.length +
      _buffers.length +
      _uniformArena.bufferCount +
      _vertexArena.bufferCount +
      _indexArena.bufferCount +
      (_disposed ? 0 : 1) +
      _library.debugTrackedModuleCount +
      _bindingLayouts.length +
      _samplers.length +
      _bindGroups.length +
      _pipelines.length;

  // ------------------------------------------------------- the conventions

  /// Top left, like Metal and Impeller and unlike OpenGL. WebGPU's framebuffer
  /// coordinates start at the top left corner and its attachments are written
  /// from there, so nothing has to be turned over anywhere: an uploaded image
  /// and a rendered one are the same way up, which is the pair the WebGL2
  /// backend has to keep apart with a flag on every texture.
  @override
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  /// Near at zero, far at one. The engine builds its projections for this and
  /// corrects at the boundary for a backend that says otherwise, so this is the
  /// case that needs no correction.
  @override
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  /// `depth32float-stencil8` where the adapter granted it, and
  /// `depth24plus-stencil8` where it did not — `A2.8`. A float is what lets
  /// `RenderSettings.reversedDepth` keep its precision to the horizon, which
  /// is why [features] reports `DeviceFeature.reversedDepth` exactly where
  /// this answers the first; `depth24plus` may be stored either way, and the
  /// browser does not say which.
  @override
  TextureFormat get defaultDepthStencilFormat =>
      _gpuDevice.features.has(GpuFeature.depth32FloatStencil8)
      ? TextureFormat.d32FloatS8UInt
      : TextureFormat.d24UnormS8Uint;

  @override
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  /// Four, which is the only multisample count above one WebGPU guarantees.
  @override
  int get preferredSampleCount => 4;

  // The superseded `supportsX` getters, `maxAnisotropy`,
  // `maxColorAttachments` and `supportsTextureFormat` are answered by
  // `DeviceCapabilityForwarders` from [features], [limits] and
  // [textureFormatSupport]; the prose that explained each answer moved there.

  @override
  ShaderLibrary get shaders => _library;

  // ------------------------------------------------------------- resources

  /// Whether `deviceTransient` targets are allocated as WebGPU transient
  /// attachments — `H7`. Asked of the browser once, since the answer is a
  /// property of its API and not of this device.
  late final bool _transientAttachments = gpuKnowsTransientAttachments();

  TextureHandle _createTarget(RenderTargetDescriptor spec) => _guard(
    'a ${spec.width}x${spec.height} ${spec.format.name} target',
    () => webgpuCreateTexture(
      _gpuDevice,
      _textures,
      spec,
      transientAttachments: _transientAttachments,
    ),
  );

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) =>
      _guard(
        'a ${width}x$height ${format.name} image',
        () => webgpuCreateTextureFromPixels(
          _gpuDevice,
          _textures,
          width: width,
          height: height,
          format: format,
          pixels: pixels,
          mipLevels: mipLevels,
        ),
      ) ??
      (throw refuseResource(
        'createTextureFromPixels',
        'the pixels (or a mip level) are not the size a ${width}x$height '
            '${format.name} texture needs, or this device has no spelling '
            'for the format',
      ));

  /// Decoded by the browser, copied in with `copyExternalImageToTexture`,
  /// and given a chain drawn level by level on the GPU — `A4.16`. See
  /// `webgpu_image_decode.dart`.
  ///
  /// [maxDimension] is held to the device's own `maxTextureDimension2D` as
  /// well, so no cap still means an image the device can allocate.
  @override
  Future<TextureHandle?> decodeTexture(
    Uint8List encoded, {
    bool mipmaps = false,
    int? maxDimension,
  }) {
    final limit = limits.maxTextureDimension2D;
    final cap = maxDimension == null || maxDimension > limit
        ? limit
        : maxDimension;
    return webgpuCreateTextureFromEncodedImage(
      _gpuDevice,
      _textures,
      _mips,
      encoded,
      mipmaps: mipmaps,
      guard: _guard,
      maxDimension: cap,
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
    _guard(
      'a ${rect.width}x${rect.height} region overwrite',
      () => webgpuOverwriteTexture(_gpuDevice, target, rgba, rect),
    );
  }

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) =>
      _guard(
        'a ${size}x$size ${format.name} cube',
        () => webgpuCreateCubeTextureFromPixels(
          _gpuDevice,
          _textures,
          size: size,
          format: format,
          faces: faces,
          mipLevels: mipLevels,
        ),
      ) ??
      (throw refuseResource(
        'createCubeTextureFromPixels',
        'six ${size}x$size ${format.name} faces (and a chain of six a '
            'level, each half the last) were not what was given, or this '
            'device has no spelling for the format',
      ));

  /// A cube a pass may aim at one face and one level of.
  ///
  /// **This used to be null, and the conformance suite is what said it could
  /// not stay null** — and since 1.0 nothing here answers null: a format
  /// with no renderable spelling is refused with a `DeviceResourceException`. The argument for the null was that a cube a probe can
  /// draw into is only useful beside a chain it can filter into, so the two
  /// should arrive together — but `DeviceFeature.cubeTextures` answering true is a
  /// promise about more than sampling: the suite reads it as "a pass can name a
  /// face of a cube", clears three of them and reads them back, and a backend
  /// that answered true and then handed back no cube failed that check rather
  /// than declining it. It was a gap wearing a refusal's clothes.
  ///
  /// The chain arrived with it and went unclaimed for a while: [mipLevels] has
  /// been honoured here since the cube was, and `DeviceFeature.renderToMipLevel` went on
  /// saying no. Both halves `ReflectionProbeNode.supportedOn` asks for are yes
  /// now. Six array layers and a view per face and level is
  /// `webgpu_resources.dart`'s whole answer.
  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) =>
      _guard(
        'a ${size}x$size ${format.name} cube target',
        () => webgpuCreateCubeRenderTarget(
          _gpuDevice,
          _textures,
          size: size,
          format: format,
          mipLevels: mipLevels,
        ),
      ) ??
      (throw refuseResource(
        'createCubeRenderTarget',
        'this device has no renderable spelling for ${format.name}',
      ));

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) => _guard(
    'a ${bytes.lengthInBytes}-byte ${usage.name} buffer',
    () => webgpuUploadGeometry(
      _gpuDevice,
      _buffers,
      bytes,
      usage,
      release: releaseGeometry,
    ),
  );

  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) => _guard(
    'a ${bytes.lengthInBytes}-byte overwrite at $offsetInBytes',
    () => webgpuOverwriteGeometry(_gpuDevice, target, offsetInBytes, bytes),
  );

  /// Records the stage pair, its layout and the reflection a bind group will
  /// need. Nothing is built: see [WebGpuPipeline], and `webgpu_encoder.dart`
  /// for what a draw does with it.
  ///
  /// The contract calls this expensive and tells callers to cache. Here it is
  /// nearly free and the expense moves to the first draw of each distinct
  /// state — which is not a contract change, but it does make the advice
  /// describe the other end of the frame.
  ///
  /// **The two stages' modules are captured, not looked up again.** That is
  /// what keeps [loadShaders]'s reload promise: a bundle refreshed under a
  /// renderer replaces the code behind a `ShaderHandle`, and a pipeline built
  /// before the refresh goes on drawing the code it was built from until
  /// `Renderer.relinkShaders` builds another. A frame in between is the old
  /// picture rather than a missing one.
  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) => createWebGpuPipeline(vertex, fragment, layout: layout);

  /// [createPipeline], and the real pipelines it will need **built off the
  /// calling turn**, through `createRenderPipelineAsync`.
  ///
  /// **What can be realised up front, and what cannot.** A pipeline here is
  /// a stage pair until a draw says the rest: the targets it draws into, the
  /// blend, the depth test, the cull, the stencil. Those are baked into a
  /// `GPURenderPipeline`, one per distinct state, and none of them is in
  /// this call. So the pair is recorded as [createPipeline] records it, and
  /// then **warmed**: built asynchronously in every draw state this device
  /// has already built a pipeline in (the most recent
  /// [warmStateLimit] of them), and kept in the same cache a draw looks in.
  /// A draw in one of those states then finds its pipeline ready; a draw in
  /// a state nobody drew before builds it synchronously, as always.
  ///
  /// The future completes when the warming has settled. A pipeline the
  /// browser refuses in one of those states is skipped — the state was a
  /// guess, and a draw that really asks for it builds it and reports why at
  /// [debugDrainErrors] — while a pair that cannot be recorded at all (two
  /// fragment stages, a stage from another backend, a layout that misses an
  /// input) completes the future with the error.
  @override
  Future<PipelineHandle> createPipelineAsync(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) async {
    final handle = createWebGpuPipeline(vertex, fragment, layout: layout);
    final pipeline = handle.backend as WebGpuPipeline;
    final layouts = _bindingsFor(pipeline);
    await Future.wait(<Future<void>>[
      for (final state in _drawStates.values.toList())
        _warm(pipeline, layouts, state.forPipeline(pipeline)),
    ]);
    return handle;
  }

  /// Builds [pipeline] in [state] through `createRenderPipelineAsync`, unless
  /// a draw already built it, and keeps it where a draw looks.
  Future<void> _warm(
    WebGpuPipeline pipeline,
    WebGpuBindingLayouts layouts,
    WebGpuDrawState state,
  ) async {
    if (_pipelines.contains(state.signature)) return;
    try {
      final built = await _gpuDevice
          .createRenderPipelineAsync(
            webgpuRenderPipelineDescriptor(pipeline, layouts, state),
          )
          .toDart;
      if (_disposed) return;
      _pipelines.offer(state.signature, built);
      _warmed++;
    } on Object {
      // A guess the pair cannot be drawn in; see `createPipelineAsync`.
      _warmRefused++;
    }
  }

  /// How many draw states [createPipelineAsync] warms a new pair in, at most:
  /// the most recently built distinct ones.
  static const int warmStateLimit = 32;

  /// The draw states this device has built a pipeline in, by
  /// `WebGpuDrawState.stateKey`, oldest first.
  final Map<Object, WebGpuDrawState> _drawStates = <Object, WebGpuDrawState>{};

  /// Remembers [state] as one a new pair is warmed in — called by a draw that
  /// builds a pipeline, not by every draw.
  void _rememberDrawState(WebGpuDrawState state) {
    final key = state.stateKey;
    _drawStates
      ..remove(key)
      ..[key] = state;
    if (_drawStates.length > warmStateLimit) {
      _drawStates.remove(_drawStates.keys.first);
    }
  }

  /// How many pipelines [createPipelineAsync] built ahead of a draw, and how
  /// many states it tried that the browser refused, for a test.
  int get debugWarmedPipelines => _warmed;
  int get debugWarmRefused => _warmRefused;
  int _warmed = 0;
  int _warmRefused = 0;

  /// The bundle's own WGSL, compiled by this device, as a library that can be
  /// reloaded.
  ///
  /// **Four lines, because the two halves meet at [compileModule].** The
  /// section codec is `webgpu_bundle_section.dart`, the refusals and the reload
  /// are `webgpu_loaded_shaders.dart`, and what this device contributes is the
  /// one thing neither can do without a browser: turning text into a module.
  /// The library is built synchronously and the future is the signature's, not
  /// a promise of work — nothing here waits on the GPU, and a browser's opinion
  /// of the WGSL arrives at [debugDrainErrors] the way [compileModule]
  /// describes.
  ///
  /// Refuses by name — [ShaderBundleException] — for a bundle with no section for
  /// this backend, a section that is not the document the codec reads, and one
  /// written to a version of that document this build does not know.
  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async =>
      WebGpuLoadedShaderLibrary.load(this, bytes);

  @override
  String get backendName => _backend;

  // -------------------------------------------------- 1.0: loss and labels

  /// The device's `lost` promise, as [GraphicsDevice.lost]: one event, never
  /// recoverable — a WebGPU device that is lost stays lost, and the
  /// application opens another.
  @override
  Stream<DeviceLoss> get lost => _lost.stream;

  @override
  bool get isLost => _isLost;
  bool _isLost = false;

  late final StreamController<DeviceLoss> _lost =
      StreamController<DeviceLoss>.broadcast(onListen: _watchLoss);
  bool _watchingLoss = false;

  void _watchLoss() {
    if (_watchingLoss) return;
    _watchingLoss = true;
    unawaited(
      _gpuDevice.lost.toDart.then((GPUDeviceLostInfo info) {
        _isLost = true;
        if (_lost.isClosed) return;
        _lost.add(
          DeviceLoss(
            reason: info.reason == 'destroyed'
                ? DeviceLossReason.destroyed
                : DeviceLossReason.unknown,
            message: info.message,
          ),
        );
      }),
    );
  }

  /// Passes the label to the browser, which names the object in its own
  /// validation errors and in a frame capture, and keeps it for [labelOf].
  @override
  void setLabel(Object resource, String label) {
    super.setLabel(resource, label);
    final backend = switch (resource) {
      TextureHandle(:final backend) => backend,
      StorageBuffer(:final backend) => backend,
      QuerySet(:final backend) => backend,
      ComputePipelineHandle(:final backend) => backend,
      _ => null,
    };
    switch (backend) {
      case WebGpuTexture(:final texture):
        texture.label = label;
      case WebGpuStorage(:final buffer):
        buffer.label = label;
      case GPUQuerySet():
        backend.label = label;
      case WebGpuComputePipeline(:final pipeline):
        pipeline.label = label;
    }
  }

  @override
  void releaseTexture(TextureHandle texture) {
    final backend = texture.backend;
    if (backend is! WebGpuTexture) return;
    if (!webgpuReleaseTexture(backend, _textures)) return;
    // The bind groups that named this texture go with it. The cache is keyed
    // by identity, so nothing would ever ask for them again — but it holds
    // them, and through them a destroyed texture's view, for the life of the
    // device: every resize remakes the full-screen targets and would leave one
    // more generation of groups behind.
    final views = backend.madeViews.toList();
    if (views.isNotEmpty) {
      _bindGroups.removeWhere(
        (_BindGroupKey key, GPUBindGroup _) => key.resources.any(
          (Object it) => views.any((GPUTextureView v) => identical(it, v)),
        ),
      );
    }
  }

  @override
  void releaseGeometry(GeometryBuffer geometry) =>
      webgpuReleaseGeometry(geometry.backend, _buffers);

  /// Drops the `GPUSampler` made for [sampler], and every cached bind group
  /// that holds it, so the object can be collected: WebGPU has no
  /// `destroy` for a sampler. The next bind of an equal description makes
  /// a new one.
  @override
  void releaseSampler(SamplerDescriptor sampler) {
    final gone = _samplers.remove(sampler);
    if (gone == null) return;
    _bindGroups.removeWhere((_BindGroupKey key, _) => key.holds(gone));
  }

  // ---------------------------------------------------------------- frame

  /// Rewinds the three frame arenas.
  ///
  /// This is the member `GraphicsDevice.beginFrame` exists for, and the one
  /// backend of the four with something real to do in it. See
  /// `webgpu_resources.dart` for why rewinding under a frame the GPU has not
  /// finished with is safe, which is the only surprising thing about it.
  @override
  void beginFrame() {
    _timer.endFrame(_timingListener);
    _uniformArena.reset();
    _vertexArena.reset();
    _indexArena.reset();
  }

  @override
  void onFrameComplete(void Function() whenDone) {
    unawaited(
      _gpuDevice.queue.onSubmittedWorkDone().toDart.then((JSAny? _) {
        whenDone();
      }),
    );
  }

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    // `gfx-50n`. WebGPU validates this itself and reports it on the device's
    // error scope, which arrives asynchronously and after the frame; the
    // throw says the same thing where the caller still is.
    descriptor
      ..checkAttachmentLimit(
        limits.maxColorAttachments,
        backend: 'this WebGPU device',
      )
      // Layers, levels, the occlusion set and timestamp writes, refused by
      // the feature they need before any handle is looked at.
      ..checkFeatures(features, backend: _backend);
    final occlusion = descriptor.occlusionQuerySet;
    if (occlusion != null && occlusion.type != QueryType.occlusion) {
      throw ArgumentError.value(
        occlusion,
        'occlusionQuerySet',
        'is a ${occlusion.type.name} query set',
      );
    }
    final label = descriptor.label;
    // The caller's own timestamp writes win over `H2`'s per-pass timing: a
    // pass writes into one set, and the caller asked for theirs by name.
    final timestamps =
        _timestampWritesOf(descriptor.timestampWrites) ??
        (_timingListener != null && label != null ? _timer.next(label) : null);
    return WebGpuEncoder(this, descriptor, timestampWrites: timestamps);
  }

  // --------------------------------------------------------------- output

  /// Copies [frame] into the canvas the browser composites.
  ///
  /// `WebGpuFramePresenter` in this same package calls this, then
  /// [applyCanvasStyle], before building the `HtmlElementView` that shows
  /// [viewType].
  ///
  /// **A copy rather than a render**, because `getCurrentTexture` is valid only
  /// for the task it was asked in and cannot be held across an `await`. The
  /// engine's target already exists and the copy is one command on an encoder
  /// submitted immediately — the same one GPU copy the WebGL2 backend's
  /// presenting blit is, arrived at from the other side.
  void copyToCanvas(TextureHandle frame) {
    // **The canvas takes the frame's size, and the clamp below is no longer the
    // thing that reconciles them.** A frame is as big as the surface asked for
    // — `SceneSurface` renders at the layout size times the device pixel ratio
    // — while the canvas was made once, at whatever `openDevice` was given.
    // Those are different numbers on any display with a ratio above one, and a
    // texture-to-texture copy cannot scale: it took the frame's top-left corner
    // the size of the canvas, and CSS then stretched that corner over the whole
    // element. What the player saw was a magnified crop whose optical centre
    // sat below and to the right of the middle of the screen — so a shot down
    // the camera's axis landed there rather than under the crosshair, which is
    // drawn at the centre by Flutter.
    //
    // Resizing the canvas is what makes the copy one-to-one; the scaling is
    // CSS's, which is what `objectFit` in [applyCanvasStyle] has always been
    // for. The WebGPU context keeps its configuration across a resize and
    // hands back a texture of the new size, so nothing has to be
    // reconfigured here.
    if (_canvas.width != frame.width || _canvas.height != frame.height) {
      _canvas
        ..width = frame.width
        ..height = frame.height;
    }
    // `R9`: an extended-range frame needs a canvas of its format, composited
    // with extended tone mapping; a standard one goes back to the canvas it
    // had. Reconfigured only when the format changes.
    if (frame.format != _canvasFormat) {
      final extended = frame.format != TextureFormat.r8g8b8a8UNormInt;
      _context.configure(
        GPUCanvasConfiguration(
          device: _gpuDevice,
          format: gpuTextureFormat(frame.format)!,
          usage: GpuTextureUsage.copyDst,
          alphaMode: 'opaque',
          toneMapping: GPUCanvasToneMapping(
            mode: extended ? 'extended' : 'standard',
          ),
        ),
      );
      _canvasFormat = frame.format;
    }
    final target = _context.getCurrentTexture();
    final source = frame.backend as WebGpuTexture;
    final width = frame.width < target.width ? frame.width : target.width;
    final height = frame.height < target.height ? frame.height : target.height;
    _guard('the copy that presents a frame', () {
      final encoder = _gpuDevice.createCommandEncoder()
        ..copyTextureToTexture(
          GPUTexelCopyTextureInfo(
            texture: source.texture,
            mipLevel: 0,
            origin: GPUOrigin3DDict(x: 0, y: 0, z: 0),
            aspect: 'all',
          ),
          GPUTexelCopyTextureInfo(
            texture: target,
            mipLevel: 0,
            origin: GPUOrigin3DDict(x: 0, y: 0, z: 0),
            aspect: 'all',
          ),
          GPUExtent3DDict(width: width, height: height, depthOrArrayLayers: 1),
        );
      _gpuDevice.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    });
  }

  /// Styles the canvas through CSS, honouring [fit] and [quality] the way
  /// Flutter would if it composited these pixels itself.
  ///
  /// A method here rather than a public canvas, because this package depends
  /// on neither `package:web` nor anything else that would hand an element to
  /// a caller outside this file — see this file's own top-of-file doc comment.
  /// `WebGlDevice` exposes its canvas directly for the same job because its
  /// canvas already depends on `package:web`; this device's does not, and
  /// keeping `_Canvas`/`_Style` private is what lets it stay that way.
  void applyCanvasStyle({
    BoxFit fit = BoxFit.fill,
    FilterQuality quality = FilterQuality.none,
  }) {
    _canvas.style
      ..width = '100%'
      ..height = '100%'
      // A display surface, not a control. Left interactive, the canvas takes
      // the pointer events over it and the Flutter widgets above the platform
      // view never see them — which reads as an application whose camera does
      // not turn while its keyboard works fine.
      ..pointerEvents = 'none'
      ..objectFit = switch (fit) {
        BoxFit.contain => 'contain',
        BoxFit.cover => 'cover',
        BoxFit.fill => 'fill',
        BoxFit.fitWidth ||
        BoxFit.fitHeight ||
        BoxFit.none ||
        BoxFit.scaleDown => 'contain',
      }
      ..imageRendering = quality == FilterQuality.none ? 'pixelated' : 'auto';
  }

  /// The platform view type this device's canvas is registered under.
  ///
  /// The registry has no unregister and never will, so the factory closure
  /// outlives [dispose] whatever anybody does. What it holds is [_CanvasSlot]
  /// rather than the element, so the pin the platform keeps is a pin on a box
  /// this device is able to empty — which, together with unconfiguring the
  /// context and destroying the device, is a genuinely complete teardown. The
  /// WebGL2 backend cannot get that far and says so.
  late final String viewType = _register();

  String _register() {
    final type = 'flutter3d-webgpu-${identityHashCode(this)}';
    final slot = _slot;
    ui_web.platformViewRegistry.registerViewFactory(
      type,
      (int viewId) => slot.element ?? _document.createElement('div'),
    );
    return type;
  }

  /// The texture's pixels, premultiplied RGBA8, rows from the top.
  ///
  /// **A copy for the eight-bit layouts and a conversion pass for a float one,
  /// because WebGPU's copy has no opinion about format.** `glReadPixels` is
  /// asked for RGBA and UNSIGNED_BYTE and the driver converts on the way out;
  /// `copyTextureToBuffer` hands over the bytes as they are stored, so a
  /// `rgba16float` target copied straight out is half-floats wearing the name of
  /// a picture. The contract names this method as *the* way to read a float
  /// target — `GraphicsDevice.readback` refuses one above every backend and says
  /// so — and a backend that answered null here left the contract with no answer
  /// at all on this API.
  ///
  /// So a float target is drawn into an `r8g8b8a8UNormInt` target of the same
  /// size by [_toEightBit] and the copy is made from that. **The price is a
  /// full-screen pass and a second allocation per call**, both of which are why
  /// the eight-bit path is still a plain copy: every golden this repository
  /// records reads back the frame, and the frame is already eight-bit. A value
  /// outside `[0, 1]` is clamped rather than wrapped — by the `rgba8unorm`
  /// target rather than by the shader, see [_conversionModule] — which is what
  /// the software rasteriser's own float-to-byte does and what a caller
  /// comparing against a PNG is asking for.
  ///
  /// Refused with a `DeviceResourceException` where the texture has nothing
  /// to read:
  ///
  ///  * an attachment-only allocation — this backend's translation of
  ///    `deviceTransient` tile memory, which holds nothing after the pass;
  ///  * a **multisampled** target, which is a refusal shared with every other
  ///    backend rather than one of this backend's own. `readbackRegionOf`
  ///    refuses it for `readback` in words — "has no pixels to copy until a pass
  ///    resolves it" — GL cannot `readPixels` a multisampled read framebuffer,
  ///    and here it is refused twice over: a multisampled target is allocated
  ///    without `TEXTURE_BINDING`, so the conversion pass could not sample one
  ///    either. Read the resolve target;
  ///  * a cube or any other non-2D texture, which is a readback of six pictures
  ///    where the interface names one;
  ///  * a block-compressed texture, which has no eight-bit bytes to hand back
  ///    and cannot be sampled into a target through a pass that assumes one
  ///    texel is one texel;
  ///  * an sRGB layout, and this one is a decision rather than a gap.
  ///    `readbackFormats` leaves the sRGB twins out because the backends
  ///    disagree about whether a readback decodes: one hands back the stored
  ///    bytes and another the linear values they stand for. A conversion pass
  ///    here would sample the texture, which *decodes*, and so would invent a
  ///    third answer. The caller's move is the one that message already names —
  ///    read the same texture through its non-sRGB layout.
  Future<ByteData> _readConverted(TextureHandle texture) async {
    final backend = texture.backend;
    if (backend is! WebGpuTexture || !backend.sampleable) {
      throw refuseResource(
        'readback',
        'the texture is an attachment-only allocation with nothing to read',
      );
    }
    if (texture.sampleCount != 1 ||
        texture.type != TextureType.texture2D ||
        texture.dimension != TextureDimension.d2) {
      throw refuseResource(
        'readback',
        'only a single-sampled 2D texture can be read back',
      );
    }
    if (readbackFormats.contains(texture.format)) {
      return _copyBack(
        backend,
        ScreenRect.of(texture),
        bgra: texture.format == TextureFormat.b8g8r8a8UNormInt,
      );
    }
    if (!_convertibleFormats.contains(texture.format)) {
      throw refuseResource(
        'readback',
        'there is no conversion from ${texture.format.name} to RGBA8 here',
      );
    }
    final converted = _toEightBit(texture, backend);
    try {
      return await _copyBack(
        converted.backend as WebGpuTexture,
        ScreenRect.of(converted),
      );
    } finally {
      releaseTexture(converted);
    }
  }

  /// The formats [_readConverted] will draw into an eight-bit target rather
  /// than refuse.
  ///
  /// **The float ones and only those**, because they are the ones the contract
  /// sends here: the whole of a float target is converted. The one-channel
  /// float comes back as `(r, 0, 0, 1)`, which is what a shader sampling it
  /// reads and so is not an invention.
  ///
  /// The eight-bit and two-channel `UNormInt` layouts are deliberately absent.
  /// Nothing in the engine renders into `r8unorm` or `rg8unorm` and reads it
  /// back, so a conversion for them would be a path with no caller and no test —
  /// and the question of what the other three backends put in the missing
  /// channels has never been asked, let alone answered the same way three times.
  static const Set<TextureFormat> _convertibleFormats = <TextureFormat>{
    TextureFormat.r16g16b16a16Float,
    TextureFormat.r32g32b32a32Float,
    TextureFormat.r32Float,
  };

  /// [texture] drawn into a fresh `r8g8b8a8UNormInt` target of the same size.
  ///
  /// The caller owns what comes back and releases it — [_readConverted] does, in a
  /// `finally`, so a copy that throws does not leak a full-size target.
  TextureHandle _toEightBit(TextureHandle texture, WebGpuTexture source) {
    final target = createTexture(
      RenderTargetDescriptor(
        width: texture.width,
        height: texture.height,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    final layout = _conversionLayout(_sampleTypeOf(texture.format));
    _guard('the readback conversion of a ${texture.format.name} target', () {
      final group = _gpuDevice.createBindGroup(
        GPUBindGroupDescriptor(
          layout: layout,
          label: 'readback conversion source',
          entries: <GPUBindGroupEntry>[
            GPUBindGroupEntry.textureView(
              binding: 0,
              resource: source.sampledView,
            ),
          ].toJS,
        ),
      );
      final encoder = _gpuDevice.createCommandEncoder();
      final pass = encoder.beginRenderPass(
        GPURenderPassDescriptor(
          label: 'readback conversion',
          colorAttachments: <GPURenderPassColorAttachment>[
            GPURenderPassColorAttachment(
              view: (target.backend as WebGpuTexture).attachmentView(),
              clearValue: GPUColorDict(r: 0, g: 0, b: 0, a: 0),
              loadOp: 'clear',
              storeOp: 'store',
            ),
          ].toJS,
        ),
      );
      pass
        ..setPipeline(_conversionPipeline(_sampleTypeOf(texture.format)))
        ..setBindGroup(0, group)
        ..draw(3)
        ..end();
      _gpuDevice.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    });
    return target;
  }

  /// Which sample type a bind group layout has to claim for [format].
  ///
  /// **`float` and `unfilterable-float` are not interchangeable, and the wrong
  /// one is a pipeline that never draws.** A 32-bit float texture's sample type
  /// is `unfilterable-float` on a device that was not granted
  /// `float32-filterable` and `float` on one that was, so this is a question
  /// about the device rather than about the format. Sixteen-bit float is
  /// filterable on every device and is always `float`.
  ///
  /// The conversion shader reads with `textureLoad` and binds no sampler at all,
  /// so filtering never happens either way — but the *layout* still has to name
  /// the type the view actually has.
  String _sampleTypeOf(TextureFormat format) =>
      (format == TextureFormat.r32g32b32a32Float ||
              format == TextureFormat.r32Float) &&
          !_gpuDevice.features.has(GpuFeature.float32Filterable)
      ? 'unfilterable-float'
      : 'float';

  /// The conversion shader, compiled once for the life of the device.
  ///
  /// Written here rather than taken from the stage table, deliberately: this
  /// device is opened over whatever [WebGpuSectionStages] it is handed — the
  /// conformance harness hands it one, a game hands it another — so a readback
  /// that named an engine stage would work in one of those and not the other.
  /// Nine lines of WGSL that belong to the backend are the smaller dependency.
  ///
  /// [compileModule] is the same seam every other module goes through, so a
  /// browser's opinion of this text reaches [debugDrainErrors] like any other.
  ///
  /// **`textureLoad` and no sampler at all**, which is what keeps the whole
  /// question of filtering — and of `float32-filterable` — out of the picture:
  /// the target is the source's own size, `@builtin(position)` in a WebGPU
  /// fragment stage is the framebuffer coordinate with the origin at the top
  /// left, and `textureLoad` takes texel coordinates from the same corner. One
  /// texel in, one texel out, and nothing to turn over.
  ///
  /// **The clamp is the colour target's rather than this shader's**, and it was
  /// written here first: `return clamp(texel, ...)` survived being deleted,
  /// because writing an `f32` into an `rgba8unorm` attachment is specified to
  /// clamp to `[0, 1]` before it quantises. So the range is held by the choice
  /// of intermediate format, which is the thing `a value outside the range
  /// clamps rather than wrapping` actually guards.
  late final GPUShaderModule _conversionModule =
      compileModule('readback conversion', r'''
@group(0) @binding(0) var source: texture_2d<f32>;

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> @builtin(position) vec4<f32> {
    let x = f32(i32(index) / 2) * 4.0 - 1.0;
    let y = f32(i32(index) & 1) * 4.0 - 1.0;
    return vec4<f32>(x, y, 0.0, 1.0);
}

@fragment
fn fs_main(@builtin(position) at: vec4<f32>) -> @location(0) vec4<f32> {
    return textureLoad(source, vec2<i32>(at.xy), 0);
}
''')
          as GPUShaderModule;

  final Map<String, GPUBindGroupLayout> _conversionLayouts =
      <String, GPUBindGroupLayout>{};
  final Map<String, GPURenderPipeline> _conversionPipelines =
      <String, GPURenderPipeline>{};

  /// The one-entry layout the conversion binds its source through, one per
  /// distinct [sampleType] — which on a device with `float32-filterable` is one
  /// for all three formats.
  GPUBindGroupLayout _conversionLayout(String sampleType) =>
      _conversionLayouts[sampleType] ??= _gpuDevice.createBindGroupLayout(
        GPUBindGroupLayoutDescriptor(
          label: 'readback conversion $sampleType',
          entries: <GPUBindGroupLayoutEntry>[
            GPUBindGroupLayoutEntry.texture(
              binding: 0,
              visibility: GpuShaderStage.fragment,
              texture: GPUTextureBindingLayout(
                sampleType: sampleType,
                viewDimension: '2d',
                multisampled: false,
              ),
            ),
          ].toJS,
        ),
      );

  GPURenderPipeline _conversionPipeline(String sampleType) =>
      _conversionPipelines[sampleType] ??= _guard(
        'the readback conversion pipeline',
        () => _gpuDevice.createRenderPipeline(
          GPURenderPipelineDescriptor.withoutDepth(
            label: 'readback conversion $sampleType',
            layout: _gpuDevice.createPipelineLayout(
              GPUPipelineLayoutDescriptor(
                label: 'readback conversion $sampleType',
                bindGroupLayouts: <GPUBindGroupLayout>[
                  _conversionLayout(sampleType),
                ].toJS,
              ),
            ),
            vertex: GPUVertexState(
              module: _conversionModule,
              entryPoint: 'vs_main',
            ),
            fragment: GPUFragmentState(
              module: _conversionModule,
              entryPoint: 'fs_main',
              targets: <GPUColorTargetState>[
                GPUColorTargetState.opaque(
                  format: gpuTextureFormat(TextureFormat.r8g8b8a8UNormInt)!,
                  writeMask: GpuColorWrite.all,
                ),
              ].toJS,
            ),
            // No culling, so the covering triangle's winding is not a decision
            // this pass has to get right on a backend whose framebuffer y runs
            // down.
            primitive: GPUPrimitiveState(
              topology: 'triangle-list',
              cullMode: 'none',
              frontFace: 'ccw',
            ),
          ),
        ),
      );

  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) {
    if (readbackConverts(texture, region: region)) {
      return _readConverted(texture);
    }
    // The contract's own refusals, decided above every backend. Called first
    // and synchronously, because a refusal that arrives as a failed future is a
    // readback that was accepted.
    final rect = readbackRegionOf(texture, region);
    return _copyBack(
      texture.backend as WebGpuTexture,
      rect,
      bgra: texture.format == TextureFormat.b8g8r8a8UNormInt,
    );
  }

  /// [rect] copied out through a staging buffer, repacked to the width the
  /// contract promises.
  ///
  /// **No rows are turned over here, and that is the whole of the difference
  /// from the WebGL2 backend's readback.** That one flips, because GL hands
  /// back rows from the bottom of a framebuffer and the contract states images
  /// from the top. WebGPU's origin *is* the top left, so a copy of it kept in
  /// order is already what was promised — and a flip carried across "just in
  /// case" would give a frame that reads back correctly and presents upside
  /// down, which is the pair this engine has pulled apart once already.
  ///
  /// [bgra] says the texture stores its channels blue first. The copy hands
  /// over the bytes as stored, and the contract promises RGBA — the order
  /// Impeller's `toByteData(rawRgba)` and every other backend answer in — so
  /// the swap is made here, on the way out.
  Future<ByteData> _copyBack(
    WebGpuTexture texture,
    ScreenRect rect, {
    bool bgra = false,
  }) async {
    // `copyTextureToBuffer` will not write rows packed tighter than 256 bytes,
    // whatever the region is — so the copy is made wide and the answer is
    // repacked. The editor's one-pixel pick is the case where the padding is
    // 252 bytes out of 256.
    final stride = paddedBytesPerRow(rect.width);
    final staging = _gpuDevice.createBuffer(
      GPUBufferDescriptor(
        size: stride * rect.height,
        usage: GpuBufferUsage.copyDst | GpuBufferUsage.mapRead,
        label: 'readback ${rect.width}x${rect.height}',
      ),
    );
    // Destroyed on every path out, the refused ones included: a copy that
    // throws or a map that rejects — a lost device — would otherwise leave
    // one staging buffer per failed readback for the life of the device.
    try {
      _guard('the readback copy of $rect', () {
        final encoder = _gpuDevice.createCommandEncoder()
          ..copyTextureToBuffer(
            GPUTexelCopyTextureInfo(
              texture: texture.texture,
              mipLevel: 0,
              origin: GPUOrigin3DDict(x: rect.x, y: rect.y, z: 0),
              aspect: 'all',
            ),
            GPUTexelCopyBufferInfo(
              buffer: staging,
              offset: 0,
              bytesPerRow: stride,
              rowsPerImage: rect.height,
            ),
            GPUExtent3DDict(
              width: rect.width,
              height: rect.height,
              depthOrArrayLayers: 1,
            ),
          );
        _gpuDevice.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
      });

      await staging.mapAsync(GpuMapMode.read).toDart;
      final mapped = staging.getMappedRange().toDart.asUint8List();
      final out = Uint8List(rect.width * rect.height * 4);
      final row = rect.width * 4;
      for (var y = 0; y < rect.height; y++) {
        out.setRange(y * row, (y + 1) * row, mapped, y * stride);
      }
      staging.unmap();
      if (bgra) swapRedAndBlue(out);
      return ByteData.sublistView(out);
    } finally {
      staging.destroy();
    }
  }

  // ------------------------------------------------- 1.0: the rest of a GPU

  /// Any shape — `webgpuCreateTextureWithDescriptor` checks what the browser
  /// would otherwise refuse asynchronously; the features each shape needs are
  /// refused here first.
  ///
  /// A [RenderTargetDescriptor] is the pool's 2D target, made as it always
  /// was; any other descriptor is the general form, `textureWrites`.
  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    if (descriptor is RenderTargetDescriptor) return _createTarget(descriptor);
    features.require(DeviceFeature.textureWrites, backend: _backend);
    final shape = switch (descriptor.dimension) {
      TextureDimension.d2Array => DeviceFeature.textureArrays,
      TextureDimension.d3 => DeviceFeature.texture3D,
      TextureDimension.cube => DeviceFeature.cubeTextures,
      TextureDimension.cubeArray => DeviceFeature.cubeArrayTextures,
      TextureDimension.d1 || TextureDimension.d2 => null,
    };
    if (shape != null) features.require(shape, backend: _backend);
    if (descriptor.usage.contains(TextureUsage.storage)) {
      features.require(DeviceFeature.storageTextures, backend: _backend);
    }
    return _guard(
      'a texture $descriptor',
      () => webgpuCreateTextureWithDescriptor(
        _gpuDevice,
        _textures,
        descriptor,
        limits: limits,
        support: textureFormatSupport(descriptor.format),
      ),
    );
  }

  /// `queue.writeTexture`, which takes any row stride.
  @override
  void writeTexture(
    TextureHandle target,
    ByteData data, {
    TextureRegion? region,
    int mipLevel = 0,
    int? bytesPerRow,
  }) {
    features.require(DeviceFeature.textureWrites, backend: _backend);
    _guard(
      'a write into a ${target.format.name} texture',
      () => webgpuWriteTexture(
        _gpuDevice,
        target,
        data,
        region: region,
        level: mipLevel,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  /// A general buffer. Its host usages are realised as `gpuBufferUsageOf`
  /// says — a real mapping where WebGPU allows one beside the rest, a staging
  /// copy or a queue write where it does not.
  @override
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) {
    features.require(DeviceFeature.buffers, backend: _backend);
    final usage = descriptor.usage;
    if (usage.contains(BufferUsage.storage) &&
        !features.has(DeviceFeature.compute) &&
        !features.has(DeviceFeature.renderStageStorage)) {
      throw UnsupportedCapability(DeviceFeature.compute, backend: _backend);
    }
    if (usage.contains(BufferUsage.indirect) &&
        !features.has(DeviceFeature.indirectDraw) &&
        !features.has(DeviceFeature.indirectDispatch)) {
      throw UnsupportedCapability(
        DeviceFeature.indirectDraw,
        backend: _backend,
      );
    }
    if (descriptor.lengthInBytes > limits.maxBufferSize) {
      throw ArgumentError.value(
        descriptor.lengthInBytes,
        'lengthInBytes',
        'is past maxBufferSize (${limits.maxBufferSize})',
      );
    }
    return _guard(
      'a ${descriptor.lengthInBytes}-byte buffer',
      () => webgpuCreateBuffer(_gpuDevice, descriptor, contents: contents),
    );
  }

  /// `queue.writeBuffer`, from an offset that is a multiple of four. A length
  /// that is not one is allowed only where it runs to the end of the buffer,
  /// whose allocation was rounded up to four: anywhere else the padding
  /// `writeBuffer` needs would land on bytes the caller did not name.
  @override
  void writeBuffer(StorageBuffer target, int offsetInBytes, ByteData bytes) {
    if (!features.has(DeviceFeature.compute)) {
      features.require(DeviceFeature.buffers, backend: _backend);
    }
    final end = offsetInBytes + bytes.lengthInBytes;
    if (offsetInBytes < 0 || end > target.lengthInBytes) {
      throw ArgumentError(
        'writeBuffer: $offsetInBytes + ${bytes.lengthInBytes} does not fit '
        'inside a ${target.lengthInBytes}-byte buffer',
      );
    }
    if (offsetInBytes % 4 != 0 ||
        (bytes.lengthInBytes % 4 != 0 && end != target.lengthInBytes)) {
      throw ArgumentError(
        'writeBuffer: offset $offsetInBytes and length '
        '${bytes.lengthInBytes} must be multiples of 4 short of the end',
      );
    }
    if (!target.usage.contains(BufferUsage.copyDestination)) {
      throw ArgumentError.value(
        target.usage,
        'target',
        'was not made with BufferUsage.copyDestination',
      );
    }
    _gpuDevice.queue.writeBuffer(
      (target.backend as WebGpuStorage).buffer,
      offsetInBytes,
      gpuWritableBytes(bytes).toJS,
    );
  }

  @override
  QuerySet createQuerySet(QueryType type, int count) {
    switch (type) {
      case QueryType.occlusion:
        features.require(DeviceFeature.occlusionQuery, backend: _backend);
      case QueryType.timestamp:
        features.require(
          DeviceFeature.timestampQuery,
          backend: _backend,
          reason: 'the adapter did not offer timestamp-query',
        );
      case QueryType.pipelineStatistics:
        // TODO(webgpu): pipeline statistics — not in the WebGPU
        // specification; a `"pipeline-statistics"` query type behind a
        // feature would unblock it.
        features.require(
          DeviceFeature.pipelineStatisticsQuery,
          backend: _backend,
          reason: 'WebGPU has no pipeline statistics queries',
        );
    }
    if (count < 1 || count > 4096) {
      throw ArgumentError.value(count, 'count', 'WebGPU takes 1 to 4096');
    }
    return wrapQuerySet(
      owner: this,
      backend: WebGpuQueries(
        _guard(
          'a query set of $count',
          () => _gpuDevice.createQuerySet(
            GPUQuerySetDescriptor(
              type: type == QueryType.occlusion ? 'occlusion' : 'timestamp',
              count: count,
              label: '${type.name} x$count',
            ),
          ),
        ),
      ),
      type: type,
      count: count,
    );
  }

  @override
  Future<List<int>> readQueryResults(
    QuerySet querySet, {
    int first = 0,
    int? count,
  }) {
    final n = count ?? querySet.count - first;
    if (first < 0 || n < 0 || first + n > querySet.count) {
      throw RangeError(
        'readQueryResults: $n queries from $first leave a set of '
        '${querySet.count}',
      );
    }
    return webgpuReadQueries(_gpuDevice, querySet, first, n);
  }

  @override
  void releaseQuerySet(QuerySet querySet) =>
      (querySet.backend as WebGpuQueries).set.destroy();

  @override
  TransferEncoder beginTransferPass({String? label}) => WebGpuTransferEncoder(
    _gpuDevice,
    features: features,
    guard: _guard,
    label: label,
  );

  /// `mapAsync`, on the buffer itself where it was made mappable and through
  /// a staging copy or a queue write where its other usages rule that out —
  /// see `gpuBufferUsageOf`.
  @override
  Future<MappedBuffer> mapBuffer(
    StorageBuffer buffer,
    MapMode mode, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) async {
    features.require(DeviceFeature.mappedBuffers, backend: _backend);
    final size = sizeInBytes ?? buffer.lengthInBytes - offsetInBytes;
    webgpuCheckRange(buffer, offsetInBytes, size, what: 'mapBuffer');
    switch (mode) {
      case MapMode.read:
        if (!buffer.usage.contains(BufferUsage.hostReadable) &&
            !buffer.hostReadable) {
          throw ArgumentError.value(
            buffer.usage,
            'buffer',
            'was not made with BufferUsage.hostReadable',
          );
        }
        final mapped = await webgpuMapRead(
          _gpuDevice,
          buffer,
          offsetInBytes,
          size,
        );
        return WebGpuMappedBuffer(mapped.bytes, mapped.release);
      case MapMode.write:
        if (!buffer.usage.contains(BufferUsage.hostWritable)) {
          throw ArgumentError.value(
            buffer.usage,
            'buffer',
            'was not made with BufferUsage.hostWritable',
          );
        }
        return webgpuMapWrite(_gpuDevice, buffer, offsetInBytes, size);
    }
  }

  // Not a `SynchronousBufferReadback`, by design and not as a gap: WebGPU
  // has no synchronous readback — every map is a promise, so that a page
  // cannot stall on its GPU. A caller wants `readBuffer` or `mapBuffer`.

  @override
  RenderBundleEncoder createRenderBundleEncoder(
    RenderBundleDescriptor descriptor,
  ) {
    features.require(DeviceFeature.renderBundles, backend: _backend);
    for (final format in descriptor.colorFormats) {
      if (!textureFormatSupport(format).renderable) {
        throw ArgumentError.value(
          format,
          'colorFormats',
          'is not a colour attachment format here',
        );
      }
    }
    return WebGpuBundleEncoder(this, descriptor);
  }

  /// Releases everything: the textures and buffers handed out, the arenas, the
  /// caches, the canvas's configuration and the device itself.
  ///
  /// **This backend can finish the job, and the WebGL2 one cannot.** There the
  /// canvas is the drawing surface and the platform view registry pins it for
  /// the life of the application; the most that backend can do is remove the
  /// element and ask `WEBGL_lose_context` to free the context behind it. Here
  /// the canvas is a copy target, the factory holds an emptiable slot rather
  /// than the element, `unconfigure` gives back the swap chain and
  /// `GPUDevice.destroy` gives back the device — so what is left afterwards is
  /// a closure over a null.
  ///
  /// Call once. A second call is a caller mistake worth surfacing rather than
  /// one this device quietly absorbs.
  @override
  void dispose() {
    if (_disposed) {
      throw StateError('WebGpuDevice.dispose() was already called');
    }
    _disposed = true;
    unawaited(_lost.close());
    webgpuDisposePersistentResources(_textures, _buffers);
    _blanks.clear();
    _uniformArena.dispose();
    _vertexArena.dispose();
    _indexArena.dispose();
    _zeroBlock.destroy();
    // Pipelines, layouts, samplers and bind groups have no `destroy` of their
    // own: they belong to the device and die with it. Forgetting them is what
    // makes the resource count fall to zero, and what stops a caller holding
    // this device from holding them too.
    _pipelines.clear();
    _drawStates.clear();
    _bindingLayouts.clear();
    _samplers.clear();
    _bindGroups.clear();
    _conversionLayouts.clear();
    _conversionPipelines.clear();
    _library.forget();

    _context.unconfigure();
    _canvas.remove();
    _slot.element = null;
    _gpuDevice.destroy();
  }
}

/// The device's own objects, for the rest of this backend: the encoder,
/// the allocators and the presenter. Not exported — `flutter3d_webgpu_web.dart`
/// shows `WebGpuDevice` alone — so no WebGPU type is in the package's API.
extension WebGpuDeviceInternals on WebGpuDevice {
  GPUDevice get gpuDevice => _gpuDevice;
  WebGpuFrameArena get indexArena => _indexArena;
  WebGpuFrameArena get uniformArena => _uniformArena;
  WebGpuFrameArena get vertexArena => _vertexArena;
  WebGpuPipelineCache<GPURenderPipeline> get pipelines => _pipelines;
  GPUBindGroup bindGroupFor(
    WebGpuBindingLayouts layouts,
    int group,
    Map<int, WebGpuSlice>? blocks,
    Map<int, GPUTextureView>? views,
    Map<int, GPUSampler>? samplers,
  ) => _bindGroupFor(layouts, group, blocks, views, samplers);
  GPUSampler samplerFor(SamplerDescriptor options) => _samplerFor(options);
  WebGpuBindingLayouts bindingsFor(WebGpuPipeline pipeline) =>
      _bindingsFor(pipeline);
  void rememberDrawState(WebGpuDrawState state) => _rememberDrawState(state);
  T guard<T>(String what, T Function() body) => _guard(what, body);
}
