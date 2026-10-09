/// Which way the view's depth runs, and the near and far planes it is drawn
/// between — `RenderSettings.reversedDepth`.
///
/// A `part` of `renderer.dart` for the reason `renderer_shadow_pass.dart`
/// gives: these are the renderer's own helpers over its own fields.
///
/// **One boundary, as `toDepthRange` is one.** A camera builds its matrix in
/// the engine's `[0, 1]` convention and knows nothing of what draws it. The
/// passes that draw into the view's depth — the scene, the transparent
/// layers, the glass — take that matrix reversed and refitted from here, and
/// open their passes through [_turnDepth], which turns every depth test they
/// set. Everything else keeps the camera's own matrix: picking, the post
/// passes that turn a pixel back into a point, the velocity, the shadows.
/// Effects read depth from the surface buffer in metres along the view axis,
/// which neither convention touches; that is why so little has to know.
part of 'renderer.dart';

/// A pass whose depth runs from one at the near plane to nought at the far
/// one, spoken to as though it ran the ordinary way.
///
/// **Every caller keeps writing `less`.** The scene's state, a material's
/// `depthCompare`, the x-ray's `greater` for "behind what is drawn", a
/// contributor that never heard of any of this: each says which depth wins
/// in the ordinary convention, and this turns the comparison round on its
/// way to the device. `less` becomes `greater`, `lessEqual` becomes
/// `greaterEqual`, and the two that do not order — `equal`, `notEqual` —
/// and the two that do not compare — `always`, `never` — pass as they are.
/// A depth bias pulls the other way for the same reason.
///
/// The alternative was a branch at each of the dozen places that name a
/// test, and a plugin's own draws would have been the thirteenth, which
/// nothing here can reach. The stencil test compares stencil values, not
/// depths, and is passed through untouched.
final class _ReversedDepthEncoder extends PassEncoder with CommandEncoder {
  _ReversedDepthEncoder(this._inner);

  final CommandEncoder _inner;

  /// [compare] as the reversed buffer has to be asked it.
  static CompareFunction turned(CompareFunction compare) => switch (compare) {
    CompareFunction.less => CompareFunction.greater,
    CompareFunction.lessEqual => CompareFunction.greaterEqual,
    CompareFunction.greater => CompareFunction.less,
    CompareFunction.greaterEqual => CompareFunction.lessEqual,
    CompareFunction.never ||
    CompareFunction.always ||
    CompareFunction.equal ||
    CompareFunction.notEqual => compare,
  };

  @override
  void setDepthCompare(CompareFunction compare) =>
      _inner.setDepthCompare(turned(compare));

  @override
  void setDepthBias(DepthBias bias) => _inner.setDepthBias(
    bias == DepthBias.none
        ? bias
        : DepthBias(
            constant: -bias.constant,
            slopeScale: -bias.slopeScale,
            clamp: -bias.clamp,
          ),
  );

  @override
  void submit() => _inner.submit();

  @override
  void setViewport(ScreenRect rect) => _inner.setViewport(rect);

  @override
  void setScissor(ScreenRect rect) => _inner.setScissor(rect);

  @override
  void setPrimitiveType(PrimitiveType type) => _inner.setPrimitiveType(type);

  @override
  void setPolygonMode(PolygonMode mode) => _inner.setPolygonMode(mode);

  @override
  void setCullMode(CullMode mode) => _inner.setCullMode(mode);

  @override
  void setWindingOrder(WindingOrder order) => _inner.setWindingOrder(order);

  @override
  void setDepthWrite({required bool enabled}) =>
      _inner.setDepthWrite(enabled: enabled);

  @override
  void setStencil(StencilState front, {StencilState? back}) =>
      _inner.setStencil(front, back: back);

  @override
  void setStencilReference(int value) => _inner.setStencilReference(value);

  @override
  void setBlend(BlendState? state, {int attachment = 0}) =>
      _inner.setBlend(state, attachment: attachment);

  @override
  void setAlphaToCoverage({required bool enabled}) =>
      _inner.setAlphaToCoverage(enabled: enabled);

  @override
  void setBlendColor(vm.Vector4 color) => _inner.setBlendColor(color);

  @override
  void bindPipeline(PipelineHandle pipeline) => _inner.bindPipeline(pipeline);

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) => _inner.bindVertexBuffer(buffer, vertexCount, slot: slot);

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _inner.bindVertexData(bytes, vertexCount, slot: slot);

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) =>
      _inner.bindIndexBuffer(buffer, type, indexCount);

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) =>
      _inner.bindIndexData(bytes, type, indexCount);

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) => _inner.bindUniformBlock(shader, blockName, members);

  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) => _inner.bindTexture(shader, slot, texture, sampler: sampler);

  @override
  void clearBindings() => _inner.clearBindings();

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) =>
      _inner.draw(
        instanceCount: instanceCount,
        firstIndex: firstIndex,
        indexCount: indexCount,
      );

  @override
  void drawIndexed(IndexedDraw draw) => _inner.drawIndexed(draw);

  @override
  void multiDraw(List<IndexedDraw> draws) => _inner.multiDraw(draws);

  @override
  void multiDrawIndirect(
    StorageBuffer arguments,
    int drawCount, {
    int offsetInBytes = 0,
    StorageBuffer? countBuffer,
    int countOffsetInBytes = 0,
  }) => _inner.multiDrawIndirect(
    arguments,
    drawCount,
    offsetInBytes: offsetInBytes,
    countBuffer: countBuffer,
    countOffsetInBytes: countOffsetInBytes,
  );

  /// Passed through as recorded: a bundle's depth test was set when it was
  /// recorded, by whoever recorded it, and a bundle meant for this pass was
  /// recorded for this convention. Nothing in the engine records one here.
  @override
  void executeBundles(List<RenderBundle> bundles) =>
      _inner.executeBundles(bundles);

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) =>
      _inner.beginPipelineStatisticsQuery(querySet, queryIndex);

  @override
  void endPipelineStatisticsQuery() => _inner.endPipelineStatisticsQuery();

  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) =>
      _inner.setColorWriteMask(mask, attachment: attachment);

  @override
  void setDepthClamp({required bool enabled}) =>
      _inner.setDepthClamp(enabled: enabled);

  @override
  bool bindStorageBuffer(
    ShaderHandle shader,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) => _inner.bindStorageBuffer(
    shader,
    name,
    buffer,
    offsetInBytes: offsetInBytes,
    sizeInBytes: sizeInBytes,
  );

  @override
  bool bindStorageTexture(
    ShaderHandle shader,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) => _inner.bindStorageTexture(
    shader,
    name,
    texture,
    mipLevel: mipLevel,
    access: access,
  );

  @override
  bool bindUniformBytes(
    ShaderHandle shader,
    String blockName,
    ByteData bytes,
  ) => _inner.bindUniformBytes(shader, blockName, bytes);

  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) =>
      _inner.drawIndirect(arguments, offsetInBytes: offsetInBytes);

  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) => _inner.drawNonIndexed(
    vertexCount: vertexCount,
    firstVertex: firstVertex,
    instanceCount: instanceCount,
    firstInstance: firstInstance,
  );

  @override
  void beginOcclusionQuery(int queryIndex) =>
      _inner.beginOcclusionQuery(queryIndex);

  @override
  void endOcclusionQuery() => _inner.endOcclusionQuery();
}

/// What stands in for an infinite far plane where a number is needed, in
/// metres.
///
/// **The largest a half float holds**, and that is where the number comes
/// from: the surface buffer keeps each pixel's depth in a half float, so
/// nothing that reads depth back can tell a surface further than this from
/// one at this distance anyway. Used for the light clusters' last slice,
/// the depth pyramid's scale, and the far point of a ray through a pixel —
/// never for drawing, which keeps its infinite plane.
const double _kFarStandIn = 65504.0;

/// The fitted near plane never comes closer to the nearest box than this
/// share of its distance: room for the box's own rounding and for a vertex
/// stage that moves a vertex a little past the bounds it was given.
const double _kNearFitMargin = 0.9;

extension _DepthConvention on Renderer {
  /// Whether [settings] draw the view reversed on this device.
  ///
  /// Not under an orthographic camera alone — that is decided per view, by
  /// [_rasterProjection] — but per frame: one depth buffer serves every
  /// view in the frame, and a buffer cleared one way cannot be tested the
  /// other way by half its views.
  bool _reversedFor(RenderSettings settings) =>
      settings.reversedDepth &&
      device.features.has(DeviceFeature.reversedDepth);

  /// [pass] as the frame's depth convention speaks to it: unchanged, or
  /// turned by [_ReversedDepthEncoder].
  CommandEncoder _turnDepth(CommandEncoder pass, {required bool reversed}) =>
      reversed ? _ReversedDepthEncoder(pass) : pass;

  /// What a depth target is cleared to: the far plane, which is one the
  /// ordinary way round and nought reversed.
  static double _farDepth({required bool reversed}) => reversed ? 0.0 : 1.0;

  /// [projection]'s far plane, or [_kFarStandIn] for an infinite one.
  static double _finiteFar(Projection projection) =>
      projection.far.isFinite ? projection.far : _kFarStandIn;

  /// [camera]'s view-projection with a finite far plane, in the engine's
  /// `[0, 1]` convention — for unprojecting a far point.
  ///
  /// The camera's own matrix wherever its far plane is finite, which is
  /// every camera before 1.0 and every matrix the post passes were given
  /// before; through an infinite one the far point is at infinity, and a
  /// ray built from it is a division by nought. The rays come out the same
  /// whichever finite plane stands in: two points on one ray.
  vm.Matrix4 _finiteViewProjection(CameraNode camera, double aspect) {
    final projection = camera.projection;
    if (projection.far.isFinite) return camera.viewProjection(aspect);
    final finite = withDepthPlanes(
      projection.toMatrix(aspect),
      near: projection.near,
      far: math.max(_kFarStandIn, projection.near * 2.0),
    );
    if (finite == null) return camera.viewProjection(aspect);
    return finite..multiply(camera.viewMatrix);
  }

  /// The volume [viewProjection] sees, for culling — with no far side when
  /// the projection has no far plane.
  ///
  /// `vm.Frustum.matrix` takes the far plane from the matrix's last two
  /// rows, which for an infinite projection is a plane with no normal:
  /// normalised, every number in it is NaN, and a NaN test happens to keep
  /// everything — on this version of `vector_math`. Said here rather than
  /// left to that: a plane that keeps everything, written as one.
  static vm.Frustum _viewFrustum(vm.Matrix4 viewProjection) {
    final frustum = vm.Frustum.matrix(viewProjection);
    for (final plane in <vm.Plane>[
      frustum.plane0,
      frustum.plane1,
      frustum.plane2,
      frustum.plane3,
      frustum.plane4,
      frustum.plane5,
    ]) {
      final n = plane.normal;
      if (n.x.isFinite && n.y.isFinite && n.z.isFinite && n.length2 > 0.0) {
        continue;
      }
      n.setZero();
      plane.constant = 1.0;
    }
    return frustum;
  }

  /// The projection [view]'s draws go through: jittered while a temporal
  /// resolve runs, and with nothing done to its depth — the matrix
  /// [Renderer._drawViewProjection] multiplies the view into.
  vm.Matrix4 _drawProjection(
    CameraNode camera,
    ScreenRect rect,
    RenderSettings settings,
  ) {
    final aspect = rect.width / rect.height;
    final temporal = settings.antiAlias.temporal;
    if (!temporal.enabled || device.limits.maxColorAttachments < 2) {
      return camera.projection.toMatrix(aspect);
    }
    return JitteredProjection.frame(
      camera.projection,
      frame: _frameIndex,
      length: temporal.sequenceLength,
      width: rect.width,
      height: rect.height,
    ).toMatrix(aspect);
  }

  /// The matrix the view's depth is drawn through — `A2.8`, `A2.9`.
  ///
  /// [Renderer._drawViewProjection] with its near plane moved out to
  /// [near] and its depth reversed when [reversed] is: worked out from the
  /// planes for a perspective matrix, which is what [withDepthPlanes] is
  /// for, and by `toReversedDepth`'s subtraction for anything else. An
  /// orthographic camera keeps its planes; its depth is linear already, and
  /// moving its near plane would buy nothing.
  vm.Matrix4 _rasterViewProjection(
    CameraNode camera,
    ScreenRect rect,
    RenderSettings settings, {
    required bool reversed,
    required double near,
  }) {
    final authored = camera.projection;
    // The matrix every earlier release drew with, to the bit, when there is
    // nothing to change: the same products in the same order.
    if (!reversed && near <= authored.near) {
      return _drawViewProjection(camera, rect, settings);
    }
    final projection = _drawProjection(camera, rect, settings);
    // Never as far as the far plane: a contributor's box may lie beyond it,
    // and the camera's far plane is the one thing the fit must not move.
    var fitted = math.max(near, authored.near);
    if (fitted >= authored.far * 0.5) {
      fitted = math.max(authored.near, authored.far * 0.5);
    }
    final planes = withDepthPlanes(
      projection,
      near: fitted,
      far: authored.far,
      reversed: reversed,
    );
    final depth =
        planes ?? (reversed ? toReversedDepth(projection) : projection);
    return toDepthRange(depth, device.depthRange)..multiply(camera.viewMatrix);
  }

  /// How far out [view]'s near plane can go this frame, in metres along its
  /// axis: just in front of the nearest thing drawn, and never nearer than
  /// the camera's own plane — `A2.9`.
  ///
  /// The nearest thing is the nearest corner of every box the render list
  /// holds — the x-ray stage draws from the same list — and every
  /// contributor's own answer ([PassContributor.boundsFor]). A contributor that cannot say keeps the
  /// camera's plane for the view, and so does a view with nothing in it —
  /// there is nothing to fit to — and an orthographic one, whose depth is
  /// linear and gains nothing from it.
  double _fittedNear(RenderView view, List<PassContributor> contributors) {
    final camera = view.camera;
    final projection = camera.projection;
    final authored = projection.near;
    if (projection is OrthographicProjection || isOrthographicLens(camera)) {
      return authored;
    }
    final eye = camera.readViewOrigin();
    final forward = camera.readForward();
    var nearest = double.infinity;

    void include(vm.Vector3 min, vm.Vector3 max) {
      if (min.x > max.x || min.y > max.y || min.z > max.z) return;
      // The box's nearest corner along the axis: its centre's depth less its
      // half-extent projected onto the axis — exact for a box, which a
      // sphere round it would not be.
      final cx = (min.x + max.x) * 0.5 - eye.x;
      final cy = (min.y + max.y) * 0.5 - eye.y;
      final cz = (min.z + max.z) * 0.5 - eye.z;
      final depth =
          cx * forward.x +
          cy * forward.y +
          cz * forward.z -
          ((max.x - min.x) * 0.5 * forward.x.abs() +
              (max.y - min.y) * 0.5 * forward.y.abs() +
              (max.z - min.z) * 0.5 * forward.z.abs());
      if (depth < nearest) nearest = depth;
    }

    for (var i = 0; i < _renderList.length; i++) {
      final node = _renderList.itemAt(i).requireNode;
      // A node that asked not to be culled by its bounds has bounds nobody
      // checked — a sky dome, a mesh moved on the GPU — and cannot be fitted
      // to either.
      if (!node.frustumCulled) return authored;
      final bounds = node.worldBounds;
      include(bounds.min, bounds.max);
      if (nearest <= authored) return authored;
    }
    for (final contributor in contributors) {
      if (!contributor.isActive) continue;
      final bounds = contributor.boundsFor(view);
      if (bounds == null) return authored;
      include(bounds.min, bounds.max);
    }
    if (!nearest.isFinite) return authored;
    return math.max(authored, nearest * _kNearFitMargin);
  }

  /// Whether [camera] sees through an orthographic lens however its
  /// projection is wrapped — a jitter or a crop around an orthographic one.
  static bool isOrthographicLens(CameraNode camera) =>
      isOrthographic(camera.projection.toMatrix(1.0));
}
