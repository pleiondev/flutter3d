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

/// Which faces a shadow pass culls to record the side [faces] names.
///
/// Culling the front faces is what leaves the back ones drawn, and the other
/// way about. The enum is named after what ends up *recorded* rather than after
/// what is culled, which is the way round that reads correctly at a call site.
///
/// **Shared because it was not, and one of the two passes had a constant in its
/// place.** The cube atlas read the setting from the day it existed; the
/// directional pass wrote `CullMode.frontFace` in three places with a comment
/// explaining why the back of a caster is the right thing to record — which is
/// what `ShadowCasterFaces.back` means, and is the default, so the setting
/// looked like it worked and its other two values did nothing at all. What that
/// costs is not a subtlety: a single-sided caster — a wall, a fence panel, a
/// billboard — has no back face, so under a hardcoded `frontFace` the sun goes
/// straight through it, and `front` and `both`, the two answers to exactly that,
/// were unreachable.
CullMode _casterCull(ShadowCasterFaces faces) => switch (faces) {
  ShadowCasterFaces.front => CullMode.backFace,
  ShadowCasterFaces.back => CullMode.frontFace,
  ShadowCasterFaces.both => CullMode.none,
};

/// The pass that draws what the sun cannot see, and the one that draws what a
/// lamp cannot.
extension _ShadowPasses on Renderer {
  /// Whether [node] casts through the cut-out shadow stages — `gfx-60n`.
  ///
  /// glTF's MASK mode and nothing else. A blended material is a different
  /// question that a shadow map cannot answer, since it holds one depth per
  /// texel and a half-transparent caster has no single depth to record; an
  /// opaque one has nothing to cut out. So this is exactly the mode whose own
  /// definition is a threshold.
  bool _castsMasked(MeshNode node) {
    final material = node.material;
    return material.alphaMode == MaterialAlphaMode.mask &&
        material.albedo != null;
  }

  /// Binds what a cut-out shadow stage reads: the map and the two numbers.
  ///
  /// The base colour's own alpha rides beside the cutoff because glTF
  /// multiplies the two, so a material faded to nothing casts nothing rather
  /// than casting its texture.
  void _bindShadowMask(
    PassEncoder pass,
    ShaderHandle stage,
    Material material,
  ) {
    final texture = material.albedo;
    if (texture == null) return;
    pass.bindTexture(stage, _kAlbedoTextureSlot, texture);
    _shadowMask[0] = material.alphaCutoff;
    _shadowMask[1] = material.baseColor.w;
    pass.bindUniformBlock(stage, _kShadowMaskBlock, <String, Float32List>{
      'mask': _shadowMask,
    });
  }

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
  /// [_CubeShadowStaticNode] for why neither atlas can be pooled. So is the
  /// depth attachment, [_cubeShadowDepth], allocated beside the atlases by
  /// [_ensureCubeAtlas] and kept for as long as they are: a pooled depth is a
  /// different texture every frame, which a backend that caches framebuffers
  /// pairs with the wrong attachment — see [_shadowDepth]. Before that it went
  /// through the pool, and earlier still straight back to it after `submit`,
  /// which handed the very same texture to the *other* atlas pass while the
  /// first one's command buffer was still in flight.
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
    // `gfx-60n`, and the same fallback the cascade pass takes: a bundle
    // without the cut-out stage draws the shadow it used to.
    final maskedShader = shaders['ShadowDistanceMasked'] ?? shader;
    final resetShader = shaders['ShadowTileReset'];
    final resetVertexShader = shaders['ShadowTileResetVertex'];
    if (resetShader == null || resetVertexShader == null) return false;

    // Whether this atlas already holds defined pixels. False exactly once per
    // texture, right after it is allocated.
    final cleared = static ? _cubeShadowStaticCleared : _cubeShadowCleared;

    final tile = _cubeShadowTile;

    // The atlas's own depth rather than one from the pool: see [_shadowDepth]
    // for what a changing depth attachment does to a cached framebuffer.
    final depth = _cubeShadowDepth!;

    developer.Timeline.startSync('Renderer.cubeShadow');
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
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

    final casterCull = _casterCull(settings.casterFaces);
    final casterState = Renderer._kShadowCasterState.copyWith(
      cullMode: casterCull,
    );
    pass.setState(casterState);

    final mvp = vm.Matrix4.identity();
    final position = vm.Vector3.zero();
    var drawn = 0;

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

      for (var face = 0; face < Renderer._cubeFaces.length; face++) {
        // A spot casts into one column. The five beside it still hold what the
        // row's previous owner drew there, and `_computeFaceSignatures` gives
        // them a blank signature so the schedule names them once — which only
        // means something if this loop visits them. It used to stop after the
        // first column, the scheduler recorded the other five as drawn, and
        // the stale picture stayed for as long as the spot held the row.
        final casts = !isSpot || face == 0;
        if (casts) {
          // The matrix is recorded for every face, drawn or not: the shading
          // projects through it whatever this frame chose to redraw, and a
          // face left out of the schedule still holds a picture that has to
          // be read with the matrix that made it.
          final vm.Vector3 faceAim;
          final vm.Vector3 faceUp;
          if (isSpot) {
            faceAim = _spotAim
              ..setValues(
                _cubeLightAim[slot * 4],
                _cubeLightAim[slot * 4 + 1],
                _cubeLightAim[slot * 4 + 2],
              );
            // Chosen against the aim rather than fixed at +Y, because
            // `Renderer._lookAt` of a straight-down spot with a +Y up vector
            // is a cross product of two parallel vectors — a zero-length
            // basis, and a matrix of NaN. A downlight is the single most
            // ordinary spot there is, so the degenerate case here is the
            // common one, not the exotic one.
            faceUp = faceAim.y.abs() > 0.99
                ? (_spotUp..setValues(0.0, 0.0, 1.0))
                : (_spotUp..setValues(0.0, 1.0, 0.0));
          } else {
            (faceAim, faceUp) = Renderer._cubeFaces[face];
          }
          final faceView = Renderer._lookAt(
            position,
            position + faceAim,
            faceUp,
          );
          _cubeMatrix
            ..setFrom(projection)
            ..multiply(faceView);
          final at = (slot * 6 + face) * 16;
          _cubeFaceMatrices.setRange(at, at + 16, _cubeMatrix.storage);

          // For drawing, in this backend's clip space. The stored value is a
          // distance rather than a depth, so the convention cannot corrupt it
          // — but the depth *test* between casters in a tile runs in clip
          // space, and the lookup reads the tile through the unremapped
          // matrix above.
          _cubeDrawMatrix.setFrom(toDepthRange(_cubeMatrix, device.depthRange));
        }

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
        _frameCounters?.drawCalls++;
        // A spot's idle column: blanked, and nothing casts into it.
        if (!casts) continue;

        pass.setState(casterState);
        // Which cull the pass is currently in. A node that casts from every
        // face switches it and the next ordinary node switches it back, so a
        // scene with none of them pays nothing and a scene with a few pays one
        // state change per run of them rather than one per draw.
        var everyFace = casterCull == CullMode.none;

        // What this face can see — `gfx-63n`. A cube face is a ninety-degree
        // frustum reaching as far as the light's range, so it holds a small
        // part of any real level, and the loop below was walking all of it six
        // times per light. Built from the unremapped matrix and reused for
        // every mesh on the face.
        _faceFrustum.setFromMatrix(_cubeMatrix);

        for (final node in scene.meshes) {
          if (!node.visibleInHierarchy || !node.shadowCasting.casts) continue;
          if (node.frustumCulled &&
              !_faceFrustum.intersectsWithAabb3(node.worldBounds)) {
            continue;
          }
          // One atlas holds the things that never move, the other the things
          // that do. Splitting them is the whole point: the walls are baked
          // once and only a spinning pickup, a monster or a door is redrawn.
          if (node.shadowIsStatic != static) continue;
          final mesh = node.mesh;
          if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;
          final instanced = node is InstancedMeshNode ? node : null;
          if (instanced != null && instanced.count == 0) continue;

          // A skinned caster needs the skinned vertex stage here for the same
          // reason it needs one in the main pass and in the cascade pass: the
          // vertex layout is read off the shader's `in` declarations, so joints
          // and weights make this a different shader whatever the body does.
          // Drawing a rigged monster with the static stage would read its
          // joints as a position.
          final skeleton = node.skeleton;
          final skinned = skeleton != null;

          // A single-sided wall recorded from one side only leaks light along
          // its seam, so a node that asks records both — and so does one whose
          // material is double-sided, which has no back to cull.
          final wantsEveryFace =
              node.castsShadowFromEveryFace || casterCull == CullMode.none;
          if (wantsEveryFace != everyFace) {
            pass.setState(
              wantsEveryFace
                  ? casterState.copyWith(cullMode: CullMode.none)
                  : casterState,
            );
            everyFace = wantsEveryFace;
          }

          // `gfx-60n`. A cut-out caster draws through a stage with a sampler
          // in it, and a point light is where the omission showed worst: a
          // cube face is a ninety-degree frustum with the caster close to it,
          // so a foliage quad's slab fills far more of the tile than it would
          // in a cascade.
          final masked = maskedShader != shader && _castsMasked(node);
          final fragment = masked ? maskedShader : shader;
          pass.bindPipeline(
            instanced != null
                ? masked
                      ? (_instancedMaskedCubeShadowPipeline ??= device
                            .createPipeline(
                              instancedVertexShader,
                              fragment,
                              layout: _kInstancedLayout,
                            ))
                      : (_instancedCubeShadowPipeline ??= device.createPipeline(
                          instancedVertexShader,
                          fragment,
                          layout: _kInstancedLayout,
                        ))
                : skinned
                ? masked
                      ? (_skinnedMaskedCubeShadowPipeline ??= device
                            .createPipeline(skinnedVertexShader, fragment))
                      : (_skinnedCubeShadowPipeline ??= device.createPipeline(
                          skinnedVertexShader,
                          fragment,
                        ))
                : masked
                ? (_maskedCubeShadowPipeline ??= device.createPipeline(
                    vertexShader,
                    fragment,
                  ))
                : (_cubeShadowPipeline ??= device.createPipeline(
                    vertexShader,
                    fragment,
                  )),
          );
          if (masked) _bindShadowMask(pass, maskedShader, node.material);
          final stage = instanced != null
              ? instancedVertexShader
              : skinned
              ? skinnedVertexShader
              : vertexShader;
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
          pass.bindUniformBlock(stage, _kFrameInfoBlock, {
            'mvp': mvp.storage,
            'model': node.worldMatrix.storage,
            'normal_matrix': node.worldNormalMatrix.storage,
          });
          _bindMorph(pass, stage, node.morph);
          if (instanced != null) {
            _bindInstanceMorph(pass, stage, instanced);
          }
          if (instanced != null) {
            pass.bindVertexData(
              instanced.instanceBytes,
              instanced.count,
              slot: 1,
            );
          }
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
            // The CPU half is not repeated, and since `gfx-64n` the skeleton
            // is what refuses rather than a set kept here: `update` returns at
            // once when the pose and the mesh transform are the ones it last
            // computed for, which is the same refusal extended to the cascade
            // pass, the pick pass and mesh encoding, all of which reached this
            // same call once per primitive and none of which had a guard.
            skeleton.update(node.worldMatrix);
            pass.bindUniformBlock(skinnedVertexShader, _kSkinInfoBlock, {
              'joint_matrices': skeleton.matrices,
            });
          }
          // Through the stage the pipeline was built with. A cut-out caster's
          // fragment stage is `ShadowDistanceMasked`, which declares its own
          // `ShadowLight`; binding it through the plain stage's handle landed
          // in the right slot only because both happen to declare it first.
          pass.bindUniformBlock(fragment, 'ShadowLight', {'light': _cubeLight});
          pass.draw(instanceCount: instanced?.count ?? 1);
          _frameCounters?.drawCalls++;
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

  /// Everything that decides a texel of the directional atlas — `gfx-68n`.
  ///
  /// A record rather than a hash, so two frames that differ are never equal by
  /// accident; the matrices are the one part reduced to a number, because the
  /// alternative is holding copies of up to four of them and comparing
  /// sixty-four doubles.
  ({int matrices, int epoch, int generation, int faces, int casters})
  _directionalBakeKey(
    Scene scene,
    ShadowSettings settings,
    List<vm.Matrix4> shaderMatrices,
  ) {
    var matrices = shaderMatrices.length;
    for (final matrix in shaderMatrices) {
      for (final value in matrix.storage) {
        matrices = 0x1fffffff & (matrices * 31 + value.hashCode);
      }
    }

    // Masked casters read a cutoff and an alpha off their material, and neither
    // a material's fields nor the texture it points at reach `changeEpoch` or
    // the static generation — a material is not a node. This is that gap
    // closed, and it costs one pass over the casters against the two or three
    // passes of drawing them it is deciding about.
    var casters = 0;
    for (final node in scene.meshes) {
      if (!node.shadowCasting.casts) continue;
      final material = node.material;
      casters = 0x1fffffff & (casters * 31 + identityHashCode(material));
      casters = 0x1fffffff & (casters * 31 + material.alphaMode.hashCode);
      casters = 0x1fffffff & (casters * 31 + material.alphaCutoff.hashCode);
      casters = 0x1fffffff & (casters * 31 + material.baseColor.w.hashCode);
      casters = 0x1fffffff & (casters * 31 + identityHashCode(material.albedo));
      // Which faces it records. Neither a material's `doubleSided` nor a
      // dynamic node's casting mode reaches `changeEpoch`, and either one
      // changes what the cascade holds.
      casters =
          0x1fffffff & (casters * 31 + (node.castsShadowFromEveryFace ? 1 : 0));
      // Nor does a swapped mesh, a morph's weights, or an instance moved
      // inside a batch — each changes the silhouette in place.
      casters = 0x1fffffff & (casters * 31 + identityHashCode(node.mesh));
      casters = 0x1fffffff & (casters * 31 + (node.morph?.version ?? 0));
      if (node is InstancedMeshNode) {
        casters = 0x1fffffff & (casters * 31 + node.dataVersion);
      }
    }

    return (
      matrices: matrices,
      epoch: SceneNode.changeEpoch,
      generation: scene.staticShadowGeneration,
      faces: settings.casterFaces.hashCode,
      casters: casters,
    );
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

    // Before anything is decided, rather than after the pass was opened and
    // the bake key recorded: a bundle without the stage used to leave a
    // render pass begun and never submitted, and a key that said the atlas
    // held this frame's casters — so the next frame skipped the pass and
    // reported a map nobody had drawn.
    final shadowShader = shaders['ShadowDepth'];
    if (shadowShader == null) return false;
    // `gfx-60n`. Falls back to the plain stage in a bundle that predates the
    // row, which is the shadow a cut-out caster used to get rather than no
    // shadow at all, and `masked` below then never fires.
    final maskedShadowShader = shaders['ShadowDepthMasked'] ?? shadowShader;

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
    // And the volume each one covers, for `gfx-63n`'s caster cull. Built from
    // the unremapped matrix, because that is the one in the clip space the
    // planes are extracted for; the drawing copy has been through the backend's
    // depth convention and the shader copy may have had its y flipped.
    final cascadeFrusta = <vm.Frustum>[];

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

      // **A near cascade reaches back to the furthest caster towards the
      // light.** Its volume is a sphere around what the camera sees, and its
      // depth ran from that sphere's own light-side edge: a tree or a wall
      // standing further out towards the sun than the sphere reaches was cut
      // by the near plane, and the ground inside the tile it shades came back
      // lit while the next cascade out had the shadow. The last cascade is the
      // whole caster set and needs nothing. The reach is rounded up to whole
      // texels so a camera walking along does not slide the depth under a
      // still scene; the bias is converted below to keep its distance.
      final ownReach = radius * padding;
      var distance = ownReach;
      if (i < centres.length - 1) {
        final reach = (centre - sceneCentre).dot(aim) + sceneRadius;
        if (reach > distance) {
          distance = (reach / texelWorld).ceilToDouble() * texelWorld;
        }
      }
      _shadowCascadeBiasScale[i] = distance == ownReach
          ? 1.0
          : (ownReach + ownReach - 0.01) / (distance + ownReach - 0.01);
      final eye = centre - aim.scaled(distance);
      final view = Renderer._lookAt(eye, centre, up);
      final projection = OrthographicProjection(
        height: radius * 2.0 * padding,
        near: 0.01,
        far: distance + ownReach,
      ).toMatrix(1.0);

      final matrix = vm.Matrix4.copy(projection)..multiply(view);
      drawMatrices.add(toDepthRange(matrix, device.depthRange));
      shaderMatrices.add(toFramebufferOrigin(matrix, device.framebufferOrigin));
      cascadeFrusta.add(vm.Frustum.matrix(matrix));
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

    // **A cascade nobody changed is not redrawn — `gfx-68n`.** Every cascade
    // was drawn from nothing every frame, which on a scene larger than the
    // nearest cascade covers is the whole caster set two or three times over,
    // for a picture identical to the one already in the texture. The map is
    // `devicePrivate` and has always survived the frame; nothing was reading it
    // back.
    //
    // The key is everything that decides a texel. The matrices carry the
    // camera, the light's aim, the scene's own bounds, the resolution and the
    // padding, because all of those went into fitting them.
    // `SceneNode.changeEpoch` carries every caster that moved, appeared,
    // vanished or was hidden, and a skinned caster's pose with it, since a joint
    // is a node. `Scene.staticShadowGeneration` carries a caster that changed
    // *how* it casts. The cull mode and the masked casters' own thresholds are
    // read directly, because neither reaches either counter.
    // Cascades live side by side in one texture, so the number of samplers the
    // fragment shader binds does not depend on how many there are.
    final atlasWidth = resolution * count;

    /// What the lighting shader reads about the map, whether or not this frame
    /// drew into it.
    ///
    /// A closure with two call sites rather than a tail with one, because the
    /// skip below leaves by a different door and these are not optional: they
    /// are applied per fragment, so a frame that left them at nought would read
    /// a perfectly good atlas with a strength of zero and come back unshadowed.
    void publishShadowParams() {
      // Horizontally the texel is a texel of the *atlas*, vertically it is a
      // texel of a tile. With one cascade they are the same number, which is
      // what keeps that path byte-identical to the one this renderer has always
      // had.
      _shadowParams[0] = 1.0 / atlasWidth;
      _shadowCascades[0] = splits[0];
      _shadowCascades[1] = splits[1];
      _shadowCascades[2] = count.toDouble();
      _shadowCascades[3] = 1.0 / resolution;
      _shadowParams[1] = settings.bias;
      for (var i = 0; i < 3; i++) {
        _shadowCascadeBias[i] =
            settings.bias * _shadowCascadeBiasScale[math.min(i, count - 1)];
      }
      _shadowParams[2] = settings.normalOffset;
      _shadowParams[3] = settings.strength.clamp(0.0, 1.0);
    }

    final bakeKey = _directionalBakeKey(scene, settings, shaderMatrices);
    if (_shadowMap != null &&
        _shadowResolution == resolution &&
        _shadowCascadeCount == count &&
        _directionalBaked == bakeKey) {
      // Zeroed by the frame, so a pass that draws nothing has to put back what
      // the last one counted or the overlay reports a scene that stopped
      // casting.
      _shadowCasters = _directionalCasters;
      publishShadowParams();
      return true;
    }
    _directionalBaked = bakeKey;
    if (_shadowMap == null ||
        _shadowResolution != resolution ||
        _shadowCascadeCount != count) {
      // Sampled by the lighting pass, so devicePrivate rather than transient.
      // The one it replaces goes back to the device once no frame in flight
      // can still be sampling it — dropping it was a free on one backend and a
      // driver object leaked per resolution or cascade change on WebGL2.
      _destroyAfterFrame(_shadowMap);
      _shadowMap = device.createTexture(
        RenderTargetSpec(
          width: atlasWidth,
          height: resolution,
          format: hdrFormat,
        ),
      );
      // Its own depth, for as long as the atlas lives. See [_shadowDepth].
      _destroyAfterFrame(_shadowDepth);
      _shadowDepth = device.createTexture(
        RenderTargetSpec(
          width: atlasWidth,
          height: resolution,
          format: device.defaultDepthStencilFormat,
          storageMode: StorageMode.deviceTransient,
        ),
      );
      _shadowResolution = resolution;
      _shadowCascadeCount = count;
    }

    final depth = _shadowDepth!;

    developer.Timeline.startSync('Renderer.shadowPass');
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
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
    // The same caster state the cube atlas uses, and now the same cull: whose
    // side is recorded is `ShadowSettings.casterFaces`, which defaults to the
    // back — the depth stored is then the far wall of each caster, which moves
    // the comparison surface away from the lit face and removes most of the
    // acne before bias and normal offset have to deal with any. That default is
    // what this line used to say outright. See [_casterCull].
    final casterCull = _casterCull(settings.casterFaces);
    pass.setState(
      Renderer._kShadowCasterState.copyWith(
        viewport: full,
        scissor: full,
        cullMode: casterCull,
      ),
    );

    // Two pipelines, for the same reason the main pass has two: a skinned mesh
    // has a different vertex layout, so it needs the skinned stage here too.
    // Drawing it with the static one would read joints and weights as position
    // and normal — and skipping skinned casters instead would mean a character
    // that walks around without a shadow.
    // Which of the three vertex stages the pass currently has bound: 0 the
    // static one, 1 the skinned one, 2 the instanced one. Null for none.
    int? boundKind;

    _shadowCasters = 0;
    final meshes = scene.meshes;
    final mvp = vm.Matrix4.identity();

    // The strip the cascade loop is currently drawing into, kept so a node
    // that casts from every face can restate the cull without losing it.
    var casterTile = full;
    // Already true when the setting asks for every face, as the cube pass does
    // it: otherwise the first node that asks for one restates a cull the pass
    // is already in, and — worse — the next ordinary node restates it back to
    // something the setting did not ask for.
    var everyFace = casterCull == CullMode.none;

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
            cullMode: casterCull,
          ),
        );
        casterTile = tile;
        everyFace = casterCull == CullMode.none;
        boundKind = null;
      }
      final drawMatrix = drawMatrices[cascade];
      final casterFrustum = cascadeFrusta[cascade];

      for (var i = 0; i < meshes.length; i++) {
        final node = meshes[i];
        if (!node.visibleInHierarchy) continue;
        if (!node.shadowCasting.casts) continue;
        final mesh = node.mesh;
        if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;
        // **A caster outside this cascade is not drawn into it — `gfx-63n`.**
        // Every cascade used to walk the whole scene, so a level larger than
        // the nearest cascade covers was recorded three or four times over,
        // most of it clipped away the moment it reached the rasteriser.
        //
        // The map cannot move a byte, and that is a property rather than a
        // hope: the box bounds every triangle the node has, so a box the
        // volume does not touch holds no triangle that could have produced a
        // fragment. What is rejected here is what the clipper was going to
        // reject anyway, only without the vertex work first.
        if (node.frustumCulled &&
            !casterFrustum.intersectsWithAabb3(node.worldBounds)) {
          continue;
        }
        final instanced = node is InstancedMeshNode ? node : null;
        if (instanced != null && instanced.count == 0) continue;

        // Both sides recorded for a surface that has only one, so the sun does
        // not come through the seam of a single-sided wall. The state carries
        // the cascade's own strip with it, or restating the cull would put the
        // rest of this cascade back into the full atlas.
        final wantsEveryFace =
            node.castsShadowFromEveryFace || casterCull == CullMode.none;
        if (wantsEveryFace != everyFace) {
          pass.setState(
            Renderer._kShadowCasterState.copyWith(
              viewport: casterTile,
              scissor: casterTile,
              cullMode: wantsEveryFace ? CullMode.none : casterCull,
            ),
          );
          everyFace = wantsEveryFace;
        }

        final skeleton = node.skeleton;
        final skinned = skeleton != null;
        // `gfx-60n`. A cut-out caster goes through a stage with a sampler in
        // it; everything else keeps the stage it has always had, which is why
        // the masked half costs the common path nothing and why forty-four
        // goldens recorded against the plain stage cannot move.
        final masked = maskedShadowShader != shadowShader && _castsMasked(node);
        final kind =
            (instanced != null
                ? 2
                : skinned
                ? 1
                : 0) +
            (masked ? 3 : 0);
        if (boundKind != kind) {
          final fragment = masked ? maskedShadowShader : shadowShader;
          pass.bindPipeline(switch (kind) {
            5 => _instancedMaskedShadowPipeline ??= device.createPipeline(
              instancedVertexShader,
              fragment,
              layout: _kInstancedLayout,
            ),
            4 => _skinnedMaskedShadowPipeline ??= device.createPipeline(
              skinnedVertexShader,
              fragment,
            ),
            3 => _maskedShadowPipeline ??= device.createPipeline(
              vertexShader,
              fragment,
            ),
            2 => _instancedShadowPipeline ??= device.createPipeline(
              instancedVertexShader,
              fragment,
              layout: _kInstancedLayout,
            ),
            1 => _skinnedShadowPipeline ??= device.createPipeline(
              skinnedVertexShader,
              fragment,
            ),
            _ => _shadowPipeline ??= device.createPipeline(
              vertexShader,
              fragment,
            ),
          });
          boundKind = kind;
        }
        if (masked) _bindShadowMask(pass, maskedShadowShader, node.material);

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
        final stage = switch (kind) {
          2 => instancedVertexShader,
          1 => skinnedVertexShader,
          _ => vertexShader,
        };
        pass.bindUniformBlock(stage, _kFrameInfoBlock, {
          'mvp': mvp.storage,
          'model': node.worldMatrix.storage,
          'normal_matrix': node.worldNormalMatrix.storage,
        });
        _bindMorph(pass, stage, node.morph);
        if (instanced != null) {
          _bindInstanceMorph(pass, stage, instanced);
        }
        if (instanced != null) {
          pass.bindVertexData(
            instanced.instanceBytes,
            instanced.count,
            slot: 1,
          );
        }
        if (skeleton != null) {
          skeleton.update(node.worldMatrix);
          pass.bindUniformBlock(skinnedVertexShader, _kSkinInfoBlock, {
            'joint_matrices': skeleton.matrices,
          });
        }
        pass.draw(instanceCount: instanced?.count ?? 1);
        // Counted once, not once per cascade: the number answers "how many things
        // cast", and a caster drawn into three tiles is still one caster.
        //
        // The draws are counted every time, which is the other half of the
        // same sentence and was missing until `gfx-01n` went looking: a
        // caster in three cascades is three draws, and a frame that reported
        // one caster and no draws at all was hiding the cost of the cascade
        // count from every measurement made of it.
        if (cascade == 0) _shadowCasters++;
        _frameCounters?.drawCalls++;
      }
    }

    pass.submit();
    developer.Timeline.finishSync();

    publishShadowParams();
    _directionalCasters = _shadowCasters;
    return true;
  }
}
