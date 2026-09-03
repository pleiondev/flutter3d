/// Records state and rasterises on `draw`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shader_library.dart';
import 'cpu_vertex_fetch.dart';

/// Records state and rasterises on `draw`.
final class CpuEncoder implements CommandEncoder {
  CpuEncoder(this._descriptor) {
    for (final color in _descriptor.colors) {
      final texture = _attachment(color);
      if (color.loadAction != LoadAction.clear) continue;
      final value = color.clearValue ?? Vector4.zero();
      // The whole attachment, whatever the scissor says. Here that is the
      // natural way to write it, which is the point of the rule being stated
      // rather than inherited from what one API happened to do.
      for (var i = 0; i < texture.pixels.length; i += 4) {
        texture.pixels[i] = value.x;
        texture.pixels[i + 1] = value.y;
        texture.pixels[i + 2] = value.z;
        texture.pixels[i + 3] = value.w;
      }
    }
    final depth = _descriptor.depth;
    if (depth != null) {
      final texture = depth.texture.backend as CpuTexture;
      texture.depthBuffer().fillRange(
        0,
        texture.width * texture.height,
        depth.clearValue,
      );
      _depthTarget = texture;
      // The stencil only where the format says there is one — the test
      // against an attachment without a stencil is specified to pass always,
      // and a null here is how the loops below get that for free.
      if (depth.texture.format.hasStencil) {
        final stencil = texture.stencilBuffer();
        if (depth.stencilLoadAction == LoadAction.clear) {
          stencil.fillRange(0, stencil.length, depth.stencilClearValue & 0xFF);
        }
        _stencilTarget = stencil;
      }
    }
  }

  final RenderPassDescriptor _descriptor;
  CpuTexture? _depthTarget;
  Uint8List? _stencilTarget;

  // Off on both faces until a pass says otherwise, which is what a fresh
  // `flutter_gpu` pass and a fresh GL context both start with.
  StencilState _stencilFront = StencilState.disabled;
  StencilState _stencilBack = StencilState.disabled;
  int _stencilReference = 0;

  /// The buffer to test against, or null when nothing would change: no
  /// attachment carries one, or both faces are still switched off. Asked once
  /// per primitive so the thirty-odd scenes that never mention the stencil
  /// pay a null check per triangle and nothing per fragment.
  Uint8List? get _activeStencil =>
      _stencilFront == StencilState.disabled &&
          _stencilBack == StencilState.disabled
      ? null
      : _stencilTarget;

  /// The array [color] actually names: a face of a cube, a level of a chain,
  /// or the texture itself. Every write in this pass goes through it, so a
  /// probe's face and a post pass's full-size target are the same code.
  static CpuTexture _attachment(ColorTarget color) =>
      (color.texture.backend as CpuTexture).subresource(
        face: color.face,
        mipLevel: color.mipLevel,
      );

  ScreenRect? _viewport;
  ScreenRect? _scissor;
  PrimitiveType _primitive = PrimitiveType.triangle;
  CullMode _cull = CullMode.none;
  WindingOrder _winding = WindingOrder.counterClockwise;
  // False, matching a fresh `flutter_gpu` RenderPass, whose
  // `DepthAttachmentDescriptor` starts with writes disabled. That default is a
  // property of the descriptor rather than of the setter 3.47 fixed, so it is
  // unchanged — and `depth_write_test.dart` still pins it, because a default
  // nobody states is a default that drifts.
  bool _depthWrite = false;
  CompareFunction _depthCompare = CompareFunction.less;
  BlendState? _blend;
  CpuPipeline? _pipeline;

  ByteData? _vertices;
  int _vertexCount = 0;
  ByteData? _indices;
  IndexType _indexType = IndexType.int16;
  int _indexCount = 0;

  final Map<String, Map<String, Float32List>> _blocks =
      <String, Map<String, Float32List>>{};
  final Map<String, BoundTexture> _textures = <String, BoundTexture>{};

  /// Whether anything bound to this pass has levels to choose between.
  ///
  /// Asked per triangle rather than cached per bind because the bindings change
  /// inside a pass and the map is small — almost every draw here binds two
  /// textures or none. The point is only to keep the gradient arithmetic off
  /// the twenty-seven scenes that have no mip chain anywhere in them.
  bool _hasMippedTexture() {
    for (final bound in _textures.values) {
      if (bound.texture.levels != null) return true;
    }
    return false;
  }

  @override
  void setViewport(ScreenRect rect) => _viewport = rect;

  @override
  void setScissor(ScreenRect rect) => _scissor = rect;

  @override
  void setPrimitiveType(PrimitiveType type) => _primitive = type;

  @override
  void setPolygonMode(PolygonMode mode) {
    if (mode == PolygonMode.line) {
      throw UnsupportedError(
        'this backend answers false to supportsWireframe and means it. Filling '
        'the triangles instead would be a picture nobody asked for.',
      );
    }
  }

  @override
  void setCullMode(CullMode mode) => _cull = mode;

  @override
  void setWindingOrder(WindingOrder order) => _winding = order;

  /// Turns depth writes on or off, which is all it has ever meant to say.
  ///
  /// For most of this backend's life it ignored its argument and turned writes
  /// on regardless, because `flutter_gpu`'s native setter assigned the literal
  /// `true` and a software backend that behaved correctly would have put the
  /// two backends five and ten percent apart on the particle scenes — a gap
  /// loud enough to hide a real regression behind. flutter_gpu 3.47 assigns the
  /// argument, so the mirror is gone.
  ///
  /// **The sentence worth keeping from all that**: when a backend has to choose
  /// between being right and being comparable, comparable wins, and the choice
  /// gets a test that fails the day it stops being necessary. That is what
  /// `test/depth_write_test.dart` was for, and it is why this line changed on
  /// the day the SDK did rather than months later.
  @override
  void setDepthWrite(bool enabled) => _depthWrite = enabled;

  @override
  void setDepthCompare(CompareFunction compare) => _depthCompare = compare;

  @override
  void setStencil(StencilState front, {StencilState? back}) {
    _stencilFront = front;
    _stencilBack = back ?? front;
  }

  @override
  void setStencilReference(int value) =>
      _stencilReference = StencilState.narrowReference(value);

  @override
  void setBlend(BlendState? state, {int attachment = 0}) => _blend = state;

  @override
  void bindPipeline(PipelineHandle pipeline) =>
      _pipeline = pipeline.backend as CpuPipeline;

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) {
    final backend = buffer.backend as ({ByteData bytes, GeometryUsage usage});
    _bindSlot(slot, backend.bytes, vertexCount);
  }

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _bindSlot(slot, bytes, vertexCount);

  /// Slot zero stays in [_vertices] and the rest go in [_slots].
  ///
  /// Two fields rather than one map because slot zero is every draw this engine
  /// has ever made and the map would be allocated for all of them to hold one
  /// entry. The layout-less path never looks at [_slots] at all.
  void _bindSlot(int slot, ByteData bytes, int count) {
    if (slot == 0) {
      _vertices = bytes;
      _vertexCount = count;
      return;
    }
    (_slots ??= <int, ByteData>{})[slot] = bytes;
  }

  Map<int, ByteData>? _slots;

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    final backend = buffer.backend as ({ByteData bytes, GeometryUsage usage});
    _indices = backend.bytes;
    _indexType = type;
    _indexCount = indexCount;
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    _indices = bytes;
    _indexType = type;
    _indexCount = indexCount;
  }

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    _blocks[blockName] = members;
    return true;
  }

  @override
  void bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
  }) =>
      // linearRepeat for a null sampler, which is now written down in
      // `CommandEncoder.bindTexture` — it was not, and this backend picked the
      // constructor's own defaults instead, nearest and clamped. Both hardware
      // backends had independently chosen linearRepeat, so the two agreed and
      // the rule stayed unstated until a third implementation read the
      // interface and answered differently. It cost two percent of every
      // textured golden and looked like a rendering bug.
      _textures[slot] = BoundTexture(
        texture.backend as CpuTexture,
        sampler ?? SamplerOptions.linearRepeat,
      );

  @override
  void clearBindings() {
    _blocks.clear();
    _textures.clear();
  }

  @override
  void submit() {
    // Nothing deferred, so nothing to flush. Draws happened as they arrived,
    // which is a different execution model from a command buffer and one the
    // contract allows: it promises passes execute in submission order, not
    // that anything is buffered.
  }

  @override
  void draw({int instanceCount = 1}) {
    // Honestly, and to no advantage — which is the point. A scene the software
    // backend refuses to draw is a scene with no cross-backend check, and the
    // two most expensive bugs this repository has found were both found by
    // exactly that check.
    //
    // With no attribute stepping per instance there is nothing to vary yet, so
    // every repetition puts the same triangles in the same places. That is not
    // a stub: it is what an instanced draw of geometry with no per-instance
    // attributes means on any backend. The instance *index* arrives with the
    // vertex layouts that give a stage something to read it for.
    for (var instance = 0; instance < instanceCount; instance++) {
      _drawOnce(instance);
    }
  }

  void _drawOnce(int instance) {
    final pipeline = _pipeline;
    final vertices = _vertices;
    if (pipeline == null || vertices == null) return;
    if (_descriptor.colors.isEmpty) return;
    if (_primitive != PrimitiveType.triangle &&
        _primitive != PrimitiveType.line) {
      throw UnsupportedError(
        'this backend rasterises triangles and lines. $_primitive would have '
        'to be drawn as something else, and drawing a primitive as a '
        'different one is how a picture comes back plausible and wrong.',
      );
    }

    final target = _attachment(_descriptor.colors.first);
    final view =
        _viewport ??
        ScreenRect(x: 0, y: 0, width: target.width, height: target.height);

    final layout = pipeline.layout;
    final fetch = layout == null
        ? PackedFetch(vertices, _floatsPerVertex(vertices, _vertexCount))
        : LayoutFetch.build(layout, vertices, _slots, instance);
    final stride = fetch.floatsPerVertex;
    final bindings = ShaderBindings(_blocks, _textures);
    final varyingCount = pipeline.vertex.varyingCount;

    final clip = <Vector4>[Vector4.zero(), Vector4.zero(), Vector4.zero()];
    final varyings = <Float32List>[
      Float32List(varyingCount),
      Float32List(varyingCount),
      Float32List(varyingCount),
    ];
    final attributes = Float32List(stride);

    final perPrimitive = _primitive == PrimitiveType.line ? 2 : 3;
    final count = _indices != null
        ? _indexCount ~/ perPrimitive
        : _vertexCount ~/ perPrimitive;

    for (var t = 0; t < count; t++) {
      for (var corner = 0; corner < perPrimitive; corner++) {
        final vertex = _indices != null
            ? _indexAt(t * perPrimitive + corner)
            : t * perPrimitive + corner;
        if (!fetch.into(attributes, vertex)) return;
        clip[corner] = pipeline.vertex.run(
          attributes,
          bindings,
          varyings[corner],
        );
      }
      if (perPrimitive == 2) {
        _rasteriseLine(
          pipeline,
          target,
          view,
          clip,
          varyings,
          varyingCount,
          bindings,
        );
      } else {
        _rasterise(
          pipeline,
          target,
          view,
          clip,
          varyings,
          varyingCount,
          bindings,
        );
      }
    }
  }

  /// One line, a pixel wide.
  ///
  /// Bresenham on the window-space endpoints, with depth and the varyings
  /// interpolated along the run. Width is one and there is no cap or join:
  /// `PrimitiveType.line` in this engine draws debug geometry — bounds, axes,
  /// light gizmos — and a wide line would have to invent a joining rule that
  /// nothing here specifies.
  ///
  /// Deliberately separate from the triangle path rather than a degenerate
  /// case of it. A zero-area triangle has no barycentric coordinates, so the
  /// shared version would divide by zero and the clever fix for that is where
  /// a rasteriser stops being readable.
  void _rasteriseLine(
    CpuPipeline pipeline,
    CpuTexture target,
    ScreenRect view,
    List<Vector4> clip,
    List<Float32List> varyings,
    int varyingCount,
    ShaderBindings bindings,
  ) {
    for (var i = 0; i < 2; i++) {
      if (clip[i].w <= 1e-6) return;
    }

    final sx = <double>[0, 0];
    final sy = <double>[0, 0];
    final sz = <double>[0, 0];
    final invW = <double>[0, 0];
    for (var i = 0; i < 2; i++) {
      invW[i] = 1.0 / clip[i].w;
      sx[i] = view.x + (clip[i].x * invW[i] * 0.5 + 0.5) * view.width;
      sy[i] = view.y + (0.5 - clip[i].y * invW[i] * 0.5) * view.height;
      sz[i] = clip[i].z * invW[i];
    }

    final dx = sx[1] - sx[0];
    final dy = sy[1] - sy[0];
    final steps = math.max(dx.abs(), dy.abs()).ceil();
    if (steps <= 0) return;

    final depth = _depthTarget?.depthBuffer();
    // A line has no facing, so it takes the front state — which is what GL
    // does with a primitive it cannot classify.
    final stencil = _activeStencil;
    final stencilState = _stencilFront;
    final interpolated = Float32List(varyingCount);
    final context = FragmentContext();

    // Screen-space gradients, once for the whole triangle, and only when a
    // bound texture actually has levels to choose between. Solved from the
    // three window positions and the three varying values: the standard
    // two-by-two system whose determinant is the signed area already computed
    // above.
    if (_hasMippedTexture()) {
      final det =
          (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0]);
      if (det != 0.0) {
        final inv = 1.0 / det;
        final ddx = context.ddx = Float32List(varyingCount);
        final ddy = context.ddy = Float32List(varyingCount);
        for (var k = 0; k < varyingCount; k++) {
          final v0 = varyings[0][k];
          final d1 = varyings[1][k] - v0;
          final d2 = varyings[2][k] - v0;
          ddx[k] = (d1 * (sy[2] - sy[0]) - d2 * (sy[1] - sy[0])) * inv;
          ddy[k] = (d2 * (sx[1] - sx[0]) - d1 * (sx[2] - sx[0])) * inv;
        }
      }
    }
    final scissor = _scissor;

    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      final x = (sx[0] + dx * t).floor();
      final y = (sy[0] + dy * t).floor();
      if (x < 0 || y < 0 || x >= target.width || y >= target.height) continue;
      if (scissor != null &&
          (x < scissor.x ||
              y < scissor.y ||
              x >= scissor.x + scissor.width ||
              y >= scissor.y + scissor.height)) {
        continue;
      }

      final z = _asStored(sz[0] + (sz[1] - sz[0]) * t);
      final index = y * target.width + x;
      final fate = _fateOf(stencil, stencilState, index, z, depth);
      final op = _operationFor(fate, stencilState);
      if (fate != _fatePass && op == StencilOperation.keep) continue;

      final iw = invW[0] + (invW[1] - invW[0]) * t;
      for (var v = 0; v < varyingCount; v++) {
        interpolated[v] =
            (varyings[0][v] * invW[0] * (1 - t) +
                varyings[1][v] * invW[1] * t) /
            iw;
      }

      context.coord.setValues(x + 0.5, y + 0.5, z, iw);
      context.surface = null;
      final colour = pipeline.fragment.run(interpolated, bindings, context);
      if (colour == null) continue;
      if (stencil != null) _stencilWrite(stencil, index, stencilState, op);
      if (fate != _fatePass) continue;

      final at = index * 4;
      target.pixels[at] = colour.x;
      target.pixels[at + 1] = colour.y;
      target.pixels[at + 2] = colour.z;
      target.pixels[at + 3] = colour.w;
      if (depth != null && _depthWrite) depth[index] = z;
    }
  }

  /// One float, for rounding a depth to what the buffer can hold.
  final Float32List _storedDepth = Float32List(1);

  /// [z] as the depth buffer would store it.
  ///
  /// **Compared at the buffer's precision, not the arithmetic's.** The buffer
  /// is a `Float32List` and the interpolation is in doubles, so a surface
  /// drawn twice — which is what the x-ray stage does — used to compare a
  /// double against its own rounded copy: `lessEqual` failed against the
  /// pixel the same triangle had just written, by one part in ten million,
  /// and `greater` passed, so a cube in plain view was painted as its own
  /// silhouette. Hardware has one precision on both sides of the test; this
  /// gives the rasteriser the same, and a coincident surface now ties the way
  /// it ties on a GPU rather than winning or losing by rounding.
  double _asStored(double z) {
    _storedDepth[0] = z;
    return _storedDepth[0];
  }

  /// A fragment the stencil test rejected.
  static const int _fateStencilFail = 0;

  /// A fragment the stencil test passed and the depth test rejected.
  static const int _fateDepthFail = 1;

  /// A fragment both tests passed: shaded, and written if it is not discarded.
  static const int _fatePass = 2;

  /// Which of the three outcomes a fragment at [index] and depth [z] meets.
  ///
  /// The stencil test first and the depth test second, which is the order
  /// the specification runs them in and the order that decides which of a
  /// state's three operations applies. Without a stencil there is only the
  /// depth test, and the answer is the one this rasteriser always gave.
  int _fateOf(
    Uint8List? stencil,
    StencilState state,
    int index,
    double z,
    Float32List? depth,
  ) {
    if (stencil != null && !_stencilPasses(state, stencil[index])) {
      return _fateStencilFail;
    }
    if (depth != null && !_depthPasses(z, depth[index])) {
      return _fateDepthFail;
    }
    return _fatePass;
  }

  static StencilOperation _operationFor(int fate, StencilState state) =>
      switch (fate) {
        _fateStencilFail => state.failOp,
        _fateDepthFail => state.depthFailOp,
        _ => state.passOp,
      };

  /// The reference against the stored value, both through the read mask, with
  /// the reference as the "new" side of the comparison — `less` passes when
  /// the reference is below what is stored, as [CompareFunction] says.
  bool _stencilPasses(StencilState state, int stored) {
    final reference = _stencilReference & state.readMask;
    final current = stored & state.readMask;
    return switch (state.compare) {
      CompareFunction.never => false,
      CompareFunction.always => true,
      CompareFunction.less => reference < current,
      CompareFunction.lessEqual => reference <= current,
      CompareFunction.greater => reference > current,
      CompareFunction.greaterEqual => reference >= current,
      CompareFunction.equal => reference == current,
      CompareFunction.notEqual => reference != current,
    };
  }

  /// Applies [op] to the byte at [index], through the write mask.
  ///
  /// **After the fragment stage, not before it**, in both rasterisers. A
  /// discarded fragment updates neither depth nor stencil on any of the three
  /// backends — that is what makes `discard` useless for a marking draw and
  /// [BlendState.keepDestination] necessary — so the operation a fragment
  /// earned by failing a test is still only applied once the stage has said
  /// the fragment exists. The cost is a shader run for a failing fragment
  /// whose operation is not `keep`; a failing fragment whose operation *is*
  /// `keep` is skipped before shading, exactly as it always was.
  void _stencilWrite(
    Uint8List stencil,
    int index,
    StencilState state,
    StencilOperation op,
  ) {
    if (op == StencilOperation.keep) return;
    final stored = stencil[index];
    final value = switch (op) {
      StencilOperation.keep => stored,
      StencilOperation.zero => 0,
      StencilOperation.setToReferenceValue => _stencilReference,
      StencilOperation.incrementClamp => math.min(stored + 1, 0xFF),
      StencilOperation.decrementClamp => math.max(stored - 1, 0),
      StencilOperation.invert => ~stored,
      StencilOperation.incrementWrap => stored + 1,
      StencilOperation.decrementWrap => stored - 1,
    };
    stencil[index] =
        (stored & ~state.writeMask) | (value & state.writeMask & 0xFF);
  }

  /// How many floats one vertex is, from the buffer and the count.
  int _floatsPerVertex(ByteData vertices, int count) =>
      count == 0 ? 0 : (vertices.lengthInBytes ~/ 4) ~/ count;

  int _indexAt(int i) => _indexType == IndexType.int16
      ? _indices!.getUint16(i * 2, Endian.little)
      : _indices!.getUint32(i * 4, Endian.little);

  /// Smallest `w` a vertex may have and still be divided by.
  static const double _nearEpsilon = 1e-5;

  /// Clips against the near plane and rasterises what survives.
  ///
  /// The earlier version of this dropped any triangle with a vertex behind the
  /// eye, with a comment saying nothing needed a clipper yet. Something did:
  /// `cube-shadow-gap` widens its ground plane to five and a half radii —
  /// every other scene uses three — so one corner of it crosses behind the
  /// camera, both of its triangles were discarded, and the golden came back a
  /// teapot floating in black with no floor and no shadow under it. The
  /// picture did not look like a clipping bug. It looked like the ground had
  /// not been added to the scene.
  ///
  /// Sutherland-Hodgman against `w = _nearEpsilon`, which is the only plane
  /// worth clipping here: the others merely waste fragments the scissor and
  /// the bounding box already reject, while this one divides by a number at or
  /// below zero and turns the projection inside out.
  void _rasterise(
    CpuPipeline pipeline,
    CpuTexture target,
    ScreenRect view,
    List<Vector4> clip,
    List<Float32List> varyings,
    int varyingCount,
    ShaderBindings bindings,
  ) {
    var behind = 0;
    for (final c in clip) {
      if (c.w <= _nearEpsilon) behind++;
    }
    if (behind == 3) return;
    if (behind == 0) {
      _rasteriseTriangle(
        pipeline,
        target,
        view,
        clip,
        varyings,
        varyingCount,
        bindings,
      );
      return;
    }

    final poly = <Vector4>[];
    final polyVaryings = <Float32List>[];
    for (var i = 0; i < 3; i++) {
      final j = (i + 1) % 3;
      final a = clip[i];
      final b = clip[j];
      final aIn = a.w > _nearEpsilon;
      final bIn = b.w > _nearEpsilon;
      if (aIn) {
        poly.add(a);
        polyVaryings.add(varyings[i]);
      }
      if (aIn != bIn) {
        // Where the edge crosses the plane. Linear in clip space, which is
        // where it is genuinely linear — interpolating after the divide is the
        // classic way to get a seam that moves as the camera does.
        final t = (_nearEpsilon - a.w) / (b.w - a.w);
        final cutVertex = a + (b - a) * t;
        // Say where it is rather than trusting the arithmetic that put it
        // there. By construction this vertex lies *on* the plane, but `Vector4`
        // is float32-backed and the interpolation rounds — sometimes to a hair
        // below the plane, and sometimes to exactly zero. Dividing x by that
        // zero gives infinity, and the bounding box's `ceil()` throws
        // "Infinity or NaN toInt" from inside a rasteriser, which is a long way
        // from where anybody would look.
        //
        // Found by pointing a camera at a level's floor from three metres up:
        // one brush a hundred and twenty metres across is one pair of triangles
        // straddling the eye, and every frame from inside such a level crashed.
        cutVertex.w = _nearEpsilon;
        poly.add(cutVertex);
        final cut = Float32List(varyingCount);
        for (var k = 0; k < varyingCount; k++) {
          cut[k] = varyings[i][k] + (varyings[j][k] - varyings[i][k]) * t;
        }
        polyVaryings.add(cut);
      }
    }
    if (poly.length < 3) return;

    // A fan from the first vertex. Clipping one plane off a triangle leaves
    // three or four corners, so this is one triangle or two.
    for (var i = 1; i + 1 < poly.length; i++) {
      _rasteriseTriangle(
        pipeline,
        target,
        view,
        <Vector4>[poly[0], poly[i], poly[i + 1]],
        <Float32List>[polyVaryings[0], polyVaryings[i], polyVaryings[i + 1]],
        varyingCount,
        bindings,
      );
    }
  }

  void _rasteriseTriangle(
    CpuPipeline pipeline,
    CpuTexture target,
    ScreenRect view,
    List<Vector4> clip,
    List<Float32List> varyings,
    int varyingCount,
    ShaderBindings bindings,
  ) {
    final sx = <double>[0, 0, 0];
    final sy = <double>[0, 0, 0];
    final sz = <double>[0, 0, 0];
    final invW = <double>[0, 0, 0];
    for (var i = 0; i < 3; i++) {
      invW[i] = 1.0 / clip[i].w;
      final ndcX = clip[i].x * invW[i];
      final ndcY = clip[i].y * invW[i];
      sz[i] = clip[i].z * invW[i];
      // NDC to the viewport, with +Y up in clip space and row zero at the top.
      sx[i] = view.x + (ndcX * 0.5 + 0.5) * view.width;
      sy[i] = view.y + (0.5 - ndcY * 0.5) * view.height;
    }

    var area =
        (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0]);
    if (area == 0.0) return;

    // Winding is measured in window space, where y runs down, so a
    // counter-clockwise triangle has negative area here.
    final frontFacing = _winding == WindingOrder.counterClockwise
        ? area < 0
        : area > 0;
    if (_cull == CullMode.backFace && !frontFacing) return;
    if (_cull == CullMode.frontFace && frontFacing) return;

    // Wound so the interior is where every edge function is positive, which
    // the fill rule below depends on. Done after culling, which is what needs
    // the original winding.
    if (area < 0) {
      final t = sx[1];
      sx[1] = sx[2];
      sx[2] = t;
      final ty = sy[1];
      sy[1] = sy[2];
      sy[2] = ty;
      final tz = sz[1];
      sz[1] = sz[2];
      sz[2] = tz;
      final tw = invW[1];
      invW[1] = invW[2];
      invW[2] = tw;
      final tv = varyings[1];
      varyings[1] = varyings[2];
      varyings[2] = tv;
      area = -area;
    }

    // The top-left fill rule: a pixel centre landing exactly on a shared edge
    // belongs to one of the two triangles rather than to both.
    //
    // Here because it is the correct rule and costs nothing, **not** because
    // it fixed anything. It was written to explain the particle burst, which
    // is drawn as additive quads and came out five percent brighter than
    // Impeller's — double coverage along every quad's diagonal was the obvious
    // culprit, since opaque geometry hides it and additive blending does not.
    // The rule changed the picture by exactly zero pixels. With floating-point
    // window coordinates a pixel centre essentially never lands on an edge, so
    // the case the rule governs did not arise. The burst is still unexplained.
    //
    // In window space, where y runs down and the interior is w > 0: a
    // horizontal edge is a *top* edge when the interior lies below it, which
    // is when it runs left to right; any edge running upwards is a *left*
    // edge. Those two include their zeros, everything else excludes them.
    bool topLeft(double ax, double ay, double bx, double by) =>
        (ay == by && bx > ax) || by < ay;
    final fill0 = topLeft(sx[0], sy[0], sx[1], sy[1]);
    final fill1 = topLeft(sx[1], sy[1], sx[2], sy[2]);
    final fill2 = topLeft(sx[2], sy[2], sx[0], sy[0]);

    final clipRect = _scissor;
    var minX = sx.reduce((a, b) => a < b ? a : b).floor();
    var maxX = sx.reduce((a, b) => a > b ? a : b).ceil();
    var minY = sy.reduce((a, b) => a < b ? a : b).floor();
    var maxY = sy.reduce((a, b) => a > b ? a : b).ceil();
    minX = minX.clamp(clipRect?.x ?? view.x, target.width - 1);
    maxX = maxX.clamp(
      0,
      ((clipRect?.x ?? view.x) + (clipRect?.width ?? view.width)) - 1,
    );
    minY = minY.clamp(clipRect?.y ?? view.y, target.height - 1);
    maxY = maxY.clamp(
      0,
      ((clipRect?.y ?? view.y) + (clipRect?.height ?? view.height)) - 1,
    );

    final depth = _depthTarget?.depthBuffer();
    // Per face, decided before the winding swap above changed what "front"
    // means for the edge functions: the state a triangle is tested against is
    // the one for the side the camera sees.
    final stencil = _activeStencil;
    final stencilState = frontFacing ? _stencilFront : _stencilBack;
    final interpolated = Float32List(varyingCount);
    final context = FragmentContext();

    // **Screen-space gradients, which the triangle path did not have and the
    // line path did.** `CpuTexture.sample` picks the base level when it is
    // given no derivatives, so every textured triangle this backend has ever
    // drawn read the top of the mip chain however small the surface was on
    // screen. The chain was built, uploaded and unit-tested — `mip_sampling_test`
    // exercises `sample` directly with derivatives it supplies itself — and
    // nothing ever handed a triangle's to it.
    //
    // What that looks like is not a missing feature. It is a 2048-square normal
    // map read at full resolution across a few hundred pixels: detail sharper
    // and darker than the hardware backends draw, and aliasing that crawls when
    // the camera moves. It made `normal-mapping` the widest disagreement this
    // backend had with Impeller, at 1.4%, where every other lit scene sat near
    // a fifth of a percent.
    //
    // Solved from the three window positions and the three varying values, the
    // same two-by-two system the line path uses, and after the winding swap
    // above so the vertices match the varyings.
    if (_hasMippedTexture()) {
      final det =
          (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0]);
      if (det != 0.0) {
        final inv = 1.0 / det;
        final ddx = context.ddx = Float32List(varyingCount);
        final ddy = context.ddy = Float32List(varyingCount);
        for (var k = 0; k < varyingCount; k++) {
          final v0 = varyings[0][k];
          final d1 = varyings[1][k] - v0;
          final d2 = varyings[2][k] - v0;
          ddx[k] = (d1 * (sy[2] - sy[0]) - d2 * (sy[1] - sy[0])) * inv;
          ddy[k] = (d2 * (sx[1] - sx[0]) - d1 * (sx[2] - sx[0])) * inv;
        }
      }
    }

    // The surface buffer, when the pass declared one. Only the second is
    // handled: the engine opens no pass with a third, and inventing a general
    // multi-target path for a call site that does not exist would be inventing
    // the semantics too.
    final extra = _descriptor.colors.length > 1
        ? _attachment(_descriptor.colors[1])
        : null;

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final px = x + 0.5;
        final py = y + 0.5;
        final w0 =
            (sx[1] - sx[0]) * (py - sy[0]) - (sy[1] - sy[0]) * (px - sx[0]);
        final w1 =
            (sx[2] - sx[1]) * (py - sy[1]) - (sy[2] - sy[1]) * (px - sx[1]);
        final w2 =
            (sx[0] - sx[2]) * (py - sy[2]) - (sy[0] - sy[2]) * (px - sx[2]);
        if (w0 < 0 || (w0 == 0 && !fill0)) continue;
        if (w1 < 0 || (w1 == 0 && !fill1)) continue;
        if (w2 < 0 || (w2 == 0 && !fill2)) continue;

        // Barycentric, named for the corner each weight belongs to rather than
        // for the edge it came from — the two are rotated by one, which is a
        // classic way to get a picture that is almost right.
        final b0 = w1 / area;
        final b1 = w2 / area;
        final b2 = w0 / area;

        final z = _asStored(sz[0] * b0 + sz[1] * b1 + sz[2] * b2);
        final index = y * target.width + x;
        final fate = _fateOf(stencil, stencilState, index, z, depth);
        final op = _operationFor(fate, stencilState);
        // Rejected with nothing to record: gone before the stage runs, which
        // is the early-z every scene without a stencil has always had.
        if (fate != _fatePass && op == StencilOperation.keep) continue;

        // Perspective-correct: interpolate over 1/w and divide back.
        final iw = invW[0] * b0 + invW[1] * b1 + invW[2] * b2;
        for (var v = 0; v < varyingCount; v++) {
          interpolated[v] =
              (varyings[0][v] * invW[0] * b0 +
                  varyings[1][v] * invW[1] * b1 +
                  varyings[2][v] * invW[2] * b2) /
              iw;
        }

        // gl_FragCoord: pixel centre, window depth, and 1/w. Rebuilt rather
        // than reused between fragments, because a stage that kept a reference
        // to it would see the next fragment's values.
        context.coord.setValues(px, py, z, iw);
        context.surface = null;
        final colour = pipeline.fragment.run(interpolated, bindings, context);
        if (colour == null) continue;
        if (stencil != null) _stencilWrite(stencil, index, stencilState, op);
        if (fate != _fatePass) continue;

        // Attachment one, when the stage wrote it and the pass has one. Both
        // conditions matter: the lit models always write it and the shadow
        // passes never do, and a pass may have a single attachment either way.
        final surface = context.surface;
        if (surface != null && extra != null) {
          final e = index * 4;
          extra.pixels[e] = surface.x;
          extra.pixels[e + 1] = surface.y;
          extra.pixels[e + 2] = surface.z;
          extra.pixels[e + 3] = surface.w;
        }

        final at = index * 4;
        final blend = _blend;
        if (blend == null) {
          target.pixels[at] = colour.x;
          target.pixels[at + 1] = colour.y;
          target.pixels[at + 2] = colour.z;
          target.pixels[at + 3] = colour.w;
        } else {
          _blendInto(blend, target.pixels, at, colour);
        }

        if (depth != null && _depthWrite) depth[index] = z;
      }
    }
  }

  /// The blend equation, factor by factor.
  ///
  /// This used to recognise exactly two states — source-over and additive —
  /// by testing two of their factors, on the argument that a general equation
  /// nothing asked for was a guess about a call site. The third state asked:
  /// [BlendState.keepDestination] is zero and one, which the two tests read
  /// as "one and one" and drew the marking pass's colour straight over the
  /// picture it was meant to leave alone. Every factor but the four that need
  /// a blend constant is a line here now; those four throw, because the
  /// interface has no way to set one and a silent 1.0 would be exactly the
  /// mistake this replaces.
  static void _blendInto(
    BlendState blend,
    Float32List pixels,
    int at,
    Vector4 source,
  ) {
    final sa = source.w;
    final da = pixels[at + 3];
    for (var channel = 0; channel < 3; channel++) {
      final s = source[channel];
      final d = pixels[at + channel];
      pixels[at + channel] = _combine(
        blend.colorOperation,
        s * _factor(blend.sourceColorFactor, s, sa, d, da, alpha: false),
        d * _factor(blend.destinationColorFactor, s, sa, d, da, alpha: false),
      );
    }
    pixels[at + 3] = _combine(
      blend.alphaOperation,
      sa * _factor(blend.sourceAlphaFactor, sa, sa, da, da, alpha: true),
      da * _factor(blend.destinationAlphaFactor, sa, sa, da, da, alpha: true),
    );
  }

  static double _combine(BlendOperation op, double s, double d) => switch (op) {
    BlendOperation.add => s + d,
    BlendOperation.subtract => s - d,
    BlendOperation.reverseSubtract => d - s,
  };

  /// One factor for one channel: [s] and [d] are that channel's source and
  /// destination, [sa] and [da] the two alphas. [alpha] says the channel is
  /// the alpha itself, where the specification pins the saturated factor at
  /// one.
  static double _factor(
    BlendFactor factor,
    double s,
    double sa,
    double d,
    double da, {
    required bool alpha,
  }) => switch (factor) {
    BlendFactor.zero => 0.0,
    BlendFactor.one => 1.0,
    BlendFactor.sourceColor => s,
    BlendFactor.oneMinusSourceColor => 1.0 - s,
    BlendFactor.sourceAlpha => sa,
    BlendFactor.oneMinusSourceAlpha => 1.0 - sa,
    BlendFactor.destinationColor => d,
    BlendFactor.oneMinusDestinationColor => 1.0 - d,
    BlendFactor.destinationAlpha => da,
    BlendFactor.oneMinusDestinationAlpha => 1.0 - da,
    BlendFactor.sourceAlphaSaturated => alpha ? 1.0 : math.min(sa, 1.0 - da),
    BlendFactor.blendColor ||
    BlendFactor.oneMinusBlendColor ||
    BlendFactor.blendAlpha ||
    BlendFactor.oneMinusBlendAlpha => throw UnsupportedError(
      'BlendFactor.${factor.name} reads a blend constant, and the interface '
      'has no way to set one. Answering with a made-up constant would draw a '
      'plausible picture nobody asked for.',
    ),
  };

  bool _depthPasses(double incoming, double stored) => switch (_depthCompare) {
    CompareFunction.never => false,
    CompareFunction.always => true,
    CompareFunction.less => incoming < stored,
    CompareFunction.lessEqual => incoming <= stored,
    CompareFunction.greater => incoming > stored,
    CompareFunction.greaterEqual => incoming >= stored,
    CompareFunction.equal => incoming == stored,
    CompareFunction.notEqual => incoming != stored,
  };
}
