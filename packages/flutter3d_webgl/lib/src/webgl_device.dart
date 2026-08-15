/// WebGL2 as an implementation of [GraphicsDevice].
///
/// The second backend, and therefore the first real test of whether
/// `flutter3d_graphics` is a seam or a description of Impeller wearing neutral
/// names. Where the two models differ the difference is written down here, at
/// the line where it bites.
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:web/web.dart' as web;

import 'webgl_formats.dart';
import 'webgl_shaders.dart';

/// What a [TextureHandle] carries on this backend.
///
/// Either a texture or a renderbuffer: WebGL2 cannot sample a multisampled
/// attachment, so a multisampled target is a renderbuffer and is resolved by
/// blitting. `deviceTransient` — Impeller's tile memory — has no equivalent and
/// becomes an ordinary renderbuffer, which is the closest honest thing: not
/// sampleable, attachment only.
final class WebGlTexture {
  WebGlTexture({this.texture, this.renderbuffer});

  final web.WebGLTexture? texture;
  final web.WebGLRenderbuffer? renderbuffer;

  bool get isSampleable => texture != null;
}

/// A linked program plus what reflection told us about it.
final class WebGlProgram {
  WebGlProgram(this.program, this.attributes, this.blocks, this.samplers,
      {this.layout});

  final web.WebGLProgram program;

  /// What the pipeline was built with, or null to keep guessing from the
  /// shader. See [WebGlDevice.createPipeline] and `_describeVertices`.
  final VertexLayoutSpec? layout;

  /// Vertex attributes in location order, with their float component counts.
  ///
  /// **This is the gap the HAL inherited from flutter_gpu, closed here.**
  /// `PassEncoder.bindVertexBuffer` hands over a buffer and a vertex count and
  /// nothing else: flutter_gpu takes the layout from the order of `in`
  /// declarations in the vertex shader, so the HAL never had to carry one.
  /// WebGL2 will not infer it — every attribute needs an explicit
  /// `vertexAttribPointer`.
  ///
  /// It is reconstructible without changing the contract, because the same
  /// thing that defines the layout on flutter_gpu defines it here: the shader.
  /// Attributes are read back by location, each contributes its component
  /// count, and the vertex is their sum interleaved in that order — which is
  /// exactly the convention `VertexLayout` in the engine already documents.
  /// So the seam survives, but only because both backends agree to take the
  /// layout from the shader. A backend that wanted an explicit descriptor
  /// would need the HAL to grow one.
  final List<WebGlAttribute> attributes;

  /// Uniform block name to its index and size.
  final Map<String, WebGlBlock> blocks;

  /// Sampler uniform name to its texture unit.
  final Map<String, int> samplers;

  int get vertexFloats {
    var total = 0;
    for (final a in attributes) {
      total += a.componentCount;
    }
    return total;
  }
}

final class WebGlAttribute {
  const WebGlAttribute(this.location, this.componentCount);
  final int location;
  final int componentCount;
}

final class WebGlBlock {
  const WebGlBlock(this.index, this.sizeInBytes, this.offsets);
  final int index;
  final int sizeInBytes;

  /// Member name to byte offset, as std140 laid it out. Reflected rather than
  /// computed: the spec's packing rules are the driver's to apply.
  final Map<String, int> offsets;
}

/// WebGL2 as a [GraphicsDevice].
final class WebGlDevice implements GraphicsDevice {
  WebGlDevice._(this._gl, this._canvas, this._library);

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
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutSpec? layout,
  }) =>
      _library.link(vertex, fragment, layout: layout);

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    final buffer = _gl.createBuffer();
    // **WebGL binds a buffer to its target for life.** One bound to
    // ARRAY_BUFFER can never afterwards be bound to ELEMENT_ARRAY_BUFFER, and
    // the attempt is an INVALID_OPERATION: the draw is dropped and the frame
    // comes back the clear colour with nothing logged.
    //
    // There is no neutral target to park it on either — COPY_WRITE_BUFFER
    // commits it just as ARRAY_BUFFER does, which is what the harness found the
    // hard way. So [usage] has to be known here, and that is why the contract
    // carries it.
    final target = switch (usage) {
      GeometryUsage.vertices => web.WebGLRenderingContext.ARRAY_BUFFER,
      GeometryUsage.indices => web.WebGLRenderingContext.ELEMENT_ARRAY_BUFFER,
    };
    _gl.bindBuffer(target, buffer);
    _gl.bufferData(
      target,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes).toJS,
      web.WebGLRenderingContext.STATIC_DRAW,
    );
    return GeometryBuffer(
      backend: buffer!,
      offsetInBytes: 0,
      lengthInBytes: bytes.lengthInBytes,
    );
  }

  @override
  TextureHandle createTexture(RenderTargetSpec spec, {int levels = 1}) {
    final internal = textureFormatToGl(spec.format);
    if (spec.sampleCount > 1 || spec.storageMode == StorageMode.deviceTransient) {
      // Multisampled or attachment-only: a renderbuffer. Cannot be sampled,
      // which is what `deviceTransient` already promises on the other backend.
      final buffer = _gl.createRenderbuffer();
      _gl.bindRenderbuffer(web.WebGLRenderingContext.RENDERBUFFER, buffer);
      if (spec.sampleCount > 1) {
        _gl.renderbufferStorageMultisample(
          web.WebGLRenderingContext.RENDERBUFFER,
          spec.sampleCount,
          internal,
          spec.width,
          spec.height,
        );
      } else {
        _gl.renderbufferStorage(
          web.WebGLRenderingContext.RENDERBUFFER,
          internal,
          spec.width,
          spec.height,
        );
      }
      return _handle(WebGlTexture(renderbuffer: buffer), spec);
    }

    final texture = _gl.createTexture();
    _gl.bindTexture(web.WebGLRenderingContext.TEXTURE_2D, texture);
    _gl.texStorage2D(
      web.WebGLRenderingContext.TEXTURE_2D,
      levels,
      internal,
      spec.width,
      spec.height,
    );
    return _handle(WebGlTexture(texture: texture), spec);
  }

  @override
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    // RGBA8 is the only format the engine uploads from the CPU, and four bytes
    // a texel is the whole of the size question here — WebGL has no padding to
    // ask about, unlike Impeller's base mip size.
    if (pixels.lengthInBytes != width * height * 4) return null;

    // **Allocated with the whole chain up front.** `texStorage2D` fixes the
    // number of levels for the texture's life, and a level written into a
    // texture allocated for one is an INVALID_OPERATION — dropped, with the
    // frame coming back looking merely unfiltered. So the count is decided
    // here and the levels are filled afterwards.
    final levels = mipLevels == null ? 1 : mipLevels.length + 1;
    final handle = createTexture(RenderTargetSpec(
      width: width,
      height: height,
      format: format,
    ), levels: levels);
    final backend = handle.backend as WebGlTexture;
    _gl.bindTexture(web.WebGLRenderingContext.TEXTURE_2D, backend.texture);

    void upload(int level, int w, int h, ByteData bytes) {
      _gl.texSubImage2D(
        web.WebGLRenderingContext.TEXTURE_2D,
        level,
        0,
        0,
        w.toJS,
        h.toJS,
        web.WebGLRenderingContext.RGBA.toJS,
        web.WebGLRenderingContext.UNSIGNED_BYTE,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes).toJS,
      );
    }

    upload(0, width, height, pixels);
    if (mipLevels != null) {
      var w = width;
      var h = height;
      for (var i = 0; i < mipLevels.length; i++) {
        w = w > 1 ? w >> 1 : 1;
        h = h > 1 ? h >> 1 : 1;
        upload(i + 1, w, h, mipLevels[i]);
      }
      // Without this the texture is incomplete for any minifying filter and
      // samples as black — the same failure mode as the float-linear extension,
      // and just as silent. `glGenerateMipmap` is deliberately not called: the
      // levels are the engine's, identical on three backends, and generating a
      // second set here would put this backend one filter away from the others.
      _gl.texParameteri(web.WebGLRenderingContext.TEXTURE_2D,
          web.WebGL2RenderingContext.TEXTURE_MAX_LEVEL, mipLevels.length);
    }
    return handle;
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
        BoxFit.fitWidth || BoxFit.fitHeight || BoxFit.none || BoxFit.scaleDown =>
          'contain',
      }
      ..imageRendering =
          quality == FilterQuality.none ? 'pixelated' : 'auto';
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
    ui_web.platformViewRegistry
        .registerViewFactory(type, (int viewId) => _canvas);
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
    final read = (js.toDart).sublist(0, 16);
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
    _attach(web.WebGL2RenderingContext.READ_FRAMEBUFFER,
        web.WebGLRenderingContext.COLOR_ATTACHMENT0, frame);
    final status =
        _gl.checkFramebufferStatus(web.WebGL2RenderingContext.READ_FRAMEBUFFER);
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

    // Flipped, by reading the source rectangle bottom to top. GL puts the
    // origin of a framebuffer at the bottom left and the engine's frames are
    // row-major from the top, so a straight blit presents the picture upside
    // down — which readPixels on this backend already corrects for, and this
    // path did not.
    //
    // Invisible to every pixel assertion written so far, because "the centre is
    // brighter than the corner" and "red dominates" are both true of a mirrored
    // frame. It took a person looking at a sphere and saying the light was
    // coming from below.
    _gl.blitFramebuffer(
      0, frame.height, frame.width, 0, //
      0, 0, _canvas.width, _canvas.height, //
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
    _gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, framebuffer);
    _attach(web.WebGL2RenderingContext.READ_FRAMEBUFFER,
        web.WebGLRenderingContext.COLOR_ATTACHMENT0, texture);

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

    // Not flipped, and this is the subtle one. GL's own origin is lower-left,
    // so the reflex is to flip — but the engine renders with clip space set up
    // for Impeller, whose framebuffer origin is upper-left, so a frame it drew
    // already has row 0 at the top of the picture. Flipping would turn a
    // correct frame upside down.
    //
    // The presenting blit does flip, and for the same reason from the other
    // side: the canvas displays row 0 at the *bottom*, so getting a top-first
    // image onto it means reading the source rectangle in reverse.
    //
    // Established by measurement, not by reasoning about conventions, which is
    // the only way anybody gets this right: put the light above and check which
    // half of the returned image is lit.
    return ByteData.sublistView(js.toDart);
  }


  void _attach(int target, int attachment, TextureHandle handle) {
    final backend = handle.backend as WebGlTexture;
    if (backend.texture != null) {
      _gl.framebufferTexture2D(target, attachment,
          web.WebGLRenderingContext.TEXTURE_2D, backend.texture, 0);
    } else {
      _gl.framebufferRenderbuffer(target, attachment,
          web.WebGLRenderingContext.RENDERBUFFER, backend.renderbuffer);
    }
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
    final status =
        _gl.checkFramebufferStatus(web.WebGLRenderingContext.FRAMEBUFFER);
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

  TextureHandle _handle(WebGlTexture backend, RenderTargetSpec spec) =>
      TextureHandle(
        backend: backend,
        width: spec.width,
        height: spec.height,
        format: spec.format,
        sampleCount: spec.sampleCount,
        storageMode: spec.storageMode,
      );
}

/// One pass, recorded straight into the context.
///
/// **There is no command buffer here, and that is the sharpest structural
/// difference from flutter_gpu.** Impeller records into a buffer and executes
/// on `submit`, so the engine orders its passes by submission. WebGL issues
/// every call as it is made, so ordering is the order the engine calls in —
/// which is the same order, arrived at differently. [submit] therefore only
/// tears the framebuffer down.
///
/// The HAL survives this because it never promised buffering; it promised that
/// passes execute in submission order, and both honour that.
final class WebGlEncoder implements CommandEncoder {
  WebGlEncoder(this._device, this._gl, RenderPassDescriptor descriptor)
      : _targetHeight = descriptor.colors.isNotEmpty
            ? descriptor.colors.first.texture.height
            : (descriptor.depth?.texture.height ?? 0) {
    _framebuffer = _gl.createFramebuffer();
    _gl.bindFramebuffer(web.WebGLRenderingContext.FRAMEBUFFER, _framebuffer);

    final buffers = <int>[];
    for (var i = 0; i < descriptor.colors.length; i++) {
      final color = descriptor.colors[i];
      final attachment = web.WebGLRenderingContext.COLOR_ATTACHMENT0 + i;
      _device._attach(
          web.WebGLRenderingContext.FRAMEBUFFER, attachment, color.texture);
      buffers.add(attachment);
      _resolves.add(color.resolveTexture);
      _sources.add(color.texture);
    }
    _gl.drawBuffers(buffers.map((int b) => b.toJS).toList().toJS);

    // A clear covers the whole attachment, whatever the scissor says. That is
    // the contract the HAL states and the one this engine relies on — the
    // shadow atlas clears once and then draws tile by tile — and GL does not
    // give it for free: clearBufferfv respects SCISSOR_TEST, which this backend
    // leaves enabled, so the clear covered whichever tile the previous pass had
    // set and left the rest of the atlas as it was allocated.
    //
    // The symptom was one white row out of four, and shadows that read as
    // absent because the lookup landed in memory nobody had written.
    _gl.disable(web.WebGLRenderingContext.SCISSOR_TEST);

    final depth = descriptor.depth;
    if (depth != null) {
      _device._attach(web.WebGLRenderingContext.FRAMEBUFFER,
          web.WebGL2RenderingContext.DEPTH_STENCIL_ATTACHMENT, depth.texture);
      // Depth must be writable for a clear to land, whatever the pass sets
      // afterwards.
      _gl.depthMask(true);
      _gl.clearDepth(depth.clearValue);
      _gl.clear(web.WebGLRenderingContext.DEPTH_BUFFER_BIT);
    }

    // Checked, not assumed. An incomplete framebuffer is not an error in
    // OpenGL: every draw against it is silently discarded, which is a whole
    // frame of work producing nothing and no way to tell from inside the
    // engine. The status word is worth more than the discovery.
    final status = _device.debugFramebufferStatus();
    if (status != 'complete') {
      throw StateError(
        'render pass target is not drawable: $status. '
        '${descriptor.colors.length} colour attachment(s)'
        '${descriptor.depth != null ? ' and a depth attachment' : ''}. '
        'A format the engine renders to may not be colour-renderable here — '
        'RGBA16F needs EXT_color_buffer_float.',
      );
    }

    for (var i = 0; i < descriptor.colors.length; i++) {
      final color = descriptor.colors[i];
      if (color.loadAction != LoadAction.clear) continue;
      final value = color.clearValue;
      // Per attachment, which is what `clearBufferfv` is for. A plain `clear`
      // would cover every attachment with one colour — and, as this engine
      // learned the hard way on the shadow atlas, a clear ignores the viewport
      // entirely on both backends.
      _gl.clearBufferfv(
        web.WebGL2RenderingContext.COLOR,
        i,
        Float32List.fromList(<double>[
          value?.x ?? 0.0,
          value?.y ?? 0.0,
          value?.z ?? 0.0,
          value?.w ?? 0.0,
        ]).toJS,
      );
    }

    // Back on, because everything after this is a draw and the engine sets a
    // scissor per tile.
    _gl.enable(web.WebGLRenderingContext.SCISSOR_TEST);

    _gl.enable(web.WebGLRenderingContext.DEPTH_TEST);
    _gl.enable(web.WebGLRenderingContext.SCISSOR_TEST);
  }

  final WebGlDevice _device;
  final web.WebGL2RenderingContext _gl;
  late final web.WebGLFramebuffer? _framebuffer;

  /// The attachment's height, for turning top-left rectangles into GL's
  /// bottom-left ones. See [_flipY].
  final int _targetHeight;

  final List<TextureHandle?> _resolves = <TextureHandle?>[];
  final List<TextureHandle> _sources = <TextureHandle>[];

  WebGlProgram? _program;
  int _primitive = web.WebGLRenderingContext.TRIANGLES;
  IndexType _indexType = IndexType.int32;
  int _indexCount = 0;
  int _nextTextureUnit = 0;
  int _nextBlockBinding = 0;

  @override
  void setViewport(ScreenRect rect) =>
      _gl.viewport(rect.x, _flipY(rect), rect.width, rect.height);

  @override
  void setScissor(ScreenRect rect) =>
      _gl.scissor(rect.x, _flipY(rect), rect.width, rect.height);

  /// A rectangle's y measured from the bottom, which is where GL measures.
  ///
  /// The engine states rectangles from the top left, matching where row zero of
  /// its render targets is. GL puts the origin of a framebuffer at the bottom
  /// left, so a rectangle handed over unchanged lands mirrored about the
  /// target's middle.
  ///
  /// Invisible for a viewport covering the whole target, which is every pass in
  /// the frame except one — and that one is the point-light atlas, six tiles
  /// across and a row per light, drawn a tile at a time. The occupied row went
  /// to the bottom of the texture while the lookup read the top, so the shadows
  /// were absent rather than wrong, and the atlas composited to a picture with
  /// content in the wrong half.
  int _flipY(ScreenRect rect) => _targetHeight - rect.y - rect.height;

  @override
  void setPrimitiveType(PrimitiveType type) =>
      _primitive = primitiveTypeToGl(type);

  /// Silently ignored for [PolygonMode.fill] and **refused** for
  /// [PolygonMode.line].
  ///
  /// ES has no `glPolygonMode`. Wireframe on this backend means drawing line
  /// primitives from an index buffer built for them, which is the renderer's
  /// decision and not a substitution a backend may make on its own. Throwing
  /// says so; quietly filling would show a solid model to somebody who asked
  /// for a wireframe and left them to wonder.
  @override
  void setPolygonMode(PolygonMode mode) {
    if (canDrawPolygonMode(mode)) return;
    throw UnsupportedError(
      'WebGL2 cannot draw PolygonMode.line: OpenGL ES has no glPolygonMode. '
      'Wireframe needs line primitives and an index buffer to match, which is '
      'a decision for the renderer.',
    );
  }

  @override
  void setCullMode(CullMode mode) {
    final face = cullModeToGl(mode);
    if (face == null) {
      _gl.disable(web.WebGLRenderingContext.CULL_FACE);
      return;
    }
    _gl.enable(web.WebGLRenderingContext.CULL_FACE);
    _gl.cullFace(face);
  }

  @override
  void setWindingOrder(WindingOrder order) =>
      _gl.frontFace(windingOrderToGl(order));

  @override
  void setDepthWrite(bool enabled) => _gl.depthMask(enabled);

  @override
  void setDepthCompare(CompareFunction compare) =>
      _gl.depthFunc(compareFunctionToGl(compare));

  /// [attachment] is ignored, and that is a real limitation rather than an
  /// oversight.
  ///
  /// Per-attachment blend state needs `EXT_draw_buffers_indexed`, which is an
  /// optional WebGL2 extension. The engine uses the index exactly once — the
  /// MRT probe switching blending off on attachment 1 — and it sets the same
  /// state on both, so nothing it draws depends on them differing. If that ever
  /// changes, this needs the extension and a capability query beside it.
  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    if (state == null) {
      _gl.disable(web.WebGLRenderingContext.BLEND);
      return;
    }
    _gl.enable(web.WebGLRenderingContext.BLEND);
    _gl.blendEquationSeparate(
      blendOperationToGl(state.colorOperation),
      blendOperationToGl(state.alphaOperation),
    );
    _gl.blendFuncSeparate(
      blendFactorToGl(state.sourceColorFactor),
      blendFactorToGl(state.destinationColorFactor),
      blendFactorToGl(state.sourceAlphaFactor),
      blendFactorToGl(state.destinationAlphaFactor),
    );
  }

  @override
  void bindPipeline(PipelineHandle pipeline) {
    final program = pipeline.backend as WebGlProgram;
    _program = program;
    _gl.useProgram(program.program);
  }

  @override
  void bindVertexBuffer(GeometryBuffer buffer, int vertexCount,
      {int slot = 0}) {
    _gl.bindBuffer(web.WebGLRenderingContext.ARRAY_BUFFER,
        buffer.backend as web.WebGLBuffer);
    _describeVertices(slot);
  }

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) {
    // Transient geometry: a buffer per call, orphaned when the frame ends. The
    // flutter_gpu backend has a ring of bump allocators for this; here the
    // driver owns the lifetime, so a fresh buffer is both correct and simpler.
    final buffer = _gl.createBuffer();
    _gl.bindBuffer(web.WebGLRenderingContext.ARRAY_BUFFER, buffer);
    _gl.bufferData(
      web.WebGLRenderingContext.ARRAY_BUFFER,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes).toJS,
      web.WebGLRenderingContext.STREAM_DRAW,
    );
    _transient.add(buffer);
    _describeVertices(slot);
  }

  /// Points the attributes of one slot at the buffer that was just bound.
  ///
  /// Two paths, and the split is the point. **Without a layout this guesses
  /// from the shader** — see [WebGlProgram.attributes] — which is what every
  /// draw in this engine did before instancing and what keeps every existing
  /// picture identical. **With a layout it stops guessing**, because a layout
  /// is the only thing that can say which of two buffers steps per instance.
  void _describeVertices(int slot) {
    final program = _program;
    if (program == null) {
      throw StateError('bind a pipeline before binding vertices: the vertex '
          'layout comes from the shader, so there is nothing to describe '
          'against yet');
    }

    final layout = program.layout;
    if (layout == null) {
      if (slot != 0) {
        throw StateError(
          'slot $slot was bound on a pipeline built without a layout. Which '
          'buffer an attribute comes from is exactly what a layout says, and '
          'reflection cannot answer it — build the pipeline with a '
          'VertexLayoutSpec.',
        );
      }
      final stride = program.vertexFloats * 4;
      var offset = 0;
      for (final attribute in program.attributes) {
        _gl.enableVertexAttribArray(attribute.location);
        _gl.vertexAttribPointer(
          attribute.location,
          attribute.componentCount,
          web.WebGLRenderingContext.FLOAT,
          false,
          stride,
          offset,
        );
        offset += attribute.componentCount * 4;
      }
      return;
    }

    if (slot < 0 || slot >= layout.buffers.length) {
      throw RangeError.range(slot, 0, layout.buffers.length - 1, 'slot',
          'the pipeline\'s layout describes ${layout.buffers.length} buffers');
    }
    final buffer = layout.buffers[slot];
    final divisor = buffer.stepMode == VertexStepMode.instance ? 1 : 0;
    for (final attribute in buffer.attributes) {
      final location =
          _gl.getAttribLocation(program.program, attribute.name);
      // Negative means the linker dropped it — an `in` the stage declares and
      // never reads. Not an error: the same thing happens on Impeller, and a
      // layout naming an attribute the shader optimised away is a layout that
      // is merely more complete than it needs to be.
      if (location < 0) continue;
      _gl.enableVertexAttribArray(location);
      _gl.vertexAttribPointer(
        location,
        attribute.format.componentCount,
        web.WebGLRenderingContext.FLOAT,
        false,
        buffer.strideInBytes,
        attribute.offsetInBytes,
      );
      _gl.vertexAttribDivisor(location, divisor);
      // **Divisors are sticky per attribute location, not per buffer and not
      // per draw.** Remembering which ones were set is what lets
      // [clearBindings] put them back; without it the next non-instanced draw
      // inherits a divisor of one and renders one instance's worth of
      // geometry, with no GL error anywhere.
      if (divisor != 0) _instancedLocations.add(location);
    }
  }

  /// Attribute locations that currently carry a non-zero divisor.
  final Set<int> _instancedLocations = <int>{};

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    _gl.bindBuffer(web.WebGLRenderingContext.ELEMENT_ARRAY_BUFFER,
        buffer.backend as web.WebGLBuffer);
    _indexType = type;
    _indexCount = indexCount;
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    final buffer = _gl.createBuffer();
    _gl.bindBuffer(web.WebGLRenderingContext.ELEMENT_ARRAY_BUFFER, buffer);
    _gl.bufferData(
      web.WebGLRenderingContext.ELEMENT_ARRAY_BUFFER,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes).toJS,
      web.WebGLRenderingContext.STREAM_DRAW,
    );
    _transient.add(buffer);
    _indexType = type;
    _indexCount = indexCount;
  }

  final List<web.WebGLBuffer?> _transient = <web.WebGLBuffer?>[];
  final List<web.WebGLBuffer?> _uniformBuffers = <web.WebGLBuffer?>[];

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    final program = _program;
    if (program == null) return false;
    final block = program.blocks[blockName];
    // False rather than throwing, exactly as the contract says: a block the
    // compiler dropped because nothing read it is not an error.
    if (block == null) return false;

    final data = Float32List(block.sizeInBytes ~/ 4);
    members.forEach((String name, Float32List values) {
      final offset = block.offsets[name];
      if (offset == null) {
        // Loud, because silence here is indistinguishable from working. A
        // member the caller wrote and the block does not have leaves zeros in
        // its place, and zeros are a plausible value for most of them — a
        // shadow strength of zero is a scene with no shadows and no error.
        //
        // Not the same as a *block* that is missing, which is an ordinary thing
        // the contract allows: a compiler drops a whole block nothing reads.
        // Having the block and not the member means the two ends disagree about
        // its shape, and that is worth stopping for.
        throw StateError(
          'uniform block "$blockName" has no member "$name". It has: '
          '${block.offsets.keys.join(', ')}. The engine and the shader '
          'disagree about this block.',
        );
      }
      if (offset ~/ 4 + values.length > data.length) {
        throw StateError(
          'uniform block "$blockName" member "$name" wants '
          '${values.length} floats at offset ${offset ~/ 4}, past the block\'s '
          '${data.length}. std140 pads array elements to sixteen bytes; a '
          'tightly packed array of scalars will overrun exactly like this.',
        );
      }
      data.setRange(offset ~/ 4, offset ~/ 4 + values.length, values);
    });

    final ubo = _gl.createBuffer();
    _gl.bindBuffer(web.WebGL2RenderingContext.UNIFORM_BUFFER, ubo);
    _gl.bufferData(web.WebGL2RenderingContext.UNIFORM_BUFFER, data.toJS,
        web.WebGLRenderingContext.STREAM_DRAW);
    final binding = _nextBlockBinding++;
    _gl.uniformBlockBinding(program.program, block.index, binding);
    _gl.bindBufferBase(
        web.WebGL2RenderingContext.UNIFORM_BUFFER, binding, ubo);
    _uniformBuffers.add(ubo);
    return true;
  }

  @override
  void bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
  }) {
    final program = _program;
    if (program == null) return;
    final location = program.samplers[slot];
    if (location == null) return;

    final backend = texture.backend as WebGlTexture;
    assert(
      backend.isSampleable,
      'the "$slot" slot was handed a texture that is a renderbuffer — '
      'multisampled or deviceTransient — which can only ever be an attachment',
    );

    final unit = _nextTextureUnit++;
    _gl.activeTexture(web.WebGLRenderingContext.TEXTURE0 + unit);
    _gl.bindTexture(web.WebGLRenderingContext.TEXTURE_2D, backend.texture);

    final options = sampler ?? SamplerOptions.linearRepeat;
    void set(int name, int value) => _gl.texParameteri(
        web.WebGLRenderingContext.TEXTURE_2D, name, value);
    set(web.WebGLRenderingContext.TEXTURE_MIN_FILTER,
        minMagFilterToGl(options.minFilter));
    set(web.WebGLRenderingContext.TEXTURE_MAG_FILTER,
        minMagFilterToGl(options.magFilter));
    set(web.WebGLRenderingContext.TEXTURE_WRAP_S,
        addressModeToGl(options.widthAddressMode));
    set(web.WebGLRenderingContext.TEXTURE_WRAP_T,
        addressModeToGl(options.heightAddressMode));

    _gl.uniform1i(_gl.getUniformLocation(program.program, slot), unit);
  }

  /// Forgets bindings without touching rasteriser state, as the contract says.
  ///
  /// Texture units and uniform block bindings restart, which is what makes the
  /// next thing drawn in this pass independent of what came before it.
  @override
  void clearBindings() {
    _nextTextureUnit = 0;
    _nextBlockBinding = 0;
    _indexCount = 0;
    // Divisors, before anything else forgets which ones were set. They are
    // global per attribute location and survive both the draw and the buffer
    // binding, so an instanced draw followed by an ordinary one would otherwise
    // draw a single triangle's worth of a mesh and report nothing.
    for (final location in _instancedLocations) {
      _gl.vertexAttribDivisor(location, 0);
    }
    _instancedLocations.clear();
    _gl.bindBuffer(web.WebGLRenderingContext.ARRAY_BUFFER, null);
    _gl.bindBuffer(web.WebGLRenderingContext.ELEMENT_ARRAY_BUFFER, null);
  }

  @override
  void draw({int instanceCount = 1}) {
    if (instanceCount <= 0) return;
    if (instanceCount == 1) {
      // Not `drawElementsInstanced` with a count of one. They are specified to
      // draw the same thing, but this path is every draw the engine has made
      // until now, and a golden that moves because a non-instanced draw quietly
      // became an instanced one would be a very expensive way to learn that a
      // driver disagrees with the specification.
      _gl.drawElements(_primitive, _indexCount, indexTypeToGl(_indexType), 0);
    } else {
      _gl.drawElementsInstanced(
          _primitive, _indexCount, indexTypeToGl(_indexType), 0, instanceCount);
    }
    // A draw consumes the bindings that were set for it, in the sense that the
    // next one rebinds from scratch. Unit counters reset so a pass with many
    // draws does not run out of texture units.
    _nextTextureUnit = 0;
    _nextBlockBinding = 0;
  }

  @override
  void submit() {
    // Resolve any multisampled attachment into the texture that was named for
    // it. On flutter_gpu this is `StoreAction.multisampleResolve` and the
    // driver does it at pass end; here it is an explicit blit, which is the
    // same operation said out loud.
    for (var i = 0; i < _resolves.length; i++) {
      final resolve = _resolves[i];
      if (resolve == null) continue;
      final source = _sources[i];
      final target = _gl.createFramebuffer();
      _gl.bindFramebuffer(web.WebGL2RenderingContext.DRAW_FRAMEBUFFER, target);
      _device._attach(web.WebGL2RenderingContext.DRAW_FRAMEBUFFER,
          web.WebGLRenderingContext.COLOR_ATTACHMENT0, resolve);
      _gl.bindFramebuffer(
          web.WebGL2RenderingContext.READ_FRAMEBUFFER, _framebuffer);
      _gl.readBuffer(web.WebGLRenderingContext.COLOR_ATTACHMENT0 + i);
      _gl.blitFramebuffer(
        0, 0, source.width, source.height, //
        0, 0, resolve.width, resolve.height, //
        web.WebGLRenderingContext.COLOR_BUFFER_BIT,
        web.WebGLRenderingContext.NEAREST,
      );
      _gl.deleteFramebuffer(target);
    }

    for (final buffer in _transient) {
      _gl.deleteBuffer(buffer);
    }
    for (final buffer in _uniformBuffers) {
      _gl.deleteBuffer(buffer);
    }
    _gl.bindFramebuffer(web.WebGLRenderingContext.FRAMEBUFFER, null);
    _gl.deleteFramebuffer(_framebuffer);
  }
}
