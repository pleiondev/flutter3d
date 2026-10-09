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
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;
import 'package:web/web.dart' as web;

import 'webgl_buffers.dart';
import 'webgl_device.dart';
import 'webgl_formats.dart';
import 'webgl_framebuffer.dart';
import 'webgl_shaders.dart';

/// One pass, recorded straight into the context. See the library note above.
final class WebGlEncoder extends PassEncoder with CommandEncoder {
  WebGlEncoder(this._device, this._gl, RenderPassDescriptor descriptor)
    : _descriptor = descriptor,
      _targetHeight = descriptor.colors.isNotEmpty
          ? _levelSize(
              descriptor.colors.first.texture.height,
              descriptor.colors.first.mipLevel,
            )
          : _levelSize(
              descriptor.depth?.texture.height ?? 0,
              descriptor.depth?.mipLevel ?? 0,
            ),
      _targetWidth = descriptor.colors.isNotEmpty
          ? _levelSize(
              descriptor.colors.first.texture.width,
              descriptor.colors.first.mipLevel,
            )
          : _levelSize(
              descriptor.depth?.texture.width ?? 0,
              descriptor.depth?.mipLevel ?? 0,
            ),
      _depthReadOnly = descriptor.depth?.depthReadOnly ?? false,
      _stencilReadOnly = descriptor.depth?.stencilReadOnly ?? false {
    _framebuffer = _gl.createFramebuffer();
    _gl.bindFramebuffer(web.WebGLRenderingContext.FRAMEBUFFER, _framebuffer);

    // The 1.0 pass state starts where the contract says, before any clear —
    // `clearBufferfv` writes through the colour mask, so a mask the last
    // pass left would clear only some channels. Context state, all three,
    // like the blend constant below.
    _gl
      ..colorMask(true, true, true, true)
      ..disable(web.WebGLRenderingContext.POLYGON_OFFSET_FILL)
      ..polygonOffset(0, 0);
    if (_device.features.has(DeviceFeature.depthClamp)) {
      _gl.disable(webglDepthClamp);
    }

    final buffers = _attachments;
    for (var i = 0; i < descriptor.colors.length; i++) {
      final color = descriptor.colors[i];
      final attachment = web.WebGLRenderingContext.COLOR_ATTACHMENT0 + i;
      _attachOrFail(
        attachment,
        color.texture,
        face: color.face,
        mipLevel: color.mipLevel,
        layer: color.layer,
      );
      buffers.add(attachment);
      _resolves.add(color.resolveTexture);
      _sources.add(color.texture);
      _faces.add(color.face);
      _mipLevels.add(color.mipLevel);
      if (color.texture.storageMode == StorageMode.deviceTransient) {
        _invalidated.add(attachment);
      }
    }
    _gl.drawBuffers(buffers.map((int b) => b.toJS).toList().toJS);
    _drawBuffers = List<int>.unmodifiable(buffers);

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

    // The blend constant starts every pass at transparent black, the same
    // promise the stencil's setters get reset for below and for the same
    // reason: `glBlendColor` is context state, so a pass that names
    // `CONSTANT_COLOR` without setting a constant would multiply by whatever
    // the pass before it happened to leave. Unlike the stencil this is not
    // gated on an attachment — any pass can blend.
    _gl.blendColor(0, 0, 0, 0);

    final depth = descriptor.depth;
    if (depth != null) {
      // A depth-only format — `d16UNormInt`, `d32Float` — attaches as depth
      // alone. On the combined point it is an incomplete framebuffer, which
      // is every draw dropped.
      final point = depth.texture.format.hasStencil
          ? web.WebGL2RenderingContext.DEPTH_STENCIL_ATTACHMENT
          : web.WebGLRenderingContext.DEPTH_ATTACHMENT;
      _attachOrFail(
        point,
        depth.texture,
        face: depth.face,
        mipLevel: depth.mipLevel,
        layer: depth.layer,
      );
      if (depth.texture.storageMode == StorageMode.deviceTransient) {
        _invalidated.add(point);
      }
      // Depth must be writable for a clear to land, whatever the pass sets
      // afterwards. Not cleared at all when the pass loads it — `R8`: a
      // texture keeps what was drawn into it, so loading is doing nothing.
      //
      // **Read-only depth is honoured, not ignored**: no clear (the contract
      // ignores the load action then) and a mask that stays off whatever
      // `setDepthWrite` asks, so the pass may sample the same texture.
      _gl.depthMask(!_depthReadOnly);
      if (!_depthReadOnly && depth.loadAction == LoadAction.clear) {
        _gl.clearDepth(depth.clearValue);
        _gl.clear(web.WebGLRenderingContext.DEPTH_BUFFER_BIT);
      }

      // The stencil starts every pass switched off, whatever the last pass
      // left — the contract says so, and here the setters are context state
      // that would otherwise carry straight over. The mask goes back to every
      // bit *before* the clear, for the same reason `depthMask(true)` is
      // above it: a clear lands only through the write mask. A read-only
      // stencil gets a mask of nothing instead, and keeps it.
      if (depth.texture.format.hasStencil) {
        _gl.stencilMask(_stencilReadOnly ? 0 : 0xFF);
        _gl.stencilFunc(web.WebGLRenderingContext.ALWAYS, 0, 0xFF);
        _gl.stencilOp(
          web.WebGLRenderingContext.KEEP,
          web.WebGLRenderingContext.KEEP,
          web.WebGLRenderingContext.KEEP,
        );
        if (!_stencilReadOnly && depth.stencilLoadAction == LoadAction.clear) {
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
        '${descriptor.depth != null ? ' and a depth attachment' : ''}'
        '${_attachmentLabels(descriptor)}. '
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

    // Off at every pass's start, as `setAlphaToCoverage` promises: it is
    // global state, and a pass of leaves left it on for the bloom after it.
    _gl.disable(web.WebGLRenderingContext.SAMPLE_ALPHA_TO_COVERAGE);

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

    // The pass's first timestamp, last of all its setup: what it times is
    // the pass's own work, as WebGPU's beginning-of-pass write does.
    _writeTimestamp(descriptor.timestampWrites?.beginningOfPassIndex);
  }

  /// What the pass was opened with: the formats `executeBundles` holds a
  /// bundle to, the query sets the queries write.
  final RenderPassDescriptor _descriptor;

  /// `DepthTarget.depthReadOnly` and `stencilReadOnly`, held for the whole
  /// pass: every later write mask is ANDed with them.
  final bool _depthReadOnly;
  final bool _stencilReadOnly;

  /// Attaches through [attachToFramebuffer], tearing the pass down if the
  /// attachment names a layer the texture does not have.
  void _attachOrFail(
    int attachment,
    TextureHandle texture, {
    int face = 0,
    int mipLevel = 0,
    int layer = 0,
  }) {
    try {
      attachToFramebuffer(
        _gl,
        web.WebGLRenderingContext.FRAMEBUFFER,
        attachment,
        texture,
        face: face,
        mipLevel: mipLevel,
        layer: layer,
      );
    } on ArgumentError {
      _release();
      rethrow;
    }
  }

  /// `queryCounterEXT` into query [index] of the pass's timestamp set, when
  /// the descriptor named one.
  void _writeTimestamp(int? index) {
    final writes = _descriptor.timestampWrites;
    final timer = _device.timerQuery;
    if (writes == null || index == null || timer == null) return;
    final queries = webglQueriesOf(writes.querySet);
    if (index < 0 || index >= queries.queries.length) {
      _fail('timestamp index $index is outside ${writes.querySet}');
    }
    timer.queryCounterEXT(queries.queries[index]!, webglTimestampTarget);
    queries.written.add(index);
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
    _gl.stencilMaskSeparate(target, _stencilReadOnly ? 0 : state.writeMask);
  }

  final WebGlDevice _device;
  final web.WebGL2RenderingContext _gl;

  /// The pass's own framebuffer, or null once [_release] has deleted it.
  /// Null is what lets [submit] tell a live pass from one already torn down —
  /// by an earlier submit, or by [_fail] on the way out.
  web.WebGLFramebuffer? _framebuffer;

  /// The attachment's height, for turning top-left rectangles into GL's
  /// bottom-left ones. See [_flipY].
  ///
  /// The height of the *level* the pass draws into, not of the texture: a
  /// probe filtering its chain attaches level three of a 64-pixel cube, and a
  /// viewport of sixty-four over an eight-pixel level would put the
  /// full-screen triangle's centre off the attachment entirely.
  final int _targetHeight;

  /// The attachment's width, for the viewport and scissor a pass starts with.
  final int _targetWidth;

  /// [base] halved [mipLevel] times and never below one — the same arithmetic
  /// `texStorage2D` allocated the level with.
  static int _levelSize(int base, int mipLevel) {
    final size = base >> mipLevel;
    return size < 1 ? 1 : size;
  }

  final List<TextureHandle?> _resolves = <TextureHandle?>[];
  final List<TextureHandle> _sources = <TextureHandle>[];

  /// The attachments whose texture is `deviceTransient`, which [submit] tells
  /// the driver it may throw away — `H7`.
  final List<int> _invalidated = <int>[];

  /// Which face and level each attachment named, so a resolve lands on the
  /// same subresource the pass drew into.
  final List<int> _faces = <int>[];
  final List<int> _mipLevels = <int>[];

  /// Every colour attachment of the pass, `COLOR_ATTACHMENT0 + i` at `i`.
  final List<int> _attachments = <int>[];

  /// The draw buffers the framebuffer currently has, set by the constructor
  /// to every attachment and by [bindPipeline] to the ones its program
  /// writes. Held so a pipeline that writes the same set does not call
  /// `drawBuffers` again.
  List<int> _drawBuffers = const <int>[];

  /// Points the pass's draw buffers at the attachments [program] writes, and
  /// the rest at `NONE`.
  ///
  /// GL ES refuses a draw that leaves an active draw buffer without a
  /// fragment output behind it (`INVALID_OPERATION`, and nothing drawn), and
  /// the draw buffers are the one thing that says which attachments a draw
  /// touches. `NONE` leaves an attachment as it was, which is what Impeller
  /// does with a target a stage does not write and what WebGPU does under a
  /// zero write mask. A program that writes them all, or whose outputs could
  /// not be read, gets the full list back.
  void _selectDrawBuffers(WebGlProgram program) {
    final outputs = program.fragmentOutputs;
    final wanted = <int>[
      for (var i = 0; i < _attachments.length; i++)
        (outputs?.contains(i) ?? true)
            ? _attachments[i]
            : web.WebGLRenderingContext.NONE,
    ];
    if (_sameBuffers(wanted, _drawBuffers)) return;
    _gl.drawBuffers(wanted.map((int b) => b.toJS).toList().toJS);
    _drawBuffers = wanted;
  }

  static bool _sameBuffers(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  WebGlProgram? _program;
  int _primitive = web.WebGLRenderingContext.TRIANGLES;
  IndexType _indexType = IndexType.int32;
  int _indexCount = 0;

  /// Where the bound index buffer's range starts, in bytes. `drawElements`
  /// takes it as its offset; it used to draw from byte zero of every buffer.
  int _indexOffset = 0;

  /// What has been bound since the pipeline was: block names, sampler names
  /// and vertex slots. A draw holds the program's declarations against these
  /// and names whatever it was not handed.
  final Set<String> _boundBlocks = <String>{};
  final Set<String> _boundSamplers = <String>{};
  final Set<int> _boundSlots = <int>{};

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
  ///
  /// An [UnsupportedCapability] naming `DeviceFeature.wireframe`, and not
  /// the [StateError] a fault raises, because this is the one that a caller
  /// asked about first: the type is what lets a caller catch this and draw
  /// lines instead without also swallowing a broken frame. Since 1.0 the pass
  /// survives it, as it survives every capability refusal: nothing reached
  /// the driver, and the caller may go on and submit.
  @override
  void setPolygonMode(PolygonMode mode) => webglGatePolygonMode(mode);

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
  void setDepthWrite({required bool enabled}) =>
      _gl.depthMask(enabled && !_depthReadOnly);

  /// `SAMPLE_ALPHA_TO_COVERAGE` — `P7`: in a pass of one sample GL turns
  /// coverage into nothing, which is what the interface promises.
  @override
  void setAlphaToCoverage({required bool enabled}) => enabled
      ? _gl.enable(web.WebGLRenderingContext.SAMPLE_ALPHA_TO_COVERAGE)
      : _gl.disable(web.WebGLRenderingContext.SAMPLE_ALPHA_TO_COVERAGE);

  @override
  void setDepthCompare(CompareFunction compare) =>
      _gl.depthFunc(compareFunctionToGl(compare));

  /// Attachment zero through the plain blend functions, which set every draw
  /// buffer at once; any other through `OES_draw_buffers_indexed`, for that
  /// buffer alone — `R8`. Without the extension the index is ignored and the
  /// call sets them all, which is what `supportsIndependentBlend` answering
  /// false promises.
  ///
  /// Zero stays on the plain functions even with the extension, because they
  /// are what put every *other* buffer back: the scene pass sets attachment
  /// zero only and has always had the surface buffer blended with it, and a
  /// pass after weighted blended transparency would otherwise inherit the
  /// revealage target's equation on draw buffer one, since here the state
  /// belongs to the context rather than to the pass.
  ///
  /// Min and max are core here; a dual-source factor needs
  /// `WEBGL_blend_func_extended` and is refused without it, before anything
  /// reaches the context.
  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    webglGateBlend(_device, state);
    final indexed = _device.drawBuffersIndexed;
    if (attachment != 0 && indexed != null) {
      if (state == null) {
        indexed.disableiOES(web.WebGLRenderingContext.BLEND, attachment);
        return;
      }
      indexed
        ..enableiOES(web.WebGLRenderingContext.BLEND, attachment)
        ..blendEquationSeparateiOES(
          attachment,
          blendOperationToGl(state.colorOperation),
          blendOperationToGl(state.alphaOperation),
        )
        ..blendFuncSeparateiOES(
          attachment,
          blendFactorToGl(state.sourceColorFactor),
          blendFactorToGl(state.destinationColorFactor),
          blendFactorToGl(state.sourceAlphaFactor),
          blendFactorToGl(state.destinationAlphaFactor),
        );
      return;
    }
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

  /// `glBlendColor`, which is what `CONSTANT_COLOR` and `CONSTANT_ALPHA` read.
  ///
  /// Context state, like every other setter here, which is why the pass
  /// constructor puts it back to transparent black — see the reset beside the
  /// stencil's.
  @override
  void setBlendColor(Vector4 color) =>
      _gl.blendColor(color.x, color.y, color.z, color.w);

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
    //
    // **Now on every call, the same program included**, because the contract
    // makes this call forget every binding. It used to skip the reset for the
    // same program, so an instanced draw's per-instance arrays stayed enabled
    // into the next draw on that pipeline, stepped per vertex once `draw` had
    // put their divisors back: another batch's instances read as vertices.
    clearBindings();
    _program = program;
    _gl.useProgram(program.program);
    _selectDrawBuffers(program);
    // Each sampler on the unit it owns, before anything is bound. A sampler's
    // uniform starts at unit zero, so one a draw never binds would otherwise
    // read whichever sampler owns zero.
    for (final MapEntry(key: name, value: sampler)
        in program.samplers.entries) {
      _gl.uniform1i(
        _gl.getUniformLocation(program.program, name),
        sampler.unit,
      );
    }
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
    // The slice's own start, which `GeometryBuffer.slice` sets and this used
    // to drop, reading every slice from byte zero.
    _describeVertices(slot, base: buffer.offsetInBytes);
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
  ///
  /// [base] is where the bound range starts in its buffer, added to every
  /// attribute's own offset.
  void _describeVertices(int slot, {int base = 0}) {
    _boundSlots.add(slot);
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
      var offset = base;
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
      // An integer format goes through `vertexAttribIPointer`, which hands the
      // shader the integers as stored. `vertexAttribPointer` with `FLOAT`
      // would read the same four bytes as a float's bit pattern — a joint
      // index of 3 arriving as 4.2e-45 — and a `uvec4` input fed that way is
      // undefined besides.
      final integer = _integerTypeOf(attribute.format);
      if (integer != null) {
        _gl.vertexAttribIPointer(
          location,
          attribute.format.componentCount,
          integer,
          buffer.strideInBytes,
          base + attribute.offsetInBytes,
        );
      } else {
        _gl.vertexAttribPointer(
          location,
          attribute.format.componentCount,
          web.WebGLRenderingContext.FLOAT,
          false,
          buffer.strideInBytes,
          base + attribute.offsetInBytes,
        );
      }
      _gl.vertexAttribDivisor(location, divisor);
      // **Divisors are sticky per attribute location, not per buffer and not
      // per draw.** Remembering which ones were set is what lets
      // [clearBindings] put them back; without it the next non-instanced draw
      // inherits a divisor of one and renders one instance's worth of
      // geometry, with no GL error anywhere.
      if (divisor != 0) _instancedLocations.add(location);
    }
  }

  /// The GL component type for an integer [format], or null for a float one.
  static int? _integerTypeOf(VertexFormat format) => switch (format) {
    VertexFormat.uint32 ||
    VertexFormat.uint32x2 ||
    VertexFormat.uint32x3 ||
    VertexFormat.uint32x4 => web.WebGLRenderingContext.UNSIGNED_INT,
    VertexFormat.sint32 ||
    VertexFormat.sint32x2 ||
    VertexFormat.sint32x3 ||
    VertexFormat.sint32x4 => web.WebGLRenderingContext.INT,
    VertexFormat.float32 ||
    VertexFormat.float32x2 ||
    VertexFormat.float32x3 ||
    VertexFormat.float32x4 => null,
    _ => null,
  };

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
    _indexOffset = buffer.offsetInBytes;
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
    _indexOffset = 0;
  }

  final List<web.WebGLBuffer?> _transient = <web.WebGLBuffer?>[];
  final List<web.WebGLBuffer?> _uniformBuffers = <web.WebGLBuffer?>[];

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    final block = _declaredBlock(shader, blockName);
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
    _uploadBlock(block, blockName, data.toJS);
    return true;
  }

  /// The block [blockName] of the bound program when [shader] declares it,
  /// or null for the answer the contract makes false.
  WebGlBlock? _declaredBlock(ShaderHandle shader, String blockName) {
    // `gfx-92n`: a block the compiled stage dropped is refused here, before
    // anything reaches the driver — binding one is a native crash on Metal.
    if (!shader.mayBindBlock(blockName)) return null;
    final block = _program?.blocks[blockName];
    // False rather than throwing, exactly as the contract says: a block the
    // compiler dropped because nothing read it is not an error. And false for
    // a block this stage does not declare, even when the other one does: the
    // contract asks of the stage, and Impeller and WebGPU answer so.
    if (block == null ||
        !(shader.backend as WebGlShader)
            .declaredIn(_gl)
            .blocks
            .contains(blockName)) {
      return null;
    }
    return block;
  }

  /// A fresh UBO holding [data], on [block]'s own binding point.
  void _uploadBlock(WebGlBlock block, String blockName, JSAny data) {
    final ubo = _gl.createBuffer();
    _gl.bindBuffer(web.WebGL2RenderingContext.UNIFORM_BUFFER, ubo);
    _gl.bufferData(
      web.WebGL2RenderingContext.UNIFORM_BUFFER,
      data,
      web.WebGLRenderingContext.STREAM_DRAW,
    );
    // **The block's own index as its binding point**, not the next number in
    // this draw. The program keeps a block's binding until told otherwise, so
    // numbering per draw let a block this draw did not bind read the buffer
    // another block had been handed at its old number.
    _gl.uniformBlockBinding(_program!.program, block.index, block.index);
    _gl.bindBufferBase(
      web.WebGL2RenderingContext.UNIFORM_BUFFER,
      block.index,
      ubo,
    );
    _uniformBuffers.add(ubo);
    _boundBlocks.add(blockName);
  }

  /// [bytes] as the block's whole contents, laid out as the linked program
  /// reports it (std140 for the engine's bundles), zero-padded to the
  /// block's size. Longer than the block is a mistake about its layout and
  /// throws, as a member past the end does in [bindUniformBlock].
  @override
  bool bindUniformBytes(ShaderHandle shader, String blockName, ByteData bytes) {
    _device.features.require(
      DeviceFeature.uniformBytes,
      backend: webglBackendName,
    );
    final block = _declaredBlock(shader, blockName);
    if (block == null) return false;
    if (bytes.lengthInBytes > block.sizeInBytes) {
      _fail(
        'uniform block "$blockName" is ${block.sizeInBytes} bytes and was '
        'handed ${bytes.lengthInBytes}',
      );
    }
    final data = Uint8List(block.sizeInBytes)
      ..setRange(
        0,
        bytes.lengthInBytes,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    _uploadBlock(block, blockName, data.toJS);
    return true;
  }

  /// False for a slot the program lacks or this stage does not declare, as
  /// the contract says.
  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    // Gated before the slot is looked at: a refusal names the sampler's
    // feature whatever slot it was aimed at.
    webglGateSampler(_device, sampler);
    if (!shader.mayBindSampler(slot)) return false;
    final program = _program;
    if (program == null) return false;
    final declared = program.samplers[slot];
    if (declared == null ||
        !(shader.backend as WebGlShader)
            .declaredIn(_gl)
            .samplers
            .contains(slot)) {
      return false;
    }

    final backend = texture.backend as WebGlTexture;
    assert(
      backend.isSampleable,
      'the "$slot" slot was handed a texture that is a renderbuffer — '
      'multisampled or deviceTransient — which can only ever be an attachment',
    );

    // The unit the sampler owns; `bindPipeline` already pointed it there.
    _gl.activeTexture(web.WebGLRenderingContext.TEXTURE0 + declared.unit);
    _gl.bindTexture(backend.target, backend.texture);

    final options = sampler ?? SamplerDescriptor.linearRepeat;
    void set(int name, int value) =>
        _gl.texParameteri(backend.target, name, value);
    set(
      web.WebGLRenderingContext.TEXTURE_MIN_FILTER,
      minFilterToGl(options.minFilter, options.mipFilter),
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
    // Set on every bind like the four above, and for the same reason: in GL
    // these are properties of the texture, not of the bind, so the same image
    // bound by a second shader with a plain sampler would otherwise keep the
    // taps the first one asked for. Skipped entirely where the extension is
    // absent — the enum is unknown to the context then, and setting it would
    // be INVALID_ENUM on every draw.
    final maxAnisotropy = _device.limits.maxSamplerAnisotropy;
    if (maxAnisotropy > 1) {
      _gl.texParameterf(
        backend.target,
        web.EXT_texture_filter_anisotropic.TEXTURE_MAX_ANISOTROPY_EXT,
        options.anisotropy.clamp(1, maxAnisotropy).toDouble(),
      );
    }
    // The third axis, for the one target that has one.
    if (backend.target == web.WebGL2RenderingContext.TEXTURE_3D) {
      set(
        web.WebGL2RenderingContext.TEXTURE_WRAP_R,
        addressModeToGl(options.depthAddressMode),
      );
    }
    // Comparison and level clamps: texture state too, so set when asked for
    // and put back to GL's defaults by the next plain bind — only then, so
    // every sampler bound before 1.0 issues exactly the calls it always did.
    if (options.usesExtendedState || backend.extendedSampling) {
      final compare = options.compare;
      set(
        web.WebGL2RenderingContext.TEXTURE_COMPARE_MODE,
        compare == null
            ? web.WebGLRenderingContext.NONE
            : web.WebGL2RenderingContext.COMPARE_REF_TO_TEXTURE,
      );
      if (compare != null) {
        set(
          web.WebGL2RenderingContext.TEXTURE_COMPARE_FUNC,
          compareFunctionToGl(compare),
        );
      }
      _gl
        ..texParameterf(
          backend.target,
          web.WebGL2RenderingContext.TEXTURE_MIN_LOD,
          options.lodMinClamp,
        )
        ..texParameterf(
          backend.target,
          web.WebGL2RenderingContext.TEXTURE_MAX_LOD,
          // GL's own default is 1000; thirty-two, the contract's "no clamp",
          // is past every chain a texture can have, so the two agree.
          options.lodMaxClamp,
        );
      backend.extendedSampling = options.usesExtendedState;
    }

    _boundSamplers.add(slot);
    return true;
  }

  /// Forgets bindings without touching rasteriser state, as the contract says.
  ///
  /// Every block, sampler and vertex slot is forgotten, so the next draw is
  /// held to exactly what is bound for it. The GL state behind a sampler or a
  /// block stays, on the unit or binding point that slot owns; `draw` clears
  /// any declared slot nobody rebound, rather than let it read a previous
  /// draw's resource.
  @override
  void clearBindings() {
    _boundBlocks.clear();
    _boundSamplers.clear();
    _boundSlots.clear();
    _indexCount = 0;
    _indexOffset = 0;
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
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) {
    final window = indexWindow(
      _indexCount,
      firstIndex: firstIndex,
      indexCount: indexCount,
    );
    if (instanceCount <= 0) return;
    // WebGL2 says where a window starts as a byte offset into the bound
    // buffer, so the start is added to the one the binding already carries.
    final offset =
        _indexOffset + window.first * (_indexType == IndexType.int16 ? 2 : 4);
    _clearWhatWasNotBound();
    if (instanceCount == 1) {
      // Not `drawElementsInstanced` with a count of one. They are specified to
      // draw the same thing, but this path is every draw the engine has made
      // until now, and a golden that moves because a non-instanced draw quietly
      // became an instanced one would be a very expensive way to learn that a
      // driver disagrees with the specification.
      _gl.drawElements(
        _primitive,
        window.count,
        indexTypeToGl(_indexType),
        offset,
      );
    } else {
      _gl.drawElementsInstanced(
        _primitive,
        window.count,
        indexTypeToGl(_indexType),
        offset,
        instanceCount,
      );
    }
    _afterDraw();
  }

  /// What every draw ends with: the divisors and the per-instance arrays put
  /// back. See the note inside.
  void _afterDraw() {
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
    //
    // The arrays go off with them, and their slots count as unbound. A draw on
    // the same pipeline that did not bind its instance slot again used to read
    // the last batch's buffer one element per vertex; now it reads the
    // attribute defaults, and `_clearWhatWasNotBound` names the slot.
    for (final location in _instancedLocations) {
      _gl.vertexAttribDivisor(location, 0);
      _gl.disableVertexAttribArray(location);
      _enabledLocations.remove(location);
    }
    _instancedLocations.clear();
    final layout = _program?.layout;
    if (layout != null) {
      for (var slot = 0; slot < layout.buffers.length; slot++) {
        if (layout.buffers[slot].stepMode == VertexStepMode.instance) {
          _boundSlots.remove(slot);
        }
      }
    }
  }

  /// Holds the program's declarations to what this draw was handed.
  ///
  /// **A declared slot left unbound is the caller's mistake, and it is named
  /// rather than served another draw's resource.** A block gets a zeroed
  /// buffer on its own binding point and a sampler an empty texture on its
  /// own unit, so the draw reads nothing it was not given, and the device's
  /// `debugDrainErrors` says which slot it was. A vertex slot the layout
  /// declares is only named: its arrays are already off.
  void _clearWhatWasNotBound() {
    final program = _program;
    if (program == null) return;
    for (final MapEntry(key: name, value: block) in program.blocks.entries) {
      if (_boundBlocks.contains(name)) continue;
      _device.reportUnbound(_placed('uniform block "$name"'));
      final zero = _gl.createBuffer();
      _gl.bindBuffer(web.WebGL2RenderingContext.UNIFORM_BUFFER, zero);
      _gl.bufferData(
        web.WebGL2RenderingContext.UNIFORM_BUFFER,
        Float32List(block.sizeInBytes ~/ 4).toJS,
        web.WebGLRenderingContext.STREAM_DRAW,
      );
      _gl.uniformBlockBinding(program.program, block.index, block.index);
      _gl.bindBufferBase(
        web.WebGL2RenderingContext.UNIFORM_BUFFER,
        block.index,
        zero,
      );
      _uniformBuffers.add(zero);
    }
    for (final MapEntry(key: name, value: sampler)
        in program.samplers.entries) {
      if (_boundSamplers.contains(name)) continue;
      _device.reportUnbound(_placed('sampler "$name"'));
      _gl.activeTexture(web.WebGLRenderingContext.TEXTURE0 + sampler.unit);
      _gl.bindTexture(sampler.target, null);
    }
    final layout = program.layout;
    if (layout != null) {
      for (var slot = 0; slot < layout.buffers.length; slot++) {
        if (!_boundSlots.contains(slot)) {
          _device.reportUnbound(_placed('vertex slot $slot'));
        }
      }
    }
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
    // A query left open ends with the pass, as GL would otherwise carry it
    // into the next one; then the pass's closing timestamp.
    if (_occlusionOpen) endOcclusionQuery();
    _writeTimestamp(_descriptor.timestampWrites?.endOfPassIndex);
    // Resolve any multisampled attachment into the texture that was named for
    // it. On flutter_gpu this is `StoreAction.multisampleResolve` and the
    // driver does it at pass end; here it is an explicit blit, which is the
    // same operation said out loud.
    //
    // **Under a scissor widened to the whole target first.** `blitFramebuffer`
    // is clipped by the scissor test, which this backend leaves enabled, and
    // the rectangle is whatever the pass's last `setScissor` named — a split
    // view, an overlay tile — so the resolve copied that rectangle and left the
    // rest of the resolve target as the previous frame had it. Widened rather
    // than switched off for the reason `WebGlDevice.blitToCanvas` gives, and
    // with nothing to put back: the pass is ending, and the next one sets its
    // own. Set per resolve, below, to the extent that resolve is written at.
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
        face: _faces[i],
        mipLevel: _mipLevels[i],
      );
      _gl.bindFramebuffer(
        web.WebGL2RenderingContext.READ_FRAMEBUFFER,
        _framebuffer,
      );
      _gl.readBuffer(web.WebGLRenderingContext.COLOR_ATTACHMENT0 + i);
      // The *level's* extent on both sides, not the texture's. Nothing in the
      // engine resolves into a level below the base today — the probe passes
      // that name one are single-sampled and ask for no resolve — but the
      // constructor computes its viewport through [_levelSize] for exactly
      // this reason, and a blit that read the base rectangle out of a
      // sixteen-pixel level would be reading three quarters of it out of
      // nothing. Written the same way here so the first pass that does resolve
      // into a level finds this already right.
      final level = _mipLevels[i];
      final resolveWidth = _levelSize(resolve.width, level);
      final resolveHeight = _levelSize(resolve.height, level);
      _gl.scissor(0, 0, resolveWidth, resolveHeight);
      _gl.blitFramebuffer(
        0,
        0,
        _levelSize(source.width, level),
        _levelSize(source.height, level), //
        0,
        0,
        resolveWidth,
        resolveHeight, //
        web.WebGLRenderingContext.COLOR_BUFFER_BIT,
        web.WebGLRenderingContext.NEAREST,
      );
      _gl.deleteFramebuffer(target);
    }

    // **Tile memory, said the only way GL can: after the resolves, these
    // attachments hold nothing anyone will read** — `H7`. `deviceTransient`
    // promises exactly that, and `invalidateFramebuffer` is what lets a tiling
    // GPU skip writing a depth or multisampled buffer back to memory at the
    // end of the pass, which is most of what a mobile browser spends on one.
    // After the blits, which read the multisampled colour, and never before.
    if (_invalidated.isNotEmpty) {
      _gl
        ..bindFramebuffer(web.WebGLRenderingContext.FRAMEBUFFER, _framebuffer)
        ..invalidateFramebuffer(
          web.WebGLRenderingContext.FRAMEBUFFER,
          <JSNumber>[
            for (final attachment in _invalidated) attachment.toJS,
          ].toJS,
        );
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

  /// The labels `GraphicsDevice.setLabel` gave [descriptor]'s attachments,
  /// as a clause for a message, or nothing when none has one.
  String _attachmentLabels(RenderPassDescriptor descriptor) {
    final labels = <String>[
      for (final color in descriptor.colors)
        if (_device.labelOf(color.texture) case final String label) '"$label"',
      if (descriptor.depth case final depth?)
        if (_device.labelOf(depth.texture) case final String label)
          '"$label" (depth)',
    ];
    return labels.isEmpty ? '' : ' (${labels.join(', ')})';
  }

  /// Tears the pass down, then throws.
  ///
  /// Every throw out of an encoder ends the pass — nothing resumes one — but
  /// until this existed the error paths kept what only [submit] deleted, so a
  /// pass that failed leaked its framebuffer and every transient buffer it had
  /// made, once per retry. Routing the encoder's own throw sites through here
  /// makes the cleanup a property of failing rather than a thing each site
  /// remembers.
  ///
  /// The message says where in the pass it happened ([_where]), since WebGL2
  /// has no debug output of its own to say it.
  Never _fail(String message) {
    _release();
    final where = _where;
    throw StateError(where == null ? message : '$message ($where)');
  }

  // ------------------------------------------------------------------------
  // 1.0: debug groups and markers.
  //
  // **WebGL2 has no `KHR_debug`**, so no browser tool and no frame capture
  // sees these: there is no call to hand them to. They are kept for this
  // backend's own words instead — a pass that fails, and a slot a draw left
  // unbound, say which group was open and which marker came last — and a
  // `RecordingDevice` over this device writes them into its trace, as it does
  // for every backend.
  // ------------------------------------------------------------------------

  /// The groups open now, outermost first.
  final List<String> _groups = <String>[];

  /// The last marker [insertDebugMarker] set, since the last group opened or
  /// closed.
  String? _marker;

  @override
  void pushDebugGroup(String label) {
    _groups.add(label);
    _marker = null;
  }

  /// Closes the innermost group. One more pop than pushes does nothing, as
  /// the backends with a debug API forgive it too.
  @override
  void popDebugGroup() {
    if (_groups.isNotEmpty) _groups.removeLast();
    _marker = null;
  }

  @override
  void insertDebugMarker(String label) => _marker = label;

  /// Where in the pass this is, for a message — the pass's label, the open
  /// groups and the last marker, joined — or null when none of them is set.
  String? get _where {
    final parts = <String>[
      if (_descriptor.label case final String label) 'pass "$label"',
      if (_groups.isNotEmpty) 'in ${_groups.map((g) => '"$g"').join(' > ')}',
      if (_marker case final String marker) 'after "$marker"',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// [what], with where in the pass it happened when anything says so.
  String _placed(String what) => switch (_where) {
    null => what,
    final where => '$what ($where)',
  };

  // ------------------------------------------------------------------------
  // 1.0. Every member gates on its feature before it looks at anything it was
  // handed, and a refusal leaves the pass as it was: nothing reached the
  // context, and the caller may go on drawing and submit. That is the one
  // way these differ from [_fail], which is for a pass that went wrong.
  // ------------------------------------------------------------------------

  /// A byte offset into the bound index buffer for the window's first index.
  int _windowOffset(int first) =>
      _indexOffset + first * (_indexType == IndexType.int16 ? 2 : 4);

  /// [draw] itself with a zero base vertex and first instance; otherwise
  /// `WEBGL_draw_instanced_base_vertex_base_instance`, called by name since
  /// `package:web` has no binding for it.
  @override
  void drawIndexed(IndexedDraw draw) {
    webglGateIndexedDraw(_device, draw);
    if (!draw.usesBaseVertexOrInstance) {
      this.draw(
        instanceCount: draw.instanceCount,
        firstIndex: draw.firstIndex,
        indexCount: draw.indexCount,
      );
      return;
    }
    final window = indexWindow(
      _indexCount,
      firstIndex: draw.firstIndex,
      indexCount: draw.indexCount,
    );
    if (draw.instanceCount <= 0) return;
    _clearWhatWasNotBound();
    _device.baseVertexBaseInstanceExtension!.callMethodVarArgs<JSAny?>(
      'drawElementsInstancedBaseVertexBaseInstanceWEBGL'.toJS,
      <JSAny?>[
        _primitive.toJS,
        window.count.toJS,
        indexTypeToGl(_indexType).toJS,
        _windowOffset(window.first).toJS,
        draw.instanceCount.toJS,
        draw.baseVertex.toJS,
        draw.firstInstance.toJS,
      ],
    );
    _afterDraw();
  }

  /// One `multiDrawElementsInstancedWEBGL` where `WEBGL_multi_draw` was
  /// granted and no draw needs a base vertex or instance; a loop of
  /// [drawIndexed] otherwise, which the contract allows.
  @override
  void multiDraw(List<IndexedDraw> draws) {
    _device.features.require(
      DeviceFeature.multiDraw,
      backend: webglBackendName,
    );
    for (final draw in draws) {
      webglGateIndexedDraw(_device, draw);
    }
    if (draws.isEmpty) return;
    final extension = _device.multiDrawExtension;
    if (extension == null ||
        draws.any((IndexedDraw d) => d.usesBaseVertexOrInstance)) {
      draws.forEach(drawIndexed);
      return;
    }
    final windows = <({int first, int count})>[
      for (final draw in draws)
        indexWindow(
          _indexCount,
          firstIndex: draw.firstIndex,
          indexCount: draw.indexCount,
        ),
    ];
    _clearWhatWasNotBound();
    extension.multiDrawElementsInstancedWEBGL(
      _primitive,
      Int32List.fromList(<int>[for (final w in windows) w.count]).toJS,
      0,
      indexTypeToGl(_indexType),
      Int32List.fromList(<int>[
        for (final w in windows) _windowOffset(w.first),
      ]).toJS,
      0,
      Int32List.fromList(<int>[
        for (final draw in draws)
          draw.instanceCount < 0 ? 0 : draw.instanceCount,
      ]).toJS,
      0,
      draws.length,
    );
    _afterDraw();
  }

  @override
  void multiDrawIndirect(
    StorageBuffer arguments,
    int drawCount, {
    int offsetInBytes = 0,
    StorageBuffer? countBuffer,
    int countOffsetInBytes = 0,
  }) => webglRefuseIndirect(DeviceFeature.multiDrawIndirect);

  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) =>
      webglRefuseIndirect(DeviceFeature.indirectDraw);

  /// `drawArrays`, `drawArraysInstanced`, or — for a first instance — the
  /// base-instance extension's `drawArraysInstancedBaseInstanceWEBGL`.
  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) {
    webglGateNonIndexed(_device, firstInstance);
    if (vertexCount < 0 || firstVertex < 0) {
      throw RangeError(
        'a draw of $vertexCount vertices from $firstVertex counts backwards',
      );
    }
    if (instanceCount <= 0 || vertexCount == 0) return;
    _clearWhatWasNotBound();
    if (firstInstance != 0) {
      _device.baseVertexBaseInstanceExtension!.callMethodVarArgs<JSAny?>(
        'drawArraysInstancedBaseInstanceWEBGL'.toJS,
        <JSAny?>[
          _primitive.toJS,
          firstVertex.toJS,
          vertexCount.toJS,
          instanceCount.toJS,
          firstInstance.toJS,
        ],
      );
    } else if (instanceCount == 1) {
      _gl.drawArrays(_primitive, firstVertex, vertexCount);
    } else {
      _gl.drawArraysInstanced(
        _primitive,
        firstVertex,
        vertexCount,
        instanceCount,
      );
    }
    _afterDraw();
  }

  /// Replays each bundle's recorded calls into this pass, each from no
  /// pipeline and no bindings, and forgets both afterwards — WebGPU's rule,
  /// which a replay has to keep by hand.
  @override
  void executeBundles(List<RenderBundle> bundles) {
    _device.features.require(
      DeviceFeature.renderBundles,
      backend: webglBackendName,
    );
    final colors = <TextureFormat>[
      for (final color in _descriptor.colors) color.texture.format,
    ];
    final depth = _descriptor.depth?.texture.format;
    final samples = _descriptor.colors.isNotEmpty
        ? _descriptor.colors.first.texture.sampleCount
        : (_descriptor.depth?.texture.sampleCount ?? 1);
    final recorded = <WebGlBundle>[
      for (final bundle in bundles)
        if (bundle.backend case final WebGlBundle backend)
          backend
        else
          throw ArgumentError.value(
            bundle,
            'bundles',
            'is not a WebGL2 bundle',
          ),
    ];
    for (final bundle in bundles) {
      final made = bundle.descriptor;
      final matches =
          made.colorFormats.length == colors.length &&
          <bool>[
            for (var i = 0; i < colors.length; i++)
              made.colorFormats[i] == colors[i],
          ].every((bool same) => same) &&
          made.depthStencilFormat == depth &&
          made.sampleCount == samples;
      if (!matches) {
        throw ArgumentError.value(
          bundle,
          'bundles',
          'was recorded for other attachments than this pass has',
        );
      }
    }
    for (final bundle in recorded) {
      _program = null;
      clearBindings();
      for (final call in bundle.calls) {
        call(this);
      }
    }
    _program = null;
    clearBindings();
  }

  /// Whether [beginOcclusionQuery] has a query open.
  bool _occlusionOpen = false;

  /// `ANY_SAMPLES_PASSED`, which answers whether any sample passed: zero
  /// means nothing was visible, as the contract promises, and one stands
  /// for any other count, which is all the contract says a count means.
  @override
  void beginOcclusionQuery(int queryIndex) {
    _device.features.require(
      DeviceFeature.occlusionQuery,
      backend: webglBackendName,
    );
    final set = _descriptor.occlusionQuerySet;
    if (set == null) {
      throw StateError('this pass was opened without an occlusionQuerySet');
    }
    if (_occlusionOpen) {
      throw StateError('one occlusion query at a time: end the open one');
    }
    final queries = webglQueriesOf(set);
    RangeError.checkValidIndex(queryIndex, queries.queries, 'queryIndex');
    _gl.beginQuery(
      web.WebGL2RenderingContext.ANY_SAMPLES_PASSED,
      queries.queries[queryIndex] ??
          (throw StateError('this query set was released')),
    );
    queries.written.add(queryIndex);
    _occlusionOpen = true;
  }

  @override
  void endOcclusionQuery() {
    _device.features.require(
      DeviceFeature.occlusionQuery,
      backend: webglBackendName,
    );
    if (!_occlusionOpen) throw StateError('no occlusion query is open');
    _gl.endQuery(web.WebGL2RenderingContext.ANY_SAMPLES_PASSED);
    _occlusionOpen = false;
  }

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) =>
      webglRefusePipelineStatistics();

  @override
  void endPipelineStatisticsQuery() => webglRefusePipelineStatistics();

  /// `polygonOffset(slopeScale, constant)` — GL's factor and units, in that
  /// order. A clamp is refused: see [webglGateDepthBias].
  @override
  void setDepthBias(DepthBias bias) {
    webglGateDepthBias(_device, bias);
    if (bias == DepthBias.none) {
      _gl
        ..disable(web.WebGLRenderingContext.POLYGON_OFFSET_FILL)
        ..polygonOffset(0, 0);
      return;
    }
    _gl
      ..enable(web.WebGLRenderingContext.POLYGON_OFFSET_FILL)
      ..polygonOffset(bias.slopeScale, bias.constant.toDouble());
  }

  /// `colorMask` for attachment zero, which sets every draw buffer at once;
  /// `colorMaskiOES` for any other where `OES_draw_buffers_indexed` was
  /// granted — [setBlend]'s rule, for the reason it gives.
  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) {
    _device.features.require(
      DeviceFeature.colorWriteMask,
      backend: webglBackendName,
    );
    final indexed = _device.drawBuffersIndexed;
    if (attachment != 0 && indexed != null) {
      indexed.colorMaskiOES(
        attachment,
        mask.writesRed,
        mask.writesGreen,
        mask.writesBlue,
        mask.writesAlpha,
      );
      return;
    }
    _gl.colorMask(
      mask.writesRed,
      mask.writesGreen,
      mask.writesBlue,
      mask.writesAlpha,
    );
  }

  /// `EXT_depth_clamp`'s `DEPTH_CLAMP_EXT`, where the extension was granted.
  @override
  void setDepthClamp({required bool enabled}) {
    webglGateDepthClamp(_device);
    enabled ? _gl.enable(webglDepthClamp) : _gl.disable(webglDepthClamp);
  }

  @override
  bool bindStorageBuffer(
    ShaderHandle shader,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) => webglRefuseRenderStageStorage();

  @override
  bool bindStorageTexture(
    ShaderHandle shader,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) => webglRefuseRenderStageStorage();
}

/// `EXT_depth_clamp`'s `DEPTH_CLAMP_EXT`, which `package:web` does not name.
const int webglDepthClamp = 0x864F;

// --------------------------------------------------------------------------
// The gates both the pass and the bundle encoder ask, so the two refuse the
// same calls in the same words.
// --------------------------------------------------------------------------

/// [PolygonMode.line] is refused: OpenGL ES has no `glPolygonMode`.
/// Wireframe on this backend means drawing line primitives from an index
/// buffer built for them, which is the renderer's decision and not a
/// substitution a backend may make on its own; quietly filling would show a
/// solid model to somebody who asked for a wireframe.
void webglGatePolygonMode(PolygonMode mode) {
  if (canDrawPolygonMode(mode)) return;
  throw UnsupportedCapability(
    DeviceFeature.wireframe,
    backend: webglBackendName,
    reason:
        'OpenGL ES has no glPolygonMode; wireframe needs line primitives and '
        'an index buffer to match, which is a decision for the renderer',
  );
}

/// The blend features a state names: the constant, min and max (all three
/// WebGL2 core) and the dual-source factors (`WEBGL_blend_func_extended`).
void webglGateBlend(WebGlDevice device, BlendState? state) {
  if (state == null) return;
  if (state.usesBlendColor) {
    device.features.require(
      DeviceFeature.blendConstant,
      backend: webglBackendName,
    );
  }
  if (state.usesMinMax) {
    device.features.require(
      DeviceFeature.minMaxBlend,
      backend: webglBackendName,
    );
  }
  if (state.usesDualSource) {
    device.features.require(
      DeviceFeature.dualSourceBlending,
      backend: webglBackendName,
      reason: 'WEBGL_blend_func_extended was not granted',
    );
  }
}

/// The sampler features a bind names. A border colour is refused always.
void webglGateSampler(WebGlDevice device, SamplerDescriptor? sampler) {
  if (sampler == null || !sampler.usesExtendedState) return;
  if (sampler.compare != null) {
    device.features.require(
      DeviceFeature.samplerCompare,
      backend: webglBackendName,
    );
  }
  if (sampler.lodMinClamp != 0 || sampler.lodMaxClamp != 32) {
    device.features.require(
      DeviceFeature.samplerLodClamp,
      backend: webglBackendName,
    );
  }
  if (sampler.borderColor != null) {
    // TODO(webgl): border colours — WebGL2 has no CLAMP_TO_BORDER (it is
    // OpenGL ES 3.2, and no WebGL extension exposes it).
    throw UnsupportedCapability(
      DeviceFeature.samplerBorderColor,
      backend: webglBackendName,
      reason: 'WebGL2 has no CLAMP_TO_BORDER',
    );
  }
}

/// Depth bias, and a refusal of the one part of it GL cannot do: a clamp.
///
/// `glPolygonOffsetClamp` is desktop GL 4.6 and an ES extension WebGL does
/// not expose, so a non-zero [DepthBias.clamp] would be silently unclamped.
/// Refused by name instead — an [UnsupportedError] rather than an
/// [UnsupportedCapability], since the device does have depth bias, and a
/// caller wanting the clamp keeps the slope small instead.
void webglGateDepthBias(WebGlDevice device, DepthBias bias) {
  device.features.require(DeviceFeature.depthBias, backend: webglBackendName);
  if (bias.clamp != 0) {
    // TODO(webgl): depth-bias clamp — needs EXT_polygon_offset_clamp exposed
    // to WebGL; until then no non-zero clamp can be honoured.
    throw UnsupportedError(
      'WebGL2 cannot clamp a depth bias (DepthBias.clamp ${bias.clamp}): it '
      'has no polygonOffsetClamp. Pass a clamp of zero.',
    );
  }
}

/// `EXT_depth_clamp`, granted or not.
void webglGateDepthClamp(WebGlDevice device) => device.features.require(
  DeviceFeature.depthClamp,
  backend: webglBackendName,
  reason: 'EXT_depth_clamp was not granted',
);

/// A base vertex or first instance needs the base-vertex extension.
void webglGateIndexedDraw(WebGlDevice device, IndexedDraw draw) {
  if (!draw.usesBaseVertexOrInstance) return;
  device.features.require(
    DeviceFeature.baseVertexBaseInstance,
    backend: webglBackendName,
    reason: 'WEBGL_draw_instanced_base_vertex_base_instance was not granted',
  );
}

/// A non-indexed draw is core; a first instance needs the same extension a
/// base instance does.
void webglGateNonIndexed(WebGlDevice device, int firstInstance) {
  device.features.require(
    DeviceFeature.nonIndexedDraw,
    backend: webglBackendName,
  );
  if (firstInstance == 0) return;
  device.features.require(
    DeviceFeature.baseVertexBaseInstance,
    backend: webglBackendName,
    reason: 'WEBGL_draw_instanced_base_vertex_base_instance was not granted',
  );
}

/// Storage bound to a render stage.
Never webglRefuseRenderStageStorage() {
  // TODO(webgl): render-stage storage — WebGL2 has no shader storage blocks
  // or image load/store (both OpenGL ES 3.1); the WebGPU backend has them.
  throw UnsupportedCapability(
    DeviceFeature.renderStageStorage,
    backend: webglBackendName,
    reason: 'WebGL2 has no storage buffers or images; that is OpenGL ES 3.1',
  );
}

/// An indirect draw of either kind.
Never webglRefuseIndirect(DeviceFeature feature) {
  // TODO(webgl): indirect draws — WebGL2 has no DRAW_INDIRECT_BUFFER (it is
  // OpenGL ES 3.1), so no draw can read its counts from a buffer.
  throw UnsupportedCapability(
    feature,
    backend: webglBackendName,
    reason: 'WebGL2 has no indirect draws; that is OpenGL ES 3.1',
  );
}

/// A pipeline-statistics query.
Never webglRefusePipelineStatistics() {
  // TODO(webgl): pipeline statistics — no WebGL2 query or extension counts
  // shader invocations or primitives.
  throw UnsupportedCapability(
    DeviceFeature.pipelineStatisticsQuery,
    backend: webglBackendName,
    reason: 'WebGL2 has no pipeline statistics query',
  );
}
