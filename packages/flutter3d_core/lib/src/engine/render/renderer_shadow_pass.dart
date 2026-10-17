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

/// The coarsest step a depth in [0, 1] is stored with in a map of [format]:
/// a half float keeps eleven significant bits, so between one half and one
/// its values are 1/2048 apart. Full floats are finer than any bias.
double _storedDepthStep(TextureFormat format) => switch (format) {
  TextureFormat.r16g16b16a16Float => 1.0 / 2048.0,
  _ => 0.0,
};

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
  /// Writes one caster's draw into [journal] — `P12`.
  ///
  /// Called only behind `if (_frameCounters?.journal case final journal?)`,
  /// so a frame nobody is journaling never reaches it.
  void _journalCaster(
    DrawJournal journal,
    MeshNode node,
    DrawableGeometry mesh,
    vm.Matrix4 mvp, {
    required int instances,
    required String target,
  }) => journal.add(
    kind: 'shadow',
    mesh: node.name,
    material: node.material.name,
    lighting: node.material.lighting.label,
    vertices: mesh.vertexCount,
    indices: mesh.indexCount,
    instances: instances,
    state: <String, Object?>{
      'target': target,
      'masked': _castsMasked(node),
      'skinned': node.skeleton != null,
      'instanced': node is InstancedMeshNode,
      'winding': node.isWorldMirrored ? 'cw' : 'ccw',
    },
    uniforms: <String, Float32List>{
      'mvp': Float32List.fromList(mvp.storage),
      'model': Float32List.fromList(node.worldMatrix.storage),
    },
  );

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
    RenderMaterial material,
  ) {
    final texture = material.albedo;
    if (texture == null) return;
    pass.bindTexture(stage, _kAlbedoTextureSlot, texture);
    _shadowMask[0] = material.alphaCutoff;
    _shadowMask[1] = material.baseColor.a;
    pass.bindBlock(stage, _maskInfo);
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
    int firstTile = 0,
    FrameWorkBudget? budget,
    Set<int>? drawnTiles,
    List<_CubeFit?>? fits,
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
            clearValue: ClearColor(1.0, 1.0, 1.0, 1.0),
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

    // A tile drawn: named to the caller, and what it took charged to the
    // allowance when there is one.
    void finishTile(int tileIndex, int started) {
      drawnTiles?.add(tileIndex);
      if (budget != null) budget.charge(budget.now() - started);
    }

    // Tile by tile from [firstTile], which is where the scheduler began its
    // scan: under an allowance the tiles at the front of this order are the
    // ones that get drawn, and a tile refused last frame has to be at the
    // front of this one. The order changes no pixel — the tiles are disjoint
    // viewports — so a frame with no allowance draws what it always drew.
    // Fitted first and drawn after, as the directional map is, so a
    // technique's own producer can draw into what the engine fitted (D22):
    // see [_fitCubeShadow]. The frame's fit when the caller has one, so a
    // frame that asked a technique for a producer and got none fits once.
    final rows = fits ?? _fitCubeShadow(slotCount);
    final tileCount = slotCount * Renderer._cubeFaces.length;
    for (var n = 0; n < tileCount; n++) {
      final tileIndex = (firstTile + n) % tileCount;
      final slot = tileIndex ~/ Renderer._cubeFaces.length;
      final face = tileIndex % Renderer._cubeFaces.length;
      final fit = rows[slot];
      if (fit == null) continue;
      position.setFrom(fit.position);
      final range = fit.range;

      _cubeLight[0] = position.x;
      _cubeLight[1] = position.y;
      _cubeLight[2] = position.z;
      _cubeLight[3] = range;

      // A spot casts into one column. The five beside it still hold what the
      // row's previous owner drew there, and `_computeFaceSignatures` gives
      // them a blank signature so the schedule names them once — which only
      // means something if this loop visits them. It used to stop after the
      // first column, the scheduler recorded the other five as drawn, and
      // the stale picture stayed for as long as the spot held the row.
      final casts = face < fit.shaderMatrices.length;
      final scheduled = tiles == null || tiles.contains(tileIndex);
      // `N3`: a scheduled tile the frame's allowance refuses is skipped
      // before its matrix is recorded, so the picture already in it is
      // still read through the matrix that drew it; the caller leaves it
      // pending and it is drawn on a later frame.
      if (scheduled && budget != null && !budget.allows()) continue;
      final tileStart = budget?.now() ?? 0;
      if (casts) {
        // The matrix is recorded for every face, drawn or not: the shading
        // projects through it whatever this frame chose to redraw, and a
        // face left out of the schedule still holds a picture that has to
        // be read with the matrix that made it.
        _cubeMatrix.setFrom(fit.shaderMatrices[face]);
        final at = (slot * 6 + face) * 16;
        _cubeFaceMatrices.setRange(at, at + 16, _cubeMatrix.storage);
        _cubeDrawMatrix.setFrom(fit.drawMatrices[face]);
      }

      if (!scheduled) continue;

      // A row of six per light: the face across, the light down.
      final tileRect = ScreenRect(
        x: face * tile,
        y: slot * tile,
        width: tile,
        height: tile,
      );
      pass.setViewport(PassViewport.ofRect(tileRect));
      pass.setScissor(tileRect);

      // Blank this tile before drawing into it, since the pass no longer
      // clears. Depth is still cleared attachment-wide by the pass, so this
      // only has to write colour — and must not touch depth, or it would
      // occlude the casters that follow it.
      pass.setState(Renderer._kShadowTileResetState);
      pass.bindPipeline(
        _cubeShadowResetPipeline ??= device.createPipelineFrom(
          PipelineDescriptor(vertex: resetVertexShader, fragment: resetShader),
        ),
      );
      pass.bindVertexBuffer(_fullscreenTriangle, 3);
      pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
      pass.draw();
      _frameCounters?.drawCalls++;
      // A spot's idle column: blanked, and nothing casts into it.
      if (!casts) {
        finishTile(tileIndex, tileStart);
        continue;
      }

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
        if (!node.isVisibleInHierarchy || !node.shadowCasting.casts) continue;
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
        // Version 2: a caster whose material moves its geometry casts
        // through the material's own vertex stage.
        final own = _bindDepthPassStage(pass, node, fragment);
        if (own == null) {
          pass.bindPipeline(
            instanced != null
                ? masked
                      ? (_instancedMaskedCubeShadowPipeline ??= device
                            .createPipelineFrom(
                              PipelineDescriptor(
                                vertex: _instancedVertexShader,
                                fragment: fragment,
                                layout: _kInstancedLayout,
                              ),
                            ))
                      : (_instancedCubeShadowPipeline ??= device
                            .createPipelineFrom(
                              PipelineDescriptor(
                                vertex: _instancedVertexShader,
                                fragment: fragment,
                                layout: _kInstancedLayout,
                              ),
                            ))
                : skinned
                ? masked
                      ? (_skinnedMaskedCubeShadowPipeline ??= device
                            .createPipelineFrom(
                              PipelineDescriptor(
                                vertex: _skinnedVertexShader,
                                fragment: fragment,
                              ),
                            ))
                      : (_skinnedCubeShadowPipeline ??= device
                            .createPipelineFrom(
                              PipelineDescriptor(
                                vertex: _skinnedVertexShader,
                                fragment: fragment,
                              ),
                            ))
                : masked
                ? (_maskedCubeShadowPipeline ??= device.createPipelineFrom(
                    PipelineDescriptor(
                      vertex: _vertexShader,
                      fragment: fragment,
                    ),
                  ))
                : (_cubeShadowPipeline ??= device.createPipelineFrom(
                    PipelineDescriptor(
                      vertex: _vertexShader,
                      fragment: fragment,
                    ),
                  )),
          );
        }
        if (masked) _bindShadowMask(pass, maskedShader, node.material);
        final stage =
            own ??
            (instanced != null
                ? _instancedVertexShader
                : skinned
                ? _skinnedVertexShader
                : _vertexShader);
        pass.setWindingOrder(
          node.isWorldMirrored
              ? WindingOrder.clockwise
              : WindingOrder.counterClockwise,
        );
        pass.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
        pass.bindIndexBuffer(mesh.indices, mesh.indexType, mesh.indexCount);

        mvp
          ..setFrom(_cubeDrawMatrix)
          ..multiply(node.worldMatrix);
        _frameInfo.mvp.setAll(0, mvp.storage);
        _frameInfo.model.setAll(0, node.worldMatrix.storage);
        _frameInfo.normalMatrix.setAll(0, node.worldNormalMatrix.storage);
        pass.bindBlock(stage, _frameInfo);
        _bindMorph(pass, stage, node.morph);
        if (own != null) {
          _bindMaterialVertex(
            pass,
            own,
            node.material,
            _cubeDrawMatrix,
            node: node,
          );
        }
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
          // [Renderer.shadowedLights] caps the lights at six. [_computeFaceSignatures]
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
          _skinInfo.jointMatrices.setAll(0, skeleton.matrices);
          pass.bindBlock(stage, _skinInfo);
        }
        // Through the stage the pipeline was built with. A cut-out caster's
        // fragment stage is `ShadowDistanceMasked`, which declares its own
        // `ShadowLight`; binding it through the plain stage's handle landed
        // in the right slot only because both happen to declare it first.
        pass.bindBlock(fragment, _shadowLight);
        pass.draw(instanceCount: instanced?.count ?? 1);
        _frameCounters?.drawCalls++;
        if (_frameCounters?.journal case final journal?) {
          _journalCaster(
            journal,
            node,
            mesh,
            mvp,
            instances: instanced?.count ?? 1,
            target: 'cube',
          );
        }
        drawn++;
      }
      finishTile(tileIndex, tileStart);
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

  /// Every occupied row's faces: where the light is, how far it reaches, and
  /// each face's matrix as the lit stages read it and as this device draws
  /// with it — the half of [_renderCubeShadow] a technique's own producer
  /// needs too (D22). Null for a row no light holds.
  ///
  /// Moved, not rewritten, from the tile loop: the same arithmetic in the
  /// same order, so every matrix is the bits it was.
  List<_CubeFit?> _fitCubeShadow(int slotCount) => <_CubeFit?>[
    for (var slot = 0; slot < slotCount; slot++) _fitCubeRow(slot),
  ];

  _CubeFit? _fitCubeRow(int slot) {
    final range = _cubeLightData[slot * 4 + 3];
    if (range <= 0.0) return null;
    final position = vm.Vector3(
      _cubeLightData[slot * 4],
      _cubeLightData[slot * 4 + 1],
      _cubeLightData[slot * 4 + 2],
    );

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
      fovY: isSpot ? 2.0 * math.atan(spotTanHalf) : math.pi / 2,
      near: 0.05,
      far: range,
    ).toMatrix(1.0);

    final shaderMatrices = <vm.Matrix4>[];
    final drawMatrices = <vm.Matrix4>[];
    for (
      var face = 0;
      face < (isSpot ? 1 : Renderer._cubeFaces.length);
      face++
    ) {
      final vm.Vector3 faceAim;
      final vm.Vector3 faceUp;
      if (isSpot) {
        faceAim = vm.Vector3(
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
            ? vm.Vector3(0.0, 0.0, 1.0)
            : vm.Vector3(0.0, 1.0, 0.0);
      } else {
        (faceAim, faceUp) = Renderer._cubeFaces[face];
      }
      final faceView = Renderer._lookAt(position, position + faceAim, faceUp);
      final shader = vm.Matrix4.copy(projection)..multiply(faceView);
      shaderMatrices.add(shader);
      // For drawing, in this backend's clip space. The stored value is a
      // distance rather than a depth, so the convention cannot corrupt it
      // — but the depth *test* between casters in a tile runs in clip
      // space, and the lookup reads the tile through the unremapped
      // matrix above.
      drawMatrices.add(toDepthRange(shader, device.depthRange));
    }
    return _CubeFit(
      position: position,
      range: range,
      shaderMatrices: shaderMatrices,
      drawMatrices: drawMatrices,
    );
  }

  /// Hands the moving cube atlas to the frame's technique's own producer,
  /// when it has one (D22): every row fitted, the matrices recorded for the
  /// lit stages, and the producer's node run where [_renderCubeShadow] would
  /// have drawn. False, and nothing done, when the technique has none.
  ///
  /// [fits] is the frame's fit, worked out the first time it is read: the
  /// technique is asked with lights that fit themselves only when it reads
  /// them, so an engine technique, which has no producer and reads nothing,
  /// costs no fit, and a technique of one's own that answers null leaves the
  /// fit for the tile loop to reuse rather than to redo.
  ///
  /// The scheduler forgets what it drew, so the frame after the producer
  /// goes draws every face of the engine's own again.
  bool _produceCubeShadow({
    required RenderFrame frame,
    required ShadowSettings settings,
    required int slotCount,
    required List<_CubeFit?> Function() fits,
  }) {
    if (!settings.enabled || settings.strength <= 0.0 || slotCount <= 0) {
      return false;
    }
    final producer = _directionalTechnique(settings).cubeAtlasProducer(
      ShadowProducerContext(
        settings: settings,
        camera: frame.view?.camera,
        cubeAtlas: ShadowCubeAtlas(
          atlas: _cubeShadow!,
          depth: _cubeShadowDepth!,
          tile: _cubeShadowTile,
          lights: _FittedCubeLights(fits),
        ),
      ),
    );
    if (producer == null) return false;
    for (final (row, fit) in fits().indexed) {
      if (fit == null) continue;
      for (final (face, matrix) in fit.shaderMatrices.indexed) {
        final at = (row * 6 + face) * 16;
        _cubeFaceMatrices.setRange(at, at + 16, matrix.storage);
      }
    }
    _shadowFaceScheduler.reset();
    producer.execute(frame);
    // What the producer drew is defined, so the engine's next pass may load.
    _cubeShadowCleared = true;
    return true;
  }

  /// [_casterFlags]: the caster is drawn into some cascade, given a volume
  /// that holds it.
  static const int _casts = 1;

  /// [_casterFlags]: the caster is see-through this frame.
  static const int _castsSeeThrough = 2;

  /// [_casterFlags]: the caster is marked static.
  static const int _castsStatic = 4;

  static int _mix(int key, int value) => 0x1fffffff & (key * 31 + value);

  /// Fills [_casterKeys] and [_casterFlags] for this frame's [scene], once,
  /// for every cascade's key to read.
  ///
  /// Masked casters read a cutoff and an alpha off their material, and
  /// neither a material's fields nor the texture it points at reach any
  /// version, so they are read directly, as are the faces a caster records,
  /// a swapped mesh, a morph's weights and an instance moved inside a batch.
  /// What is read is the same whichever cascade asks, so it is read once:
  /// the keys used to walk every caster's material, mesh and joints again
  /// for every cascade and once more for the static tiles.
  void _keyCasters(Scene scene, bool Function(MeshNode node) seeThrough) {
    final meshes = scene.meshes;
    if (_casterKeys.length < meshes.length) {
      final capacity = math.max(meshes.length, _casterKeys.length * 2);
      _casterKeys = Int32List(capacity);
      _casterFlags = Uint8List(capacity);
    }
    for (var i = 0; i < meshes.length; i++) {
      final node = meshes[i];
      if (!_castsShadow(node)) {
        _casterFlags[i] = 0;
        continue;
      }
      final translucent = seeThrough(node);
      _casterFlags[i] =
          _casts |
          (translucent ? _castsSeeThrough : 0) |
          (node.shadowIsStatic ? _castsStatic : 0);
      final material = node.material;
      var key = 17;
      if (translucent) {
        // What it lets through is read off the material, which no version
        // follows: its colour, its transmission, its index and its volume.
        key = _mix(key, material.baseColor.r.hashCode);
        key = _mix(key, material.baseColor.g.hashCode);
        key = _mix(key, material.baseColor.b.hashCode);
        key = _mix(key, (material.extensions?.transmission ?? 0.0).hashCode);
        key = _mix(key, (material.extensions?.ior ?? 1.5).hashCode);
        final volume = material.extensions;
        if (volume != null) {
          key = _mix(key, volume.thickness.hashCode);
          key = _mix(key, volume.attenuationDistance.hashCode);
          final through = volume.attenuationColor;
          key = _mix(key, through.r.hashCode);
          key = _mix(key, through.g.hashCode);
          key = _mix(key, through.b.hashCode);
        }
      }
      key = _mix(key, identityHashCode(node));
      key = _mix(key, node.worldVersion);
      key = _mix(key, identityHashCode(material));
      key = _mix(key, material.alphaMode.hashCode);
      key = _mix(key, material.alphaCutoff.hashCode);
      key = _mix(key, material.baseColor.a.hashCode);
      key = _mix(key, identityHashCode(material.albedo));
      key = _mix(key, node.castsShadowFromEveryFace ? 1 : 0);
      key = _mix(key, identityHashCode(node.mesh));
      key = _mix(key, node.morph?.version ?? 0);
      if (node is InstancedMeshNode) key = _mix(key, node.dataVersion);
      final skeleton = node.skeleton;
      if (skeleton != null) {
        for (final joint in skeleton.joints) {
          key = _mix(key, joint.worldVersion);
        }
      }
      _casterKeys[i] = key;
    }
  }

  /// Everything that decides a texel of cascade [shaderMatrix]'s tile —
  /// `gfx-68n`, per cascade since `S1` — from the casters [_keyCasters]
  /// keyed this frame.
  ///
  /// **Per cascade, so a caster moving in one does not redraw the others.**
  /// The whole atlas used to share one key with `sceneChangeEpoch` in
  /// it, so anything moving anywhere, and every step of the camera, drew
  /// every cascade again. Now a tile keys on its own matrix and on the
  /// casters its volume holds, each by its own `worldVersion` (and a skinned
  /// one by its joints'), so the last cascade, which is the whole scene and
  /// is fitted to the casters rather than to the camera, stays drawn while
  /// the camera walks, and a character crossing the near cascade leaves the
  /// far ones alone.
  int _cascadeBakeKey(
    Scene scene,
    ShadowSettings settings,
    vm.Matrix4? shaderMatrix,
    vm.Frustum? frustum, {
    bool? only,
  }) {
    var key = _mix(
      settings.directionalCasterFaces.hashCode,
      scene.staticShadowGeneration,
    );
    if (shaderMatrix != null) {
      final storage = shaderMatrix.storage;
      for (var i = 0; i < storage.length; i++) {
        key = _mix(key, storage[i].hashCode);
      }
    }
    final meshes = scene.meshes;
    for (var i = 0; i < meshes.length; i++) {
      final flags = _casterFlags[i];
      if (flags & _casts == 0) continue;
      // A see-through caster is never kept in the static atlas — its share
      // of the map is blended into the frame's, after the walls — so it
      // belongs to the frame's key whatever it is marked as.
      if (only != null &&
          (flags & _castsSeeThrough != 0
              ? only
              : (flags & _castsStatic != 0) != only)) {
        continue;
      }
      if (!_inCascadeVolume(meshes[i], frustum)) continue;
      key = _mix(key, _casterKeys[i]);
    }
    return key;
  }

  /// [matrix] as a number, for a key.
  static int _matrixKey(vm.Matrix4 matrix) {
    var key = 17;
    for (final value in matrix.storage) {
      key = 0x1fffffff & (key * 31 + value.hashCode);
    }
    return key;
  }

  /// Whether [node] is drawn into the cascade whose volume is [frustum]: the
  /// tests the draw loop makes, in one place so the key and the loop agree.
  static bool _drawsIntoCascade(MeshNode node, vm.Frustum? frustum) =>
      _castsShadow(node) && _inCascadeVolume(node, frustum);

  /// The half of [_drawsIntoCascade] no cascade changes.
  static bool _castsShadow(MeshNode node) {
    if (!node.isVisibleInHierarchy) return false;
    if (!node.shadowCasting.casts) return false;
    final mesh = node.mesh;
    if (mesh is! DrawableGeometry || mesh.indexCount == 0) return false;
    return node is! InstancedMeshNode || node.count > 0;
  }

  /// The half of [_drawsIntoCascade] each cascade asks: whether its volume
  /// [frustum] holds [node], or there is no volume to ask.
  static bool _inCascadeVolume(MeshNode node, vm.Frustum? frustum) =>
      frustum == null ||
      !node.frustumCulled ||
      frustum.intersectsWithAabb3(node.worldBounds);

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
  ///
  /// [reversed] keeps the map's depth the other way round — `A2.8`, see
  /// `lib/shadow_storage.glsl` — and in 32-bit floats where the device
  /// renders, filters and blends them.
  bool _renderShadowMap({
    required FrameResources resources,
    required Scene scene,
    required ShadowSettings settings,
    required int casterIndex,
    CameraNode? camera,
    bool reversed = false,
    RenderFrame? frame,
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
    // `ShadowSettings.translucentCasters`: null when it is off, under the
    // moments filter whose blur takes over the channels it writes, or in a
    // bundle without the stage — and then every caster is drawn as before.
    final transmittanceShader =
        settings.translucentCasters &&
            !_directionalTechnique(settings).kernelFor(settings).readsMoments
        ? shaders['ShadowTransmittance']
        : null;
    final transmits = transmittanceShader != null;
    // `A2.8`: what the atlas is made of and which way its depth runs. Full
    // floats only with the flag, so the flag off is the half-float atlas
    // every earlier frame was drawn with, and only where the device can do
    // everything the atlas is used for: drawn into, read filtered, and —
    // with see-through casters — blended into, which also needs the three
    // channels those write.
    final features = device.features;
    final fullFloat =
        reversed &&
        features.has(DeviceFeature.float32Renderable) &&
        features.has(DeviceFeature.float32Filterable) &&
        (!transmits || features.has(DeviceFeature.float32Blendable));
    final atlasFormat = !fullFloat
        ? hdrFormat
        : (transmits
              ? TextureFormat.r32g32b32a32Float
              : TextureFormat.r32Float);
    // `ShadowSettings.caustics`: the three stages it adds and the copy it
    // borrows, or nothing at all.
    final causticSurface = shaders['CausticSurface'];
    final photonVertex = shaders['CausticPhotonVertex'];
    final photonFragment = shaders['CausticPhoton'];
    final caustics =
        transmits &&
        settings.caustics &&
        causticSurface != null &&
        photonVertex != null &&
        photonFragment != null &&
        shaders['ShadowCopy'] != null &&
        shaders['FullscreenVertex'] != null;
    bool seeThrough(MeshNode node) {
      if (!transmits) return false;
      final material = node.material;
      return material.isTransparent ||
          (material.extensions?.transmission ?? 0.0) > 0.0;
    }

    // Whether [node]'s light is followed as photons: a static caster with a
    // volume — transmission and a thickness. A thin-walled one refracts
    // nothing worth following.
    bool refracts(MeshNode node) {
      if (!caustics || !seeThrough(node)) return false;
      if (node is InstancedMeshNode || node.skeleton != null) return false;
      final extensions = node.material.extensions;
      return extensions != null &&
          extensions.transmission > 0.0 &&
          extensions.thickness > 0.0;
    }

    // Fitted first and drawn after, so a technique's own producer can draw
    // into what the engine fitted (D22): see [_fitShadowMap].
    final fit = _fitShadowMap(
      resources: resources,
      scene: scene,
      settings: settings,
      casterIndex: casterIndex,
      camera: camera,
      reversed: reversed,
    );
    if (fit == null) return false;
    final _ShadowFit(
      :aim,
      :count,
      :resolution,
      :splits,
      :drawMatrices,
      :shaderMatrices,
      :cascadeFrusta,
      :rawMatrices,
    ) = fit;

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
    // `sceneChangeEpoch` carries every caster that moved, appeared,
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
      // `A2.8`: how the map stores its depth, in the lane the bias held
      // and nothing read — see `shadow_params` in `surface.glsl`.
      _shadowStorage = !reversed ? 0.0 : (fullFloat ? 2.0 : 1.0);
      _shadowParams[1] = _shadowStorage;
      // **Never finer than the map can store.** The bias is kept in metres
      // when a near cascade reaches back to a far caster, so in stored depth
      // it shrinks with that reach: in a river valley two hundred metres long
      // it came to a tenth of a half-float step. A lit floor compared against
      // its own depth rounded to that step then shadowed itself in bands, on
      // Metal and every other device that stores the map as it says, and not
      // on the software backend, which keeps full floats in any format.
      //
      // **And never more metres than the nearest cascade's.** The bias was
      // a share of each cascade's depth range, and the last cascade's range
      // is the whole level: in a valley 880 m square that was 2.24 m along
      // the light, more than a tanker stands out of the water, and its
      // shadow came in only once the near cascades reached it
      // (`flutter3d/test/far_cascade_shadow_test.dart`). The
      // slope is not what this term is for — the normal offset clears a
      // surface's own plane by the texels the kernel reads, in each
      // cascade's own texels (`shadow.glsl`) — so what is left is precision,
      // and precision does not grow with a texel. It grows with what one
      // step of the stored depth is in metres, which is the floor above:
      // 0.42 m in that valley, and in metres every cascade's bias is now
      // either that or the nearest one's 3 cm. With one cascade the first is
      // the only one, and its metres are what they were.
      // Turned round, a half-float map's floor is taken per fragment at its
      // own depth — `ShadowStoredStep` in `lib/shadow_storage.glsl` — and a
      // 32-bit one has none; either way none is added here.
      final storedStep = reversed ? 0.0 : _storedDepthStep(atlasFormat);
      final nearMetres =
          settings.bias *
          _shadowCascadeBiasScale[0] *
          _shadowCascadeDepthRange[0];
      for (var i = 0; i < 3; i++) {
        final which = math.min(i, count - 1);
        final range = _shadowCascadeDepthRange[which];
        final meters = math.min(
          settings.bias * _shadowCascadeBiasScale[which] * range,
          nearMetres,
        );
        _shadowCascadeBias[i] = math.max(
          meters / range,
          math.min(settings.bias, storedStep),
        );
      }
      _shadowParams[2] = settings.normalOffset;
      _shadowParams[3] = settings.strength.clamp(0.0, 1.0);
    }

    // How many things cast into the near cascade, whether or not this frame
    // draws it: the figure answers "how many things cast", and a kept tile
    // still holds every one of them.
    _shadowCasters = 0;
    for (final node in scene.meshes) {
      if (_drawsIntoCascade(node, cascadeFrusta[0])) _shadowCasters++;
    }

    // `S1`: static casters in an atlas of their own, drawn when they change,
    // and the frame's atlas starting each redrawn tile from a copy of it.
    // Only when there is something static to keep and the bundle has the
    // copy; otherwise every caster is drawn into the frame's atlas, which is
    // the pass a scene with nothing marked static has always had.
    final copyShader = shaders['ShadowCopy'];
    final copyVertexShader = shaders['FullscreenVertex'];
    final resetShader = shaders['ShadowTileReset'];
    final resetVertexShader = shaders['ShadowTileResetVertex'];
    final split =
        copyShader != null &&
        copyVertexShader != null &&
        resetShader != null &&
        resetVertexShader != null &&
        scene.meshes.any(
          (node) => node.shadowIsStatic && node.shadowCasting.casts,
        );

    // Which tiles still hold what this frame would draw. A new or reshaped
    // atlas holds nothing, so every tile is drawn and the pass clears;
    // otherwise the pass keeps the atlas and redraws only the rest. A frame
    // tile's key takes in its static tile's, so a static change redraws both.
    // A change of layout is a fresh atlas too: one drawn without the
    // see-through channels holds ones where this frame reads "all taken".
    // And a change of convention or format: an atlas drawn the other way
    // round reads as a shadow over everything.
    final fresh =
        _shadowMap == null ||
        _shadowResolution != resolution ||
        _shadowCascadeCount != count ||
        _shadowTransmits != transmits ||
        _shadowCaustics != caustics ||
        _shadowReversed != reversed ||
        _shadowFormat != atlasFormat;
    RenderTargetDescriptor atlasSpec() => RenderTargetDescriptor(
      width: atlasWidth,
      height: resolution,
      format: atlasFormat,
    );
    if (fresh) {
      // Sampled by the lighting pass, so devicePrivate rather than transient.
      // The one it replaces goes back to the device once no frame in flight
      // can still be sampling it — dropping it was a free on one backend and a
      // driver object leaked per resolution or cascade change on WebGL2.
      _destroyAfterFrame(_shadowMap);
      _shadowMap = device.createTexture(atlasSpec());
      _destroyAfterFrame(_shadowMapStatic);
      _shadowMapStatic = null;
      _destroyAfterFrame(_shadowMapStaticSpare);
      _shadowMapStaticSpare = null;
      // Its own depth, for as long as the atlas lives. See [_shadowDepth].
      _destroyAfterFrame(_shadowDepth);
      _shadowDepth = device.createTexture(
        RenderTargetDescriptor(
          width: atlasWidth,
          height: resolution,
          format: device.defaultDepthStencilFormat,
          storageMode: StorageMode.deviceTransient,
        ),
      );
      _shadowResolution = resolution;
      _shadowCascadeCount = count;
      _shadowTransmits = transmits;
      _shadowCaustics = caustics;
      _shadowReversed = reversed;
      _shadowFormat = atlasFormat;
    }

    // D22: a technique's own producer draws the casters, into the atlas laid
    // out above and with the matrices fitted above, which the lit stages read
    // as they read the engine's. The engine's tiles are left unbaked, so the
    // frame after the producer goes draws every caster again.
    final producer = frame == null
        ? null
        : _directionalTechnique(settings).shadowMapProducer(
            ShadowProducerContext(
              settings: settings,
              camera: camera,
              cascades: ShadowCascades(
                atlas: _shadowMap!,
                depth: _shadowDepth!,
                resolution: resolution,
                viewProjections: List<vm.Matrix4>.unmodifiable(drawMatrices),
                lightDirection: aim.clone(),
                reversed: reversed,
              ),
            ),
          );
    if (producer != null) {
      _directionalBaked.fillRange(0, _directionalBaked.length, null);
      producer.execute(frame!);
      _shadowMapVersion++;
      publishShadowParams();
      return true;
    }

    final staticFresh = fresh || _shadowMapStatic == null;
    _keyCasters(scene, seeThrough);
    // `S1`: the static casters keyed as a whole rather than per tile, since
    // a tile that scrolls gains the casters its new strip holds without any
    // of them having changed; and each tile's key is that and its matrix.
    final staticScene = split
        ? _cascadeBakeKey(scene, settings, null, null, only: true)
        : 0;
    final staticKeys = <int>[
      for (var i = 0; i < count; i++)
        split
            ? 0x1fffffff & (_matrixKey(shaderMatrices[i]) * 31 + staticScene)
            : 0,
    ];
    final keys = <int>[
      for (var i = 0; i < count; i++)
        0x1fffffff &
            (_cascadeBakeKey(
                      scene,
                      settings,
                      shaderMatrices[i],
                      cascadeFrusta[i],
                      only: split ? false : null,
                    ) *
                    31 +
                (split ? staticKeys[i] + 1 : 0)),
    ];
    final dirty = <bool>[
      for (var i = 0; i < count; i++) fresh || _directionalBaked[i] != keys[i],
    ];
    if (!dirty.contains(true)) {
      publishShadowParams();
      return true;
    }
    // The tile reset is what lets a pass keep the others; a bundle without it
    // draws every tile from a clear, as the pass always did.
    // Not with see-through casters: their share is blended over what is
    // there, so a redrawn tile has to start from the clear, and a clear takes
    // the whole atlas.
    // Turned round, a tile is reset through the copy stage rather than the
    // cube atlas's reset, which writes the ordinary far plane — see
    // `resetTile` — so a bundle without the copy draws from a clear.
    //
    // **And not when every tile is being redrawn**: there is nothing left to
    // keep, and the clear does in one step what the resets do as a full-tile
    // draw each. Turned round, that draw is the copy stage reading a texture
    // for every texel of every tile; on the software device it was nine
    // tenths of a frame for any renderer whose casters changed each frame —
    // an impostor bake, four frames to a view, from a fresh scene each.
    final keep =
        !fresh &&
        dirty.contains(false) &&
        !transmits &&
        resetShader != null &&
        resetVertexShader != null &&
        (!reversed || (copyShader != null && copyVertexShader != null));
    for (var i = 0; i < count; i++) {
      if (!keep) dirty[i] = true;
      if (dirty[i]) _directionalBaked[i] = keys[i];
    }
    // What each static tile does this frame: kept as it is, scrolled by
    // whole texels with the strip that came into view drawn, or drawn again.
    final staticModes = List<_StaticTile>.filled(count, _StaticTile.keep);
    final scrolls = List<_Scroll?>.filled(count, null);
    for (var i = 0; split && i < count; i++) {
      if (staticFresh ||
          _staticSceneKey != staticScene ||
          _staticShaderMatrices[i] == null) {
        staticModes[i] = _StaticTile.redraw;
      } else if (_directionalStaticBaked[i] != staticKeys[i]) {
        final scroll = _scrollBetween(
          _staticShaderMatrices[i]!,
          shaderMatrices[i],
          _staticRawMatrices[i]!,
          rawMatrices[i],
          resolution,
        );
        scrolls[i] = scroll;
        staticModes[i] = scroll == null
            ? _StaticTile.redraw
            : _StaticTile.scroll;
      }
    }

    if (split && staticModes.any((mode) => mode != _StaticTile.keep)) {
      _shadowMapStaticSpare ??= device.createTexture(atlasSpec());
    }

    final depth = _shadowDepth!;
    final full = ScreenRect(width: atlasWidth, height: resolution);
    // The same caster state the cube atlas uses, with a cull of its own: whose
    // side is recorded is `ShadowSettings.directionalCasterFaces`, which
    // defaults to both. It shared the cube pass's `casterFaces` and its
    // back until a sunlit room showed a dotted line of light along every
    // inside corner, the floor compared against the wall's inner face at its
    // own depth; the field's documentation has the rest. See [_casterCull].
    final casterCull = _casterCull(settings.directionalCasterFaces);
    final meshes = scene.meshes;
    final mvp = vm.Matrix4.identity();

    ScreenRect tileOf(int cascade) => count > 1
        ? ScreenRect(
            x: cascade * resolution,
            width: resolution,
            height: resolution,
          )
        : full;

    /// Binds [node]'s geometry, matrices, morph, instances and joints for the
    /// vertex stage [kind] picks (0 static, 1 skinned, 2 instanced, plus
    /// three for a masked fragment stage), and draws it once.
    ///
    /// [own] is the caster's material's vertex stage, already bound in a
    /// pipeline, when the material draws its depth through it — version 2's
    /// `vertex` block — and null for the engine's.
    void drawNode(
      CommandEncoder pass,
      MeshNode node,
      int kind,
      vm.Matrix4 drawMatrix, {
      ShaderHandle? own,
    }) {
      final mesh = node.mesh as DrawableGeometry;
      final instanced = node is InstancedMeshNode ? node : null;
      final skeleton = node.skeleton;
      pass.setWindingOrder(
        node.isWorldMirrored
            ? WindingOrder.clockwise
            : WindingOrder.counterClockwise,
      );
      pass.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
      pass.bindIndexBuffer(mesh.indices, mesh.indexType, mesh.indexCount);

      mvp
        ..setFrom(drawMatrix)
        ..multiply(node.worldMatrix);
      final stage =
          own ??
          switch (kind) {
            2 => _instancedVertexShader,
            1 => _skinnedVertexShader,
            _ => _vertexShader,
          };
      _frameInfo.mvp.setAll(0, mvp.storage);
      _frameInfo.model.setAll(0, node.worldMatrix.storage);
      _frameInfo.normalMatrix.setAll(0, node.worldNormalMatrix.storage);
      pass.bindBlock(stage, _frameInfo);
      _bindMorph(pass, stage, node.morph);
      if (own != null) {
        _bindMaterialVertex(pass, own, node.material, drawMatrix, node: node);
      }
      if (instanced != null) {
        _bindInstanceMorph(pass, stage, instanced);
      }
      if (instanced != null) {
        pass.bindVertexData(instanced.instanceBytes, instanced.count, slot: 1);
      }
      if (skeleton != null) {
        skeleton.update(node.worldMatrix);
        _skinInfo.jointMatrices.setAll(0, skeleton.matrices);
        pass.bindBlock(own ?? _skinnedVertexShader, _skinInfo);
      }
      pass.draw(instanceCount: instanced?.count ?? 1);
      // A caster in three cascades is three draws, and a frame that
      // reported one caster and no draws at all was hiding the cost of the
      // cascade count from every measurement made of it — `gfx-01n`.
      _frameCounters?.drawCalls++;
      if (_frameCounters?.journal case final journal?) {
        _journalCaster(
          journal,
          node,
          mesh,
          mvp,
          instances: instanced?.count ?? 1,
          target: 'cascade',
        );
      }
    }

    /// Draws the casters of [cascade] into [pass] — every caster when [only]
    /// is null, and the static or the dynamic ones otherwise.
    void drawCasters(
      CommandEncoder pass,
      int cascade, {
      bool? only,
      List<vm.Frustum>? within,
    }) {
      final tile = tileOf(cascade);
      pass.setState(
        Renderer._kShadowCasterState.copyWith(
          viewport: PassViewport.ofRect(tile),
          scissor: tile,
          cullMode: casterCull,
        ),
      );
      // The strip the loop is drawing into, kept so a node that casts from
      // every face can restate the cull without losing it.
      final casterTile = tile;
      // Already true when the setting asks for every face, as the cube pass
      // does it: otherwise the first node that asks for one restates a cull
      // the pass is already in, and — worse — the next ordinary node restates
      // it back to something the setting did not ask for.
      var everyFace = casterCull == CullMode.none;
      // Which of the three vertex stages the pass currently has bound: 0 the
      // static one, 1 the skinned one, 2 the instanced one, and three more
      // for the masked stage. Null for none. A skinned mesh has a different
      // vertex layout, so it needs the skinned stage here too; drawing it with
      // the static one would read joints and weights as position and normal.
      int? boundKind;
      final casterFrustum = cascadeFrusta[cascade];

      for (var i = 0; i < meshes.length; i++) {
        final node = meshes[i];
        // Drawn after the walls, by [drawSeeThrough], in the frame's atlas.
        if (seeThrough(node)) continue;
        if (only != null && node.shadowIsStatic != only) continue;
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
        if (!_drawsIntoCascade(node, casterFrustum)) continue;
        // `S1`: a scroll draws only what its new strips hold.
        if (within != null &&
            node.frustumCulled &&
            !within.any((f) => f.intersectsWithAabb3(node.worldBounds))) {
          continue;
        }
        final instanced = node is InstancedMeshNode ? node : null;

        // Both sides recorded for a surface that has only one, so the sun does
        // not come through the seam of a single-sided wall. The state carries
        // the cascade's own strip with it, or restating the cull would put the
        // rest of this cascade back into the full atlas.
        final wantsEveryFace =
            node.castsShadowFromEveryFace || casterCull == CullMode.none;
        if (wantsEveryFace != everyFace) {
          pass.setState(
            Renderer._kShadowCasterState.copyWith(
              viewport: PassViewport.ofRect(casterTile),
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
        // the masked half costs the common path nothing and why 96
        // goldens recorded against the plain stage cannot move.
        final masked = maskedShadowShader != shadowShader && _castsMasked(node);
        final kind =
            (instanced != null
                ? 2
                : skinned
                ? 1
                : 0) +
            (masked ? 3 : 0);
        // Version 2: a caster whose material moves its geometry casts
        // through the material's own vertex stage.
        final own = _bindDepthPassStage(
          pass,
          node,
          masked ? maskedShadowShader : shadowShader,
        );
        if (own != null) {
          boundKind = null;
        } else if (boundKind != kind) {
          final fragment = masked ? maskedShadowShader : shadowShader;
          pass.bindPipeline(switch (kind) {
            5 => _instancedMaskedShadowPipeline ??= device.createPipelineFrom(
              PipelineDescriptor(
                vertex: _instancedVertexShader,
                fragment: fragment,
                layout: _kInstancedLayout,
              ),
            ),
            4 => _skinnedMaskedShadowPipeline ??= device.createPipelineFrom(
              PipelineDescriptor(
                vertex: _skinnedVertexShader,
                fragment: fragment,
              ),
            ),
            3 => _maskedShadowPipeline ??= device.createPipelineFrom(
              PipelineDescriptor(vertex: _vertexShader, fragment: fragment),
            ),
            2 => _instancedShadowPipeline ??= device.createPipelineFrom(
              PipelineDescriptor(
                vertex: _instancedVertexShader,
                fragment: fragment,
                layout: _kInstancedLayout,
              ),
            ),
            1 => _skinnedShadowPipeline ??= device.createPipelineFrom(
              PipelineDescriptor(
                vertex: _skinnedVertexShader,
                fragment: fragment,
              ),
            ),
            _ => _shadowPipeline ??= device.createPipelineFrom(
              PipelineDescriptor(vertex: _vertexShader, fragment: fragment),
            ),
          });
          boundKind = kind;
        }
        if (masked) _bindShadowMask(pass, maskedShadowShader, node.material);
        drawNode(pass, node, kind, drawMatrices[cascade], own: own);
      }
    }

    /// Draws [cascade]'s see-through casters into [pass], over the walls
    /// [drawCasters] left there — `ShadowSettings.translucentCasters`.
    void drawSeeThrough(CommandEncoder pass, int cascade) {
      final shader = transmittanceShader;
      if (shader == null) return;
      final tile = tileOf(cascade);
      final casterFrustum = cascadeFrusta[cascade];
      var stated = false;
      int? boundKind;
      for (final node in meshes) {
        if (!seeThrough(node) || !_drawsIntoCascade(node, casterFrustum)) {
          continue;
        }
        if (!stated) {
          pass.setState(
            Renderer._kShadowTransmittanceState.copyWith(
              viewport: PassViewport.ofRect(tile),
              scissor: tile,
            ),
          );
          stated = true;
        }
        final kind = node is InstancedMeshNode
            ? 2
            : node.skeleton != null
            ? 1
            : 0;
        final own = _bindDepthPassStage(pass, node, shader);
        if (own != null) {
          boundKind = null;
        } else if (boundKind != kind) {
          pass.bindPipeline(switch (kind) {
            2 =>
              _instancedTransmittanceShadowPipeline ??= device
                  .createPipelineFrom(
                    PipelineDescriptor(
                      vertex: _instancedVertexShader,
                      fragment: shader,
                      layout: _kInstancedLayout,
                    ),
                  ),
            1 =>
              _skinnedTransmittanceShadowPipeline ??= device.createPipelineFrom(
                PipelineDescriptor(
                  vertex: _skinnedVertexShader,
                  fragment: shader,
                ),
              ),
            _ => _transmittanceShadowPipeline ??= device.createPipelineFrom(
              PipelineDescriptor(vertex: _vertexShader, fragment: shader),
            ),
          });
          boundKind = kind;
        }
        final material = node.material;
        final extensions = material.extensions;
        // Encoded, as the transmittance has always been tinted by.
        final color = material.baseColorEncoded;
        final ior = extensions?.ior ?? 1.5;
        final f0 = (ior - 1.0) / (ior + 1.0);
        final transmits = (extensions?.transmission ?? 0.0) > 0.0;
        // **What reaches the far side of a transmitting body is the colour of
        // its depth, not of its surface** — glTF's transmission and volume:
        // the base colour tints what is transmitted, and the attenuation
        // colour is what is left after [MaterialExtensions.attenuationDistance]
        // of it, raised to the thickness over that distance. A solution's
        // shadow comes out the deep colour light through it really is. And
        // a transmitting material's alpha says how it looks, not that light
        // goes round it, so it is taken as wholly there: read as coverage it
        // let a fifth of the sun through untinted, and washed the colour out.
        var tint = vm.Vector3(color.r, color.g, color.b);
        if (transmits) {
          final distance = extensions!.attenuationDistance;
          final thickness = extensions.thickness;
          if (distance.isFinite && distance > 0.0 && thickness > 0.0) {
            final depth = thickness / distance;
            final through = extensions.attenuationColor;
            tint = vm.Vector3(
              tint.x * math.pow(through.r.clamp(0.0, 1.0), depth),
              tint.y * math.pow(through.g.clamp(0.0, 1.0), depth),
              tint.z * math.pow(through.b.clamp(0.0, 1.0), depth),
            );
          }
        }
        _transmittanceInfo.color
          ..[0] = tint.x
          ..[1] = tint.y
          ..[2] = tint.z
          ..[3] = transmits
              ? 1.0
              : material.isTransparent
              ? color.a
              : 1.0;
        _transmittanceInfo.light
          ..[0] = -aim.x
          ..[1] = -aim.y
          ..[2] = -aim.z
          ..[3] = 0.0;
        final transmission = material.extensions?.transmission ?? 0.0;
        _transmittanceInfo.params
          ..[0] = transmission
          ..[1] = f0 * f0
          // Its light stopped here and given back by its photons.
          ..[2] = refracts(node) ? 1.0 : 0.0
          ..[3] = 0.0;
        pass
          ..bindBlock(shader, _transmittanceInfo)
          // What it lets through, painted: white for a material with no map.
          ..bindTexture(
            shader,
            _kAlbedoTextureSlot,
            material.albedo ?? fallbackAlbedo,
            sampler: SamplerDescriptor.linearClamp,
          );
        drawNode(pass, node, kind, drawMatrices[cascade], own: own);
      }
    }

    /// Blanks [cascade]'s tile by a draw, since a clear would take the kept
    /// tiles with it. Colour only; the depth was cleared by the pass.
    void resetTile(CommandEncoder pass, int cascade) {
      final tile = tileOf(cascade);
      pass.setState(
        Renderer._kShadowTileResetState.copyWith(
          viewport: PassViewport.ofRect(tile),
          scissor: tile,
        ),
      );
      pass.bindPipeline(
        // The cube atlas's own: the same stages into the same format.
        _cubeShadowResetPipeline ??= device.createPipelineFrom(
          PipelineDescriptor(
            vertex: resetVertexShader!,
            fragment: resetShader!,
          ),
        ),
      );
      pass.bindVertexBuffer(_fullscreenTriangle, 3);
      pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
      pass.draw();
      _frameCounters?.drawCalls++;
    }

    CommandEncoder open(
      TextureHandle target, {
      required bool load,
      bool transmittance = false,
    }) => _turnDepth(
      device.beginRenderPass(
        RenderPassDescriptor(
          label: _passLabel,
          colors: <ColorTarget>[
            ColorTarget(
              texture: target,
              // Cleared to the far plane, so anything the pass does not draw
              // reads as "nothing between here and the light" — or, since
              // `S1`, kept, when some tiles still hold this frame's
              // picture. The depth is cleared either way: it lives only as
              // long as the pass, and a kept tile draws nothing that would
              // test against it.
              //
              // With see-through casters the frame's atlas clears to
              // (1, 0, 0, 1) instead: the far plane, nothing taken from red
              // or green, all of blue left — the layout
              // `shadow_transmittance.frag` explains.
              //
              // Turned round — `A2.8` — the far plane is nought, in red and in
              // the depth both.
              clearValue: transmittance
                  ? ClearColor(reversed ? 0.0 : 1.0, 0.0, 0.0, 1.0)
                  : ClearColor(reversed ? 0.0 : 1.0, 1.0, 1.0, 1.0),
              loadAction: load ? LoadAction.load : LoadAction.clear,
            ),
          ],
          depth: DepthTarget(
            texture: depth,
            clearValue: _DepthConvention._farDepth(reversed: reversed),
          ),
        ),
      ),
      reversed: reversed,
    );

    developer.Timeline.startSync('Renderer.shadowPass');

    /// [source]'s tile of [cascade] into [pass]'s, colour and depth, moved
    /// by [scroll] when there is one.
    ///
    /// [outside] reads every texel from outside the source tile, which
    /// writes "nothing" — how a turned-round tile is reset, from a [source]
    /// that is never really read and must not be the atlas being drawn.
    void copyTile(
      CommandEncoder pass,
      TextureHandle source,
      int cascade, [
      _Scroll? scroll,
      bool outside = false,
    ]) {
      final tile = tileOf(cascade);
      pass.setState(
        Renderer._kShadowCopyState.copyWith(
          viewport: PassViewport.ofRect(tile),
          scissor: tile,
        ),
      );
      pass.bindPipeline(
        _shadowCopyPipeline ??= device.createPipelineFrom(
          PipelineDescriptor(vertex: copyVertexShader!, fragment: copyShader!),
        ),
      );
      _shadowCopyInfo.tile
        ..[0] = count > 1 ? cascade / count : 0.0
        ..[1] = 0.0
        ..[2] = 1.0 / count
        ..[3] = 1.0;
      // Turned round, the move along the light is the other way in what is
      // stored, and the copy is told the map's mode — `shadow_copy.frag`.
      final dz = scroll?.dz ?? 0.0;
      _shadowCopyInfo.shift
        ..[0] = outside ? 2.0 : (scroll?.du ?? 0.0)
        ..[1] = outside ? 2.0 : (scroll?.dv ?? 0.0)
        ..[2] = reversed ? -dz : dz
        ..[3] = reversed ? 1.0 : 0.0;
      pass
        ..bindBlock(copyShader!, _shadowCopyInfo)
        ..bindTexture(
          copyShader,
          'static_shadow_texture',
          source,
          sampler: SamplerDescriptor.nearestClamp,
        )
        ..bindVertexBuffer(_fullscreenTriangle, 3)
        ..bindIndexBuffer(_identityIndices(3), IndexType.int32, 3)
        ..draw();
      _frameCounters?.drawCalls++;
    }

    /// `ShadowSettings.caustics` for [cascade]: its opaque depth copied out,
    /// each refracting caster's near and far faces drawn into maps of its
    /// own, and one photon per texel of them followed through it and added
    /// back into the tile where it lands. See `caustic_photon.vert`.
    void followPhotons(int cascade) {
      final frustum = cascadeFrusta[cascade];
      final casters = <MeshNode>[
        for (final node in meshes)
          if (refracts(node) && _drawsIntoCascade(node, frustum)) node,
      ];
      if (casters.isEmpty) return;

      // The tile's opaque depth, where photons land, in a texture of its own:
      // the atlas cannot be read by the pass that draws into it.
      final depthCopy = resources.transient(
        RenderTargetDescriptor(
          width: resolution,
          height: resolution,
          format: hdrFormat,
        ),
      );
      final copyDepth = resources.transient(
        RenderTargetDescriptor(
          width: resolution,
          height: resolution,
          format: device.defaultDepthStencilFormat,
          storageMode: StorageMode.deviceTransient,
        ),
      );
      final whole = ScreenRect(width: resolution, height: resolution);
      final copyPass = device.beginRenderPass(
        RenderPassDescriptor(
          label: _passLabel,
          colors: <ColorTarget>[
            ColorTarget(
              texture: depthCopy,
              clearValue: ClearColor(1.0, 0.0, 0.0, 1.0),
            ),
          ],
          depth: DepthTarget(texture: copyDepth),
        ),
      );
      final copyShader = shaders['ShadowCopy']!;
      _shadowCopyInfo.tile
        ..[0] = count > 1 ? cascade / count : 0.0
        ..[1] = 0.0
        ..[2] = 1.0 / count
        ..[3] = 1.0;
      // Mode two from a turned-round atlas: the photons compare against the
      // depth as drawn, so the copy turns it back on the way.
      _shadowCopyInfo.shift
        ..[0] = 0.0
        ..[1] = 0.0
        ..[2] = 0.0
        ..[3] = reversed ? 2.0 : 0.0;
      copyPass
        ..setState(
          Renderer._kShadowCopyState.copyWith(
            viewport: PassViewport.ofRect(whole),
            scissor: whole,
          ),
        )
        ..bindPipeline(
          _shadowCopyPipeline ??= device.createPipelineFrom(
            PipelineDescriptor(
              vertex: shaders['FullscreenVertex']!,
              fragment: copyShader,
            ),
          ),
        )
        ..bindBlock(copyShader, _shadowCopyInfo)
        ..bindTexture(
          copyShader,
          'static_shadow_texture',
          _shadowMap!,
          sampler: SamplerDescriptor.nearestClamp,
        )
        ..bindVertexBuffer(_fullscreenTriangle, 3)
        ..bindIndexBuffer(_identityIndices(3), IndexType.int32, 3)
        ..draw();
      copyPass.submit();
      _frameCounters?.drawCalls++;

      final photons = settings.causticPhotons.clamp(8, 512);
      final raw = rawMatrices[cascade];
      final surfacePipeline = _causticSurfacePipeline ??= device
          .createPipelineFrom(
            PipelineDescriptor(
              vertex: _vertexShader,
              fragment: causticSurface!,
            ),
          );

      final maps =
          <
            ({
              MeshNode node,
              TextureHandle front,
              TextureHandle back,
              vm.Matrix4 toMap,
              double width,
              double height,
            })
          >[];
      for (final node in casters) {
        // The caster's footprint in the cascade's clip space, a little
        // padded, and the cascade's matrix cropped to it.
        final box = node.worldBounds;
        var x0 = double.infinity, x1 = -double.infinity;
        var y0 = double.infinity, y1 = -double.infinity;
        for (var corner = 0; corner < 8; corner++) {
          final p = raw.transform(
            vm.Vector4(
              corner & 1 == 0 ? box.min.x : box.max.x,
              corner & 2 == 0 ? box.min.y : box.max.y,
              corner & 4 == 0 ? box.min.z : box.max.z,
              1.0,
            ),
          );
          x0 = math.min(x0, p.x / p.w);
          x1 = math.max(x1, p.x / p.w);
          y0 = math.min(y0, p.y / p.w);
          y1 = math.max(y1, p.y / p.w);
        }
        final padX = (x1 - x0) * 0.02, padY = (y1 - y0) * 0.02;
        x0 = math.max(x0 - padX, -1.0);
        x1 = math.min(x1 + padX, 1.0);
        y0 = math.max(y0 - padY, -1.0);
        y1 = math.min(y1 + padY, 1.0);
        if (x1 - x0 < 1e-6 || y1 - y0 < 1e-6) continue;
        final crop = vm.Matrix4.identity()
          ..setEntry(0, 0, 2.0 / (x1 - x0))
          ..setEntry(1, 1, 2.0 / (y1 - y0))
          ..setEntry(0, 3, -(x1 + x0) / (x1 - x0))
          ..setEntry(1, 3, -(y1 + y0) / (y1 - y0));
        final cropped = crop.multiplied(raw);
        final drawCropped = toDepthRange(cropped, device.depthRange);
        final sampleCropped = toFramebufferOrigin(
          cropped,
          device.framebufferOrigin,
        );

        TextureHandle face({required bool near}) {
          final target = resources.transient(
            RenderTargetDescriptor(
              width: photons,
              height: photons,
              format: hdrFormat,
            ),
          );
          final depth = resources.transient(
            RenderTargetDescriptor(
              width: photons,
              height: photons,
              format: device.defaultDepthStencilFormat,
              storageMode: StorageMode.deviceTransient,
            ),
          );
          final facePass = device.beginRenderPass(
            RenderPassDescriptor(
              label: _passLabel,
              colors: <ColorTarget>[
                ColorTarget(
                  texture: target,
                  // No surface: a depth past the far plane for the near
                  // faces, before the near one for the far faces.
                  clearValue: near
                      ? ClearColor(0.0, 0.0, 0.0, 1.0)
                      : ClearColor.transparentBlack,
                ),
              ],
              depth: DepthTarget(texture: depth, clearValue: near ? 1.0 : 0.0),
            ),
          );
          final square = ScreenRect(width: photons, height: photons);
          facePass
            ..setState(
              PassState(
                primitiveType: PrimitiveType.triangle,
                viewport: PassViewport.ofRect(square),
                scissor: square,
                cullMode: near ? CullMode.backFace : CullMode.frontFace,
                depthWrite: true,
                depthCompare: near
                    ? CompareFunction.less
                    : CompareFunction.greater,
              ),
            )
            ..bindPipeline(surfacePipeline);
          drawNode(facePass, node, 0, drawCropped);
          facePass.submit();
          return target;
        }

        maps.add((
          node: node,
          front: face(near: true),
          back: face(near: false),
          toMap: sampleCropped,
          width: x1 - x0,
          height: y1 - y0,
        ));
      }
      if (maps.isEmpty) return;

      // The photons, into the tile.
      final tile = tileOf(cascade);
      final photonPass = open(_shadowMap!, load: true);
      final quad = _causticQuad ??= device.uploadGeometry(
        Float32List.fromList(<double>[
          -1.0, -1.0, 1.0, -1.0, 1.0, 1.0, //
          -1.0, -1.0, 1.0, 1.0, -1.0, 1.0,
        ]).buffer.asByteData(),
        GeometryUsage.vertices,
      );
      photonPass
        ..setState(
          Renderer._kCausticPhotonState.copyWith(
            viewport: PassViewport.ofRect(tile),
            scissor: tile,
          ),
        )
        ..bindPipeline(
          _causticPhotonPipeline ??= device.createPipelineFrom(
            PipelineDescriptor(
              vertex: photonVertex!,
              fragment: photonFragment!,
            ),
          ),
        )
        ..bindVertexBuffer(quad, 6)
        ..bindIndexBuffer(_identityIndices(6), IndexType.int32, 6);
      final texel = 2.0 / resolution;
      for (final map in maps) {
        final material = map.node.material;
        final extensions = material.extensions!;
        final ior = math.max(extensions.ior, 1.0);
        final f0 = (ior - 1.0) / (ior + 1.0);
        // The least a photon's quad reaches either way: two texels, or a
        // photon gathered to a point falls between texel centres.
        final least = 2.0 * texel;
        final distance = extensions.attenuationDistance;
        _causticInfo.mapToWorld.setAll(
          0,
          vm.Matrix4.inverted(map.toMap).storage,
        );
        _causticInfo.worldToMap.setAll(0, map.toMap.storage);
        _causticInfo.worldToTile.setAll(0, shaderMatrices[cascade].storage);
        _causticInfo.worldToClip.setAll(0, drawMatrices[cascade].storage);
        _causticInfo.grid
          ..[0] = photons.toDouble()
          ..[1] = least
          ..[2] = map.width / photons
          ..[3] = map.height / photons;
        _causticInfo.light
          ..[0] = aim.x
          ..[1] = aim.y
          ..[2] = aim.z
          ..[3] = 0.0;
        _causticInfo.optics
          ..[0] = ior
          ..[1] = f0 * f0
          ..[2] = distance.isFinite && distance > 0.0 ? distance : 0.0
          ..[3] = 0.0;
        final transmission = extensions.transmission;
        _causticInfo.tint
          ..[0] = transmission * material.baseColorEncoded.r
          ..[1] = transmission * material.baseColorEncoded.g
          ..[2] = transmission * material.baseColorEncoded.b
          ..[3] = 0.0;
        _causticInfo.attenuation
          ..[0] = extensions.attenuationColor.r
          ..[1] = extensions.attenuationColor.g
          ..[2] = extensions.attenuationColor.b
          ..[3] = 0.0;
        photonPass
          ..bindBlock(photonVertex!, _causticInfo)
          ..bindTexture(
            photonVertex,
            'caustic_front',
            map.front,
            sampler: SamplerDescriptor.nearestClamp,
          )
          ..bindTexture(
            photonVertex,
            'caustic_back',
            map.back,
            sampler: SamplerDescriptor.nearestClamp,
          )
          ..bindTexture(
            photonVertex,
            'caustic_depth',
            depthCopy,
            sampler: SamplerDescriptor.nearestClamp,
          )
          ..draw(instanceCount: photons * photons);
        _frameCounters?.drawCalls++;
      }
      photonPass.submit();
    }

    developer.Timeline.startSync('Renderer.shadowPass');
    if (split && staticModes.any((mode) => mode != _StaticTile.keep)) {
      // Into the spare atlas, every tile: a kept one copied across, a
      // scrolled one copied across moved and its new strips drawn, the rest
      // drawn whole. A texture cannot be read and written in one pass, which
      // is the whole reason there are two.
      final source = _shadowMapStatic;
      final staticPass = open(_shadowMapStaticSpare!, load: false);
      for (var cascade = 0; cascade < count; cascade++) {
        switch (staticModes[cascade]) {
          case _StaticTile.keep:
            copyTile(staticPass, source!, cascade);
          case _StaticTile.scroll:
            final scroll = scrolls[cascade]!;
            copyTile(staticPass, source!, cascade, scroll);
            drawCasters(staticPass, cascade, only: true, within: scroll.strips);
          case _StaticTile.redraw:
            drawCasters(staticPass, cascade, only: true);
        }
        _directionalStaticBaked[cascade] = staticKeys[cascade];
        _staticShaderMatrices[cascade] = vm.Matrix4.copy(
          shaderMatrices[cascade],
        );
        _staticRawMatrices[cascade] = vm.Matrix4.copy(rawMatrices[cascade]);
      }
      staticPass.submit();
      final spare = _shadowMapStatic;
      _shadowMapStatic = _shadowMapStaticSpare;
      _shadowMapStaticSpare = spare;
      _staticSceneKey = staticScene;
    }

    final pass = open(_shadowMap!, load: keep, transmittance: transmits);
    for (var cascade = 0; cascade < count; cascade++) {
      if (!dirty[cascade]) continue;
      if (split) {
        // The static tile, into colour and depth, so the dynamic casters that
        // follow test against the walls already there.
        copyTile(pass, _shadowMapStatic!, cascade);
        drawCasters(pass, cascade, only: false);
      } else {
        // Turned round, "nothing" is nought, which the cube atlas's reset
        // does not write. The copy stage does for a source it reads wholly
        // outside the tile — the strip a scroll brings in — and the depth it
        // writes beside it is the far plane the pass was cleared to.
        if (keep && reversed) {
          copyTile(pass, fallbackBlack, cascade, null, true);
        } else if (keep) {
          resetTile(pass, cascade);
        }
        drawCasters(pass, cascade);
      }
      drawSeeThrough(pass, cascade);
    }
    pass.submit();
    if (caustics) {
      for (var cascade = 0; cascade < count; cascade++) {
        if (dirty[cascade]) followPhotons(cascade);
      }
    }
    developer.Timeline.finishSync();
    _shadowMapVersion++;

    publishShadowParams();
    return true;
  }

  /// Where the directional map looks this frame: the casters' bounds, the
  /// light's aim, the cascades along the view and one matrix for each,
  /// written into the fields the lit draws read. Null when there is nothing
  /// to fit — no casters, a scene of no size, a light with no aim.
  ///
  /// **Apart from the drawing so a producer can take the drawing's place**
  /// (D22): [_renderShadowMap] fits with this and then either draws the
  /// casters itself or hands the fit to the technique's
  /// `ShadowTechnique.shadowMapProducer`. Moved, not rewritten: every number
  /// is the one the single method computed.
  _ShadowFit? _fitShadowMap({
    required FrameResources resources,
    required Scene scene,
    required ShadowSettings settings,
    required int casterIndex,
    required CameraNode? camera,
    required bool reversed,
  }) {
    // Casters only. The last cascade is fitted to this, so anything counted
    // here that cannot cast a shadow spends texels on nothing: a sky dome or a
    // camera-locked backdrop would blow the volume out to its own radius and
    // coarsen every shadow in the level without contributing a single one.
    final bounds = scene.computeBounds(castersOnly: true);
    if (!bounds.min.x.isFinite) return null;

    final sceneCentre = (bounds.min + bounds.max)..scale(0.5);
    final sceneRadius = ((bounds.max - bounds.min)..scale(0.5)).length;
    if (sceneRadius <= 0.0) return null;

    // The light's aim, taken from the packed buffer so the pass sees the same
    // direction the shading does.
    final aim = vm.Vector3(
      _frameLights.directions[casterIndex * 4],
      _frameLights.directions[casterIndex * 4 + 1],
      _frameLights.directions[casterIndex * 4 + 2],
    );
    if (aim.length2 < 1e-12) return null;
    aim.normalize();

    // **How deep the casters are along the light, which is not how wide.**
    // The box's own extent along the aim, half of it: the sphere round the
    // casters is the right width for a map that has to hold them whichever
    // way it turns, and too deep by the ratio of the two. A valley 880 m
    // square under a sun 40° up is 620 m to its corners and 360 m along the
    // light, and the depth one stored step stands for, the bias's floor, is
    // in proportion. Only depth is fitted to it; the tiles keep the sphere.
    final half = (bounds.max - bounds.min)..scale(0.5);
    final sceneDepth = math.min(
      aim.x.abs() * half.x + aim.y.abs() * half.y + aim.z.abs() * half.z,
      sceneRadius,
    );

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
    // The technique's count, which is `settings.cascades` for every
    // built-in filter.
    final count = _directionalTechnique(
      settings,
    ).cascadesFor(settings).clamp(1, 3);

    // Where each cascade looks, and how much it covers.
    //
    // **The last one is always the whole scene**, which is what makes this safe
    // rather than clever: a fragment the near cascades do not reach falls
    // through to a map that is exactly the one this renderer has always drawn,
    // so nothing is ever left unshadowed by a gap between volumes.
    final centers = <vm.Vector3>[];
    final radii = <double>[];
    final splits = <double>[0.0, 0.0];

    final orthographic = switch (camera?.projection) {
      final OrthographicProjection projection => projection,
      _ => null,
    };
    if (count > 1 && camera != null && orthographic != null) {
      // `P7`: **slabs along the view axis, for a lens whose rays are
      // parallel.** The spheres below grow with distance from the eye because
      // a perspective view widens with it; an orthographic one is as wide at
      // every depth, so a near cascade sized by distance covered the air in
      // front of the camera and everything fell to the last, softest one.
      // Here each cascade is a slab of the view's box, from where the casters
      // begin: even in depth — a texel covers the same world at every depth,
      // so there is nothing for a logarithm to follow — and as wide as the
      // frame's half-diagonal, from the frame's own aspect. `shadow.glsl` picks one by depth along
      // the axis to match.
      final eyeAt = camera.readViewOrigin();
      final forward = camera.readForward();
      final aspect = resources.frameHeight > 0
          ? resources.frameWidth / resources.frameHeight
          : 1.0;
      final halfHeight = orthographic.height * 0.5;
      final across = halfHeight * math.sqrt(1.0 + aspect * aspect);
      // The depth the casters span *within the frame*, not the scene's: an
      // orthographic camera is usually stood well back from a level far
      // larger than its view, and slabs from its near plane, or across the
      // whole level, spend the near cascades on air and on ground nobody can
      // see. Read off five rays down the view's axis — through its middle
      // and its four corners — each clipped by the casters' box. Something
      // standing between the rays and outside their depths still falls
      // through to the last cascade, so this costs sharpness, never coverage.
      final m = camera.worldMatrix.storage;
      final right = vm.Vector3(m[0], m[1], m[2])..normalize();
      final up = vm.Vector3(m[4], m[5], m[6])..normalize();
      final halfWidth = halfHeight * aspect;
      final seen = <(double, double)>[
        for (final (x, y) in const <(double, double)>[
          (0.0, 0.0),
          (-1.0, -1.0),
          (1.0, -1.0),
          (-1.0, 1.0),
          (1.0, 1.0),
        ])
          ?_rayThroughBox(
            eyeAt + right.scaled(x * halfWidth) + up.scaled(y * halfHeight),
            forward,
            bounds.min,
            bounds.max,
          ),
      ];
      final centreDepth = (sceneCentre - eyeAt).dot(forward);
      final (nearest, furthest) = seen.isEmpty
          ? (centreDepth - sceneRadius, centreDepth + sceneRadius)
          : seen.reduce((a, b) => (math.min(a.$1, b.$1), math.max(a.$2, b.$2)));
      final start = math.max(orthographic.near, nearest);
      // The length taken as itself rather than as `end - start`, which in
      // doubles comes back a bit either side of the reach as `start` moves:
      // at a reach that is a power of two, that is a grid step twice as long.
      final length = math.max(
        math.min(
          math.min(orthographic.far, furthest) - start,
          math.max(settings.viewDistance, 1.0),
        ),
        1.0,
      );
      // **Both ends on a grid** — see [_cascadeQuantum]. What the slabs are
      // fitted to slides with every pan and every caster that rises or
      // falls, and the snap below keeps a map's texels still only while its
      // radius is.
      final step = _cascadeQuantum(length);
      final low = (start / step).floorToDouble() * step;
      final high = ((start + length) / step).ceilToDouble() * step;
      // All of it to the near slabs: the last cascade is the whole scene
      // either way, and a fragment the frame shows should not need it.
      final slabs = count - 1;
      for (var i = 0; i < slabs; i++) {
        final from = low + (high - low) * i / slabs;
        final to = low + (high - low) * (i + 1) / slabs;
        splits[i] = to;
        final half = (to - from) * 0.5;
        centers.add(eyeAt + forward.scaled(from + half));
        radii.add(_roundUpToQuantum(math.sqrt(across * across + half * half)));
      }
    } else if (count > 1 && camera != null) {
      final eyeAt = camera.readViewOrigin();
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
        centers.add(eyeAt + forward.scaled(atEnd * 0.55));
        radii.add(atEnd * 0.9);
      }
    }
    centers.add(sceneCentre);
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
    // The engine's own, unadjusted: what the frusta and a scroll's strips
    // are cut from.
    final rawMatrices = <vm.Matrix4>[];

    for (var i = 0; i < centers.length; i++) {
      final radius = radii[i];
      var center = centers[i];

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
      final inLight = snapFrame.transformed3(center.clone());
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
      center = back.transformed3(inLight);

      if (i == 0) _shadowCascadeCentres.clear();
      _shadowCascadeCentres.add(center.clone());

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
      final last = i == centers.length - 1;
      // The last cascade is as deep as the casters are along the light; a
      // near one is its own sphere's depth on this side of its centre.
      final ownDepth = last ? sceneDepth * padding : ownReach;
      var distance = ownDepth;
      if (!last) {
        final reach = (center - sceneCentre).dot(aim) + sceneDepth;
        if (reach > distance) {
          distance = (reach / texelWorld).ceilToDouble() * texelWorld;
        }
      }
      // The bias keeps the metres it has always had — `ShadowSettings.bias`
      // of the sphere's own depth — whatever range the cascade is drawn over.
      final range = distance + ownDepth - 0.01;
      _shadowCascadeBiasScale[i] = (ownReach + ownReach - 0.01) / range;
      _shadowCascadeDepthRange[i] = range;
      final eye = center - aim.scaled(distance);
      final view = Renderer._lookAt(eye, center, up);
      final projection = OrthographicProjection(
        height: radius * 2.0 * padding,
        near: 0.01,
        far: distance + ownDepth,
      ).toMatrix(1.0);

      final matrix = vm.Matrix4.copy(projection)..multiply(view);
      // `A2.8`: drawn turned round when the map stores it so, and only drawn:
      // what the lit stages and the static tiles' scrolls compute with stays
      // the ordinary matrix, and `lib/shadow_storage.glsl` turns the stored
      // depth back.
      drawMatrices.add(
        toDepthRange(
          reversed ? toReversedDepth(matrix) : matrix,
          device.depthRange,
        ),
      );
      shaderMatrices.add(toFramebufferOrigin(matrix, device.framebufferOrigin));
      cascadeFrusta.add(vm.Frustum.matrix(matrix));
      rawMatrices.add(matrix);
    }

    _shadowMatrix.setFrom(shaderMatrices.first);
    _shadowMatrixFar.setFrom(shaderMatrices[math.min(1, count - 1)]);
    _shadowMatrixFarthest.setFrom(shaderMatrices[count - 1]);
    _shadowDrawMatrix.setFrom(drawMatrices.first);

    return _ShadowFit(
      aim: aim,
      count: count,
      resolution: resolution,
      splits: splits,
      drawMatrices: drawMatrices,
      shaderMatrices: shaderMatrices,
      cascadeFrusta: cascadeFrusta,
      rawMatrices: rawMatrices,
    );
  }

  /// The directional atlas into blurred exponential moments — `S2`.
  ///
  /// Two passes of [filter], the stage [prefilter] names, over the whole
  /// atlas: across, warping depth as it reads, into
  /// [_shadowMomentsScratch]; then down, into [_shadowMoments]. Skipped when
  /// the atlas has not been drawn into since the moments were last made,
  /// which with `S1`'s static half is most frames of a still camera.
  ///
  /// Two atlases the size of the depth one at sixteen bytes a texel, where
  /// the depth atlas is eight: at the default three 1024 tiles, 50 MB each.
  /// The price of [ShadowFilter.evsm], and a reason it is not the default.
  TextureHandle _renderShadowMoments(
    TextureHandle depth,
    ShadowPrefilter prefilter,
    ShaderHandle filter,
  ) {
    final radius = prefilter.radius.clamp(0, 8);
    final key = (_shadowMapVersion, radius, _shadowCascadeCount, filter.name);
    final current = _shadowMoments;
    if (current != null &&
        _shadowMomentsKey == key &&
        current.width == depth.width &&
        current.height == depth.height) {
      return current;
    }

    RenderTargetDescriptor spec() => RenderTargetDescriptor(
      width: depth.width,
      height: depth.height,
      format: TextureFormat.r32g32b32a32Float,
    );
    if (current == null ||
        current.width != depth.width ||
        current.height != depth.height) {
      // Sampled by the lit draws of frames still in flight, so handed back
      // once they are done, as the depth atlas is.
      _destroyAfterFrame(_shadowMoments);
      _destroyAfterFrame(_shadowMomentsScratch);
      _shadowMoments = device.createTexture(spec());
      _shadowMomentsScratch = device.createTexture(spec());
    }
    final moments = _shadowMoments!;
    final scratch = _shadowMomentsScratch!;

    developer.Timeline.startSync('Renderer.shadowMoments');
    final texelU = 1.0 / math.max(depth.width, 1);
    final texelV = 1.0 / math.max(depth.height, 1);
    _evsmFilterInfo.tile
      ..[0] = _shadowCascadeCount.toDouble()
      ..[1] = 0.5 * texelU
      ..[2] = 0.5 * texelV
      // `A2.8`: how the depth atlas stores its depth, which the warp undoes.
      ..[3] = _shadowStorage;

    /// One axis of the blur, from [source] into [target].
    void blur(
      TextureHandle source,
      TextureHandle target, {
      required bool across,
    }) {
      _evsmFilterInfo.axis
        ..[0] = across ? texelU : 0.0
        ..[1] = across ? 0.0 : texelV
        ..[2] = radius.toDouble()
        ..[3] = across ? 1.0 : 0.0;
      drawFullscreen(
        FullscreenDraw(
          target: target,
          fragment: filter,
          textures: <String, TextureHandle>{'evsm_source': source},
          uniforms: <String, Map<String, Float32List>>{
            _evsmFilterInfo.name: _evsmFilterInfo.members,
          },
          // Nearest: every tap lands on a texel centre, and depth must not be
          // blended across a silhouette before it is warped — the average of
          // two warped depths is the point, the warp of an average is not.
          sampler: SamplerDescriptor.nearestClamp,
        ),
      );
    }

    blur(depth, scratch, across: true);
    blur(scratch, moments, across: false);
    developer.Timeline.finishSync();
    _shadowMomentsKey = key;
    return moments;
  }

  /// How the static tile drawn with [oldShader] moves to [newShader]'s — `S1`
  /// — or null when it cannot be scrolled: the two views differ by more than
  /// a move, or the move is not whole texels of a [resolution]-texel tile.
  ///
  /// A cascade is fitted round a centre snapped to whole texels in the
  /// light's frame, so a camera that walks moves it by whole texels across
  /// and by some amount along the light; across is a shift of the picture,
  /// along is the same amount added to every depth it holds.
  static _Scroll? _scrollBetween(
    vm.Matrix4 oldShader,
    vm.Matrix4 newShader,
    vm.Matrix4 oldRaw,
    vm.Matrix4 newRaw,
    int resolution,
  ) {
    final inverse = vm.Matrix4.copy(oldShader);
    if (inverse.invert() == 0.0) return null;
    final d = (vm.Matrix4.copy(newShader)..multiply(inverse)).storage;
    const eps = 1e-5;
    for (var column = 0; column < 3; column++) {
      for (var row = 0; row < 4; row++) {
        final want = column == row ? 1.0 : 0.0;
        if ((d[column * 4 + row] - want).abs() > eps) return null;
      }
    }
    if ((d[15] - 1.0).abs() > eps) return null;
    final du = d[12] * 0.5;
    final dv = -d[13] * 0.5;
    final texelsU = du * resolution;
    final texelsV = dv * resolution;
    if ((texelsU - texelsU.roundToDouble()).abs() > 1e-3 ||
        (texelsV - texelsV.roundToDouble()).abs() > 1e-3 ||
        du.abs() >= 1.0 ||
        dv.abs() >= 1.0) {
      return null;
    }

    // The strips that came into view, in the engine's own clip space, and a
    // texel wider than they are so a caster at their edge is not missed.
    final rawInverse = vm.Matrix4.copy(oldRaw)..invert();
    final r = (vm.Matrix4.copy(newRaw)..multiply(rawInverse)).storage;
    final margin = 2.0 / resolution;
    final strips = <vm.Frustum>[];
    vm.Frustum band(int axis, double from, double to) {
      final lo = math.max(from - margin, -1.0);
      final hi = math.min(to + margin, 1.0);
      final squeeze = vm.Matrix4.identity();
      final at = axis == 0 ? 0 : 5;
      squeeze.storage[at] = 2.0 / (hi - lo);
      squeeze.storage[axis == 0 ? 12 : 13] = -(hi + lo) / (hi - lo);
      return vm.Frustum.matrix(squeeze..multiply(newRaw));
    }

    for (final axis in <int>[0, 1]) {
      final shift = r[axis == 0 ? 12 : 13];
      if (shift > 1e-9) strips.add(band(axis, -1.0, -1.0 + shift));
      if (shift < -1e-9) strips.add(band(axis, 1.0 + shift, 1.0));
    }
    return _Scroll(du: du, dv: dv, dz: d[14], strips: strips);
  }
}

/// What a static cascade tile does in a frame — `S1`.
enum _StaticTile { keep, scroll, redraw }

/// A static tile's move — `S1`: how far back, in the tile's own texture
/// coordinates, a texel's picture was, what the move added to its depth, and
/// the volumes of the strips that came into view.
final class _Scroll {
  const _Scroll({
    required this.du,
    required this.dv,
    required this.dz,
    required this.strips,
  });

  /// Across, in the tile's UV: a fraction of its width.
  final double du;

  /// Down, in the tile's UV: a fraction of its height.
  final double dv;

  /// In the shadow map's clip space depth.
  final double dz;
  final List<vm.Frustum> strips;
}

/// A step for rounding a length of about [length]: a sixteenth of the power
/// of two at or above it — `P7`'s orthographic slabs.
///
/// **Rounded, because the fit moves with everything.** An orthographic
/// view's near slabs are fitted to where the frame meets the casters, which
/// slides with every pan of the camera and every caster that rises or falls
/// — a character jumping is enough. The shadow pass snaps each map to whole
/// texels of its radius, and a radius that changes every frame is a texel
/// grid that rescales every frame: shadow edges crawl, and the scroll that
/// keeps a still tile from being redrawn refuses a map whose scale changed.
/// On steps a sixteenth of the length's power of two the radii and the slab
/// ends stay put until the fit has moved by a whole step, and a radius
/// rounded up is at most an eighth longer than it needs to be.
///
/// The power of two is found by doubling and halving, exactly, rather than
/// by a logarithm, whose last bit at a power of two is the platform's.
double _cascadeQuantum(double length) {
  final target = math.max(length, 1e-3);
  var power = 1.0;
  while (power < target) {
    power *= 2.0;
  }
  while (power * 0.5 >= target) {
    power *= 0.5;
  }
  return power / 16.0;
}

/// [length] rounded up onto its [_cascadeQuantum].
double _roundUpToQuantum(double length) {
  final step = _cascadeQuantum(length);
  return (length / step).ceilToDouble() * step;
}

/// Where the ray from [origin] along [direction] (unit length) is inside the
/// box [min]–[max], as distances along it — or null when it misses. The slab
/// test, clamped to what lies ahead of [origin].
(double, double)? _rayThroughBox(
  vm.Vector3 origin,
  vm.Vector3 direction,
  vm.Vector3 min,
  vm.Vector3 max,
) {
  var enter = 0.0;
  var leave = double.infinity;
  for (var axis = 0; axis < 3; axis++) {
    final o = origin[axis];
    final d = direction[axis];
    if (d.abs() < 1e-12) {
      if (o < min[axis] || o > max[axis]) return null;
      continue;
    }
    final a = (min[axis] - o) / d;
    final b = (max[axis] - o) / d;
    enter = math.max(enter, math.min(a, b));
    leave = math.min(leave, math.max(a, b));
  }
  return enter <= leave ? (enter, leave) : null;
}

/// What [Renderer._fitShadowMap] decided for one frame's directional map.
final class _ShadowFit {
  const _ShadowFit({
    required this.aim,
    required this.count,
    required this.resolution,
    required this.splits,
    required this.drawMatrices,
    required this.shaderMatrices,
    required this.cascadeFrusta,
    required this.rawMatrices,
  });

  /// The light's direction, unit length.
  final vm.Vector3 aim;

  /// Cascades, one to three, side by side in the atlas.
  final int count;

  /// One tile's side, in texels.
  final int resolution;

  /// Where along the view the near cascades end.
  final List<double> splits;

  /// Each cascade's matrix as the device draws with it.
  final List<vm.Matrix4> drawMatrices;

  /// Each cascade's matrix as the lit stages read it.
  final List<vm.Matrix4> shaderMatrices;

  /// The volume each cascade covers, for the caster cull.
  final List<vm.Frustum> cascadeFrusta;

  /// The engine's own matrices, unadjusted for the device.
  final List<vm.Matrix4> rawMatrices;
}

/// What [Renderer._fitCubeShadow] decided for one row of the cube atlas.
final class _CubeFit {
  const _CubeFit({
    required this.position,
    required this.range,
    required this.shaderMatrices,
    required this.drawMatrices,
  });

  /// Where the light is, in world space.
  final vm.Vector3 position;

  /// How far it reaches, in metres.
  final double range;

  /// Each face's matrix as the lit stages read it: six for a point light,
  /// one for a spot.
  final List<vm.Matrix4> shaderMatrices;

  /// Each face's matrix as the device draws with it.
  final List<vm.Matrix4> drawMatrices;
}

/// [ShadowCubeAtlas.lights] as a technique is handed them: the rows the
/// frame's fit holds, fitted the first time anything reads the list, so
/// asking a technique that never looks costs nothing. Unmodifiable, as the
/// list it stands for always was.
final class _FittedCubeLights extends ListBase<ShadowCubeLight> {
  _FittedCubeLights(this._fits);

  final List<_CubeFit?> Function() _fits;

  late final List<ShadowCubeLight> _lights = <ShadowCubeLight>[
    for (final (row, fit) in _fits().indexed)
      if (fit != null)
        ShadowCubeLight(
          row: row,
          position: fit.position.clone(),
          range: fit.range,
          viewProjections: List<vm.Matrix4>.unmodifiable(fit.drawMatrices),
        ),
  ];

  @override
  int get length => _lights.length;

  @override
  set length(int value) =>
      throw UnsupportedError('the cube atlas\'s lights cannot be changed');

  @override
  ShadowCubeLight operator [](int index) => _lights[index];

  @override
  void operator []=(int index, ShadowCubeLight value) =>
      throw UnsupportedError('the cube atlas\'s lights cannot be changed');
}
