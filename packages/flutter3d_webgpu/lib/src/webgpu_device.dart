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
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_bundle_section.dart';
import 'webgpu_encoder.dart';
import 'webgpu_formats.dart';
import 'webgpu_interop.dart';
import 'webgpu_loaded_shaders.dart';
import 'webgpu_pipeline_cache.dart';
import 'webgpu_resources.dart';
import 'webgpu_shaders.dart';
import 'webgpu_types.dart';

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external JSObject createElement(String tag);
}

extension type _Canvas._(JSObject _) implements JSObject {
  external set width(int value);
  external set height(int value);
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
/// view once, a sampler is one object per distinct `SamplerOptions`, and a
/// uniform block names the frame arena rather than a slice of it.
final class _BindGroupKey {
  _BindGroupKey(this.layout, this.resources);

  final GPUBindGroupLayout layout;
  final List<Object> resources;

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

/// WebGPU as a [GraphicsDevice], and as the compiler its shader libraries reach
/// a browser through.
final class WebGpuDevice implements GraphicsDevice, WgslModuleCompiler {
  WebGpuDevice._(this.gpuDevice, this._canvas, this._context, this._stages)
    : _slot = _CanvasSlot(_canvas),
      uniformArena = WebGpuFrameArena(
        gpuDevice,
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
      vertexArena = WebGpuFrameArena(
        gpuDevice,
        usage: GpuBufferUsage.vertex,
        alignment: 4,
        label: 'flutter3d vertices',
      ),
      indexArena = WebGpuFrameArena(
        gpuDevice,
        usage: GpuBufferUsage.index,
        alignment: 4,
        label: 'flutter3d indices',
      ) {
    _zeroBlock = gpuDevice.createBuffer(
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
    final module = gpuDevice.createShaderModule(
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

  /// Opens a device over a canvas of [width] by [height], or answers null where
  /// this browser has no WebGPU.
  ///
  /// **Asynchronous, and it is the one place the fourth backend costs anything
  /// outside itself.** `requestAdapter` and `requestDevice` are both promises,
  /// so a WebGPU device cannot be built by a constructor the way the other
  /// three are. Nothing in `flutter3d_hardware` says how a device is made — the
  /// contract starts once one exists — so this costs the contract nothing and
  /// costs whatever chooses a backend an `await`.
  ///
  /// Null rather than a throw for a browser with no WebGPU: that is the
  /// ordinary case and not a failure, and a caller's move is to pick another
  /// backend. `openWebGpu` is where the null becomes the one sentence worth
  /// putting on a screen.
  ///
  /// **The features are asked for rather than assumed.** A WebGPU device gets
  /// exactly what it requested: sampling a BC7 texture on a device that did not
  /// ask for `texture-compression-bc` is a validation error, not a slow path.
  /// Two are requested where the adapter has them — filtering of 32-bit float
  /// textures, and the full-precision depth-stencil format — and the three
  /// compression families deliberately are not, which is why
  /// [supportsTextureFormat] answers false for every block-compressed format
  /// and an asset that carries one is left out with a reason.
  static Future<WebGpuDevice?> create({
    required int width,
    required int height,
    required WebGpuSectionStages stages,
  }) async {
    final gpu = gpuNavigator.gpu;
    if (gpu == null) return null;
    final adapter = await gpu
        .requestAdapter(
          GPURequestAdapterOptions(powerPreference: 'high-performance'),
        )
        .toDart;
    if (adapter == null) return null;
    final wanted = <String>[
      for (final feature in const <String>[
        GpuFeature.float32Filterable,
        GpuFeature.depth32FloatStencil8,
      ])
        if (adapter.features.has(feature)) feature,
    ];
    final gpuDevice = await adapter
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
      gpuDevice.destroy();
      return null;
    }
    context.configure(
      GPUCanvasConfiguration(
        device: gpuDevice,
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
    return WebGpuDevice._(gpuDevice, canvas, context, stages);
  }

  /// The browser's device. Public because the encoder beside this one records
  /// into it.
  final GPUDevice gpuDevice;

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
  final WebGpuFrameArena uniformArena;

  /// Where `PassEncoder.bindVertexData`'s bytes land.
  final WebGpuFrameArena vertexArena;

  /// Where `PassEncoder.bindIndexData`'s bytes land.
  final WebGpuFrameArena indexArena;

  /// Real pipelines, by the signature that produced each. Shared across passes:
  /// the signature already carries the attachment formats and the sample count.
  final WebGpuPipelineCache<GPURenderPipeline> pipelines =
      WebGpuPipelineCache<GPURenderPipeline>();

  final Map<String, WebGpuBindingLayouts> _bindingLayouts =
      <String, WebGpuBindingLayouts>{};
  final Map<SamplerOptions, GPUSampler> _samplers =
      <SamplerOptions, GPUSampler>{};
  final Map<_BindGroupKey, GPUBindGroup> _bindGroups =
      <_BindGroupKey, GPUBindGroup>{};

  final List<WebGpuTexture> _textures = <WebGpuTexture>[];
  final List<GPUBuffer> _buffers = <GPUBuffer>[];

  late final GPUBuffer _zeroBlock;
  WebGpuTexture? _blankImage;
  WebGpuTexture? _blankCube;

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
  T guard<T>(String what, T Function() body) {
    gpuDevice.pushErrorScope(GpuErrorFilter.validation);
    final T result;
    try {
      result = body();
    } catch (_) {
      // Popped either way: an unbalanced scope makes the *next* pop answer for
      // this call's errors, which reports the mistake against whatever ran
      // afterwards.
      _pending.add(gpuDevice.popErrorScope().toDart.then((GPUError? _) {}));
      rethrow;
    }
    _pending.add(
      gpuDevice.popErrorScope().toDart.then((GPUError? error) {
        if (error != null) _errors.add('$what: ${error.message}');
      }),
    );
    return result;
  }

  /// Everything the browser complained about since the last drain, or null when
  /// it complained about nothing.
  ///
  /// Asynchronous because the verdicts are: every scope [guard] opened is a
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
  /// Keyed on the pair's name rather than on the pipeline object, because the
  /// layouts come out of the two stages' reflection and nothing else: two
  /// pipelines over one pair with different vertex layouts are two pipelines
  /// and one set of bind group layouts.
  WebGpuBindingLayouts bindingsFor(WebGpuPipeline pipeline) =>
      _bindingLayouts[pipeline.name] ??= guard(
        'the bind group layouts of ${pipeline.name}',
        () => WebGpuBindingLayouts.of(gpuDevice, pipeline),
      );

  /// The sampler object for [options], made once per distinct description.
  ///
  /// **This is where all of the WebGL2 backend's sampler trouble disappears.**
  /// In GL the filter and the wrap modes are properties of the *texture*, so
  /// that backend sets four `texParameteri` on every bind and one image bound
  /// twice with two descriptions keeps whichever came last. WebGPU has real
  /// sampler objects compared by value, `SamplerOptions` already is a value,
  /// and so a map is the whole of it.
  ///
  /// [SamplerOptions.anisotropy] is clamped to [maxAnisotropy] rather than
  /// refused, which is the contract's own rule: a caller may ask for sixteen
  /// without asking first.
  GPUSampler samplerFor(SamplerOptions options) =>
      _samplers[options] ??= gpuDevice.createSampler(
        GPUSamplerDescriptor(
          addressModeU: gpuAddressMode(options.widthAddressMode),
          addressModeV: gpuAddressMode(options.heightAddressMode),
          // Nothing in this engine samples a 3D texture, so the third axis is
          // the second's — a value is required and any of the three is legal.
          addressModeW: gpuAddressMode(options.heightAddressMode),
          magFilter: gpuFilterMode(options.magFilter),
          minFilter: gpuFilterMode(options.minFilter),
          mipmapFilter: gpuMipmapFilterMode(options.mipFilter),
          lodMinClamp: 0.0,
          // The whole chain. A texture with one level ignores it, and one built
          // with a chain on purpose wants every level of it.
          lodMaxClamp: 32.0,
          maxAnisotropy: options.anisotropy > maxAnisotropy
              ? maxAnisotropy
              : options.anisotropy,
          label: options.toString(),
        ),
      );

  /// The bind group for one `@group` of [layouts], assembled from what the pass
  /// has bound and cached by what went into it.
  ///
  /// A binding the pass never filled gets a neutral resource rather than being
  /// left out: WebGPU refuses an incomplete group outright, and the contract
  /// already says a declared sampler must have something bound to it. An
  /// unfilled block reads the zeroed buffer, which is what GL would have given
  /// it.
  GPUBindGroup bindGroupFor(
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
      final buffer = blocks?[block.binding]?.buffer ?? _zeroBlock;
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
      final view =
          views?[sampler.textureBinding] ?? _blankView(sampler.dimension);
      final object =
          samplers?[sampler.samplerBinding] ??
          samplerFor(SamplerOptions.linearRepeat);
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
    )] ??= guard(
      'a bind group for group $group',
      () => gpuDevice.createBindGroup(
        GPUBindGroupDescriptor(
          layout: layouts.groups[group],
          entries: entries.toJS,
          label: 'group $group',
        ),
      ),
    );
  }

  /// One white texel, in the shape a slot with nothing bound to it wants.
  ///
  /// Made on first need rather than at startup, because a bundle whose stages
  /// declare no sampler never asks — and because a device that allocated for a
  /// case that never happens is a device counting resources it did not need.
  GPUTextureView _blankView(WebGpuTextureDimension dimension) {
    ByteData white() => ByteData(4)
      ..setUint8(0, 255)
      ..setUint8(1, 255)
      ..setUint8(2, 255)
      ..setUint8(3, 255);
    if (dimension == WebGpuTextureDimension.cube) {
      return (_blankCube ??= _backendOf(
        webgpuCreateCubeTextureFromPixels(
          gpuDevice,
          _textures,
          size: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
          faces: <ByteData>[for (var i = 0; i < 6; i++) white()],
        ),
      )).sampledView;
    }
    return (_blankImage ??= _backendOf(
      webgpuCreateTextureFromPixels(
        gpuDevice,
        _textures,
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: white(),
      ),
    )).sampledView;
  }

  /// The backend of a texture this file just made, which cannot be null: the
  /// creation paths answer null for bytes that disagree with a description, and
  /// these two describe one white texel.
  static WebGpuTexture _backendOf(TextureHandle? handle) =>
      handle!.backend as WebGpuTexture;

  /// Every GPU object this device owns and would have to release: the textures
  /// and geometry it handed out, the frame arenas and fallbacks it made for
  /// itself, and the modules, layouts, samplers, bind groups and pipelines it
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
  /// Diagnostic, and the number that says whether [samplerFor] is doing its
  /// job: a frame binding a hundred textures with `SamplerOptions.linearRepeat`
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
      uniformArena.bufferCount +
      vertexArena.bufferCount +
      indexArena.bufferCount +
      (_disposed ? 0 : 1) +
      _library.debugTrackedModuleCount +
      _bindingLayouts.length +
      _samplers.length +
      _bindGroups.length +
      pipelines.length;

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

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d24UnormS8Uint;

  @override
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  /// Four, which is the only multisample count above one WebGPU guarantees.
  @override
  int get preferredSampleCount => 4;

  @override
  bool get supportsOffscreenMsaa => true;

  /// **False, and the false is a finding rather than a limitation.** See
  /// `WebGpuEncoder.setBlendColor`, which is the refusal this promises.
  @override
  bool get supportsBlendColor => false;

  /// False: WebGPU has no polygon fill mode at all. A wireframe here is line
  /// primitives and an index buffer built for them, which is the renderer's
  /// decision — the same answer WebGL2 gives for the same reason.
  @override
  bool get supportsWireframe => false;

  @override
  bool get supportsStencil => true;

  @override
  bool get supportsMipmaps => true;

  /// True: a cube is a six-layer texture with a `"cube"` view over it, and the
  /// sky pass needs one. It is the one of the three cube-shaped capabilities
  /// this iteration answers yes to.
  @override
  bool get supportsCubeTextures => true;

  /// **False for now, and the false is a refusal rather than a wrong picture.**
  /// A view built with a `baseMipLevel` is an ordinary attachment in this API,
  /// so nothing here is impossible; what is missing is
  /// [createCubeRenderTarget], and a probe needs both. Answering true with no
  /// cube to draw into would give `ReflectionProbeNode.supportedOn` a yes and
  /// the conformance suite a crash instead of a skip.
  @override
  bool get supportsRenderToMip => false;

  /// Sixteen, which is what this API's `maxAnisotropy` tops out at. A sampler
  /// asking for more is clamped by [samplerFor] rather than refused.
  @override
  int get maxAnisotropy => 16;

  /// Whether WebGPU has a name for [format] *and* this device asked for the
  /// feature it needs.
  ///
  /// Every block-compressed format comes back false, because [create] requests
  /// none of the three compression families — see the note there. That is the
  /// honest coupling: a format the device did not ask for is one a sample of
  /// would be a validation error, so a loader gets a false and leaves the
  /// texture out with a reason.
  @override
  bool supportsTextureFormat(TextureFormat format) =>
      gpuTextureFormat(format) != null && !format.isCompressed;

  @override
  ShaderLibrary get shaders => _library;

  // ------------------------------------------------------------- resources

  @override
  TextureHandle createTexture(RenderTargetSpec spec, {int levels = 1}) => guard(
    'a ${spec.width}x${spec.height} ${spec.format.name} target',
    () => webgpuCreateTexture(gpuDevice, _textures, spec, levels: levels),
  );

  @override
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) => guard(
    'a ${width}x$height ${format.name} image',
    () => webgpuCreateTextureFromPixels(
      gpuDevice,
      _textures,
      width: width,
      height: height,
      format: format,
      pixels: pixels,
      mipLevels: mipLevels,
    ),
  );

  @override
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) => guard(
    'a ${size}x$size ${format.name} cube',
    () => webgpuCreateCubeTextureFromPixels(
      gpuDevice,
      _textures,
      size: size,
      format: format,
      faces: faces,
      mipLevels: mipLevels,
    ),
  );

  /// A cube a pass may aim at one face of.
  ///
  /// **This used to be null, and the conformance suite is what said it could
  /// not stay null.** The argument for the null was that a cube a probe can
  /// draw into is only useful beside a chain it can filter into, so the two
  /// should arrive together — but [supportsCubeTextures] answering true is a
  /// promise about more than sampling: the suite reads it as "a pass can name a
  /// face of a cube", clears three of them and reads them back, and a backend
  /// that answered true and then handed back no cube failed that check rather
  /// than declining it. It was a gap wearing a refusal's clothes.
  ///
  /// [supportsRenderToMip] stays false and stays a real refusal, which is what
  /// keeps `ReflectionProbeNode.supportedOn` — it asks for both — from turning
  /// a probe on over half an implementation. Six array layers and a view per
  /// face is `webgpu_resources.dart`'s whole answer.
  @override
  TextureHandle? createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) => guard(
    'a ${size}x$size ${format.name} cube target',
    () => webgpuCreateCubeRenderTarget(
      gpuDevice,
      _textures,
      size: size,
      format: format,
      mipLevels: mipLevels,
    ),
  );

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) => guard(
    'a ${bytes.lengthInBytes}-byte ${usage.name} buffer',
    () => webgpuUploadGeometry(gpuDevice, _buffers, bytes, usage),
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
    VertexLayoutSpec? layout,
  }) => createWebGpuPipeline(vertex, fragment, layout: layout);

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
  /// Refuses by name — [ShaderBundleRefused] — for a bundle with no section for
  /// this backend, a section that is not the document the codec reads, and one
  /// written to a version of that document this build does not know.
  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async =>
      WebGpuLoadedShaderLibrary.load(this, bytes);

  @override
  void releaseTexture(TextureHandle texture) {
    final backend = texture.backend;
    if (backend is! WebGpuTexture) return;
    webgpuReleaseTexture(backend, _textures);
  }

  @override
  void releaseGeometry(GeometryBuffer geometry) =>
      webgpuReleaseGeometry(geometry.backend, _buffers);

  // ---------------------------------------------------------------- frame

  /// Rewinds the three frame arenas.
  ///
  /// This is the member `GraphicsDevice.beginFrame` exists for, and the one
  /// backend of the four with something real to do in it. See
  /// `webgpu_resources.dart` for why rewinding under a frame the GPU has not
  /// finished with is safe, which is the only surprising thing about it.
  @override
  void beginFrame() {
    uniformArena.reset();
    vertexArena.reset();
    indexArena.reset();
  }

  @override
  void onFrameComplete(void Function() whenDone) {
    unawaited(
      gpuDevice.queue.onSubmittedWorkDone().toDart.then((JSAny? _) {
        whenDone();
      }),
    );
  }

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) =>
      WebGpuEncoder(this, descriptor);

  // --------------------------------------------------------------- output

  /// The canvas, in the widget tree, with [frame] copied into it.
  ///
  /// **A copy rather than a render**, because `getCurrentTexture` is valid only
  /// for the task it was asked in and cannot be held across an `await`. The
  /// engine's target already exists and the copy is one command on an encoder
  /// submitted immediately — the same one GPU copy the WebGL2 backend's
  /// presenting blit is, arrived at from the other side.
  ///
  /// [fit] and [quality] are honoured through CSS on the element rather than by
  /// Flutter, since Flutter does not composite these pixels.
  @override
  Widget present(
    TextureHandle frame, {
    BoxFit fit = BoxFit.fill,
    FilterQuality quality = FilterQuality.none,
  }) {
    _copyToCanvas(frame);
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
    return HtmlElementView(viewType: viewType);
  }

  void _copyToCanvas(TextureHandle frame) {
    final target = _context.getCurrentTexture();
    final source = frame.backend as WebGpuTexture;
    final width = frame.width < target.width ? frame.width : target.width;
    final height = frame.height < target.height ? frame.height : target.height;
    guard('the copy that presents a frame', () {
      final encoder = gpuDevice.createCommandEncoder()
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
      gpuDevice.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    });
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
  /// Null where the texture has nothing to read: an attachment-only allocation
  /// — this backend's translation of tile memory — a multisampled target, and,
  /// for now, any format but the two eight-bit RGBA layouts. The contract
  /// offers this as the way to read a float target back, and doing that here
  /// means a conversion pass rather than a copy, because WebGPU has no
  /// format-converting readback the way `glReadPixels` does. Null rather than a
  /// wrong picture until that pass exists.
  @override
  Future<ByteData?> readPixels(TextureHandle texture) async {
    final backend = texture.backend;
    if (backend is! WebGpuTexture || !backend.sampleable) return null;
    if (texture.sampleCount != 1) return null;
    if (!readbackFormats.contains(texture.format)) return null;
    if (texture.type != TextureType.texture2D) return null;
    return _copyBack(backend, ScreenRect.of(texture));
  }

  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) {
    // The contract's own refusals, decided above every backend. Called first
    // and synchronously, because a refusal that arrives as a failed future is a
    // readback that was accepted.
    final rect = readbackRegionOf(texture, region);
    return _copyBack(texture.backend as WebGpuTexture, rect);
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
  Future<ByteData> _copyBack(WebGpuTexture texture, ScreenRect rect) async {
    // `copyTextureToBuffer` will not write rows packed tighter than 256 bytes,
    // whatever the region is — so the copy is made wide and the answer is
    // repacked. The editor's one-pixel pick is the case where the padding is
    // 252 bytes out of 256.
    final stride = paddedBytesPerRow(rect.width);
    final staging = gpuDevice.createBuffer(
      GPUBufferDescriptor(
        size: stride * rect.height,
        usage: GpuBufferUsage.copyDst | GpuBufferUsage.mapRead,
        label: 'readback ${rect.width}x${rect.height}',
      ),
    );
    guard('the readback copy of $rect', () {
      final encoder = gpuDevice.createCommandEncoder()
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
      gpuDevice.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    });

    await staging.mapAsync(GpuMapMode.read).toDart;
    final mapped = staging.getMappedRange().toDart.asUint8List();
    final out = Uint8List(rect.width * rect.height * 4);
    final row = rect.width * 4;
    for (var y = 0; y < rect.height; y++) {
      out.setRange(y * row, (y + 1) * row, mapped, y * stride);
    }
    staging
      ..unmap()
      ..destroy();
    return ByteData.sublistView(out);
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
    webgpuDisposePersistentResources(_textures, _buffers);
    _blankImage = null;
    _blankCube = null;
    uniformArena.dispose();
    vertexArena.dispose();
    indexArena.dispose();
    _zeroBlock.destroy();
    // Pipelines, layouts, samplers and bind groups have no `destroy` of their
    // own: they belong to the device and die with it. Forgetting them is what
    // makes the resource count fall to zero, and what stops a caller holding
    // this device from holding them too.
    pipelines.clear();
    _bindingLayouts.clear();
    _samplers.clear();
    _bindGroups.clear();
    _library.forget();

    _context.unconfigure();
    _canvas.remove();
    _slot.element = null;
    gpuDevice.destroy();
  }
}
