/// WebGL2 as an implementation of [GraphicsDevice].
///
/// The second backend, and therefore the first real test of whether
/// `flutter3d_hardware` is a seam or a description of Impeller wearing neutral
/// names. Where the two models differ the difference is written down here, at
/// the line where it bites.
///
/// Split across a few files by cohesive concern, all re-exported from here so
/// the public surface is unchanged: [WebGlTexture], [WebGlProgram],
/// [WebGlAttribute] and [WebGlBlock] are the value types a handle carries
/// (`webgl_types.dart`); persistent texture/buffer creation and the teardown
/// that undoes it live in `webgl_resources.dart`; [WebGlEncoder] — one pass,
/// recorded straight into the context — is `webgl_encoder.dart`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import '../engine_shaders.dart';

import 'webgl_buffers.dart';
import 'webgl_bundle.dart';
import 'webgl_encoder.dart';
import 'webgl_formats.dart';
import 'webgl_framebuffer.dart';
import 'webgl_image_decode.dart';
import 'webgl_loaded_shaders.dart';
import 'webgl_resources.dart';
import 'webgl_shaders.dart';
import 'webgl_textures.dart';
import 'webgl_transfer.dart';
import 'webgl_types.dart';

export 'webgl_bundle.dart';
export 'webgl_encoder.dart';
export 'webgl_loaded_shaders.dart';
export 'webgl_transfer.dart';
export 'webgl_types.dart';

/// WebGL2 as a [GraphicsDevice].
///
/// **Its capabilities are one answer, [features]**, decided once in [open]
/// from what the context and its extensions handed back; the `supportsX`
/// getters read it through [DeviceCapabilityForwarders]. Why each feature is
/// or is not there is written beside it, in [_decideFeatures].
final class WebGlDevice extends GraphicsDevice
    with EncodedImageUpload, SynchronousBufferReadback {
  // TODO(webgl): GPU timings per labelled pass — `onGpuTimings` could be fed
  // from `EXT_disjoint_timer_query_webgl2`'s TIME_ELAPSED queries around each
  // pass, which this backend already uses for timestamp query sets; nothing
  // wires them to the frame's labels yet, so gpuTimestamps stays unlisted.
  @override
  void onGpuTimings(void Function(GpuFrameTimings timings)? listener) {}

  // TODO(webgl): compute — WebGL2 has no compute stage; the WebGL 2.0
  // Compute draft was abandoned, and compute on the web goes through the
  // WebGPU backend. Nothing here can unblock it.
  static UnsupportedCapability _noCompute() => UnsupportedCapability(
    DeviceFeature.compute,
    backend: webglBackendName,
    reason:
        'WebGL2 has no compute stage — the WebGL 2.0 Compute draft was '
        'abandoned; compute on the web goes through the WebGPU backend',
  );

  @override
  StorageBuffer createStorageBuffer(
    ByteData bytes, {
    bool hostReadable = false,
    bool bindableAsIndices = false,
  }) => throw _noCompute();

  @override
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) =>
      throw _noCompute();

  @override
  ComputeEncoder beginComputePass({
    String? label,
    PassTimestampWrites? timestampWrites,
  }) => throw _noCompute();

  /// A buffer [createBuffer] made [BufferUsage.hostReadable], once every
  /// pass before this call is done with it: a fence, then
  /// `getBufferSubData`, which by then has nothing to wait for.
  @override
  Future<ByteData> readBuffer(StorageBuffer buffer) async {
    features.require(DeviceFeature.buffers, backend: webglBackendName);
    if (!buffer.hostReadable) {
      throw ArgumentError.value(buffer, 'buffer', 'is not hostReadable');
    }
    webglRefuseMapped(webglBufferOf(buffer), 'readBuffer');
    await webglFinishedSoFar(_gl);
    return webglReadBufferNow(_gl, buffer);
  }

  @override
  void releaseStorageBuffer(StorageBuffer buffer) {
    final backend = webglBufferOf(buffer);
    if (!webglReleaseBuffer(_gl, backend.buffer, _persistentBuffers)) return;
    _bufferTargets.removeWhere(
      (web.WebGLBuffer it, int _) => identical(it, backend.buffer),
    );
  }

  @override
  List<TextureFormat> get hdrOutputFormats => const <TextureFormat>[];

  WebGlDevice._(this._gl, this._canvas, this._library);

  @override
  String get backendName => 'WebGL2';

  // ------------------------------------------------ 1.0: a context that goes

  /// `webglcontextlost` and `webglcontextrestored` on [_canvas], as
  /// [GraphicsDevice.lost]. A WebGL context is recoverable: the loss event
  /// says so, and the restore that may follow arrives as a second event with
  /// [DeviceLoss.restored]. Every handle is spent either way; a renderer is
  /// rebuilt on this device after the restore.
  ///
  /// The loss is `preventDefault`ed, which is what tells the browser the page
  /// wants the context back.
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
    _canvas
      ..addEventListener(
        'webglcontextlost',
        (web.Event event) {
          event.preventDefault();
          _isLost = true;
          if (_disposed || _lost.isClosed) return;
          _lost.add(
            const DeviceLoss(
              reason: DeviceLossReason.unknown,
              message: 'webglcontextlost',
              isRecoverable: true,
            ),
          );
        }.toJS,
      )
      ..addEventListener(
        'webglcontextrestored',
        (web.Event _) {
          _isLost = false;
          if (_disposed || _lost.isClosed) return;
          _lost.add(
            const DeviceLoss(
              reason: DeviceLossReason.unknown,
              message: 'webglcontextrestored',
              isRecoverable: true,
              restored: true,
            ),
          );
        }.toJS,
      );
  }

  // Debug groups and labels. WebGL2 has no `KHR_debug`, so neither reaches
  // a browser's GPU tools or a frame capture. The labels are kept by the
  // inherited `setLabel` for `labelOf`, and a pass that cannot draw into its
  // attachments names them; the groups are kept by the encoder, whose
  // refusals and unbound-slot reports say which group was open. A
  // `RecordingDevice` over this device writes both into its trace.

  /// Vertex attribute locations currently switched on in this context.
  ///
  /// **Context state, not pass state, and that distinction is the whole bug.**
  /// `enableVertexAttribArray` acts on the context — on the default vertex
  /// array object — so it outlives the encoder that called it, outlives the
  /// pass, and outlives the frame. An encoder that tracked its own would put
  /// back only what it had switched on itself, which is exactly nothing when
  /// the next pass is a new encoder.
  ///
  /// The sky is what found it. Its vertex stage takes eight attributes against
  /// a mesh's five and a post stage's none, so after the sky pass ended,
  /// locations 5, 6 and 7 stayed on with no buffer under them — and in WebGL2 a
  /// draw with an enabled array and no bound buffer is `INVALID_OPERATION`,
  /// dropped with nothing logged. The composite never landed and the frame came
  /// back the clear colour. Not a scene missing its sky: black.
  final Set<int> _enabledAttributeLocations = <int>{};

  /// Vertex attribute locations currently carrying a non-zero divisor.
  ///
  /// Context state for the same reason as the set above, and it leaked the same
  /// way: `vertexAttribDivisor` belongs to the location, survives the draw, the
  /// buffer, the program and the pass, and an encoder that tracked its own put
  /// back only what it had set — which is nothing, once the next pass is a new
  /// encoder.
  final Set<int> _instancedAttributeLocations = <int>{};

  /// Builds a device over a _canvas of [width] by [height].
  ///
  /// The _canvas is the thing the browser composites; see [blitToCanvas]. It is
  /// created here rather than taken as an argument so that nothing above has to
  /// know a DOM element is involved.
  ///
  /// [sources] are the engine's own shaders by default — GLSL ES 3.00,
  /// translated from `flutter3d_shaders` by `tool/generate_shaders.dart`.
  /// There is no compiled bundle on this backend: a browser compiles GLSL
  /// itself, so a "bundle" is a map from the engine's entry point names to
  /// source text.
  ///
  /// [highpMaterials] compiles the lit models at highp throughout, the
  /// picture before `A1.1` — see [WebGlShaderLibrary.highpMaterials].
  ///
  /// **Throws a [DeviceUnavailableException]** when the browser has no
  /// WebGL2, rather than returning null (decision 4). A browser without it is
  /// not a case a game can carry on from, and the sentence saying so belongs
  /// here rather than in each game. This is the one way to open the backend
  /// since 1.0 — `openWebGl` was the same call with the sentence added — and
  /// what `registerWebGlBackend` adds to an engine's registry.
  static WebGlDevice open({
    required int width,
    required int height,
    ShaderSources? sources,
    bool highpMaterials = false,
  }) {
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = width
      ..height = height;
    // preserveDrawingBuffer, because this engine does not drive the browser's
    // frame loop. A WebGL canvas is cleared as soon as the browser composites
    // it, so a frame rendered once — a golden, a still, anything not inside a
    // requestAnimationFrame — has already been wiped by the time Flutter shows
    // the platform view. The result is a black rectangle with no error
    // anywhere, which is how this was found: every check passed and nothing
    // appeared.
    //
    // It costs a copy per composite on some drivers. A frame the user cannot
    // see costs more.
    // antialias: false, because the canvas is a blit target and nothing else.
    // A WebGL context is antialiased by default, which makes its default
    // framebuffer multisampled — and blitting into a multisampled draw buffer
    // is INVALID_OPERATION, so the presenting blit failed on every frame while
    // the frame itself was drawn perfectly well. Nothing else reported it: the
    // error sat in the queue, the canvas stayed black, and every counter in the
    // engine read correctly.
    //
    // Losing nothing by it either. The engine resolves its own MSAA offscreen;
    // this surface only receives the finished picture.
    final attributes = web.WebGLContextAttributes(
      preserveDrawingBuffer: true,
      antialias: false,
    );
    final gl =
        canvas.getContext('webgl2', attributes) as web.WebGL2RenderingContext?;
    if (gl == null) {
      throw const DeviceUnavailableException(
        'WebGL2 is not available in this browser. The engine needs WebGL2 '
        '(not WebGL1) and EXT_color_buffer_float for its HDR target.',
        backend: webglBackendName,
      );
    }

    // WebGL2 accepts RGBA16F as a *texture* format out of the box and refuses
    // to *render* to it: half-float colour is not renderable until this
    // extension is asked for. The engine's whole scene pass targets RGBA16F —
    // it renders in linear HDR and tone maps at the end — so without this every
    // framebuffer it builds is incomplete, every draw into one is dropped, and
    // no error is raised anywhere. The frame comes back transparent black and
    // the draw counters all say the right numbers.
    //
    // That is exactly how this was found, after the counters were believed
    // once.
    final colorBufferFloat = gl.getExtension('EXT_color_buffer_float');

    // And this one, which is the other half and easy to miss. Rendering *to* a
    // half-float target is EXT_color_buffer_float; *sampling* one with linear
    // filtering is OES_texture_float_linear, and without it such a texture is
    // incomplete — it samples as zero, silently, with no error and no warning.
    //
    // The engine's shadow maps are half-float and bound with a linear sampler,
    // so this is the difference between shadows and no shadows. The frame comes
    // back fully lit, which reads as "the shadow pass did not run" and is
    // really "the lookup read nothing".
    final floatLinear = gl.getExtension('OES_texture_float_linear');
    // `A2.8`: clip depth in `[0, 1]`, where the extension is offered — and
    // the depth this backend allocates a float there, so a reversed
    // projection keeps its precision. Asked before the multisample probe,
    // which tries the depth format this answers.
    final clipControl = _enableClipControl(gl);
    final device =
        WebGlDevice._(
            gl,
            canvas,
            WebGlShaderLibrary(
              gl,
              sources ?? webGlEngineShaders,
              highpMaterials: highpMaterials,
            ),
          )
          .._clipControl = clipControl
          .._floatLinear = floatLinear != null
          .._colorBufferFloat = colorBufferFloat != null
          // The rest of what WebGL2 offers past its core, each asked for once
          // here because an extension is off until `getExtension` names it.
          .._floatBlend = gl.getExtension('EXT_float_blend') != null
          .._depthClamp = gl.getExtension('EXT_depth_clamp') != null
          .._blendFuncExtended =
              gl.getExtension('WEBGL_blend_func_extended') != null
          .._timerQuery = _grantedTimestamps(gl)
          .._multiDraw =
              gl.getExtension('WEBGL_multi_draw') as web.WEBGL_multi_draw?
          .._baseVertexBaseInstance = gl.getExtension(
            'WEBGL_draw_instanced_base_vertex_base_instance',
          )
          .._drawBuffersIndexed =
              gl.getExtension('OES_draw_buffers_indexed')
                  as web.OES_draw_buffers_indexed?
          .._msaaSamples = _provenMsaaSamples(
            gl,
            depth: clipControl
                ? web.WebGL2RenderingContext.DEPTH32F_STENCIL8
                : web.WebGL2RenderingContext.DEPTH24_STENCIL8,
          )
          .._maxAnisotropy = _queryMaxAnisotropy(gl)
          .._maxColorAttachments = _queryMaxColorAttachments(gl)
          .._compressedTextureSupport = CompressedTextureSupport.query(gl);
    return device
      .._features = device._decideFeatures()
      .._limits = device._queryLimits();
  }

  /// `EXT_disjoint_timer_query_webgl2`, when it is granted *and* counts
  /// timestamps. The extension is offered by browsers whose GPU process
  /// answers `QUERY_COUNTER_BITS_EXT` of zero for `TIMESTAMP_EXT` — elapsed
  /// time works there, a point in time does not — and a timestamp query set
  /// on such a context would read zeros. `getQuery` is called through
  /// `callMethod` because `package:web` types its answer as a query object,
  /// and for this parameter it is a number.
  static web.EXT_disjoint_timer_query_webgl2? _grantedTimestamps(
    web.WebGL2RenderingContext gl,
  ) {
    final timer =
        gl.getExtension('EXT_disjoint_timer_query_webgl2')
            as web.EXT_disjoint_timer_query_webgl2?;
    if (timer == null) return null;
    final bits = (gl as JSObject).callMethod<JSAny?>(
      'getQuery'.toJS,
      webglTimestampTarget.toJS,
      web.EXT_disjoint_timer_query_webgl2.QUERY_COUNTER_BITS_EXT.toJS,
    );
    // Drained: a context that does not know the query raises INVALID_ENUM,
    // which is this probe's answer and nobody else's error.
    while (gl.getError() != web.WebGLRenderingContext.NO_ERROR) {}
    return bits != null &&
            bits.isA<JSNumber>() &&
            (bits as JSNumber).toDartInt > 0
        ? timer
        : null;
  }

  /// Every [DeviceFeature] this context has, and beside each the reason it
  /// is or is not here.
  DeviceFeatures _decideFeatures() {
    final compressed = _compressedTextureSupport;
    return DeviceFeatures(<DeviceFeature>[
      // WebGL2 has multisampled renderbuffers, so offscreen MSAA exists — but
      // it cannot be *sampled*, only blitted. The engine uses MSAA by
      // attaching a multisampled colour and a resolve target, which is
      // exactly a blit, so the answer is honest. Measured rather than
      // assumed: [_provenMsaaSamples] asks the driver at [create] and comes
      // back zero on the ones that cannot multisample an HDR format, which is
      // most phones.
      if (_msaaSamples > 1) DeviceFeature.offscreenMultisample,
      // `glBlendColor` is WebGL1 core, and `CONSTANT_COLOR`/`CONSTANT_ALPHA`
      // are what the four constant-reading factors already mapped to — the
      // setter was the missing half, not the reader.
      DeviceFeature.blendConstant,
      // WebGL2 samples a hand-built chain correctly as a matter of
      // specification: `texStorage2D` allocates every level and
      // `TEXTURE_MAX_LEVEL` bounds it. The device this capability exists to
      // warn about is an OpenGL ES 2 one, which this backend does not run on.
      DeviceFeature.manualMipmaps,
      // WebGL2 has had cube maps since WebGL1, and samples across their
      // edges seamlessly without an extension. Nothing to probe.
      DeviceFeature.cubeTextures,
      // `framebufferTexture2D` takes a level, and WebGL2 attaches any level of
      // an immutable texture — the mip-level restriction was WebGL1's.
      DeviceFeature.renderToMipLevel,
      // Not wireframe: OpenGL ES has no glPolygonMode. See
      // `canDrawPolygonMode`.
      //
      // Alpha to coverage where the context multisamples offscreen targets,
      // which is where coverage has samples to spread over — `P7`.
      if (_msaaSamples > 1) DeviceFeature.alphaToCoverage,
      // `DEPTH24_STENCIL8` is WebGL2 core, and it is the format every depth
      // attachment this backend makes is allocated in.
      DeviceFeature.stencil,
      // Not gpuTimestamps (see the TODO at `onGpuTimings`), and not compute
      // (see the TODO at `createStorageBuffer`).
      //
      // `OES_texture_float_linear` — `S2`. Filtering a 32-bit float texture
      // is this extension alone, and without it such a texture samples as
      // zero.
      if (_floatLinear) DeviceFeature.float32Filterable,
      // Rendering into one is `EXT_color_buffer_float`, which [create] asks
      // for because the HDR target needs it.
      if (_colorBufferFloat) DeviceFeature.float32Renderable,
      // `A2.8`: clip depth in `[0, 1]` and a float depth, both from
      // `EXT_clip_control` — see [depthRange].
      if (_clipControl) DeviceFeature.reversedDepth,
      // Where `OES_draw_buffers_indexed` is offered, which is most desktop
      // browsers and not every phone — `R8`. Without it weighted blended
      // transparency draws its list once per target.
      if (_drawBuffersIndexed != null) DeviceFeature.independentBlend,
      // `TEXTURE_2D_ARRAY`, `TEXTURE_3D` and `framebufferTextureLayer` are
      // WebGL2 core; `texSubImage*` and `compressedTexSubImage*` write any
      // level and layer.
      DeviceFeature.textureArrays,
      DeviceFeature.texture3D,
      DeviceFeature.renderToArrayLayer,
      DeviceFeature.textureWrites,
      // Not cube arrays: TEXTURE_CUBE_MAP_ARRAY is GL ES 3.2, and WebGL2 is
      // ES 3.0 with no extension for it.
      //
      // Vertex, index, uniform and copy buffers, `copyBufferSubData`, the
      // pixel pack and unpack buffers: all core.
      DeviceFeature.buffers,
      DeviceFeature.bufferCopy,
      DeviceFeature.textureCopy,
      DeviceFeature.bufferTextureCopy,
      // Not storage textures, read-write storage, render-stage storage,
      // indirect draws or dispatches: WebGL2 has no storage resources and no
      // indirect commands. See the TODOs at each refusal.
      DeviceFeature.nonIndexedDraw,
      DeviceFeature.depthBias,
      DeviceFeature.colorWriteMask,
      if (_depthClamp) DeviceFeature.depthClamp,
      DeviceFeature.minMaxBlend,
      if (_blendFuncExtended) DeviceFeature.dualSourceBlending,
      // `TEXTURE_COMPARE_MODE` and `TEXTURE_MIN_LOD`/`MAX_LOD` are core. A
      // border colour is not: WebGL2 has no CLAMP_TO_BORDER.
      DeviceFeature.samplerCompare,
      DeviceFeature.samplerLodClamp,
      DeviceFeature.occlusionQuery,
      if (_timerQuery != null) DeviceFeature.timestampQuery,
      // The families as the contract defines them. BC is the whole family,
      // as WebGPU's feature is, so it takes all four extensions that carry
      // its formats here — S3TC (BC1, BC3), its sRGB half, RGTC (BC5) and
      // BPTC (BC7); a context with BPTC alone samples BC7 and says so per
      // format, not as the family. ETC2 and ASTC LDR by their extension. No
      // ASTC HDR: `WEBGL_compressed_texture_astc` is LDR here.
      if (compressed.s3tc &&
          compressed.s3tcSrgb &&
          compressed.rgtc &&
          compressed.bptc)
        DeviceFeature.textureCompressionBC,
      if (compressed.etc2) DeviceFeature.textureCompressionETC2,
      if (compressed.astc) DeviceFeature.textureCompressionASTC,
      if (_colorBufferFloat && _floatBlend) DeviceFeature.float32Blendable,
      if (_colorBufferFloat) DeviceFeature.rg11b10Renderable,
      // Uniform blocks are UBOs here with layouts read back from the linked
      // program, so laid-out bytes go straight into one.
      DeviceFeature.uniformBytes,
      // A mapping is a copy here (WebGL2 maps nothing into host memory), and
      // `getBufferSubData` is the synchronous read WebGPU does not have.
      DeviceFeature.mappedBuffers,
      DeviceFeature.synchronousReadback,
      // Recorded and replayed: WebGL has no native bundle, and the contract
      // allows a replay.
      DeviceFeature.renderBundles,
      // One `WEBGL_multi_draw` call where the extension is granted, a loop of
      // draws where it is not — which the contract allows.
      DeviceFeature.multiDraw,
      if (_baseVertexBaseInstance != null) DeviceFeature.baseVertexBaseInstance,
      // Not pipeline statistics: WebGL2 has no such query and no extension
      // for one.
    ]);
  }

  /// The numbers this context answers `getParameter` with, in the contract's
  /// names. Where GL has no such limit — bind groups, a buffer's size — the
  /// WebGPU default stands; where this backend has none of the thing —
  /// storage, compute, 1D textures — the limit is zero.
  DeviceLimits _queryLimits() {
    int ask(int name, int fallback) {
      final value = _gl.getParameter(name);
      return value != null && value.isA<JSNumber>()
          ? (value as JSNumber).toDartInt
          : fallback;
    }

    int least(int a, int b) => a < b ? a : b;
    final textureSize = ask(web.WebGLRenderingContext.MAX_TEXTURE_SIZE, 2048);
    final attributes = ask(web.WebGLRenderingContext.MAX_VERTEX_ATTRIBS, 16);
    final units = least(
      ask(web.WebGLRenderingContext.MAX_TEXTURE_IMAGE_UNITS, 16),
      ask(web.WebGLRenderingContext.MAX_VERTEX_TEXTURE_IMAGE_UNITS, 16),
    );
    return DeviceLimits(
      // GL ES has no 1D texture; see `webglTargetOf`.
      maxTextureDimension1D: 0,
      maxTextureDimension2D: textureSize,
      maxTextureDimension3D: ask(
        web.WebGL2RenderingContext.MAX_3D_TEXTURE_SIZE,
        256,
      ),
      maxTextureArrayLayers: ask(
        web.WebGL2RenderingContext.MAX_ARRAY_TEXTURE_LAYERS,
        256,
      ),
      maxColorAttachments: _maxColorAttachments,
      // GL budgets attachments by count, not bytes; the widest texel any
      // colour format here has is sixteen bytes.
      maxColorAttachmentBytesPerSample: _maxColorAttachments * 16,
      maxSampleCount: _msaaSamples > 1 ? _msaaSamples : 1,
      maxSamplerAnisotropy: _maxAnisotropy,
      maxSampledTexturesPerShaderStage: units,
      maxSamplersPerShaderStage: units,
      maxStorageBuffersPerShaderStage: 0,
      maxStorageTexturesPerShaderStage: 0,
      maxUniformBuffersPerShaderStage: least(
        ask(web.WebGL2RenderingContext.MAX_VERTEX_UNIFORM_BLOCKS, 12),
        ask(web.WebGL2RenderingContext.MAX_FRAGMENT_UNIFORM_BLOCKS, 12),
      ),
      maxUniformBufferBindingSize: ask(
        web.WebGL2RenderingContext.MAX_UNIFORM_BLOCK_SIZE,
        16384,
      ),
      maxStorageBufferBindingSize: 0,
      minUniformBufferOffsetAlignment: ask(
        web.WebGL2RenderingContext.UNIFORM_BUFFER_OFFSET_ALIGNMENT,
        256,
      ),
      // Each attribute names its own buffer in GL, so the attribute count
      // is the buffer count too.
      maxVertexBuffers: attributes,
      maxVertexAttributes: attributes,
      // WebGL caps `vertexAttribPointer`'s stride at 255, whatever the GL
      // underneath allows.
      maxVertexBufferArrayStride: 255,
      maxInterStageShaderVariables: ask(
        web.WebGLRenderingContext.MAX_VARYING_VECTORS,
        15,
      ),
      maxComputeWorkgroupStorageSize: 0,
      maxComputeInvocationsPerWorkgroup: 0,
      maxComputeWorkgroupSizeX: 0,
      maxComputeWorkgroupSizeY: 0,
      maxComputeWorkgroupSizeZ: 0,
      maxComputeWorkgroupsPerDimension: 0,
    );
  }

  late final DeviceFeatures _features;
  late final DeviceLimits _limits;

  @override
  DeviceFeatures get features => _features;

  @override
  DeviceLimits get limits => _limits;

  /// See [webglTextureFormatSupport], which this reads with what [open]
  /// found.
  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      webglTextureFormatSupport(
        format,
        WebGlFormatCaps(
          colorBufferFloat: _colorBufferFloat,
          floatLinear: _floatLinear,
          floatBlend: _floatBlend,
          halfFloatMultisample: _msaaSamples > 1,
          compressed: _compressedTextureSupport,
        ),
      );

  bool _colorBufferFloat = false;
  bool _floatBlend = false;
  bool _depthClamp = false;
  bool _blendFuncExtended = false;

  /// `EXT_disjoint_timer_query_webgl2` where it counts timestamps; see
  /// [_grantedTimestamps].
  web.EXT_disjoint_timer_query_webgl2? _timerQuery;

  web.WEBGL_multi_draw? _multiDraw;

  /// `WEBGL_multi_draw`, for the encoder, or null where it was not granted
  /// and `multiDraw` loops.
  web.WEBGL_multi_draw? get _multiDrawExtension => _multiDraw;

  JSObject? _baseVertexBaseInstance;

  /// `WEBGL_draw_instanced_base_vertex_base_instance`, which `package:web`
  /// has no binding for, as a plain object the encoder calls by name.
  JSObject? get _baseVertexBaseInstanceExtension => _baseVertexBaseInstance;

  /// What `MAX_DRAW_BUFFERS` says here — `gfx-50n`.
  ///
  /// Core in WebGL2 rather than an extension, and the specification's floor
  /// is four, so this is the one backend where the number is a genuine query
  /// with a guaranteed answer. Asked anyway rather than assumed four: a
  /// software GL behind a headless browser is still a GL, and the floor is a
  /// promise about conforming implementations rather than about whatever is
  /// actually running.
  static int _queryMaxColorAttachments(web.WebGL2RenderingContext gl) {
    final value = gl.getParameter(web.WebGL2RenderingContext.MAX_DRAW_BUFFERS);
    final max = value != null && value.isA<JSNumber>()
        ? (value as JSNumber).toDartInt
        : 1;
    return max < 1 ? 1 : max;
  }

  /// What `EXT_texture_filter_anisotropic` allows here, or 1 without it.
  ///
  /// Asked for at create time like every other extension, because in WebGL
  /// an extension is not on until `getExtension` has named it — and the
  /// parameter it unlocks reads as an error until then. The extension is
  /// universal on desktop browsers and near-universal on mobile ones, but
  /// "near" is the word, so the answer is a query rather than a constant.
  static int _queryMaxAnisotropy(web.WebGL2RenderingContext gl) {
    if (gl.getExtension('EXT_texture_filter_anisotropic') == null) return 1;
    final value = gl.getParameter(
      web.EXT_texture_filter_anisotropic.MAX_TEXTURE_MAX_ANISOTROPY_EXT,
    );
    // A float per the extension's specification, whole-valued in practice.
    // Floored rather than rounded so a driver answering 15.99 is not asked
    // for sixteen, which would be INVALID_VALUE on every bind.
    final max = value != null && value.isA<JSNumber>()
        ? (value as JSNumber).toDartDouble.floor()
        : 1;
    return max < 1 ? 1 : max;
  }

  /// The sample count the MSAA path can actually have here, proven rather
  /// than asked for.
  ///
  /// **Desktop GL multisamples a half-float renderbuffer; mobile GLES very
  /// often does not** — and the refusal is not an answer at create time, it
  /// is a `GL_INVALID_OPERATION` out of `renderbufferStorageMultisample` on
  /// every frame, which is a white screen on every phone. That is how the
  /// demos looked the day somebody first opened them on one.
  ///
  /// Proven by doing, not by asking: the Android emulator's GL translator
  /// *advertises* multisampled RGBA16F through `getInternalformatParameter`
  /// and then errors on the allocation anyway, so the only trustworthy
  /// probe is a real one-pixel allocation checked with `getError`. Both
  /// formats the MSAA framebuffer attaches are tried — half-float colour
  /// and packed depth-stencil — because a pair only works when both halves
  /// do. Zero means the renderer takes its ordinary single-sample path.
  static int _provenMsaaSamples(
    web.WebGL2RenderingContext gl, {
    required int depth,
  }) {
    // Drained first: the error queue is cumulative, and a stale entry would
    // convict the first candidate below of somebody else's mistake.
    while (gl.getError() != 0) {}

    for (final samples in const <int>[4, 2]) {
      var ok = true;
      for (final format in <int>[web.WebGL2RenderingContext.RGBA16F, depth]) {
        final buffer = gl.createRenderbuffer();
        gl.bindRenderbuffer(web.WebGLRenderingContext.RENDERBUFFER, buffer);
        gl.renderbufferStorageMultisample(
          web.WebGLRenderingContext.RENDERBUFFER,
          samples,
          format,
          1,
          1,
        );
        if (gl.getError() != 0) ok = false;
        gl.deleteRenderbuffer(buffer);
      }
      gl.bindRenderbuffer(web.WebGLRenderingContext.RENDERBUFFER, null);
      if (ok) return samples;
    }
    return 0;
  }

  final web.WebGL2RenderingContext _gl;
  final web.HTMLCanvasElement _canvas;
  final WebGlShaderLibrary _library;

  /// Every persistent texture and renderbuffer this device has handed out,
  /// tracked so [dispose] has something to delete.
  ///
  /// **Persistent, not transient.** The buffers a pass makes for `submit`-time
  /// geometry are already deleted at the end of the pass that made them — see
  /// [WebGlEncoder.submit] — because their lifetime is the pass. A texture from
  /// [createTexture] or [createCubeTextureFromPixels] has no such moment: WebGL2
  /// objects are explicitly deletable, unlike flutter_gpu's `Texture`, so
  /// nothing frees these unless something tracks them and calls
  /// `gl.deleteTexture`/`gl.deleteRenderbuffer` itself. The tracking and the
  /// deletion themselves are `webgl_resources.dart`'s; these lists are what it
  /// is handed.
  final List<web.WebGLTexture> _persistentTextures = <web.WebGLTexture>[];
  final List<web.WebGLRenderbuffer> _persistentRenderbuffers =
      <web.WebGLRenderbuffer>[];

  /// Every geometry buffer [uploadGeometry] has handed out, for the same
  /// reason as [_persistentTextures].
  final List<web.WebGLBuffer> _persistentBuffers = <web.WebGLBuffer>[];

  /// The GL target each buffer in [_persistentBuffers] was bound to when made
  /// — `ARRAY_BUFFER` or `ELEMENT_ARRAY_BUFFER` — since a buffer bound to one
  /// for life cannot be rebound to the other, and [overwriteGeometry] needs to
  /// bind it again without being told a second time. See
  /// `webglUploadGeometry`.
  final Map<web.WebGLBuffer, int> _bufferTargets = <web.WebGLBuffer, int>{};

  /// Whether [dispose] has already run. Guards against deleting the same GL
  /// object twice, which is harmless by the WebGL spec but worth refusing
  /// anyway: a second [dispose] call is a caller mistake worth surfacing rather
  /// than one this device quietly absorbs.
  bool _disposed = false;

  /// The count of persistent GL objects currently tracked, for tests: textures,
  /// renderbuffers and buffers, plus the shader library's compiled shaders and
  /// linked programs — which are driver objects just the same, and were the one
  /// class this count (and [dispose]) used to miss. Falls to zero after
  /// [dispose].
  int get debugTrackedResourceCount =>
      _persistentTextures.length +
      _persistentRenderbuffers.length +
      _persistentBuffers.length +
      _library.debugTrackedResourceCount +
      _loaded.fold(
        0,
        (int count, WebGlLoadedShaderLibrary library) =>
            count + library.debugTrackedResourceCount,
      );

  /// Every library [loadShaders] built, so [dispose] can delete what they
  /// compiled: a loaded stage is a driver object like any of the engine's.
  final List<WebGlLoadedShaderLibrary> _loaded = <WebGlLoadedShaderLibrary>[];

  /// The bundle's `webgl` section, compiled by the browser on first use.
  /// Nothing is waited for; the future is the interface's, for the backend
  /// whose loader is asynchronous.
  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async {
    final library = WebGlLoadedShaderLibrary.load(_gl, _library, bytes);
    _loaded.add(library);
    return library;
  }

  @override
  void releaseTexture(TextureHandle texture) {
    final backend = texture.backend;
    if (backend is! WebGlTexture) return;
    webglReleaseTexture(
      _gl,
      backend,
      _persistentTextures,
      _persistentRenderbuffers,
    );
  }

  /// Deletes the buffer and forgets which target it was made against.
  ///
  /// The second half is not bookkeeping for its own sake. [_bufferTargets] is
  /// what [overwriteGeometry] recognises this device's buffers by, so an entry
  /// left behind was a map growing by one per released mesh for the life of
  /// the tab — and an overwrite of a released buffer found its target, bound a
  /// deleted object and wrote into nothing, where it should have been refused
  /// as a buffer this device does not hold.
  @override
  void releaseGeometry(GeometryBuffer geometry) {
    final backend = geometry.backend;
    if (!webglReleaseBuffer(_gl, backend, _persistentBuffers)) return;
    _bufferTargets.removeWhere(
      (web.WebGLBuffer buffer, int _) => identical(buffer, backend),
    );
  }

  @override
  void dispose() {
    if (_disposed) {
      throw StateError('WebGlDevice.dispose() was already called');
    }
    _disposed = true;
    unawaited(_lost.close());
    webglDisposePersistentResources(
      _gl,
      _persistentTextures,
      _persistentRenderbuffers,
      _persistentBuffers,
    );
    _bufferTargets.clear();
    // The shader library's programs and shaders go with the device that made
    // them: the library has no life of its own — it is built in [create] and
    // reachable only through this device — so this is the one moment they can
    // be deleted. The loaded libraries first, because their programs live in
    // the device's library and are forgotten through it.
    for (final library in _loaded) {
      library.dispose();
    }
    _loaded.clear();
    _library.dispose();

    // What can be released of the _canvas and the context, released honestly.
    // The platform-view registry has no unregister, and the factory closure
    // [_register] handed it holds [_canvas] for the life of the app — that pin
    // is not this device's to undo. What *is*: the element's place in the
    // document, and the GPU-side context behind it. `WEBGL_lose_context` is
    // the one sanctioned way to free a context before its _canvas is collected,
    // so it is asked for here and used where the browser has it.
    _canvas.remove();
    final lose =
        _gl.getExtension('WEBGL_lose_context') as web.WEBGL_lose_context?;
    lose?.loseContext();
    // Losing the context queues CONTEXT_LOST_WEBGL. The loss is this method's
    // own doing rather than an error the caller should be handed — a test
    // draining the queue after dispose would blame it on the deletes above —
    // so the queue is drained before returning.
    for (var i = 0; i < 8; i++) {
      if (_gl.getError() == web.WebGLRenderingContext.NO_ERROR) break;
    }
  }

  /// Whether half-float textures may be filtered linearly here. Diagnostic:
  /// see the note in [open].
  bool _floatLinear = false;

  /// Which compressed-texture extensions this context actually has, queried
  /// once in [open]. See `CompressedTextureSupport`.
  CompressedTextureSupport _compressedTextureSupport =
      const CompressedTextureSupport(
        etc2: false,
        s3tc: false,
        s3tcSrgb: false,
        rgtc: false,
        bptc: false,
        astc: false,
      );

  /// Whether this context can sample a half-float texture with linear
  /// filtering. False makes every shadow map read as zero.
  bool get _supportsFloatLinearFiltering => _floatLinear;

  /// `OES_draw_buffers_indexed`, when the context offers it — `R8`. What a
  /// blend for one draw buffer is set through; null leaves the plain blend
  /// functions, which set every draw buffer at once.
  web.OES_draw_buffers_indexed? _drawBuffersIndexed;

  /// What [_queryMaxAnisotropy] found at [open]. One without the extension.
  ///
  /// The extension's ceiling, and the number every bind clamps to —
  /// `limits.maxSamplerAnisotropy`: in GL the parameter is texture state
  /// rather than sampler state, and a value above this is `INVALID_VALUE` —
  /// an error in the queue, a bind that did not land, and a picture that is
  /// merely blurrier than asked for.
  int _maxAnisotropy = 1;

  /// What [_queryMaxColorAttachments] found at [open] —
  /// `limits.maxColorAttachments`. One until then, which is the answer that
  /// refuses everything rather than the one that promises it.
  int _maxColorAttachments = 1;

  @override
  ShaderLibrary get shaders => _library;

  /// RGBA8. There is no `defaultColorFormat` to ask WebGL for — the _canvas is
  /// what it is — so this states the engine's own choice rather than reporting
  /// a device property. On flutter_gpu the same getter is a genuine runtime
  /// query, which is a small asymmetry the HAL's wording already allows for.
  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  /// `DEPTH24_STENCIL8`, or `DEPTH32F_STENCIL8` where `EXT_clip_control` put
  /// clip depth in `[0, 1]` — `A2.8`. Both are WebGL2 core; the float is
  /// what a reversed projection needs to gain anything, and it is chosen
  /// only where the depth range lets it, which is where [features] reports
  /// `DeviceFeature.reversedDepth`.
  @override
  TextureFormat get defaultDepthStencilFormat => _clipControl
      ? TextureFormat.d32FloatS8UInt
      : TextureFormat.d24UnormS8Uint;

  @override
  // OpenGL, and WebGL2 exposes no glClipControl to change it.
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.bottomLeft;

  /// OpenGL's, unless `EXT_clip_control` was offered — `A2.8` — in which
  /// case [open] set it to `ZERO_TO_ONE_EXT` and the engine's matrices go
  /// through unremapped. The window depth a frame stores is the same number
  /// either way for an ordinary projection; what the extension buys is a
  /// reversed one that keeps its precision.
  @override
  DepthRange get depthRange =>
      _clipControl ? DepthRange.zeroToOne : DepthRange.negativeOneToOne;

  /// Whether [open] found `EXT_clip_control` and turned clip depth to
  /// `[0, 1]` with it.
  bool _clipControl = false;

  /// Asks for `EXT_clip_control` and, where it is offered, puts clip depth in
  /// `[0, 1]` with the origin where OpenGL keeps it — `A2.8`. False where it
  /// is not offered, which leaves the context as WebGL2 makes it.
  ///
  /// Through `callMethod` because `package:web` does not name the extension.
  /// The state belongs to the context and is never set again: every pass on
  /// this device draws in the one depth range [depthRange] reports.
  static bool _enableClipControl(web.WebGL2RenderingContext gl) {
    final extension = gl.getExtension('EXT_clip_control');
    if (extension == null) return false;
    // `LOWER_LEFT_EXT` keeps OpenGL's origin — the backend's row zero is at
    // the bottom, and `framebufferOrigin` says so — and `ZERO_TO_ONE_EXT` is
    // the depth range.
    const lowerLeft = 0x8CA1;
    const zeroToOne = 0x935F;
    extension.callMethod<JSAny?>(
      'clipControlEXT'.toJS,
      lowerLeft.toJS,
      zeroToOne.toJS,
    );
    // Drained: a context that refused the call says so here, and the range
    // is then the one it was.
    final refused = gl.getError() != web.WebGLRenderingContext.NO_ERROR;
    while (gl.getError() != web.WebGLRenderingContext.NO_ERROR) {}
    return !refused;
  }

  @override
  // Renderable here only because EXT_color_buffer_float is requested when the
  // context is made; see create(). Without it this is a texture format that
  // silently accepts no draws.
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  /// What [_provenMsaaSamples] measured at [open]. Zero on drivers that
  /// cannot multisample the HDR formats — most phones.
  int _msaaSamples = 0;

  @override
  int get preferredSampleCount => _msaaSamples;

  // ------------------------------------------------------------------------
  // 1.0: the rest of the contract. Every call gates on its feature first,
  // before it looks at a handle — a refusal has to name the feature whatever
  // it was handed.
  // ------------------------------------------------------------------------

  /// 2D, 2D-array, 3D and cube textures; see `webgl_textures.dart`. A
  /// [RenderTargetDescriptor] is the pool's 2D target, made as it always was;
  /// any other descriptor is the general form, `textureWrites`.
  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    if (descriptor is RenderTargetDescriptor) return _createTarget(descriptor);
    features.require(DeviceFeature.textureWrites, backend: webglBackendName);
    switch (descriptor.dimension) {
      case TextureDimension.d2Array:
        features.require(
          DeviceFeature.textureArrays,
          backend: webglBackendName,
        );
      case TextureDimension.d3:
        features.require(DeviceFeature.texture3D, backend: webglBackendName);
      case TextureDimension.cube:
        features.require(DeviceFeature.cubeTextures, backend: webglBackendName);
      case TextureDimension.cubeArray:
        // TODO(webgl): cube-array textures — TEXTURE_CUBE_MAP_ARRAY is
        // OpenGL ES 3.2 and WebGL2 is ES 3.0, with no extension for it.
        // Only a later WebGL would unblock it.
        throw UnsupportedCapability(
          DeviceFeature.cubeArrayTextures,
          backend: webglBackendName,
          reason: 'cube-map arrays are OpenGL ES 3.2, and WebGL2 is ES 3.0',
        );
      case TextureDimension.d1:
        throw UnsupportedError(
          'WebGL2 has no 1D texture: OpenGL ES never had one. Make a 2D '
          'texture one texel high.',
        );
      case TextureDimension.d2:
        break;
    }
    if (descriptor.usage.contains(TextureUsage.storage)) {
      // TODO(webgl): storage textures — WebGL2 has no image load/store
      // (that is OpenGL ES 3.1); storage on the web is the WebGPU backend's.
      throw UnsupportedCapability(
        DeviceFeature.storageTextures,
        backend: webglBackendName,
        reason: 'WebGL2 has no image load/store; that is OpenGL ES 3.1',
      );
    }
    final limits = this.limits;
    final tooBig = switch (descriptor.dimension) {
      TextureDimension.d3 =>
        descriptor.width > limits.maxTextureDimension3D ||
            descriptor.height > limits.maxTextureDimension3D ||
            descriptor.depthOrArrayLayers > limits.maxTextureDimension3D,
      _ =>
        descriptor.width > limits.maxTextureDimension2D ||
            descriptor.height > limits.maxTextureDimension2D ||
            descriptor.depthOrArrayLayers > limits.maxTextureArrayLayers,
    };
    if (tooBig) {
      throw ArgumentError('$descriptor is past this context\'s limits');
    }
    return webglCreateTextureWithDescriptor(
      _gl,
      _persistentTextures,
      _persistentRenderbuffers,
      _compressedTextureSupport,
      descriptor,
    );
  }

  @override
  void writeTexture(
    TextureHandle target,
    ByteData data, {
    TextureRegion? region,
    int mipLevel = 0,
    int? bytesPerRow,
  }) {
    features.require(DeviceFeature.textureWrites, backend: webglBackendName);
    webglWriteTexture(
      _gl,
      _compressedTextureSupport,
      target,
      data,
      region: region,
      mipLevel: mipLevel,
      bytesPerRow: bytesPerRow,
    );
  }

  @override
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) {
    features.require(DeviceFeature.buffers, backend: webglBackendName);
    if (descriptor.usage.contains(BufferUsage.storage)) {
      // TODO(webgl): storage buffers — WebGL2 has no shader storage blocks
      // (OpenGL ES 3.1) and no compute; the WebGPU backend has both.
      throw UnsupportedCapability(
        DeviceFeature.renderStageStorage,
        backend: webglBackendName,
        reason: 'WebGL2 has no shader storage buffers; that is OpenGL ES 3.1',
      );
    }
    if (descriptor.usage.contains(BufferUsage.indirect)) {
      // TODO(webgl): indirect buffers — WebGL2 has no indirect draw or
      // dispatch at all (OpenGL ES 3.1 again), so nothing would read one.
      throw UnsupportedCapability(
        DeviceFeature.indirectDraw,
        backend: webglBackendName,
        reason: 'WebGL2 has no indirect commands to read an argument buffer',
      );
    }
    return webglCreateBuffer(
      _gl,
      _persistentBuffers,
      _bufferTargets,
      descriptor,
      contents: contents,
    );
  }

  @override
  void writeBuffer(StorageBuffer target, int offsetInBytes, ByteData bytes) {
    features.require(DeviceFeature.buffers, backend: webglBackendName);
    webglWriteBuffer(_gl, target, offsetInBytes, bytes);
  }

  @override
  Future<MappedBuffer> mapBuffer(
    StorageBuffer buffer,
    MapMode mode, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) async {
    features.require(DeviceFeature.mappedBuffers, backend: webglBackendName);
    final backend = webglBufferOf(buffer);
    final needs = mode == MapMode.read
        ? BufferUsage.hostReadable
        : BufferUsage.hostWritable;
    if (!buffer.usage.contains(needs)) {
      throw ArgumentError.value(
        buffer,
        'buffer',
        'maps for ${mode.name} only when made with $needs',
      );
    }
    webglRefuseMapped(backend, 'mapBuffer');
    final size = webglCheckRange(buffer, offsetInBytes, sizeInBytes);
    await webglFinishedSoFar(_gl);
    // What the range holds now, for both modes: WebGPU hands a write mapping
    // the buffer's current bytes too, and a caller filling part of it keeps
    // the rest.
    final bytes = _readRange(backend, offsetInBytes, size);
    backend.mapped = true;
    return WebGlMapping(
      _gl,
      backend,
      bytes,
      offsetInBytes: offsetInBytes,
      mode: mode,
    );
  }

  /// [size] bytes from [offset] of [buffer], whatever its usage — the read
  /// a mapping starts from. `getBufferSubData` through `COPY_READ_BUFFER`.
  ByteData _readRange(WebGlBuffer buffer, int offset, int size) {
    final js = Uint8List(size).toJS;
    _gl
      ..bindBuffer(web.WebGL2RenderingContext.COPY_READ_BUFFER, buffer.buffer)
      ..getBufferSubData(
        web.WebGL2RenderingContext.COPY_READ_BUFFER,
        offset,
        js,
      )
      ..bindBuffer(web.WebGL2RenderingContext.COPY_READ_BUFFER, null);
    return ByteData.sublistView(Uint8List.fromList(js.toDart));
  }

  /// `getBufferSubData`, which stalls for every command before it — the
  /// price the contract names.
  @override
  ByteData readBufferSync(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    features.require(
      DeviceFeature.synchronousReadback,
      backend: webglBackendName,
    );
    webglRefuseMapped(webglBufferOf(buffer), 'readBufferSync');
    return webglReadBufferNow(
      _gl,
      buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
  }

  @override
  QuerySet createQuerySet(QueryType type, int count) {
    switch (type) {
      case QueryType.occlusion:
        features.require(
          DeviceFeature.occlusionQuery,
          backend: webglBackendName,
        );
      case QueryType.timestamp:
        // TODO(webgl): timestamps where the browser grants
        // EXT_disjoint_timer_query_webgl2 without timestamp counters — only
        // elapsed-time queries would remain, which a pass's begin and end
        // timestamps cannot be built from.
        features.require(
          DeviceFeature.timestampQuery,
          backend: webglBackendName,
          reason:
              'EXT_disjoint_timer_query_webgl2 is absent here, or counts no '
              'timestamps',
        );
      case QueryType.pipelineStatistics:
        // TODO(webgl): pipeline statistics — WebGL2 has no such query and no
        // extension that adds one.
        throw UnsupportedCapability(
          DeviceFeature.pipelineStatisticsQuery,
          backend: webglBackendName,
          reason: 'WebGL2 has no pipeline statistics query',
        );
    }
    return webglCreateQuerySet(_gl, type, count);
  }

  @override
  Future<List<int>> readQueryResults(
    QuerySet querySet, {
    int first = 0,
    int? count,
  }) => webglReadQueryResults(_gl, querySet, first: first, count: count);

  @override
  void releaseQuerySet(QuerySet querySet) =>
      webglReleaseQuerySet(_gl, querySet);

  /// Never refused; each copy gates itself. See `webgl_transfer.dart`.
  @override
  TransferEncoder beginTransferPass({String? label}) =>
      WebGlTransferEncoder(this, _gl);

  /// A recording replayed into a pass; see `webgl_bundle.dart`.
  @override
  RenderBundleEncoder createRenderBundleEncoder(
    RenderBundleDescriptor descriptor,
  ) {
    features.require(DeviceFeature.renderBundles, backend: webglBackendName);
    return WebGlRenderBundleEncoder(this, _gl, descriptor);
  }

  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) => webglCreateCubeRenderTarget(
    _gl,
    _persistentTextures,
    size: size,
    format: format,
    mipLevels: mipLevels,
  );

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) =>
      webglCreateCubeTextureFromPixels(
        _gl,
        _persistentTextures,
        size: size,
        format: format,
        faces: faces,
        mipLevels: mipLevels,
      ) ??
      (throw refuseResource(
        'createCubeTextureFromPixels',
        'six ${size}x$size ${format.name} faces (and a chain of six a '
            'level, each half the last) were not what was given, or WebGL2 '
            'has no upload for the format',
      ));

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) => _library.link(vertex, fragment, layout: layout);

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) =>
      webglUploadGeometry(
        _gl,
        _persistentBuffers,
        _bufferTargets,
        bytes,
        usage,
        release: releaseGeometry,
      );

  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) =>
      webglOverwriteGeometry(_gl, _bufferTargets, target, offsetInBytes, bytes);

  TextureHandle _createTarget(RenderTargetDescriptor spec) =>
      webglCreateTexture(
        _gl,
        _persistentTextures,
        _persistentRenderbuffers,
        spec,
      );

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) =>
      webglCreateTextureFromPixels(
        _gl,
        _persistentTextures,
        _persistentRenderbuffers,
        _compressedTextureSupport,
        width: width,
        height: height,
        format: format,
        pixels: pixels,
        mipLevels: mipLevels,
      ) ??
      (throw refuseResource(
        'createTextureFromPixels',
        'the pixels (or a mip level) are not the size a ${width}x$height '
            '${format.name} texture needs, or WebGL2 has no upload for the '
            'format',
      ));

  /// Decoded by the browser and uploaded as it comes, with the chain built by
  /// `generateMipmap` — `A4.16`. See `webgl_image_decode.dart`.
  ///
  /// [maxDimension] is held to this context's own `MAX_TEXTURE_SIZE` as well,
  /// so a caller who asked for no cap still gets an image the context can
  /// allocate.
  @override
  Future<TextureHandle?> decodeTexture(
    Uint8List encoded, {
    bool mipmaps = false,
    int? maxDimension,
  }) async {
    final limit = limits.maxTextureDimension2D;
    final bitmap = await decodeImageBitmap(
      encoded,
      maxDimension: maxDimension == null || maxDimension > limit
          ? limit
          : maxDimension,
    );
    if (bitmap == null) return null;
    return webglCreateTextureFromBitmap(
      _gl,
      _persistentTextures,
      _persistentRenderbuffers,
      bitmap,
      mipmaps: mipmaps,
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
    webglOverwriteTexture(_gl, target, rgba, rect);
  }

  /// Nothing to rotate.
  ///
  /// The flutter_gpu backend cycles a ring of uniform allocators here, because
  /// `submit` is asynchronous and rewinding one the GPU may still be reading
  /// corrupts a live frame. WebGL commands are issued into the context as they
  /// are called, and the driver owns the fencing, so there is no ring to keep.
  /// The member is not dead weight — it is where a backend says "nothing",
  /// which is different from the engine assuming nothing needs saying.
  @override
  void beginFrame() {}

  @override
  void onFrameComplete(void Function() whenDone) {
    // Straight away. WebGL's commands are queued, but what is presented here is
    // the _canvas the browser composites — the engine never hands a texture of
    // its own to a compositor, so there is nothing for a later frame to
    // overwrite under one.
    whenDone();
  }

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    // `gfx-50n`. GL would answer this itself with an incomplete framebuffer,
    // which is every draw silently discarded — the same refusal said as a
    // frame of nothing rather than as a throw.
    descriptor
      ..checkAttachmentLimit(
        limits.maxColorAttachments,
        backend: 'this WebGL2 context',
      )
      ..checkFeatures(features, backend: webglBackendName);
    if (descriptor.occlusionQuerySet case final set?
        when set.type != QueryType.occlusion) {
      throw ArgumentError.value(set, 'occlusionQuerySet', 'is not occlusion');
    }
    if (descriptor.timestampWrites case final writes?
        when writes.querySet.type != QueryType.timestamp) {
      throw ArgumentError.value(
        writes.querySet,
        'timestampWrites.querySet',
        'is not a timestamp set',
      );
    }
    return WebGlEncoder(this, _gl, descriptor);
  }

  /// The platform view type this device's _canvas is registered under.
  ///
  /// Registered here rather than by the application, because the _canvas is this
  /// package's own and nothing above should have to learn that a DOM element is
  /// involved to show a frame. Registration is idempotent per device: the
  /// factory hands back the one _canvas this device draws into.
  ///
  /// The registry has no unregister, so the factory — and through it the
  /// _canvas object — outlives [dispose]. That pin is the platform's, not this
  /// device's; what dispose *can* release of the _canvas and its context, it
  /// does, and says so there.
  late final String viewType = _register();

  String _register() {
    final type = 'flutter3d-webgl-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(
      type,
      (int viewId) => _canvas,
    );
    return type;
  }

  /// The error the last blit to the _canvas raised, or zero. Diagnostic only.
  int _lastBlitError = 0;

  /// What the _canvas holds, for when it holds nothing and should not.
  ///
  /// Reads back the default framebuffer — the thing the browser composites —
  /// rather than the texture the engine drew into. The two are different
  /// claims, and telling them apart is the whole difficulty here: a frame can
  /// be drawn correctly and still never reach the screen.
  String debugCanvasState() {
    _gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, null);
    final pixels = Uint8List(4 * 4 * 4);
    final js = pixels.toJS;
    _gl.readPixels(
      _canvas.width ~/ 2 - 2,
      _canvas.height ~/ 2 - 2,
      4,
      4,
      web.WebGLRenderingContext.RGBA,
      web.WebGLRenderingContext.UNSIGNED_BYTE,
      js,
    );
    final read = js.toDart.sublist(0, 16);
    final error = _gl.getError();
    final nonZero = read.where((int b) => b != 0).length;
    return '_canvas ${_canvas.width}x${_canvas.height} '
        'attached=${_canvas.isConnected} '
        'centre=${read.take(4).toList()} nonzero=$nonZero/16 '
        'blitError=$lastBlitError readError=$error';
  }

  /// One pixel of the _canvas, as RGBA, counted from the bottom left.
  ///
  /// The companion to [debugCanvasState], which reads the middle. The middle is
  /// the *last* place a presenting blit stops reaching, so a check that only
  /// looks there passes while three quarters of the _canvas is black — which is
  /// exactly what happened, in public, on every display that is not retina.
  /// Corners are what say the blit covered the _canvas.
  List<int> debugCanvasPixelAt(int x, int y) {
    _gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, null);
    final pixels = Uint8List(4);
    final js = pixels.toJS;
    _gl.readPixels(
      x,
      y,
      1,
      1,
      web.WebGLRenderingContext.RGBA,
      web.WebGLRenderingContext.UNSIGNED_BYTE,
      js,
    );
    return js.toDart.sublist(0, 4);
  }

  /// Blits [frame] onto the _canvas the browser composites.
  ///
  /// `presentFrame` in `flutter3d_app` calls this before building the
  /// `HtmlElementView` that shows [_canvas], because the engine draws into a
  /// texture it owns and the browser composites the _canvas instead. That blit
  /// is the price of this route, and it is one GPU copy rather than the
  /// GPU→CPU→GPU round trip a `ui.Image` would have cost.
  void blitToCanvas(TextureHandle frame) {
    final source = _gl.createFramebuffer();
    _gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, source);
    attachToFramebuffer(
      _gl,
      web.WebGL2RenderingContext.READ_FRAMEBUFFER,
      web.WebGLRenderingContext.COLOR_ATTACHMENT0,
      frame,
    );
    final status = _gl.checkFramebufferStatus(
      web.WebGL2RenderingContext.READ_FRAMEBUFFER,
    );
    if (status != web.WebGLRenderingContext.FRAMEBUFFER_COMPLETE) {
      // The status in words first, the delete second: this runs every frame,
      // so a frame that stays unreadable would otherwise leak one framebuffer
      // per frame for as long as the caller keeps trying.
      final why = debugFramebufferStatus();
      _gl.deleteFramebuffer(source);
      throw StateError('the frame cannot be read for presenting: $why');
    }
    _gl.bindFramebuffer(web.WebGL2RenderingContext.DRAW_FRAMEBUFFER, null);

    // **The scissor is widened to the whole _canvas — not turned off.**
    // `blitFramebuffer` is one of the operations the scissor test clips, and a
    // pass leaves `SCISSOR_TEST` enabled with its own rectangle — see
    // `WebGlEncoder`, which enables it per pass and has no reason to put it
    // back. So the blit that presents a frame was clipped to whatever the last
    // pass had been drawing into.
    //
    // Invisible whenever the frame is at least as large as this _canvas, which
    // is why it survived: on a 2x display the requested frame is bigger than
    // the _canvas, the clip covers it, and everything looks right. On a 1x
    // display in a small embedded frame the request is *smaller*, and the blit
    // then wrote a rectangle in the corner and left the rest of the _canvas
    // black — the corner being the bottom left, because that is where GL puts
    // its origin.
    //
    // **Disabling the test instead was the first attempt, and it broke two of
    // the three public demos.** The flag is global and is left behind for
    // whatever runs next; the two games that skin a mesh threw once a frame and
    // drew nothing, while the one that does not was fine. Widening the
    // rectangle un-clips this blit and leaves the flag where the rest of the
    // engine expects it.
    _gl.scissor(0, 0, _canvas.width, _canvas.height);

    // Drained first, so the code below reports this blit rather than whatever
    // the frame left behind. An error queue is cumulative and getError clears
    // one entry at a time, which is how a stale error gets blamed on the wrong
    // call. Set aside rather than dropped: they are the frame's, and
    // `debugDrainErrors` still answers for them.
    _setAsideErrors('before a _canvas blit');

    // **Not flipped**, and it used to be. The _canvas wants row zero at the
    // bottom and that is now exactly where a finished frame keeps it: the
    // full-screen triangle is wound for this backend's origin, so the last pass
    // in the chain leaves the picture the way GL stores one rather than the way
    // Metal does. See `Renderer._fullscreenTriangle` for why that changed and
    // what it fixed.
    //
    // Invisible to every pixel assertion written so far, because "the centre is
    // brighter than the corner" and "red dominates" are both true of a mirrored
    // frame. It took a person looking at a sphere and saying the light was
    // coming from below. Which is also why [_readConverted] flips and this does
    // not — the two are one decision made once, and splitting them is how a
    // frame comes back right and presents upside down.
    _gl.blitFramebuffer(
      0,
      0,
      frame.width,
      frame.height, //
      0,
      0,
      _canvas.width,
      _canvas.height, //
      web.WebGLRenderingContext.COLOR_BUFFER_BIT,
      web.WebGLRenderingContext.NEAREST,
    );
    _lastBlitError = _gl.getError();
    if (_lastBlitError != web.WebGLRenderingContext.NO_ERROR) {
      final said = '${_errorName(_lastBlitError)} from the _canvas blit';
      if (!_setAside.contains(said)) _setAside.add(said);
    }
    _gl.deleteFramebuffer(source);
  }

  /// The whole of a texture outside `readbackFormats`, read as floats and
  /// converted — what [readback] answers when `readbackConverts` says so.
  Future<ByteData> _readConverted(TextureHandle texture) async {
    final backend = texture.backend as WebGlTexture;
    if (!backend.isSampleable && backend.renderbuffer == null) {
      throw refuseResource(
        'readback',
        'the texture has neither a texture nor a renderbuffer behind it',
      );
    }

    final framebuffer = _gl.createFramebuffer();
    _gl.bindFramebuffer(
      web.WebGL2RenderingContext.READ_FRAMEBUFFER,
      framebuffer,
    );
    attachToFramebuffer(
      _gl,
      web.WebGL2RenderingContext.READ_FRAMEBUFFER,
      web.WebGLRenderingContext.COLOR_ATTACHMENT0,
      texture,
    );

    final rows = _floatReadFormats.contains(texture.format)
        ? _readFloatAsBytes(texture.width, texture.height)
        : _readBytes(texture.width, texture.height);
    _gl.deleteFramebuffer(framebuffer);

    // **Flipped for a frame, not for an upload**, and this is the subtle one.
    // `glReadPixels` hands back rows from the bottom of the framebuffer up, and
    // every caller here — a golden, a parity fixture, a comparison against
    // another backend — reads row zero as the top of the picture. Since the
    // full-screen triangle started being wound for this backend's origin, a
    // finished frame is stored the way GL stores one, so its rows arrive in the
    // opposite order to the one the engine states its images in.
    //
    // An uploaded texture is not: `texImage2D` puts the first row it was given
    // at texture coordinate zero, which is what a glTF UV expects and what
    // `WebGlTexture.rendered` is carried to distinguish. One flip for both
    // would trade a mirrored frame for a mirrored texture.
    //
    // The presenting blit does *not* flip, and for the same reason from the
    // other side: the _canvas displays row zero at the bottom, which is already
    // where the frame keeps it. The two are one decision, and the way to check
    // it is to make sure both agree — a frame that reads back correctly and
    // presents upside down is this pair pulled apart.
    //
    // Established by measurement, not by reasoning about conventions, which is
    // the only way anybody gets this right: put the light above and check which
    // half of the returned image is lit.
    if (!backend.rendered) return ByteData.sublistView(rows);
    final stride = texture.width * 4;
    final flipped = Uint8List(rows.length);
    for (var y = 0; y < texture.height; y++) {
      final from = (texture.height - 1 - y) * stride;
      flipped.setRange(y * stride, y * stride + stride, rows, from);
    }
    return ByteData.sublistView(flipped);
  }

  /// The float colour formats [readback] reads as floats and converts, rather
  /// than asking for bytes.
  ///
  /// **The contract converts the whole of a float target** — a region of one
  /// is refused and says so — and `readPixels(RGBA, UNSIGNED_BYTE)`
  /// on a float colour buffer is an `INVALID_OPERATION` that leaves the
  /// destination at the zeros it was made with. So this read a half-float
  /// frame as transparent black and completed successfully. `RGBA`/`FLOAT` is
  /// the pair WebGL2 does accept for a float buffer once
  /// `EXT_color_buffer_float` is on, which [open] insists on; see
  /// `test/float_readback_probe_test.dart` for the measurement.
  static const Set<TextureFormat> _floatReadFormats = <TextureFormat>{
    TextureFormat.r16g16b16a16Float,
    TextureFormat.r32g32b32a32Float,
    TextureFormat.r32Float,
  };

  /// The bound read framebuffer's bottom-left [width] by [height], as RGBA8.
  ///
  /// Filled on the JS side and copied back: under dart2wasm `toJS` is a copy,
  /// and a Dart list handed across that way comes back as the zeros it was
  /// made with.
  Uint8List _readBytes(int width, int height) {
    final js = Uint8List(width * height * 4).toJS;
    _gl.readPixels(
      0,
      0,
      width,
      height,
      web.WebGLRenderingContext.RGBA,
      web.WebGLRenderingContext.UNSIGNED_BYTE,
      js,
    );
    return Uint8List.fromList(js.toDart);
  }

  /// The same rectangle of a float colour buffer, read as floats and stored as
  /// RGBA8 — each channel clamped to `[0, 1]` and rounded, which is what the
  /// WebGPU backend's conversion into an `rgba8unorm` target does and what the
  /// software rasteriser's float-to-byte does. A one-channel float comes back
  /// `(r, 0, 0, 1)`, which is what GL hands back for it and what a shader
  /// sampling it reads.
  Uint8List _readFloatAsBytes(int width, int height) {
    final js = Float32List(width * height * 4).toJS;
    _gl.readPixels(
      0,
      0,
      width,
      height,
      web.WebGLRenderingContext.RGBA,
      web.WebGLRenderingContext.FLOAT,
      js,
    );
    final floats = js.toDart;
    return Uint8List.fromList(<int>[
      for (final value in floats) (value.clamp(0.0, 1.0) * 255).round(),
    ]);
  }

  /// `readPixels` into a pixel-pack buffer behind a fence, and the bytes
  /// fetched once the fence says the GPU got there.
  ///
  /// The two halves of the contract, said in GL's terms. **In order**: a
  /// `readPixels` with a buffer bound to `PIXEL_PACK_BUFFER` is a command in
  /// the stream like any draw, so it reads the texture as the commands before
  /// it left it and nothing issued afterwards reaches it. **Without waiting**:
  /// the same call with client memory as its destination stalls until the GPU
  /// has drained everything before it — that is what [_readConverted] costs, and
  /// what a golden run can afford — where a pack buffer returns at once and a
  /// `fenceSync` says when the copy is done. The wait is a poll on a timer
  /// rather than a `clientWaitSync` with a timeout, because the latter blocks
  /// the thread this whole engine runs on.
  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) {
    if (readbackConverts(texture, region: region)) {
      return _readConverted(texture);
    }
    final rect = readbackRegionOf(texture, region);
    final backend = texture.backend as WebGlTexture;
    if (!backend.isSampleable && backend.renderbuffer == null) {
      throw ArgumentError.value(
        texture,
        'texture',
        'has neither a texture nor a renderbuffer behind it on this backend',
      );
    }

    final framebuffer = _gl.createFramebuffer();
    _gl.bindFramebuffer(
      web.WebGL2RenderingContext.READ_FRAMEBUFFER,
      framebuffer,
    );
    attachToFramebuffer(
      _gl,
      web.WebGL2RenderingContext.READ_FRAMEBUFFER,
      web.WebGLRenderingContext.COLOR_ATTACHMENT0,
      texture,
    );

    final length = rect.width * rect.height * 4;
    final pack = _gl.createBuffer();
    _gl.bindBuffer(web.WebGL2RenderingContext.PIXEL_PACK_BUFFER, pack);
    _gl.bufferData(
      web.WebGL2RenderingContext.PIXEL_PACK_BUFFER,
      length.toJS,
      web.WebGL2RenderingContext.STREAM_READ,
    );
    // The region is stated from the top, and GL measures from the bottom for
    // a texture it drew — the same distinction [_readConverted] draws, applied
    // to the rectangle rather than to the rows: a rendered texture's row y from
    // the top is row `height - y - h` from the bottom, and an uploaded one's is
    // row y, because `texImage2D` put the first row given at zero.
    final y = backend.rendered ? texture.height - rect.y - rect.height : rect.y;
    _gl.readPixels(
      rect.x,
      y,
      rect.width,
      rect.height,
      web.WebGLRenderingContext.RGBA,
      web.WebGLRenderingContext.UNSIGNED_BYTE,
      0.toJS,
    );
    final sync = _gl.fenceSync(
      web.WebGL2RenderingContext.SYNC_GPU_COMMANDS_COMPLETE,
      0,
    );
    // Sent rather than left in the queue. A fence that is never flushed is a
    // fence that signals when the browser next composites, which may be never
    // for a page drawing nothing else.
    _gl.flush();
    _gl.bindBuffer(web.WebGL2RenderingContext.PIXEL_PACK_BUFFER, null);
    _gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, null);
    _gl.deleteFramebuffer(framebuffer);

    if (sync == null) {
      _gl.deleteBuffer(pack);
      throw StateError('the context refused a fence for the readback');
    }
    return _collectReadback(sync, pack, rect, flip: backend.rendered);
  }

  Future<ByteData> _collectReadback(
    web.WebGLSync sync,
    web.WebGLBuffer? pack,
    ScreenRect rect, {
    required bool flip,
  }) async {
    try {
      // Bounded, because a fence on a context that has been lost never
      // signals, and a readback that never answers is a caller that never
      // stops waiting for it.
      var waited = Duration.zero;
      const step = Duration(milliseconds: 1);
      const patience = Duration(seconds: 2);
      while (true) {
        final status = _gl.clientWaitSync(sync, 0, 0);
        if (status == web.WebGL2RenderingContext.ALREADY_SIGNALED ||
            status == web.WebGL2RenderingContext.CONDITION_SATISFIED) {
          break;
        }
        if (status == web.WebGL2RenderingContext.WAIT_FAILED) {
          throw StateError('the readback fence failed');
        }
        if (waited >= patience) {
          throw StateError('the readback fence did not signal in $patience');
        }
        await Future<void>.delayed(step);
        waited += step;
      }

      // Filled on the JS side and copied back, the way [_readConverted] does it.
      // Under dart2js `toJS` is the same buffer, so writing into it would fill
      // a Dart list too; under dart2wasm it is a copy, and a Dart list handed
      // across that way comes back as the zeros it was made with. The Chrome
      // tests run dart2js and would not notice the difference — the `--wasm`
      // build in ci.sh is what would, one meter pinned at maxExposure later.
      final js = Uint8List(rect.width * rect.height * 4).toJS;
      _gl.bindBuffer(web.WebGL2RenderingContext.PIXEL_PACK_BUFFER, pack);
      _gl.getBufferSubData(web.WebGL2RenderingContext.PIXEL_PACK_BUFFER, 0, js);
      _gl.bindBuffer(web.WebGL2RenderingContext.PIXEL_PACK_BUFFER, null);
      final bytes = Uint8List.fromList(js.toDart);

      if (!flip) return ByteData.sublistView(bytes);
      // Rows come up from the bottom of the region; the contract wants them
      // from the top, as [_readConverted] says at length.
      final stride = rect.width * 4;
      final flipped = Uint8List(bytes.length);
      for (var row = 0; row < rect.height; row++) {
        final from = (rect.height - 1 - row) * stride;
        flipped.setRange(row * stride, row * stride + stride, bytes, from);
      }
      return ByteData.sublistView(flipped);
    } finally {
      _gl.deleteSync(sync);
      _gl.deleteBuffer(pack);
    }
  }

  /// The GL error queue, drained, or null when it was empty.
  ///
  /// Diagnostic only, and it exists because guessing was cheaper than looking
  /// exactly once. WebGL reports nothing when a call is rejected: the draw is
  /// dropped and the frame comes back the clear colour, which is
  /// indistinguishable from a scene that drew nothing.
  ///
  /// Declared slots a draw left unbound come first: the contract makes them
  /// the caller's mistake, and this backend sees them at every draw. See
  /// [_reportUnbound].
  ///
  /// So do errors the _canvas blit found queued and set aside: see
  /// [_setAsideErrors].
  String? debugDrainErrors(String where) {
    final seen = <String>[..._unbound, ..._setAside];
    _unbound.clear();
    _setAside.clear();
    for (var i = 0; i < 8; i++) {
      final error = _gl.getError();
      if (error == web.WebGLRenderingContext.NO_ERROR) break;
      seen.add(_errorName(error));
    }
    return seen.isEmpty ? null : '$where: ${seen.join(', ')}';
  }

  static String _errorName(int error) => switch (error) {
    web.WebGLRenderingContext.INVALID_ENUM => 'INVALID_ENUM',
    web.WebGLRenderingContext.INVALID_VALUE => 'INVALID_VALUE',
    web.WebGLRenderingContext.INVALID_OPERATION => 'INVALID_OPERATION',
    web.WebGLRenderingContext.INVALID_FRAMEBUFFER_OPERATION =>
      'INVALID_FRAMEBUFFER_OPERATION',
    web.WebGLRenderingContext.OUT_OF_MEMORY => 'OUT_OF_MEMORY',
    _ => 'gl error $error',
  };

  /// Empties the GL error queue into [_setAside], so a call that wants to
  /// read its own error reads its own, and the ones before it are still
  /// there for [debugDrainErrors].
  ///
  /// The _canvas blit used to drop them. It drains the queue so a stale error
  /// is not blamed on it, and every frame that reaches the screen goes through
  /// it, so an error made while drawing a presented frame was thrown away one
  /// blit later: a draw the browser refused every frame read, afterwards, as
  /// a frame with no errors. Each distinct error is kept once, since the same
  /// refusal repeats every frame.
  void _setAsideErrors(String where) {
    for (var i = 0; i < 8; i++) {
      final error = _gl.getError();
      if (error == web.WebGLRenderingContext.NO_ERROR) break;
      final said = '${_errorName(error)} $where';
      if (!_setAside.contains(said)) _setAside.add(said);
    }
  }

  final List<String> _setAside = <String>[];

  /// Records a declared slot a draw left unbound, once per slot per device, so
  /// a mistake repeated every frame is one line rather than a flood.
  void _reportUnbound(String what) {
    if (_reportedUnbound.add(what)) {
      _unbound.add('$what is declared and nothing was bound to it');
    }
  }

  final Set<String> _reportedUnbound = <String>{};
  final List<String> _unbound = <String>[];

  /// Whether the currently bound framebuffer can be drawn to, in words.
  String debugFramebufferStatus() {
    final status = _gl.checkFramebufferStatus(
      web.WebGLRenderingContext.FRAMEBUFFER,
    );
    return switch (status) {
      web.WebGLRenderingContext.FRAMEBUFFER_COMPLETE => 'complete',
      web.WebGLRenderingContext.FRAMEBUFFER_INCOMPLETE_ATTACHMENT =>
        'INCOMPLETE_ATTACHMENT',
      web.WebGLRenderingContext.FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT =>
        'INCOMPLETE_MISSING_ATTACHMENT',
      web.WebGLRenderingContext.FRAMEBUFFER_INCOMPLETE_DIMENSIONS =>
        'INCOMPLETE_DIMENSIONS',
      web.WebGLRenderingContext.FRAMEBUFFER_UNSUPPORTED => 'UNSUPPORTED',
      web.WebGL2RenderingContext.FRAMEBUFFER_INCOMPLETE_MULTISAMPLE =>
        'INCOMPLETE_MULTISAMPLE',
      _ => 'status $status',
    };
  }
}

/// The device's own objects, for the rest of this backend: the encoders, the
/// presenter and the transfer pass. Not exported — `flutter3d_webgl.dart`
/// shows `WebGlDevice` alone — so no `package:web` type is in the package's
/// API.
extension WebGlDeviceInternals on WebGlDevice {
  web.HTMLCanvasElement get canvas => _canvas;
  web.EXT_disjoint_timer_query_webgl2? get timerQuery => _timerQuery;
  web.WEBGL_multi_draw? get multiDrawExtension => _multiDrawExtension;
  web.OES_draw_buffers_indexed? get drawBuffersIndexed => _drawBuffersIndexed;
  JSObject? get baseVertexBaseInstanceExtension =>
      _baseVertexBaseInstanceExtension;
  Set<int> get enabledAttributeLocations => _enabledAttributeLocations;
  Set<int> get instancedAttributeLocations => _instancedAttributeLocations;

  /// The GL error the last blit to the canvas left, for a debugger reading
  /// why the canvas stayed empty.
  int get lastBlitError => _lastBlitError;
  CompressedTextureSupport get compressedTextureSupport =>
      _compressedTextureSupport;
  bool get supportsFloatLinearFiltering => _supportsFloatLinearFiltering;
  void reportUnbound(String what) => _reportUnbound(what);
}
