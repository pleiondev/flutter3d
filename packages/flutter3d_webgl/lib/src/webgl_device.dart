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
  WebGlProgram(this.program, this.attributes, this.blocks, this.samplers);

  final web.WebGLProgram program;

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
    final attributes = web.WebGLContextAttributes(preserveDrawingBuffer: true);
    final gl =
        canvas.getContext('webgl2', attributes) as web.WebGL2RenderingContext?;
    if (gl == null) return null;
    return WebGlDevice._(gl, canvas, WebGlShaderLibrary(gl, sources));
  }

  final web.WebGL2RenderingContext _gl;
  final web.HTMLCanvasElement _canvas;
  final WebGlShaderLibrary _library;

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
  bool get supportsOffscreenMsaa => true;

  @override
  // OpenGL ES has no glPolygonMode. See canDrawPolygonMode.
  bool get supportsWireframe => false;

  @override
  PipelineHandle createPipeline(ShaderHandle vertex, ShaderHandle fragment) =>
      _library.link(vertex, fragment);

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
  TextureHandle createTexture(RenderTargetSpec spec) {
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
      1,
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
  }) {
    // RGBA8 is the only format the engine uploads from the CPU, and four bytes
    // a texel is the whole of the size question here — WebGL has no padding to
    // ask about, unlike Impeller's base mip size.
    if (pixels.lengthInBytes != width * height * 4) return null;

    final handle = createTexture(RenderTargetSpec(
      width: width,
      height: height,
      format: format,
    ));
    final backend = handle.backend as WebGlTexture;
    _gl.bindTexture(web.WebGLRenderingContext.TEXTURE_2D, backend.texture);
    _gl.texSubImage2D(
      web.WebGLRenderingContext.TEXTURE_2D,
      0,
      0,
      0,
      width.toJS,
      height.toJS,
      web.WebGLRenderingContext.RGBA.toJS,
      web.WebGLRenderingContext.UNSIGNED_BYTE,
      pixels.buffer
          .asUint8List(pixels.offsetInBytes, pixels.lengthInBytes)
          .toJS,
    );
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

  void _blitToCanvas(TextureHandle frame) {
    final source = _gl.createFramebuffer();
    _gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, source);
    _attach(web.WebGL2RenderingContext.READ_FRAMEBUFFER,
        web.WebGLRenderingContext.COLOR_ATTACHMENT0, frame);
    _gl.bindFramebuffer(web.WebGL2RenderingContext.DRAW_FRAMEBUFFER, null);
    _gl.blitFramebuffer(
      0, 0, frame.width, frame.height, //
      0, 0, _canvas.width, _canvas.height, //
      web.WebGLRenderingContext.COLOR_BUFFER_BIT,
      web.WebGLRenderingContext.NEAREST,
    );
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

    // `readPixels` returns bottom-up: GL's origin is the lower-left corner and
    // the HAL says row-major from the *top*-left. Flipping here rather than
    // leaving it to the caller, because a caller cannot tell which way round a
    // backend handed it pixels — and a golden comparison against a vertically
    // mirrored frame fails in a way that looks like a rendering bug.
    return _flipVertically(js.toDart, texture.width, texture.height);
  }

  static ByteData _flipVertically(Uint8List pixels, int width, int height) {
    final stride = width * 4;
    final out = Uint8List(pixels.length);
    for (var row = 0; row < height; row++) {
      final from = (height - 1 - row) * stride;
      out.setRange(row * stride, row * stride + stride, pixels, from);
    }
    return ByteData.sublistView(out);
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
  WebGlEncoder(this._device, this._gl, RenderPassDescriptor descriptor) {
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

    _gl.enable(web.WebGLRenderingContext.DEPTH_TEST);
    _gl.enable(web.WebGLRenderingContext.SCISSOR_TEST);
  }

  final WebGlDevice _device;
  final web.WebGL2RenderingContext _gl;
  late final web.WebGLFramebuffer? _framebuffer;

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
      _gl.viewport(rect.x, rect.y, rect.width, rect.height);

  @override
  void setScissor(ScreenRect rect) =>
      _gl.scissor(rect.x, rect.y, rect.width, rect.height);

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
  void bindVertexBuffer(GeometryBuffer buffer, int vertexCount) {
    _gl.bindBuffer(web.WebGLRenderingContext.ARRAY_BUFFER,
        buffer.backend as web.WebGLBuffer);
    _describeVertices();
  }

  @override
  void bindVertexData(ByteData bytes, int vertexCount) {
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
    _describeVertices();
  }

  /// Points every attribute the bound program declares at the bound buffer.
  ///
  /// See [WebGlProgram.attributes] for why this can be done at all without the
  /// HAL carrying a vertex layout.
  void _describeVertices() {
    final program = _program;
    if (program == null) {
      throw StateError('bind a pipeline before binding vertices: the vertex '
          'layout comes from the shader, so there is nothing to describe '
          'against yet');
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
  }

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
      if (offset == null) return;
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
    _gl.bindBuffer(web.WebGLRenderingContext.ARRAY_BUFFER, null);
    _gl.bindBuffer(web.WebGLRenderingContext.ELEMENT_ARRAY_BUFFER, null);
  }

  @override
  void draw() {
    _gl.drawElements(_primitive, _indexCount, indexTypeToGl(_indexType), 0);
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
