/// One pass, recorded straight into the context.
///
/// **There is no command buffer here, and that is the sharpest structural
/// difference from flutter_gpu.** Impeller records into a buffer and executes
/// on `submit`, so the engine orders its passes by submission. WebGL issues
/// every call as it is made, so ordering is the order the engine calls in —
/// which is the same order, arrived at differently. [WebGlEncoder.submit]
/// therefore only tears the framebuffer down.
///
/// The HAL survives this because it never promised buffering; it promised that
/// passes execute in submission order, and both honour that.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgl_device.dart';
import 'webgl_formats.dart';
import 'webgl_framebuffer.dart';

/// One pass, recorded straight into the context. See the library note above.
final class WebGlEncoder implements CommandEncoder {
  WebGlEncoder(this._device, this._gl, RenderPassDescriptor descriptor)
    : _targetHeight = descriptor.colors.isNotEmpty
          ? descriptor.colors.first.texture.height
          : (descriptor.depth?.texture.height ?? 0),
      _targetWidth = descriptor.colors.isNotEmpty
          ? descriptor.colors.first.texture.width
          : (descriptor.depth?.texture.width ?? 0) {
    _framebuffer = _gl.createFramebuffer();
    _gl.bindFramebuffer(web.WebGLRenderingContext.FRAMEBUFFER, _framebuffer);

    final buffers = <int>[];
    for (var i = 0; i < descriptor.colors.length; i++) {
      final color = descriptor.colors[i];
      final attachment = web.WebGLRenderingContext.COLOR_ATTACHMENT0 + i;
      attachToFramebuffer(
        _gl,
        web.WebGLRenderingContext.FRAMEBUFFER,
        attachment,
        color.texture,
      );
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
      attachToFramebuffer(
        _gl,
        web.WebGLRenderingContext.FRAMEBUFFER,
        web.WebGL2RenderingContext.DEPTH_STENCIL_ATTACHMENT,
        depth.texture,
      );
      // Depth must be writable for a clear to land, whatever the pass sets
      // afterwards.
      _gl.depthMask(true);
      _gl.clearDepth(depth.clearValue);
      _gl.clear(web.WebGLRenderingContext.DEPTH_BUFFER_BIT);

      // The stencil starts every pass switched off, whatever the last pass
      // left — the contract says so, and here the setters are context state
      // that would otherwise carry straight over. The mask goes back to every
      // bit *before* the clear, for the same reason `depthMask(true)` is
      // above it: a clear lands only through the write mask.
      if (depth.texture.format.hasStencil) {
        _gl.stencilMask(0xFF);
        _gl.stencilFunc(web.WebGLRenderingContext.ALWAYS, 0, 0xFF);
        _gl.stencilOp(
          web.WebGLRenderingContext.KEEP,
          web.WebGLRenderingContext.KEEP,
          web.WebGLRenderingContext.KEEP,
        );
        if (depth.stencilLoadAction == LoadAction.clear) {
          _gl.clearStencil(depth.stencilClearValue);
          _gl.clear(web.WebGLRenderingContext.STENCIL_BUFFER_BIT);
        }
      }
    }

    // Checked, not assumed. An incomplete framebuffer is not an error in
    // OpenGL: every draw against it is silently discarded, which is a whole
    // frame of work producing nothing and no way to tell from inside the
    // engine. The status word is worth more than the discovery.
    final status = _device.debugFramebufferStatus();
    if (status != 'complete') {
      // Through [_fail], so the framebuffer made a few lines up does not
      // outlive the constructor that could never hand it to anybody.
      _fail(
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

    // **A pass starts covering the whole of what it draws into.** Neither
    // rectangle was ever set here, so both were whatever the last pass left —
    // and for the first pass of a frame, whatever size the canvas is.
    //
    // The engine did not notice because every one of its passes sets a viewport
    // of its own before drawing. `flutter3d_conformance` is written against the
    // contract rather than against this engine's habits, and its pipeline-switch
    // check draws into a 16×16 target on a 64×64 device: the viewport stayed
    // 64×64, so the centre pixel of the attachment was three quarters of the way
    // out along the full-screen triangle, and the particle's radial falloff had
    // faded to nothing by the time it got there. The check reported a stale
    // uniform block, which is the one thing it was not — Impeller passes all ten
    // and the block was bound correctly on both.
    //
    // The scissor matters more than the viewport and is why this is not
    // cosmetic: SCISSOR_TEST goes back on immediately below, and the rectangle
    // it went back on with belonged to the previous pass — a shadow-atlas tile,
    // most of the time. Every draw of the next pass outside that tile was
    // discarded.
    _gl.viewport(0, 0, _targetWidth, _targetHeight);
    _gl.scissor(0, 0, _targetWidth, _targetHeight);

    // Back on, because everything after this is a draw and the engine sets a
    // scissor per tile.
    _gl.enable(web.WebGLRenderingContext.SCISSOR_TEST);

    // Depth testing follows the attachment rather than being switched on for
    // every pass. Without a depth buffer GL specifies the test as passing
    // always, so leaving it enabled was harmless and dishonest; a pass that has
    // no depth now says so, and does not inherit the last pass's answer.
    if (depth != null) {
      _gl.enable(web.WebGLRenderingContext.DEPTH_TEST);
    } else {
      _gl.disable(web.WebGLRenderingContext.DEPTH_TEST);
    }
    // The stencil test the same way: on whenever the attachment carries one,
    // in the disabled configuration set above, and off when nothing does.
    // Enabled-but-inert rather than switched on at the first `setStencil`,
    // so that switching it back off is one state rather than two.
    if (depth != null && depth.texture.format.hasStencil) {
      _gl.enable(web.WebGLRenderingContext.STENCIL_TEST);
    } else {
      _gl.disable(web.WebGLRenderingContext.STENCIL_TEST);
    }
  }

  StencilState _stencilFront = StencilState.disabled;
  StencilState _stencilBack = StencilState.disabled;
  int _stencilReference = 0;

  @override
  void setStencil(StencilState front, {StencilState? back}) {
    _stencilFront = front;
    _stencilBack = back ?? front;
    _applyStencil();
  }

  /// Re-issues the whole configuration, because GL keeps the reference on
  /// the same call as the compare — `stencilFunc(func, ref, mask)` — where
  /// the contract keeps them apart. Either setter therefore repeats the
  /// other's half; three calls per face, a handful of times a frame.
  ///
  /// Narrowed before it reaches GL, which would otherwise *clamp* it to the
  /// attachment's range and make this the one backend where a reference of
  /// 0x101 means 255 rather than 1.
  @override
  void setStencilReference(int value) {
    _stencilReference = StencilState.narrowReference(value);
    _applyStencil();
  }

  void _applyStencil() {
    if (_stencilFront == _stencilBack) {
      _applyStencilFace(StencilFace.both, _stencilFront);
      return;
    }
    _applyStencilFace(StencilFace.front, _stencilFront);
    _applyStencilFace(StencilFace.back, _stencilBack);
  }

  void _applyStencilFace(StencilFace face, StencilState state) {
    final target = stencilFaceToGl(face);
    _gl.stencilFuncSeparate(
      target,
      compareFunctionToGl(state.compare),
      _stencilReference,
      state.readMask,
    );
    _gl.stencilOpSeparate(
      target,
      stencilOperationToGl(state.failOp),
      stencilOperationToGl(state.depthFailOp),
      stencilOperationToGl(state.passOp),
    );
    _gl.stencilMaskSeparate(target, state.writeMask);
  }

  final WebGlDevice _device;
  final web.WebGL2RenderingContext _gl;

  /// The pass's own framebuffer, or null once [_release] has deleted it.
  /// Null is what lets [submit] tell a live pass from one already torn down —
  /// by an earlier submit, or by [_fail] on the way out.
  web.WebGLFramebuffer? _framebuffer;

  /// The attachment's height, for turning top-left rectangles into GL's
  /// bottom-left ones. See [_flipY].
  final int _targetHeight;

  /// The attachment's width, for the viewport and scissor a pass starts with.
  final int _targetWidth;

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
    _fail(
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
    // **Attribute arrays are global state and outlive the program that enabled
    // them.** A stage with more attributes than the next one leaves the extras
    // switched on, pointing at whatever buffer follows — and in WebGL2 an
    // enabled array with no buffer bound is `INVALID_OPERATION`, which drops
    // the draw with nothing logged.
    //
    // The sky is what found this. Its vertex stage takes eight attributes
    // against a mesh's five, so every draw after it — including the composite
    // that puts the frame on screen — was silently discarded and the whole
    // frame came back black. Not "a scene without a sky": black. Nothing had
    // ever compared a sky between the backends, so nothing could see it.
    if (!identical(program, _program)) {
      for (final location in _enabledLocations) {
        _gl.disableVertexAttribArray(location);
      }
      _enabledLocations.clear();
    }
    _program = program;
    _gl.useProgram(program.program);
  }

  /// Attribute locations switched on in this context, wherever they were
  /// switched on. Held by the device, because the state is the context's — see
  /// [WebGlDevice.enabledAttributeLocations].
  Set<int> get _enabledLocations => _device.enabledAttributeLocations;

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) {
    _gl.bindBuffer(
      web.WebGLRenderingContext.ARRAY_BUFFER,
      buffer.backend as web.WebGLBuffer,
    );
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
      _fail(
        'bind a pipeline before binding vertices: the vertex '
        'layout comes from the shader, so there is nothing to describe '
        'against yet',
      );
    }

    final layout = program.layout;
    if (layout == null) {
      if (slot != 0) {
        _fail(
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
        _enabledLocations.add(attribute.location);
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
      _fail(
        'slot $slot is out of range: the pipeline\'s layout describes '
        '${layout.buffers.length} buffer(s)',
      );
    }
    final buffer = layout.buffers[slot];
    final divisor = buffer.stepMode == VertexStepMode.instance ? 1 : 0;
    for (final attribute in buffer.attributes) {
      final location = _gl.getAttribLocation(program.program, attribute.name);
      // Negative means the linker dropped it — an `in` the stage declares and
      // never reads. Not an error: the same thing happens on Impeller, and a
      // layout naming an attribute the shader optimised away is a layout that
      // is merely more complete than it needs to be.
      if (location < 0) continue;
      _gl.enableVertexAttribArray(location);
      _enabledLocations.add(location);
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

  /// Attribute locations carrying a non-zero divisor, wherever they were set.
  /// Held by the device, because the state is the context's — see
  /// [WebGlDevice.instancedAttributeLocations].
  Set<int> get _instancedLocations => _device.instancedAttributeLocations;

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    _gl.bindBuffer(
      web.WebGLRenderingContext.ELEMENT_ARRAY_BUFFER,
      buffer.backend as web.WebGLBuffer,
    );
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
        _fail(
          'uniform block "$blockName" has no member "$name". It has: '
          '${block.offsets.keys.join(', ')}. The engine and the shader '
          'disagree about this block.',
        );
      }
      if (offset ~/ 4 + values.length > data.length) {
        _fail(
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
    _gl.bufferData(
      web.WebGL2RenderingContext.UNIFORM_BUFFER,
      data.toJS,
      web.WebGLRenderingContext.STREAM_DRAW,
    );
    final binding = _nextBlockBinding++;
    _gl.uniformBlockBinding(program.program, block.index, binding);
    _gl.bindBufferBase(web.WebGL2RenderingContext.UNIFORM_BUFFER, binding, ubo);
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
    _gl.bindTexture(backend.target, backend.texture);

    final options = sampler ?? SamplerOptions.linearRepeat;
    void set(int name, int value) =>
        _gl.texParameteri(backend.target, name, value);
    set(
      web.WebGLRenderingContext.TEXTURE_MIN_FILTER,
      minMagFilterToGl(options.minFilter),
    );
    set(
      web.WebGLRenderingContext.TEXTURE_MAG_FILTER,
      minMagFilterToGl(options.magFilter),
    );
    set(
      web.WebGLRenderingContext.TEXTURE_WRAP_S,
      addressModeToGl(options.widthAddressMode),
    );
    set(
      web.WebGLRenderingContext.TEXTURE_WRAP_T,
      addressModeToGl(options.heightAddressMode),
    );

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
    // Then the arrays themselves, for the reason `bindPipeline` gives: an
    // enabled array with no buffer under it is `INVALID_OPERATION`, and this
    // method unbinds the buffer two lines down.
    for (final location in _enabledLocations) {
      _gl.disableVertexAttribArray(location);
    }
    _enabledLocations.clear();
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
        _primitive,
        _indexCount,
        indexTypeToGl(_indexType),
        0,
        instanceCount,
      );
    }
    // **Divisors go back here, not in `clearBindings`.** They are state of an
    // attribute location: they survive the draw, the buffer, the program and
    // the pass, so an ordinary draw that follows an instanced one reads one
    // value for a whole triangle and the frame comes back flat, with every
    // counter in the engine reporting the right numbers.
    //
    // `clearBindings` also puts them back, and `divisor_leak_test.dart` proved
    // that it does — while calling it itself, and describing it as "what every
    // pass in this engine does between draws". The engine calls it in three
    // places, and the mesh-particle contributor calls it *before* its own draw
    // rather than after. So the divisors outlived the frame, and the next
    // frame's mesh read its texture coordinate once for the whole quad: the
    // checkerboard cube in `particles-mesh` came back a flat average of itself.
    //
    // Undoing it here instead makes the leak structurally impossible rather
    // than a thing each caller has to remember, which is what the enabled
    // arrays above already learned.
    for (final location in _instancedLocations) {
      _gl.vertexAttribDivisor(location, 0);
    }
    _instancedLocations.clear();

    // A draw consumes the bindings that were set for it, in the sense that the
    // next one rebinds from scratch. Unit counters reset so a pass with many
    // draws does not run out of texture units.
    _nextTextureUnit = 0;
    _nextBlockBinding = 0;
  }

  @override
  void submit() {
    if (_framebuffer == null) {
      // Refused rather than repeated. A second submit would re-run the
      // resolve blits below against a framebuffer the first one deleted —
      // reads from nothing, silently — so a pass already torn down, by an
      // earlier submit or by [_fail], says so out loud.
      throw StateError(
        'this pass was already submitted, or failed and was cleaned up: '
        'a WebGlEncoder is one pass, not a reusable object',
      );
    }
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
      attachToFramebuffer(
        _gl,
        web.WebGL2RenderingContext.DRAW_FRAMEBUFFER,
        web.WebGLRenderingContext.COLOR_ATTACHMENT0,
        resolve,
      );
      _gl.bindFramebuffer(
        web.WebGL2RenderingContext.READ_FRAMEBUFFER,
        _framebuffer,
      );
      _gl.readBuffer(web.WebGLRenderingContext.COLOR_ATTACHMENT0 + i);
      _gl.blitFramebuffer(
        0,
        0,
        source.width,
        source.height, //
        0,
        0,
        resolve.width,
        resolve.height, //
        web.WebGLRenderingContext.COLOR_BUFFER_BIT,
        web.WebGLRenderingContext.NEAREST,
      );
      _gl.deleteFramebuffer(target);
    }

    _release();
  }

  /// Deletes what this pass created and nothing else will: the framebuffer
  /// and every transient and uniform buffer. The lists are cleared and the
  /// framebuffer nulled so a second run deletes nothing twice — that null is
  /// also how [submit] recognises a pass already torn down.
  void _release() {
    for (final buffer in _transient) {
      _gl.deleteBuffer(buffer);
    }
    _transient.clear();
    for (final buffer in _uniformBuffers) {
      _gl.deleteBuffer(buffer);
    }
    _uniformBuffers.clear();
    _gl.bindFramebuffer(web.WebGLRenderingContext.FRAMEBUFFER, null);
    _gl.deleteFramebuffer(_framebuffer);
    _framebuffer = null;
  }

  /// Tears the pass down, then throws.
  ///
  /// Every throw out of an encoder ends the pass — nothing resumes one — but
  /// until this existed the error paths kept what only [submit] deleted, so a
  /// pass that failed leaked its framebuffer and every transient buffer it had
  /// made, once per retry. Routing the encoder's own throw sites through here
  /// makes the cleanup a property of failing rather than a thing each site
  /// remembers.
  Never _fail(String message) {
    _release();
    throw StateError(message);
  }
}
