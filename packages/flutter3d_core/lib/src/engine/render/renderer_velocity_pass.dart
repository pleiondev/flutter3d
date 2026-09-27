/// The object velocity pass: every node that moved since the last frame,
/// drawn again over the camera's velocity with how far it moved — `R1`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why these
/// are extensions on `Renderer` rather than files of their own.
///
/// **Only what moved.** The camera velocity already answers for everything
/// that stood still in the world, which in most frames is nearly everything;
/// a node whose world matrix, pose, morph and instances are all where the
/// frame history left them is not drawn here at all. A scene where nothing
/// moves costs this pass one walk of its render list.
///
/// **Opaque only.** A blended surface wrote no depth into the surface
/// buffer, so the pixel it covers shows the motion of what is behind it, and
/// that is the motion the resolve should follow.
part of 'renderer.dart';

/// Slot 0 as the velocity stages read it: the position alone, stepped over
/// the standard sixty-four-byte vertex.
final VertexLayoutSpec _kVelocityLayout = VertexLayoutSpec(<BufferLayout>[
  BufferLayout(
    strideInBytes: VertexLayout.standard.strideInBytes,
    attributes: const <InputAttribute>[
      InputAttribute(name: 'position', format: VertexFormat.float32x3),
    ],
  ),
]);

/// The skinned vertex: position, joints and weights, over its own stride.
final VertexLayoutSpec _kVelocitySkinnedLayout = VertexLayoutSpec(
  <BufferLayout>[
    BufferLayout(
      strideInBytes: VertexLayout.skinned.strideInBytes,
      attributes: <InputAttribute>[
        for (final name in <String>['position', 'joints', 'weights'])
          InputAttribute(
            name: name,
            format: name == 'position'
                ? VertexFormat.float32x3
                : VertexFormat.float32x4,
            offsetInBytes: VertexLayout.skinned.floatOffsetOf(name) * 4,
          ),
      ],
    ),
  ],
);

/// The batch: the position per vertex, then the rows of the placement now
/// (slot 1) and last frame (slot 2), both laid out as `InstancedMeshNode`
/// holds them.
final VertexLayoutSpec _kVelocityInstancedLayout = VertexLayoutSpec(
  <BufferLayout>[
    _kVelocityLayout.buffers.single,
    for (final prefix in <String>['i_', 'i_prev_'])
      BufferLayout(
        strideInBytes: InstancedMeshNode.strideInBytes,
        stepMode: VertexStepMode.instance,
        attributes: <InputAttribute>[
          for (var row = 0; row < 3; row++)
            InputAttribute(
              name: '${prefix}row$row',
              format: VertexFormat.float32x4,
              offsetInBytes: row * 16,
            ),
        ],
      ),
  ],
);

extension _VelocityPass on Renderer {
  /// The pipeline that draws through the velocity vertex stage the node
  /// needs and [fragment] — `Velocity`, or `R4`'s `Reactive`, which [name]
  /// says for the cache.
  PipelineHandle _velocityPipelineFor({
    required bool skinned,
    required bool instanced,
    required ShaderHandle fragment,
    required String name,
  }) {
    final key = instanced
        ? 'instanced/$name'
        : skinned
        ? 'skinned/$name'
        : name;
    return _pipelineCache.putIfAbsent(
      key,
      () => device.createPipeline(
        instanced
            ? velocityInstancedVertexShader
            : skinned
            ? velocitySkinnedVertexShader
            : velocityVertexShader,
        fragment,
        layout: instanced
            ? _kVelocityInstancedLayout
            : skinned
            ? _kVelocitySkinnedLayout
            : _kVelocityLayout,
      ),
    );
  }

  /// Writes where the eye is and which way it looks into the block the
  /// velocity vertex stages measure depth with, for [camera].
  void _velocityCamera(CameraNode camera) {
    final eye = vm.Vector3.zero();
    final forward = vm.Vector3.zero();
    camera
      ..readWorldPosition(eye)
      ..readForward(forward);
    _prevFrameInfo.camera
      ..[0] = eye.x
      ..[1] = eye.y
      ..[2] = eye.z;
    _prevFrameInfo.forward
      ..[0] = forward.x
      ..[1] = forward.y
      ..[2] = forward.z;
  }

  /// Binds everything the velocity vertex stages read for [node] and its
  /// geometry, through a pipeline ending in [fragment], and returns the
  /// vertex stage — or null when there is nothing of the node to draw.
  ///
  /// [past] is what the frame history kept of the node; null takes last
  /// frame's placement, pose and weights to be this frame's, which is what a
  /// caller that reads no motion — `R4`'s reactive mask — wants.
  ShaderHandle? _bindVelocityNode({
    required PassEncoder pass,
    required MeshNode node,
    required NodeHistory? past,
    required vm.Matrix4 jittered,
    required vm.Matrix4 current,
    required vm.Matrix4 previous,
    required ShaderHandle fragment,
    required String name,
    required RenderSettings settings,
  }) {
    final mesh = node.mesh as DrawableGeometry;
    if (mesh.indexCount == 0) return null;
    final instanced = node is InstancedMeshNode ? node : null;
    if (instanced != null && instanced.count == 0) return null;
    final skeleton = node.skeleton;
    final stage = instanced != null
        ? velocityInstancedVertexShader
        : skeleton != null
        ? velocitySkinnedVertexShader
        : velocityVertexShader;

    pass.bindPipeline(
      _velocityPipelineFor(
        skinned: skeleton != null,
        instanced: instanced != null,
        fragment: fragment,
        name: name,
      ),
    );
    pass
      ..setWindingOrder(
        node.worldIsMirrored
            ? WindingOrder.clockwise
            : WindingOrder.counterClockwise,
      )
      ..setCullMode(
        settings.backfaceCulling && !node.material.doubleSided
            ? CullMode.backFace
            : CullMode.none,
      )
      ..bindVertexBuffer(mesh.vertices, mesh.vertexCount)
      ..bindIndexBuffer(mesh.indices, mesh.indexType, mesh.indexCount);

    if (instanced != null) {
      final before = past?.instances;
      final bytes = instanced.instanceBytes;
      pass
        ..bindVertexData(bytes, instanced.count, slot: 1)
        ..bindVertexData(
          // A batch whose count changed has no instance-for-instance past;
          // its placements are taken as unmoved and the node's own motion
          // is what shows.
          before != null && past!.instanceCount == instanced.count
              ? ByteData.sublistView(before)
              : bytes,
          instanced.count,
          slot: 2,
        );
    }

    final model = node.worldMatrix;
    final mvp = vm.Matrix4.copy(jittered)..multiply(model);
    _frameInfo.mvp.setAll(0, mvp.storage);
    _frameInfo.model.setAll(0, model.storage);
    _frameInfo.normalMatrix.setAll(0, node.worldNormalMatrix.storage);
    pass.bindBlock(stage, _frameInfo);

    mvp
      ..setFrom(current)
      ..multiply(model);
    _prevFrameInfo.currentMvp.setAll(0, mvp.storage);
    mvp
      ..setFrom(previous)
      ..multiply(past?.world ?? model);
    _prevFrameInfo.previousMvp.setAll(0, mvp.storage);
    final weights = past == null ? node.morph?.weights : past.morphWeights;
    for (var i = 0; i < _prevFrameInfo.previousMorphWeights.length; i++) {
      _prevFrameInfo.previousMorphWeights[i] =
          weights != null && i < weights.length ? weights[i] : 0.0;
    }
    pass.bindBlock(stage, _prevFrameInfo);
    _bindMorph(pass, stage, node.morph);

    if (skeleton != null) {
      skeleton.update(model);
      _skinInfo.jointMatrices.setAll(0, skeleton.matrices);
      pass.bindBlock(stage, _skinInfo);
      // Last frame's palette as a texture of columns, one joint a row —
      // see `velocity_skinned.vert`. Made for this draw and released after
      // the frame; a skinned node that moves every frame pays one small
      // upload a frame, as a batch with per-instance weights already does.
      final palette = past?.joints ?? skeleton.matrices;
      final texture = device.createTextureFromPixels(
        width: 4,
        height: palette.length ~/ 16,
        format: TextureFormat.r32g32b32a32Float,
        pixels: ByteData.sublistView(palette),
      );
      if (texture != null) _destroyAfterFrame(texture);
      pass.bindTexture(
        stage,
        'prev_joint_texture',
        texture ?? fallbackAlbedo,
        sampler: SamplerOptions.nearestClamp,
      );
    }
    return stage;
  }

  /// Draws every opaque node [frameHistory] says moved into [target], which
  /// holds the camera's velocity already.
  ///
  /// Returns how many nodes were drawn.
  int _encodeObjectVelocity({
    required TextureHandle target,
    required TextureHandle surface,
    required Scene scene,
    required RenderView view,
    required RenderSettings settings,
    required int width,
    required int height,
  }) {
    final rect = Renderer._viewportPixels(view.viewportFraction, width, height);
    final camera = view.camera;
    final aspect = rect.width / rect.height;
    final unjittered = camera.viewProjection(aspect);
    _renderList.build(
      scene,
      view,
      viewMatrix: camera.viewMatrix,
      frustum: vm.Frustum.matrix(unjittered),
    );
    final moved = <MeshNode>[
      for (final index in _renderList.opaque)
        if (_renderList.itemAt(index).requireNode case final node
            when frameHistory.moved(node) &&
                frameHistory.of(node) != null &&
                node.mesh is DrawableGeometry)
          node,
    ];
    if (moved.isEmpty) return 0;

    developer.Timeline.startSync('Renderer.objectVelocity');
    final origin = device.framebufferOrigin;
    final current = toFramebufferOrigin(unjittered, origin);
    final previous = toFramebufferOrigin(
      frameHistory.viewProjection(camera) ?? unjittered,
      origin,
    );
    final jittered = _drawViewProjection(camera, rect, settings);

    _velocityCamera(camera);
    _velocityInfo.target
      ..[0] = 1.0 / target.width
      ..[1] = 1.0 / target.height
      // **Nought on every backend, not `_rowsFromBottom`.** The stage uses
      // `FragCoordFromTop` to find the surface-buffer texel under the
      // fragment, and that texel is `gl_FragCoord` itself wherever row zero
      // is: the surface buffer was drawn by the same backend into the same
      // rows, so on WebGL2 its row zero is the bottom of the picture just as
      // the fragment's is. Counting from the top there read the mirrored row,
      // where the sky or a nearer surface dropped almost every moved
      // fragment, and the velocity buffer came out all but empty. The flip
      // is for patterns that must match across backends, not for reading a
      // texture back where it was drawn.
      ..[2] = 0.0
      // A hundredth of the distance: the surface buffer stores the depth of
      // the same triangle this draws, so the two agree to rounding, and a
      // hundredth is far below the gap between a surface and anything in
      // front of it.
      ..[3] = 0.01;

    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          ColorTarget(texture: target, loadAction: LoadAction.load),
        ],
      ),
    );
    pass.setState(
      Renderer._kSceneViewState.copyWith(
        viewport: rect,
        scissor: rect,
        polygonMode: PolygonMode.fill,
        blend: null,
        depthWrite: false,
        depthCompare: CompareFunction.always,
      ),
    );

    for (final node in moved) {
      final stage = _bindVelocityNode(
        pass: pass,
        node: node,
        past: frameHistory.of(node),
        jittered: jittered,
        current: current,
        previous: previous,
        fragment: velocityShader,
        name: 'Velocity',
        settings: settings,
      );
      if (stage == null) continue;
      pass
        ..bindBlock(velocityShader, _velocityInfo)
        ..bindTexture(
          velocityShader,
          'surface_texture',
          surface,
          sampler: SamplerOptions.nearestClamp,
        )
        ..draw(instanceCount: node is InstancedMeshNode ? node.count : 1);
    }
    pass.submit();
    developer.Timeline.finishSync();
    return moved.length;
  }

  /// Marks, in [target]'s blue, how much of each pixel a blended surface or
  /// a contributor's particles and splats cover — `R4`. [target] holds the
  /// velocity already, and adding nought to its other three channels leaves
  /// them as they were.
  ///
  /// Blended meshes are drawn through the velocity vertex stages, so they
  /// land where the scene drew them however they are skinned, morphed or
  /// batched; each [contributors] entry draws its own through
  /// [PassContributor.encodeReactive].
  ///
  /// Returns how many meshes were marked.
  int _encodeReactive({
    required TextureHandle target,
    required TextureHandle surface,
    required Scene scene,
    required RenderView view,
    required RenderSettings settings,
    required List<PassContributor> contributors,
    required int width,
    required int height,
  }) {
    final rect = Renderer._viewportPixels(view.viewportFraction, width, height);
    final camera = view.camera;
    final aspect = rect.width / rect.height;
    final unjittered = camera.viewProjection(aspect);
    _renderList.build(
      scene,
      view,
      viewMatrix: camera.viewMatrix,
      frustum: vm.Frustum.matrix(unjittered),
    );
    final blended = <MeshNode>[
      for (final index in _renderList.transparent)
        if (_renderList.itemAt(index).requireNode case final node
            when node.mesh is DrawableGeometry &&
                node.material.baseColor.w > 0.0)
          node,
    ];
    if (blended.isEmpty && contributors.isEmpty) return 0;

    developer.Timeline.startSync('Renderer.reactive');
    final current = toFramebufferOrigin(unjittered, device.framebufferOrigin);
    final jittered = _drawViewProjection(camera, rect, settings);

    _velocityCamera(camera);
    _reactiveInfo.eye.setAll(0, _prevFrameInfo.camera);
    _reactiveInfo.forward.setAll(0, _prevFrameInfo.forward);
    _reactiveInfo.target
      ..[0] = 1.0 / target.width
      ..[1] = 1.0 / target.height
      // Nought for the reason the velocity pass gives: the surface-buffer
      // texel under a fragment is `gl_FragCoord` on every backend.
      ..[2] = 0.0
      // The velocity pass's hundredth, for the same reason: a surface drawn
      // over itself agrees with the buffer to rounding.
      ..[3] = 0.01;
    _reactiveInfo.params
      ..[0] = settings.antiAlias.temporal.reactive.clamp(0.0, 1.0)
      ..[1] = 0.0
      ..[2] = 0.0;

    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          ColorTarget(texture: target, loadAction: LoadAction.load),
        ],
      ),
    );
    pass.setState(
      Renderer._kSceneViewState.copyWith(
        viewport: rect,
        scissor: rect,
        polygonMode: PolygonMode.fill,
        blend: ReactiveFrame.state.blend,
        depthWrite: false,
        depthCompare: CompareFunction.always,
      ),
    );

    for (final node in blended) {
      final stage = _bindVelocityNode(
        pass: pass,
        node: node,
        past: null,
        jittered: jittered,
        current: current,
        previous: current,
        fragment: reactiveShader,
        name: 'Reactive',
        settings: settings,
      );
      if (stage == null) continue;
      // The material's alpha is how much of the pixel it covers: glass at a
      // fifth is a fifth reactive.
      _reactiveInfo.params[2] = node.material.baseColor.w.clamp(0.0, 1.0);
      pass
        ..bindBlock(reactiveShader, _reactiveInfo)
        ..bindTexture(
          reactiveShader,
          'surface_texture',
          surface,
          sampler: SamplerOptions.nearestClamp,
        )
        ..draw(instanceCount: node is InstancedMeshNode ? node.count : 1);
    }

    if (contributors.isNotEmpty) {
      final frame = ReactiveFrame(
        encoder: pass,
        device: device,
        view: view,
        viewProjection: jittered,
        surface: surface,
        white: fallbackAlbedo,
        info: _reactiveInfo,
      );
      for (final contributor in contributors) {
        contributor.encodeReactive(frame);
      }
    }
    pass.submit();
    developer.Timeline.finishSync();
    return blended.length;
  }
}
