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

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgl_encoder.dart';
import 'webgl_framebuffer.dart';
import 'webgl_resources.dart';
import 'webgl_shaders.dart';
import 'webgl_types.dart';

export 'webgl_encoder.dart';
export 'webgl_types.dart';

/// WebGL2 as a [GraphicsDevice].
final class WebGlDevice implements GraphicsDevice {
  WebGlDevice._(this._gl, this._canvas, this._library);

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
  final Set<int> enabledAttributeLocations = <int>{};

  /// Vertex attribute locations currently carrying a non-zero divisor.
  ///
  /// Context state for the same reason as the set above, and it leaked the same
  /// way: `vertexAttribDivisor` belongs to the location, survives the draw, the
  /// buffer, the program and the pass, and an encoder that tracked its own put
  /// back only what it had set — which is nothing, once the next pass is a new
  /// encoder.
  final Set<int> instancedAttributeLocations = <int>{};

  /// Builds a device over a canvas of [width] by [height].
  ///
  /// The canvas is the thing the browser composites; see [present]. It is
  /// created here rather than taken as an argument so that nothing above has to
  /// know a DOM element is involved.
  static WebGlDevice? create({
    required int width,
    required int height,
    required ShaderSources sources,
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
    if (gl == null) return null;

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
    gl.getExtension('EXT_color_buffer_float');

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
    return WebGlDevice._(gl, canvas, WebGlShaderLibrary(gl, sources))
      .._floatLinear = floatLinear != null;
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

  /// Whether [dispose] has already run. Guards against deleting the same GL
  /// object twice, which is harmless by the WebGL spec but worth refusing
  /// anyway: a second [dispose] call is a caller mistake worth surfacing rather
  /// than one this device quietly absorbs.
  bool _disposed = false;

  /// The count of persistent GL objects currently tracked, for tests. Falls to
  /// zero after [dispose].
  int get debugTrackedResourceCount =>
      _persistentTextures.length +
      _persistentRenderbuffers.length +
      _persistentBuffers.length;

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

  @override
  void releaseGeometry(GeometryBuffer geometry) =>
      webglReleaseBuffer(_gl, geometry.backend, _persistentBuffers);

  @override
  void dispose() {
    if (_disposed) {
      throw StateError('WebGlDevice.dispose() was already called');
    }
    _disposed = true;
    webglDisposePersistentResources(
      _gl,
      _persistentTextures,
      _persistentRenderbuffers,
      _persistentBuffers,
    );
  }

  /// Whether half-float textures may be filtered linearly here. Diagnostic:
  /// see the note in [create].
  bool _floatLinear = false;

  /// Whether this context can sample a half-float texture with linear
  /// filtering. False makes every shadow map read as zero.
  bool get supportsFloatLinearFiltering => _floatLinear;

  @override
  ShaderLibrary get shaders => _library;

  /// RGBA8. There is no `defaultColorFormat` to ask WebGL for — the canvas is
  /// what it is — so this states the engine's own choice rather than reporting
  /// a device property. On flutter_gpu the same getter is a genuine runtime
  /// query, which is a small asymmetry the HAL's wording already allows for.
  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d24UnormS8Uint;

  /// WebGL2 has multisampled renderbuffers, so offscreen MSAA exists — but it
  /// cannot be *sampled*, only blitted. The engine uses MSAA by attaching a
  /// multisampled colour and a resolve target, which is exactly a blit, so the
  /// answer is honest.
  @override
  @override
  // OpenGL, and WebGL2 exposes no glClipControl to change it.
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.bottomLeft;

  @override
  DepthRange get depthRange => DepthRange.negativeOneToOne;

  @override
  // Renderable here only because EXT_color_buffer_float is requested when the
  // context is made; see create(). Without it this is a texture format that
  // silently accepts no draws.
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  int get preferredSampleCount => 4;

  @override
  bool get supportsOffscreenMsaa => true;

  @override
  // OpenGL ES has no glPolygonMode. See canDrawPolygonMode.
  bool get supportsWireframe => false;

  @override
  // WebGL2 samples a hand-built chain correctly as a matter of specification:
  // `texStorage2D` allocates every level and `TEXTURE_MAX_LEVEL` bounds it. The
  // device this capability exists to warn about is an OpenGL ES 2 one, which
  // this backend does not run on at all.
  bool get supportsMipmaps => true;

  @override
  // WebGL2 has had cube maps since WebGL1, and samples across their edges
  // seamlessly without an extension. Nothing to probe.
  bool get supportsCubeTextures => true;

  @override
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) => webglCreateCubeTextureFromPixels(
    _gl,
    _persistentTextures,
    size: size,
    format: format,
    faces: faces,
    mipLevels: mipLevels,
  );

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutSpec? layout,
  }) => _library.link(vertex, fragment, layout: layout);

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) =>
      webglUploadGeometry(_gl, _persistentBuffers, bytes, usage);

  @override
  TextureHandle createTexture(RenderTargetSpec spec, {int levels = 1}) =>
      webglCreateTexture(
        _gl,
        _persistentTextures,
        _persistentRenderbuffers,
        spec,
        levels: levels,
      );

  @override
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) => webglCreateTextureFromPixels(
    _gl,
    _persistentTextures,
    _persistentRenderbuffers,
    width: width,
    height: height,
    format: format,
    pixels: pixels,
    mipLevels: mipLevels,
  );

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
    // the canvas the browser composites — the engine never hands a texture of
    // its own to a compositor, so there is nothing for a later frame to
    // overwrite under one.
    whenDone();
  }

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) =>
      WebGlEncoder(this, _gl, descriptor);

  /// The canvas, in the widget tree.
  ///
  /// [frame] is blitted onto the default framebuffer first, because the engine
  /// draws into a texture it owns and the browser composites the canvas. That
  /// blit is the price of this route, and it is one GPU copy rather than the
  /// GPU→CPU→GPU round trip a `ui.Image` would have cost.
  ///
  /// [fit] and [quality] are honoured through CSS on the element rather than by
  /// Flutter, since Flutter does not composite these pixels.
  @override
  Widget present(
    TextureHandle frame, {
    BoxFit fit = BoxFit.fill,
    FilterQuality quality = FilterQuality.none,
  }) {
    _blitToCanvas(frame);
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

  /// The platform view type this device's canvas is registered under.
  ///
  /// Registered here rather than by the application, because the canvas is this
  /// package's own and nothing above should have to learn that a DOM element is
  /// involved to show a frame. Registration is idempotent per device: the
  /// factory hands back the one canvas this device draws into.
  late final String viewType = _register();

  String _register() {
    final type = 'flutter3d-webgl-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(
      type,
      (int viewId) => _canvas,
    );
    return type;
  }

  /// The error the last blit to the canvas raised, or zero. Diagnostic only.
  int lastBlitError = 0;

  /// What the canvas holds, for when it holds nothing and should not.
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
    return 'canvas ${_canvas.width}x${_canvas.height} '
        'attached=${_canvas.isConnected} '
        'centre=${read.take(4).toList()} nonzero=$nonZero/16 '
        'blitError=$lastBlitError readError=$error';
  }

  void _blitToCanvas(TextureHandle frame) {
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
      throw StateError(
        'the frame cannot be read for presenting: ${debugFramebufferStatus()}',
      );
    }
    _gl.bindFramebuffer(web.WebGL2RenderingContext.DRAW_FRAMEBUFFER, null);

    // Drained first, so the code below reports this blit rather than whatever
    // the frame left behind. An error queue is cumulative and getError clears
    // one entry at a time, which is how a stale error gets blamed on the wrong
    // call.
    while (_gl.getError() != 0) {}

    // **Not flipped**, and it used to be. The canvas wants row zero at the
    // bottom and that is now exactly where a finished frame keeps it: the
    // full-screen triangle is wound for this backend's origin, so the last pass
    // in the chain leaves the picture the way GL stores one rather than the way
    // Metal does. See `Renderer._fullscreenTriangle` for why that changed and
    // what it fixed.
    //
    // Invisible to every pixel assertion written so far, because "the centre is
    // brighter than the corner" and "red dominates" are both true of a mirrored
    // frame. It took a person looking at a sphere and saying the light was
    // coming from below. Which is also why [readPixels] flips and this does
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
    lastBlitError = _gl.getError();
    _gl.deleteFramebuffer(source);
  }

  @override
  Future<ByteData?> readPixels(TextureHandle texture) async {
    final backend = texture.backend as WebGlTexture;
    if (!backend.isSampleable && backend.renderbuffer == null) return null;

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

    final pixels = Uint8List(texture.width * texture.height * 4);
    final js = pixels.toJS;
    _gl.readPixels(
      0,
      0,
      texture.width,
      texture.height,
      web.WebGLRenderingContext.RGBA,
      web.WebGLRenderingContext.UNSIGNED_BYTE,
      js,
    );
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
    // other side: the canvas displays row zero at the bottom, which is already
    // where the frame keeps it. The two are one decision, and the way to check
    // it is to make sure both agree — a frame that reads back correctly and
    // presents upside down is this pair pulled apart.
    //
    // Established by measurement, not by reasoning about conventions, which is
    // the only way anybody gets this right: put the light above and check which
    // half of the returned image is lit.
    final rows = Uint8List.fromList(js.toDart);
    if (!backend.rendered) return ByteData.sublistView(rows);
    final stride = texture.width * 4;
    final flipped = Uint8List(rows.length);
    for (var y = 0; y < texture.height; y++) {
      final from = (texture.height - 1 - y) * stride;
      flipped.setRange(y * stride, y * stride + stride, rows, from);
    }
    return ByteData.sublistView(flipped);
  }

  /// The GL error queue, drained, or null when it was empty.
  ///
  /// Diagnostic only, and it exists because guessing was cheaper than looking
  /// exactly once. WebGL reports nothing when a call is rejected: the draw is
  /// dropped and the frame comes back the clear colour, which is
  /// indistinguishable from a scene that drew nothing.
  String? debugDrainErrors(String where) {
    final seen = <String>[];
    for (var i = 0; i < 8; i++) {
      final error = _gl.getError();
      if (error == web.WebGLRenderingContext.NO_ERROR) break;
      seen.add(switch (error) {
        web.WebGLRenderingContext.INVALID_ENUM => 'INVALID_ENUM',
        web.WebGLRenderingContext.INVALID_VALUE => 'INVALID_VALUE',
        web.WebGLRenderingContext.INVALID_OPERATION => 'INVALID_OPERATION',
        web.WebGLRenderingContext.INVALID_FRAMEBUFFER_OPERATION =>
          'INVALID_FRAMEBUFFER_OPERATION',
        web.WebGLRenderingContext.OUT_OF_MEMORY => 'OUT_OF_MEMORY',
        _ => 'gl error $error',
      });
    }
    return seen.isEmpty ? null : '$where: ${seen.join(', ')}';
  }

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
