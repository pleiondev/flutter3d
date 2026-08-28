/// The two shadow passes, which are the heaviest thing this renderer does.
///
/// **A part of `renderer.dart`, not a file of its own**, and the difference is
/// the point: these are `Renderer`'s methods, reading `Renderer`'s private
/// fields, and pretending otherwise would mean widening a dozen fields to
/// public for the sake of a directory listing. A `part` shares the library, so
/// the privacy that keeps the frame's scratch buffers out of everybody's way
/// survives the move.
///
/// Two hundred and nine lines with a nesting depth of eight, and a hundred and
/// seventy-four with a depth of nine, in a class that was three and a half
/// thousand lines long. They came out first because they are the biggest and
/// the best isolated: everything they touch is either an argument or a field
/// named for shadows.
///
/// **The goldens are the criterion.** Not one frame may change by a byte — if
/// one does, this was a rewrite rather than a move.
part of 'renderer.dart';

/// The pass that draws what the sun cannot see, and the one that draws what a
/// lamp cannot.
extension _ShadowPasses on Renderer {
  /// Draws [slotCount] lights' cube faces into one atlas, in one pass.
  ///
  /// Every row at once, and not one call per light, because a pass clears its
  /// whole colour attachment: viewport and scissor bound where the rasteriser
  /// may write, but the load action does not honour either. A call per light
  /// therefore wiped the rows already drawn and left only the last one — four
  /// lights rendered and one cast a shadow. The lights are read from
  /// [_cubeLightData], which the frame fills before any of the atlas is drawn.
  ///
  /// The colour attachment is a renderer field and stays one — see
  /// [_CubeShadowStaticNode] for why neither atlas can be pooled. The depth
  /// attachment is the opposite case: nothing names it, nothing reads it, and
  /// it goes through [FrameResources.transient] so the release is deferred by
  /// the frame ring. It used to go straight back to the pool after `submit`,
  /// which handed the very same texture to the *other* atlas pass while the
  /// first one's command buffer was still in flight — the two passes have
  /// identical depth specs, so the pool could not have handed back anything
  /// else.
  bool _renderCubeShadow({
    required FrameResources resources,
    required Scene scene,
    required ShadowSettings settings,
    required bool static,
    required int slotCount,
    Set<int>? tiles,
  }) {
    if (!settings.enabled || settings.strength <= 0.0) return false;
    if (slotCount <= 0) return false;

    final shader = shaders['ShadowDistance'];
    if (shader == null) return false;
    final resetShader = shaders['ShadowTileReset'];
    final resetVertexShader = shaders['ShadowTileResetVertex'];
    if (resetShader == null || resetVertexShader == null) return false;

    // Whether this atlas already holds defined pixels. False exactly once per
    // texture, right after it is allocated.
    final cleared = static ? _cubeShadowStaticCleared : _cubeShadowCleared;

    final tile = _cubeShadowTile;
    final width = tile * 6;
    final height = tile * Renderer.kShadowedLights;

    final depth = resources.transient(
      RenderTargetSpec(
        width: width,
        height: height,
        format: device.defaultDepthStencilFormat,
        storageMode: StorageMode.deviceTransient,
      ),
    );

    developer.Timeline.startSync('Renderer.cubeShadow');
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: static ? _cubeShadowStatic! : _cubeShadow!,
            // Loaded, not cleared, and each tile reset by drawing over it.
            //
            // A clear covers the whole attachment however the viewport is set,
            // so a pass that clears can only ever refresh every tile — which is
            // exactly the constraint that has to go before a face can be
            // refreshed on its own schedule. A draw is bounded by the viewport;
            // a clear is not. See shadow_tile_reset.frag.
            //
            // Except once, into a freshly allocated texture, where a clear is
            // still the right tool: `devicePrivate` contents start undefined, and
            // rows nobody owns are never written by anything afterwards. Shading
            // would not care — the slot table never points at an unowned row —
            // but `showShadowMap` composites the raw atlas, so leaving them
            // undefined puts uninitialised memory in the one view used to check
            // this subsystem. That is how it was caught: `cube-shadow` has one
            // occupied row of four and 75% of its pixels changed.
            loadAction: cleared ? LoadAction.load : LoadAction.clear,
            clearValue: vm.Vector4(1.0, 1.0, 1.0, 1.0),
          ),
        ],
        depth: DepthTarget(texture: depth),
      ),
    );

    final casterCull = switch (settings.casterFaces) {
      // Culling the front faces is what leaves the back ones drawn, and the
      // other way about. The enum is named after what ends up *recorded*
      // rather than after what is culled, which is the way round that reads
      // correctly at a call site.
      ShadowCasterFaces.front => CullMode.backFace,
      ShadowCasterFaces.back => CullMode.frontFace,
      ShadowCasterFaces.both => CullMode.none,
    };
    final casterState = Renderer._kShadowCasterState.copyWith(
      cullMode: casterCull,
    );
    pass.setState(casterState);

    final mvp = vm.Matrix4.identity();
    final position = vm.Vector3.zero();
    var drawn = 0;

    // Which skinned casters have had their pose evaluated in this pass. See
    // [_cubeShadowPosed]: the loop below reaches the same node once per face
    // of every light, and the pose it would compute is the same each time.
    _cubeShadowPosed.clear();

    for (var slot = 0; slot < slotCount; slot++) {
      position.setValues(
        _cubeLightData[slot * 4],
        _cubeLightData[slot * 4 + 1],
        _cubeLightData[slot * 4 + 2],
      );
      final range = _cubeLightData[slot * 4 + 3];
      if (range <= 0.0) continue;

      _cubeLight[0] = position.x;
      _cubeLight[1] = position.y;
      _cubeLight[2] = position.z;
      _cubeLight[3] = range;

      // A spot is a cube with five of its faces switched off: one column, aimed
      // where the light aims, opened to the cone rather than to ninety degrees.
      // Sharing the row rather than taking an atlas of its own is what keeps
      // the lit shaders at the two samplers they already bind — a third would
      // have to be declared by every one of them, and a declared sampler that
      // nobody binds is a native crash on Metal rather than a black texture.
      final spotTanHalf = _cubeLightAim[slot * 4 + 3];
      final isSpot = spotTanHalf > 0.0;

      final projection = PerspectiveProjection(
        // `atan(tan(θ)) == θ`, so this is the cone's own opening angle taken
        // the long way round — the tangent is what the shader and the filter
        // want, and it is stored once rather than derived in three places.
        fovYRadians: isSpot ? 2.0 * math.atan(spotTanHalf) : math.pi / 2,
        near: 0.05,
        far: range,
      ).toMatrix(1.0);

      final faceCount = isSpot ? 1 : Renderer._cubeFaces.length;
      for (var face = 0; face < faceCount; face++) {
        // The matrix is recorded for every face, drawn or not: the shading
        // projects through it whatever this frame chose to redraw, and a face
        // left out of the schedule still holds a picture that has to be read
        // with the matrix that made it.
        final vm.Vector3 faceAim;
        final vm.Vector3 faceUp;
        if (isSpot) {
          faceAim = _spotAim
            ..setValues(
              _cubeLightAim[slot * 4],
              _cubeLightAim[slot * 4 + 1],
              _cubeLightAim[slot * 4 + 2],
            );
          // Chosen against the aim rather than fixed at +Y, because `Renderer._lookAt`
          // of a straight-down spot with a +Y up vector is a cross product of
          // two parallel vectors — a zero-length basis, and a matrix of NaN.
          // A downlight is the single most ordinary spot there is, so the
          // degenerate case here is the common one, not the exotic one.
          faceUp = faceAim.y.abs() > 0.99
              ? (_spotUp..setValues(0.0, 0.0, 1.0))
              : (_spotUp..setValues(0.0, 1.0, 0.0));
        } else {
          (faceAim, faceUp) = Renderer._cubeFaces[face];
        }
        final faceView = Renderer._lookAt(position, position + faceAim, faceUp);
        _cubeMatrix
          ..setFrom(projection)
          ..multiply(faceView);
        final at = (slot * 6 + face) * 16;
        _cubeFaceMatrices.setRange(at, at + 16, _cubeMatrix.storage);

        // For drawing, in this backend's clip space. The stored value is a
        // distance rather than a depth, so the convention cannot corrupt it —
        // but the depth *test* between casters in a tile runs in clip space,
        // and the lookup reads the tile through the unremapped matrix above.
        _cubeDrawMatrix.setFrom(toDepthRange(_cubeMatrix, device.depthRange));

        if (tiles != null && !tiles.contains(slot * 6 + face)) continue;

        // A row of six per light: the face across, the light down.
        final tileRect = ScreenRect(
          x: face * tile,
          y: slot * tile,
          width: tile,
          height: tile,
        );
        pass.setViewport(tileRect);
        pass.setScissor(tileRect);

        // Blank this tile before drawing into it, since the pass no longer
        // clears. Depth is still cleared attachment-wide by the pass, so this
        // only has to write colour — and must not touch depth, or it would
        // occlude the casters that follow it.
        pass.setState(Renderer._kShadowTileResetState);
        pass.bindPipeline(
          _cubeShadowResetPipeline ??= device.createPipeline(
            resetVertexShader,
            resetShader,
          ),
        );
        pass.bindVertexBuffer(_fullscreenTriangle, 3);
        pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
        pass.draw();

        pass.setState(casterState);

        for (final node in scene.meshes) {
          if (!node.visibleInHierarchy || !node.castsShadow) continue;
          // One atlas holds the things that never move, the other the things
          // that do. Splitting them is the whole point: the walls are baked
          // once and only a spinning pickup, a monster or a door is redrawn.
          if (node.shadowIsStatic != static) continue;
          final mesh = node.mesh;
          if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;

          // A skinned caster needs the skinned vertex stage here for the same
          // reason it needs one in the main pass and in the cascade pass: the
          // vertex layout is read off the shader's `in` declarations, so joints
          // and weights make this a different shader whatever the body does.
          // Drawing a rigged monster with the static stage would read its
          // joints as a position.
          final skeleton = node.skeleton;
          final skinned = skeleton != null;

          pass.bindPipeline(
            skinned
                ? (_skinnedCubeShadowPipeline ??= device.createPipeline(
                    skinnedVertexShader,
                    shader,
                  ))
                : (_cubeShadowPipeline ??= device.createPipeline(
                    vertexShader,
                    shader,
                  )),
          );
          pass.setWindingOrder(
            node.worldIsMirrored
                ? WindingOrder.clockwise
                : WindingOrder.counterClockwise,
          );
          pass.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
          pass.bindIndexBuffer(mesh.indices, mesh.indexType, mesh.indexCount);

          mvp
            ..setFrom(_cubeDrawMatrix)
            ..multiply(node.worldMatrix);
          pass.bindUniformBlock(
            skinned ? skinnedVertexShader : vertexShader,
            _kFrameInfoBlock,
            {
              'mvp': mvp.storage,
              'model': node.worldMatrix.storage,
              'normal_matrix': node.worldNormalMatrix.storage,
            },
          );
          if (skeleton != null) {
            // What a skinned caster costs here, plainly: the joint array is
            // bound again for every face this node is drawn into, so one
            // character in front of one point light is up to six 4 KB uploads
            // and six passes of the skinning arithmetic over its vertices
            // instead of one — and up to thirty-six across the six rows the
            // atlas holds. The GPU-side skinning is genuinely repeated, because
            // each face is a separate draw and nothing caches a deformed
            // vertex buffer.
            //
            // Three things bound it, none of which is a per-caster budget.
            // [Renderer.kShadowedLights] caps the lights at six. [_computeFaceSignatures]
            // names only the faces whose ninety-degree frustum the caster's
            // bounding sphere might touch, so a character standing off to one
            // side lands in one or two of the six rather than all of them; and
            // [ShadowFaceScheduler] then skips any named face whose signature
            // did not change. That last one does *not* help a character that is
            // actually animating: its pose stamp moves every frame, which is
            // exactly what makes the shadow follow the animation, so an
            // animated caster near a shadowed light pays this every frame.
            //
            // The CPU half is not repeated. `update` allocates a matrix per
            // joint, and running it once per face would be sixty-odd
            // allocations six times over for a pose that cannot change inside
            // one pass.
            if (_cubeShadowPosed.add(node)) {
              skeleton.update(node.worldMatrix);
            }
            pass.bindUniformBlock(skinnedVertexShader, _kSkinInfoBlock, {
              'joint_matrices': skeleton.matrices,
            });
          }
          pass.bindUniformBlock(shader, 'ShadowLight', {'light': _cubeLight});
          pass.draw();
          drawn++;
        }
      }
    }

    pass.submit();
    if (static) {
      _cubeShadowStaticCleared = true;
    } else {
      _cubeShadowCleared = true;
    }
    developer.Timeline.finishSync();
    return drawn > 0;
  }

  /// Draws the directional light's shadow map, and says whether it drew one.
  ///
  /// The frame's own resources are handed in for the depth attachment, which is
  /// scratch: no other pass names it, it must not go back to the pool while the
  /// command buffer that wrote it is in flight, and [FrameResources.transient]
  /// is where that deferral is now automatic rather than remembered at each
  /// call site. The colour target is the opposite case and stays a renderer
  /// field — see [_ShadowMapNode].
  ///
  /// [_shadowParams] and [_shadowCasters] are zeroed by the frame rather than
  /// here, because a pass the graph culled never runs and would otherwise leave
  /// last frame's numbers standing.
  bool _renderShadowMap({
    required FrameResources resources,
    required Scene scene,
    required ShadowSettings settings,
    required int casterIndex,
    CameraNode? camera,
  }) {
    if (!settings.enabled || settings.strength <= 0.0) return false;
    if (casterIndex < 0) return false;

    // Casters only. The last cascade is fitted to this, so anything counted
    // here that cannot cast a shadow spends texels on nothing: a sky dome or a
    // camera-locked backdrop would blow the volume out to its own radius and
    // coarsen every shadow in the level without contributing a single one.
    final bounds = scene.computeBounds(castersOnly: true);
    if (!bounds.min.x.isFinite) return false;

    final sceneCentre = (bounds.min + bounds.max)..scale(0.5);
    final sceneRadius = ((bounds.max - bounds.min)..scale(0.5)).length;
    if (sceneRadius <= 0.0) return false;

    // The light's aim, taken from the packed buffer so the pass sees the same
    // direction the shading does.
    final aim = vm.Vector3(
      lights.directions[casterIndex * 4],
      lights.directions[casterIndex * 4 + 1],
      lights.directions[casterIndex * 4 + 2],
    );
    if (aim.length2 < 1e-12) return false;
    aim.normalize();

    // Any up vector that is not parallel to the aim will do; the choice only
    // rotates the map, and a rotated map shadows identically.
    final up = aim.y.abs() > 0.99
        ? vm.Vector3(0.0, 0.0, 1.0)
        : vm.Vector3(0.0, 1.0, 0.0);
    final padding = math.max(settings.depthPadding, 1.0);
    final resolution = settings.resolution.clamp(
      ShadowSettings.minResolution,
      ShadowSettings.maxResolution,
    );
    final count = settings.cascades.clamp(1, 3);

    // Where each cascade looks, and how much it covers.
    //
    // **The last one is always the whole scene**, which is what makes this safe
    // rather than clever: a fragment the near cascades do not reach falls
    // through to a map that is exactly the one this renderer has always drawn,
    // so nothing is ever left unshadowed by a gap between volumes.
    final centres = <vm.Vector3>[];
    final radii = <double>[];
    final splits = <double>[0.0, 0.0];

    if (count > 1 && camera != null) {
      final eyeAt = camera.readWorldPosition();
      final forward = camera.readForward();
      final near = 1.0;
      final far = math.min(
        math.min(sceneRadius * 2.0, Renderer._cameraFar(camera)),
        math.max(settings.viewDistance, near * 2.0),
      );

      for (var i = 1; i < count; i++) {
        final ratio = i / count;
        // Between an even split and a logarithmic one. Perspective wants the
        // logarithm — a texel covers more world the further away it is — and
        // pure logarithm puts the first split so close that the near cascade
        // covers the player's feet and nothing else.
        final even = near + (far - near) * ratio;
        final logarithmic = near * math.pow(far / near, ratio).toDouble();
        final atEnd = even + (logarithmic - even) * settings.cascadeSplit;
        splits[i - 1] = atEnd;

        // A sphere on the line of sight rather than a fitted frustum: what is
        // outside it is picked up by the next cascade, and the arithmetic that
        // fits a frustum exactly is arithmetic that has to be right about the
        // aspect ratio, which this pass does not know.
        centres.add(eyeAt + forward.scaled(atEnd * 0.55));
        radii.add(atEnd * 0.9);
      }
    }
    centres.add(sceneCentre);
    radii.add(sceneRadius);
    _shadowCascadeRadii
      ..clear()
      ..addAll(radii);

    // One matrix per cascade, plus the copy each backend needs to *draw* with.
    final drawMatrices = <vm.Matrix4>[];
    final shaderMatrices = <vm.Matrix4>[];

    for (var i = 0; i < centres.length; i++) {
      final radius = radii[i];
      var centre = centres[i];

      // Snapped to whole texels, in the light's own space. Without this a
      // camera that moves by half a texel redraws every shadow edge in a
      // slightly different place and the whole level crawls — the single most
      // recognisable artefact cascades have.
      //
      // **The frame has to be fixed, and the first version of this got it
      // wrong.** Building the light view from the centre puts the centre at
      // that view's own origin, so its x and y are zero, snapping zero to a
      // texel gives zero, and the whole thing is an expensive no-op — which is
      // exactly what the mutation test reported when deleting it changed
      // nothing. A rotation about the world origin depends on the light's
      // direction alone, and a point's coordinates in it move when the point
      // does.
      final texelWorld = radius * 2.0 * padding / resolution;
      final snapFrame = Renderer._lookAt(vm.Vector3.zero(), aim, up);
      final inLight = snapFrame.transformed3(centre.clone());
      // All three, not just the two the map is indexed by. Depth along the
      // light axis does not shimmer — the volume has padding to spare — but a
      // centre that slides in z is a centre that slides, and the point of
      // quantising is that the whole thing either stays put or moves by a whole
      // texel. Snapping two of three leaves it sliding along the third, which
      // is what the test caught.
      inLight
        ..x = (inLight.x / texelWorld).floorToDouble() * texelWorld
        ..y = (inLight.y / texelWorld).floorToDouble() * texelWorld
        ..z = (inLight.z / texelWorld).floorToDouble() * texelWorld;
      final back = vm.Matrix4.copy(snapFrame)..invert();
      centre = back.transformed3(inLight);

      if (i == 0) _shadowCascadeCentres.clear();
      _shadowCascadeCentres.add(centre.clone());

      final distance = radius * padding;
      final eye = centre - aim.scaled(distance);
      final view = Renderer._lookAt(eye, centre, up);
      final projection = OrthographicProjection(
        height: radius * 2.0 * padding,
        near: 0.01,
        far: distance + radius * padding,
      ).toMatrix(1.0);

      final matrix = vm.Matrix4.copy(projection)..multiply(view);
      drawMatrices.add(toDepthRange(matrix, device.depthRange));
      shaderMatrices.add(toFramebufferOrigin(matrix, device.framebufferOrigin));
    }

    _shadowMatrix.setFrom(shaderMatrices.first);
    _shadowMatrixFar.setFrom(shaderMatrices[math.min(1, count - 1)]);
    _shadowMatrixFarthest.setFrom(shaderMatrices[count - 1]);
    _shadowDrawMatrix.setFrom(drawMatrices.first);

    // Two matrices per cascade, and they have to differ. The reason is subtle
    // enough to have cost a session. The shadow pass stores `gl_FragCoord.z`,
    // which is window depth: on a backend whose NDC depth is already [0, 1]
    // that is the projected z unchanged, and on one whose NDC is [-1, 1] it is
    // (z + 1) / 2. Draw with an unremapped matrix on the second and every
    // stored depth lands in [0.5, 1] while the lighting shader, computing the
    // expected depth from the unremapped matrix, looks for it in [0, 1].
    // Nothing compares as occluded and the frame comes back fully lit — which
    // reads exactly like a shadow pass that never ran.
    //
    // The shader's copy also carries the framebuffer-origin convention: on a
    // bottom-left backend the map it is about to read is mirrored in memory, so
    // the uv it computes has to be mirrored with it. Measured: that alone takes
    // the directional shadow from a worst cell of 32 to 4.

    // Cascades live side by side in one texture, so the number of samplers the
    // fragment shader binds does not depend on how many there are.
    final atlasWidth = resolution * count;
    if (_shadowMap == null ||
        _shadowResolution != resolution ||
        _shadowCascadeCount != count) {
      // Sampled by the lighting pass, so devicePrivate rather than transient.
      _shadowMap = device.createTexture(
        RenderTargetSpec(
          width: atlasWidth,
          height: resolution,
          format: hdrFormat,
        ),
      );
      _shadowResolution = resolution;
      _shadowCascadeCount = count;
    }

    final depth = resources.transient(
      RenderTargetSpec(
        width: atlasWidth,
        height: resolution,
        format: device.defaultDepthStencilFormat,
        storageMode: StorageMode.deviceTransient,
      ),
    );

    developer.Timeline.startSync('Renderer.shadowPass');
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: _shadowMap!,
            // Cleared to the far plane, so anything the pass does not draw reads
            // as "nothing between here and the light".
            clearValue: vm.Vector4(1.0, 1.0, 1.0, 1.0),
          ),
        ],
        depth: DepthTarget(texture: depth),
      ),
    );

    final full = ScreenRect(width: atlasWidth, height: resolution);
    // The same caster state the cube atlas uses, with one difference: front
    // faces culled, so the depth stored is the *back* of each caster. That
    // moves the comparison surface away from the lit face and removes most of
    // the acne before bias and normal offset have to deal with any.
    pass.setState(
      Renderer._kShadowCasterState.copyWith(
        viewport: full,
        scissor: full,
        cullMode: CullMode.frontFace,
      ),
    );

    final shadowShader = shaders['ShadowDepth'];
    if (shadowShader == null) {
      developer.Timeline.finishSync();
      return false;
    }
    // Two pipelines, for the same reason the main pass has two: a skinned mesh
    // has a different vertex layout, so it needs the skinned stage here too.
    // Drawing it with the static one would read joints and weights as position
    // and normal — and skipping skinned casters instead would mean a character
    // that walks around without a shadow.
    bool? boundSkinned;

    _shadowCasters = 0;
    final meshes = scene.meshes;
    final mvp = vm.Matrix4.identity();

    for (var cascade = 0; cascade < count; cascade++) {
      // Each cascade is the same casters drawn again into its own strip of the
      // atlas. A viewport rather than a second pass: the clear has already
      // happened, and the pipelines and buffers are the same.
      if (count > 1) {
        final tile = ScreenRect(
          x: cascade * resolution,
          width: resolution,
          height: resolution,
        );
        pass.setState(
          Renderer._kShadowCasterState.copyWith(
            viewport: tile,
            scissor: tile,
            cullMode: CullMode.frontFace,
          ),
        );
        boundSkinned = null;
      }
      final drawMatrix = drawMatrices[cascade];

      for (var i = 0; i < meshes.length; i++) {
        final node = meshes[i];
        if (!node.visibleInHierarchy) continue;
        if (!node.castsShadow) continue;
        final mesh = node.mesh;
        if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;

        final skeleton = node.skeleton;
        final skinned = skeleton != null;
        if (boundSkinned != skinned) {
          pass.bindPipeline(
            skinned
                ? (_skinnedShadowPipeline ??= device.createPipeline(
                    skinnedVertexShader,
                    shadowShader,
                  ))
                : (_shadowPipeline ??= device.createPipeline(
                    vertexShader,
                    shadowShader,
                  )),
          );
          boundSkinned = skinned;
        }

        pass.setWindingOrder(
          node.worldIsMirrored
              ? WindingOrder.clockwise
              : WindingOrder.counterClockwise,
        );
        pass.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
        pass.bindIndexBuffer(mesh.indices, mesh.indexType, mesh.indexCount);

        mvp
          ..setFrom(drawMatrix)
          ..multiply(node.worldMatrix);
        final stage = skinned ? skinnedVertexShader : vertexShader;
        pass.bindUniformBlock(stage, _kFrameInfoBlock, {
          'mvp': mvp.storage,
          'model': node.worldMatrix.storage,
          'normal_matrix': node.worldNormalMatrix.storage,
        });
        if (skeleton != null) {
          skeleton.update(node.worldMatrix);
          pass.bindUniformBlock(skinnedVertexShader, _kSkinInfoBlock, {
            'joint_matrices': skeleton.matrices,
          });
        }
        pass.draw();
        // Counted once, not once per cascade: the number answers "how many things
        // cast", and a caster drawn into three tiles is still one caster. The
        // draw call count is the graph's business.
        if (cascade == 0) _shadowCasters++;
      }
    }

    pass.submit();
    developer.Timeline.finishSync();

    // Horizontally the texel is a texel of the *atlas*, vertically it is a
    // texel of a tile. With one cascade they are the same number, which is what
    // keeps that path byte-identical to the one this renderer has always had.
    _shadowParams[0] = 1.0 / atlasWidth;
    _shadowCascades[0] = splits[0];
    _shadowCascades[1] = splits[1];
    _shadowCascades[2] = count.toDouble();
    _shadowCascades[3] = 1.0 / resolution;
    _shadowParams[1] = settings.bias;
    _shadowParams[2] = settings.normalOffset;
    _shadowParams[3] = settings.strength.clamp(0.0, 1.0);
    return true;
  }
}
