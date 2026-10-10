/// Encoding one mesh node into an open pass: pipeline, uniforms, textures,
/// draw.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// Split out of `renderer_scene_pass.dart` along the seam the code already
/// names: [_encodeNode] is "extracted so the view-model pass draws through
/// exactly the same code as the scene" — it is a self-contained procedure over
/// one node, called both from the scene pass's per-view loop and, through
/// `Renderer.encodeScene`, from any contributor drawing ordinary geometry
/// somewhere unordinary. Everything it touches is a renderer field or an
/// argument; nothing here is specific to iterating views or building a render
/// list, which is what stayed behind.
part of 'renderer.dart';

/// What the x-ray stage swaps in when it draws a node again.
///
/// A material for the node's own, and a blend the material cannot express:
/// [BlendState.keepDestination] is not an alpha mode, and the marking draw
/// needs it to leave the picture alone. Depth is not here because the
/// material already carries it — `depthWrite` and `depthCompare` are the two
/// fields a backdrop asked for, and a silhouette wants exactly those two.
final class _DrawOverride {
  const _DrawOverride({
    required this.material,
    required this.blend,
    this.fogged = false,
  });

  final RenderMaterial material;

  /// Null is blending off, as it is on `setBlend`.
  final BlendState? blend;

  /// Whether the frame's fog reaches the draw. Not for a silhouette, which
  /// is a marker; yes for a planar reflection, which is light leaving a
  /// surface and crosses the same air the surface's own light does.
  final bool fogged;
}

/// Writes [transform] into [out] at [at] as the two rows `MapUv` reads — `C8`.
///
/// `KHR_texture_transform`'s own order, the one `withTextureTransform` bakes
/// with: scale, then rotate, then move. Null is the identity, whose rows read
/// a coordinate back unchanged. The rotation is counter-clockwise in a texture
/// whose `v` runs down, as `withTextureTransform` turns it.
void _writeUvTransform(Float32List out, int at, TextureTransform? transform) {
  final (cosine, sine, scale, offset) = switch (transform) {
    null => (1.0, 0.0, vm.Vector2(1.0, 1.0), vm.Vector2.zero()),
    final t => (math.cos(t.rotation), math.sin(t.rotation), t.scale, t.offset),
  };
  out
    ..[at] = cosine * scale.x
    ..[at + 1] = sine * scale.y
    ..[at + 2] = offset.x
    ..[at + 3] = 0.0
    ..[at + 4] = -sine * scale.x
    ..[at + 5] = cosine * scale.y
    ..[at + 6] = offset.y
    ..[at + 7] = 0.0;
}

/// How a node is drawn — see [_MeshEncode._opaqueRoute].
///
/// Constants rather than an enum, for the rule every published package
/// keeps: these are compared, never switched over.
final class _OpaqueRoute {
  // A name each, which is also what keeps the three apart: const instances
  // with nothing in them would be one instance.
  const _OpaqueRoute._(this.name);

  final String name;

  /// One draw, as every node was drawn before `A1.2`.
  static const draw = _OpaqueRoute._('draw');

  /// The depth pre-draw, then the lit draw tested `equal`.
  static const predraw = _OpaqueRoute._('predraw');

  /// Not at all this frame: the smaller share of a fade that cannot be
  /// pre-drawn.
  static const skip = _OpaqueRoute._('skip');
}

/// Which of a node's draws [_MeshEncode._encodeNode] is encoding — `A1.2`,
/// `A1.3`. Constants rather than an enum, as [_OpaqueRoute] is.
final class _DrawPhase {
  const _DrawPhase._(this.name);

  final String name;

  /// The node, decided here: one draw, or the two below.
  static const whole = _DrawPhase._('whole');

  /// Depth only, where the cut or the fade keeps the surface; no colour.
  static const predraw = _DrawPhase._('predraw');

  /// The lit draw after a pre-draw, tested `equal` against what it wrote,
  /// through the lighting model's opaque variant where there is one.
  static const afterPredraw = _DrawPhase._('afterPredraw');
}

/// [kernel] as the one number the lit stages read it from,
/// `ambient_ground.w` (`lib/shadow.glsl` says why it rides there): nought
/// for the 3×3 box, the light's radius above nought for the blocker search,
/// and minus one less the bleed cut for the moments tap. A moments kernel in
/// a frame with no moments ([hasMoments] false) is the box, the fallback a
/// refused prefilter draws.
double _shadowKernelSlot(ShadowKernel kernel, {required bool hasMoments}) =>
    switch (kernel.name) {
      'moments' when hasMoments =>
        -1.0 - kernel.bleedReduction.clamp(0.0, 0.95),
      'blockerSearch' when kernel.lightRadius > 0.0 => kernel.lightRadius,
      _ => 0.0,
    };

extension _MeshEncode on Renderer {
  /// Binds the morph state for a draw through one of the mesh vertex stages.
  ///
  /// **Every path that binds `FrameInfo` has to call this**, and that is the
  /// price of putting the deltas in a texture: `lib/morph.glsl` is included by
  /// all four mesh vertex stages, so the block and the sampler are declared on
  /// every pipeline they build, and a stage whose block nobody wrote reads
  /// whatever was in that memory. The first time this was missed the shadow and
  /// pick passes still bound `FrameInfo` and not this, and the browser drew
  /// shadows displaced by a garbage weight — 217 pixels out where 8 is the
  /// budget — while Impeller happened to see zeros and looked fine.
  ///
  /// One helper rather than the same six lines in four places, for the reason
  /// this file already gives about the material binding: two copies of a
  /// binding eventually disagree, and the disagreement arrives as a picture
  /// nobody can explain.
  /// Whether [stage] keeps [block]: what its compiled bundle says, and
  /// [declared] only where the device cannot say — `gfx-92n`.
  bool _keepsBlock(
    ShaderHandle stage,
    String block, {
    required bool declared,
  }) => stage.kept?.blocks.contains(block) ?? declared;

  /// Whether [stage] keeps [sampler], as [_keepsBlock].
  bool _keepsSampler(
    ShaderHandle stage,
    String sampler, {
    required bool declared,
  }) => stage.kept?.samplers.contains(sampler) ?? declared;

  void _bindMorph(PassEncoder pass, ShaderHandle stage, [MorphState? morph]) {
    final count = morph == null
        ? 0
        : (morph.targetCount < _morphWeights.length
              ? morph.targetCount
              : _morphWeights.length);

    for (var i = 0; i < _morphWeights.length; i++) {
      _morphWeights[i] = i < count ? morph!.weights[i] : 0.0;
    }
    _morphParams[0] = count.toDouble();
    // One texel across and one down, so the shader can reach a texel centre
    // without `textureSize` — which is a second thing that would have to
    // survive the compiler that crashes on `texelFetch`. Nought when there is
    // nothing to read, which the count already stops.
    _morphParams[1] = morph == null ? 0.0 : 1.0 / morph.texture.width;
    _morphParams[2] = morph == null ? 0.0 : 1.0 / morph.texture.height;

    pass
      ..bindBlock(stage, _morphInfo)
      ..bindTexture(
        stage,
        'morph_texture',
        morph?.texture ?? fallbackAlbedo,
        // Nearest and clamped: the coordinate names a texel centre exactly, and
        // a filtered read would blend a vertex with its neighbour — a model
        // that shimmers along its own index order.
        sampler: SamplerDescriptor.nearestClamp,
      );
  }

  /// Binds the per-instance weights for a draw through the *instanced* stage.
  ///
  /// Called only for that stage, and always for it: `MorphInstanceInfo` and
  /// `morph_instance_weights` are declared on it and on nothing else, so
  /// binding them elsewhere is a phantom sampler and not binding them here is
  /// a block nobody wrote — the two ways this repository has already found to
  /// draw a wrong picture with no error anywhere.
  ///
  /// A batch with no per-instance weights still binds: the flag goes to nought,
  /// the shader falls through to the batch-wide uniform, and the sampler holds
  /// a stand-in it never reads.
  void _bindInstanceMorph(
    PassEncoder pass,
    ShaderHandle stage,
    InstancedMeshNode? batch,
  ) {
    final texture = batch?.instanceMorphWeights(device);
    _morphInstanceParams[0] = texture == null ? 0.0 : 1.0;
    _morphInstanceParams[1] = texture == null ? 0.0 : 1.0 / texture.width;
    _morphInstanceParams[2] = texture == null ? 0.0 : 1.0 / texture.height;

    pass
      ..bindBlock(stage, _morphInstanceInfo)
      ..bindTexture(
        stage,
        'morph_instance_weights',
        texture ?? fallbackAlbedo,
        sampler: SamplerDescriptor.nearestClamp,
      );
  }

  /// Encodes one mesh node into an open pass.
  ///
  /// Extracted so the view-model pass draws through exactly the same code as
  /// the scene. The alternative was a second copy of the material binding, and
  /// that binding is where the phantom-sampler trap lives: a shader that never
  /// reads a texture has no slot for it, and binding one anyway is a native
  /// crash rather than a no-op. Two copies of that would eventually disagree,
  /// and the disagreement would arrive as a segfault with no Dart stack.
  void _encodeNode({
    required PassEncoder encoder,
    required MeshNode node,
    required Scene scene,
    required RenderSettings settings,
    required vm.Matrix4 viewProjection,
    required SceneShadows shadows,
    // A parameter shadowing the renderer's field on purpose: the scene pass
    // hands the frame's buffer and slot table in, and `encodeScene` hands in
    // whatever its scene actually holds. Read from the field they were wrong
    // for every scene that was not the world's — the view model's studio
    // lights went unbound, and its light indices read the world's slot rows.
    required LightBuffer lights,
    required Float32List shadowSlots,
    required FramePassState state,
    // The x-ray stage's, and null for every other caller: the node is drawn
    // with a different material and a blend its alpha mode cannot say, and
    // the rest of this procedure — pipeline, matrices, skinning, instancing,
    // the texture slots the model declares — is exactly what it must not
    // grow a second copy of.
    _DrawOverride? override,
    // The probes this draw may reflect, answered by the calling node the way
    // the shadows are. None by default: the view model and a probe's own
    // capture both draw without one.
    _SceneProbes probes = _SceneProbes.none,
    // Whether the view-projection mirrors the picture. A probe's face is drawn
    // through one — see `probeFaceViewProjection` — and a mirror reverses
    // which way every triangle winds, so the winding set below flips with it.
    bool mirrored = false,
    // `R8`'s, and null for every other draw: a transparent draw into the
    // weighted blended targets takes their blends instead of its material's,
    // and writes no depth whatever the material says. See
    // `renderer_transparency_pass.dart`.
    _OrderIndependentBlend? orderIndependent,
    // `A1.2`: which of the node's draws this is. A caller always says
    // `whole`, and this decides whether that is one draw or two.
    _DrawPhase phase = _DrawPhase.whole,
  }) {
    final mesh = node.mesh;
    // The scene deals in MeshGeometry so that culling and picking need no
    // device; only here does it matter that the geometry actually reached
    // the GPU. A CPU-only mesh in a drawn scene is a bug in the caller,
    // not something to skip quietly.
    if (mesh is! DrawableGeometry) {
      throw StateError(
        'MeshNode "${node.name}" holds ${mesh.runtimeType}, which has no '
        'GPU buffers. Upload it with DeviceMesh.upload before drawing it.',
      );
    }
    final material = override?.material ?? node.material;

    // `A1.2`, `A1.3`: a cut or a fade is made by the depth pre-draw, and the
    // lit draw follows it tested `equal` — two draws through this procedure,
    // so the second binds everything the first did and nothing can differ.
    if (phase == _DrawPhase.whole) {
      final route = _opaqueRoute(
        node,
        material,
        state: state,
        overridden: override != null,
        orderIndependent: orderIndependent != null,
      );
      if (route == _OpaqueRoute.skip) return;
      if (route == _OpaqueRoute.predraw) {
        for (final step in const <_DrawPhase>[
          _DrawPhase.predraw,
          _DrawPhase.afterPredraw,
        ]) {
          _encodeNode(
            encoder: encoder,
            node: node,
            scene: scene,
            settings: settings,
            viewProjection: viewProjection,
            shadows: shadows,
            lights: lights,
            shadowSlots: shadowSlots,
            state: state,
            override: override,
            probes: probes,
            mirrored: mirrored,
            orderIndependent: orderIndependent,
            phase: step,
          );
        }
        return;
      }
    }
    final predraw = phase == _DrawPhase.predraw;
    final afterPredraw = phase == _DrawPhase.afterPredraw;

    final skeleton = node.skeleton;
    final skinned = skeleton != null;
    // A batch draws its instances in one call from a third vertex stage; a
    // batch with nothing in it draws nothing, and binding for it would leave
    // the pass state describing a pipeline no draw used.
    final instanced = node is InstancedMeshNode ? node : null;
    if (instanced != null && instanced.count == 0) return;
    final batched = instanced != null;
    // `C9`: the clusters of a split mesh this view can see, repacked, or null
    // to draw it whole. Before anything is bound, so a mesh with none in view
    // leaves the pass as it found it.
    final clustered = override == null && !mirrored && orderIndependent == null
        ? _clusterIndicesFor(node, mesh, material, settings)
        : null;
    if (clustered != null && clustered.count == 0) return;
    // A level's batches read their colour as a lightmap coordinate; neither
    // a skinned mesh nor an instanced one is a level, so the flag is ignored
    // where it cannot apply rather than asserted against. Nor is a
    // silhouette: an override draws through the plain stage, whose clip
    // position is the same arithmetic, rather than linking a fourth pipeline
    // for a term the flat colour never reads.
    final lightmapped =
        node.lightmapped && !skinned && !batched && override == null;
    // `A1.2`: the lighting model's opaque variant wherever nothing this draw
    // does needs the cut — an opaque material, one whose edge is coverage,
    // and the lit half of a pre-drawn one — and the model has one.
    final opaqueStage =
        !predraw &&
        override == null &&
        orderIndependent == null &&
        node.tint.a >= 1.0 &&
        (afterPredraw ||
            material.alphaMode == MaterialAlphaMode.opaque ||
            (material.alphaMode == MaterialAlphaMode.mask &&
                material.alphaToCoverage &&
                state.coverageAvailable)) &&
        _opaqueStageFor(material.lighting) != null;
    // The stage the pipeline is built with; see where `FrameInfo` is bound.
    final activeVertexShader = batched
        ? _instancedVertexShader
        : _vertexShaderFor(
            material.lighting,
            skinned: skinned,
            lightmapped: lightmapped,
          );
    if (predraw) {
      encoder.bindPipeline(
        _predrawPipelines[activeVertexShader] ??= device.createPipeline(
          activeVertexShader,
          shaders['DepthPredraw']!,
          layout: batched ? _kInstancedLayout : null,
        ),
      );
      // The tracker describes the lit pipelines, and this replaced one.
      state.invalidatePipeline();
      state.pipelineSwitches++;
    } else if (state.boundPipeline != material.lighting ||
        state.boundSkinned != skinned ||
        state.boundInstanced != batched ||
        state.boundLightmapped != lightmapped ||
        state.boundOpaque != opaqueStage) {
      encoder.bindPipeline(
        _pipelineFor(
          material.lighting,
          skinned: skinned,
          instanced: batched,
          lightmapped: lightmapped,
          opaque: opaqueStage,
        ),
      );
      state.boundPipeline = material.lighting;
      state.boundSkinned = skinned;
      state.boundInstanced = batched;
      state.boundLightmapped = lightmapped;
      state.boundOpaque = opaqueStage;
      state.pipelineSwitches++;
    }

    // Both matrices are cached on the node and keyed on its transform
    // version, so a static object costs nothing here.
    final modelMatrix = node.worldMatrix;
    final normalMatrix = node.worldNormalMatrix;

    encoder.setWindingOrder(
      node.isWorldMirrored != mirrored
          ? WindingOrder.clockwise
          : WindingOrder.counterClockwise,
    );
    final cull =
        settings.backfaceCulling &&
        !settings.wireframe &&
        !material.doubleSided;
    encoder.setCullMode(cull ? CullMode.backFace : CullMode.none);

    final blend =
        material.alphaMode == MaterialAlphaMode.blend || node.tint.a < 1.0;
    if (predraw) {
      // Depth only: the colour is the lit draw's to write.
      encoder.setBlend(BlendState.keepDestination);
    } else if (orderIndependent == null) {
      // `RenderMaterial.blendMode` for a material that blends; a fade of an
      // opaque one by its node's tint is over, as it always was.
      final blendState = !blend
          ? null
          : material.isTransparent
          ? _MaterialStages._blendFor(material)
          : BlendState.alphaBlend;
      encoder.setBlend(override != null ? override.blend : blendState);
      // `RenderMaterial.effectsDepth`: the surface buffer written whole while the
      // colour blends, where the device can blend the two apart. Put back
      // after the draw.
      if (override == null &&
          blendState != null &&
          material.effectsDepth &&
          device.features.has(DeviceFeature.independentBlend)) {
        encoder.setBlend(null, attachment: 1);
      }
    } else {
      // Attachment zero first, then one: on WebGL2 the first call sets every
      // draw buffer, and only the second is for one buffer alone.
      encoder.setBlend(orderIndependent.first);
      if (orderIndependent.second case final second?) {
        encoder.setBlend(second, attachment: 1);
      }
    }
    // Transparent surfaces must not occlude what is behind them — unless the
    // material has an opinion, which is how a backdrop says it is drawn but
    // is not there. Never under weighted blended transparency: a layer that
    // wrote depth would hide the layers drawn after it and not those drawn
    // before, which is the order the targets exist to forget.
    //
    // `A1.2`: the pre-draw writes the depth the lit draw after it is tested
    // `equal` against, and that draw then has nothing to write.
    encoder.setDepthWrite(
      enabled:
          predraw ||
          (!afterPredraw &&
              orderIndependent == null &&
              (material.depthWrite ?? !blend)),
    );

    // Only when it changes. A scene where nothing overrides the test never
    // emits this call, so the pass's own `less` stands and every frame the
    // golden sets were recorded from is byte-identical.
    // `RenderMaterial.depthLayer`: a layered surface passes at its own depth, so
    // the later of two coplanar faces wins where no bias separates them.
    final depthLayered = override == null && material.depthLayer != 0;
    final depthCompare = afterPredraw
        ? CompareFunction.equal
        : (material.depthCompare ??
              (depthLayered
                  ? CompareFunction.lessEqual
                  : CompareFunction.less));
    if (state.depthCompare != depthCompare) {
      encoder.setDepthCompare(depthCompare);
      state.depthCompare = depthCompare;
    }

    encoder.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
    final indexCount = clustered?.count ?? mesh.indexCount;
    encoder.bindIndexBuffer(
      clustered?.buffer ?? mesh.indices,
      mesh.indexType,
      indexCount,
    );

    if (instanced != null) {
      encoder.bindVertexData(instanced.instanceBytes, instanced.count, slot: 1);
    }
    // **[activeVertexShader] is the stage the pipeline was built with,
    // including one a material brought — `gfx-86n`.** This used to pick among
    // the engine's own four and bind `FrameInfo` through `MeshVertex` even
    // when the pipeline's vertex stage was somebody else's. The software
    // backend binds a block by name for the whole pass and never noticed; a
    // backend that resolves the slot through the handle it was given was
    // writing into the engine's stage's layout and landing in the right place
    // only because a stage that copies `FrameInfo` from `mesh.vert` puts it at
    // the same index. A stage that declares a block of its own — the
    // polyline's viewport — would not.
    //
    // Typed, because `Matrix4.operator*` returns `dynamic`: without the
    // annotation `.storage` here is an unchecked call on an untyped value,
    // and a typo in it would compile and fail at the draw.
    final vm.Matrix4 mvp = viewProjection * modelMatrix;
    _frameInfo.mvp.setAll(0, mvp.storage);
    _frameInfo.model.setAll(0, modelMatrix.storage);
    _frameInfo.normalMatrix.setAll(0, normalMatrix.storage);
    encoder.bindBlock(activeVertexShader, _frameInfo);
    // Version 2's vertex block: the view-projection its `world` output is
    // projected through. Its parameters are bound below with the rest.
    if (!batched && !lightmapped) {
      _bindMaterialVertex(
        encoder,
        activeVertexShader,
        material,
        viewProjection,
        parameters: false,
      );
    }
    // `RenderMaterial.depthLayer`, where the device has a depth bias: a layered
    // surface pulled towards the eye by its layer, reset after its draws.
    final layerBias =
        depthLayered && device.features.has(DeviceFeature.depthBias)
        ? _depthLayerBias(material.depthLayer)
        : null;
    if (layerBias != null) encoder.setDepthBias(layerBias);

    // Always for the engine's own mesh stages, even when nothing morphs: all
    // four declare the block and the sampler. See [_bindMorph].
    //
    // **A material's own stage when it says it declares them**, which is
    // `LightingModel.vertexStageMorphs`. `PolylineVertex` declares neither,
    // and binding the morph texture to it is a thrown "Failed to bind
    // texture" on Impeller at the first draw of every `RenderMaterial.polyline`.
    // 0.7.2 keyed this on whether the node morphed instead, which left a stage
    // written from `mesh.vert` without its block on every plain mesh. Asking
    // the node is the wrong question: a stage declares what it declares.
    final ownStage =
        !batched && !lightmapped && material.lighting.vertexShaderName != null;
    if (_keepsBlock(
      activeVertexShader,
      _kMorphInfoBlock,
      declared: !ownStage || material.lighting.vertexStageMorphs,
    )) {
      _bindMorph(encoder, activeVertexShader, node.morph);
    }
    if (batched) _bindInstanceMorph(encoder, activeVertexShader, instanced);

    if (skeleton != null) {
      // Recomputed here rather than by the caller: the matrices depend on
      // the mesh node's own world transform, which is exactly what the
      // renderer is holding at this point.
      skeleton.update(modelMatrix);
      _skinInfo.jointMatrices.setAll(0, skeleton.matrices);
      encoder.bindBlock(activeVertexShader, _skinInfo);
      state.skinnedDraws++;
    }

    // **A material's own vertex stage reads its parameters too — `gfx-86n`.**
    // They were bound to the fragment stage alone, which is where every stage
    // a material could supply used to be; since `gfx-75n` a material can bring
    // the vertex half as well, and a vertex stage has things to be told — a
    // wave height, a wind, the viewport a line is widened against. Only a
    // stage the material brought: the engine's own read `FrameInfo` and
    // nothing else, and a material naming no vertex stage draws exactly as it
    // did, which is why no golden could move.
    if (material.parameters.isNotEmpty &&
        material.lighting.vertexShaderName != null &&
        !batched) {
      encoder.bindUniformBlock(
        activeVertexShader,
        material.parameterBlock,
        material.parameters,
      );
    }

    // `A1.2`: the pre-draw's fragment half — the cut, the fade, no colour —
    // and then nothing more to bind; the lit half of the node follows as its
    // own draw.
    if (predraw) {
      // Coverage off: the stage writes alpha nought, which turned into
      // coverage would leave the pre-draw covering no sample and writing no
      // depth, and the lit draw's `equal` would pass nowhere.
      if (state.alphaToCoverage) {
        encoder.setAlphaToCoverage(enabled: false);
        state.alphaToCoverage = false;
      }
      _encodePredrawFragment(
        encoder: encoder,
        node: node,
        material: material,
        settings: settings,
        state: state,
      );
      encoder.draw(instanceCount: instanced?.count ?? 1);
      if (layerBias != null) encoder.setDepthBias(DepthBias.none);
      state.drawCalls++;
      state.journal?.add(
        kind: 'predraw',
        node: node,
        mesh: node.name,
        material: material.name,
        lighting: 'DepthPredraw',
        vertices: mesh.vertexCount,
        indices: indexCount,
        instances: instanced?.count ?? 1,
        state: <String, Object?>{
          'cull': cull ? 'back' : 'none',
          'blend': 'keep',
          'depthWrite': true,
          'depthCompare': depthCompare.name,
          'lodFade': node.lodFade,
        },
        uniforms: <String, Float32List>{
          'mvp': Float32List.fromList(mvp.storage),
          'mask': Float32List.fromList(_predrawInfo.mask),
        },
      );
      return;
    }

    final fragmentShader = _fragmentShaderFor(
      material.lighting,
      opaque: opaqueStage,
    );

    // Gated on model metadata, not reflection: a shader that only DECLARES
    // FragInfo still reports it with a non-zero size while the compiled
    // function binds no buffer, and binding that segfaults inside Metal.
    // Only when there is a real cube *and* the device can hold one: on a
    // backend with no cube support the fallback is null too, and a level
    // count with nothing bound is the branch this exists to avoid.
    //
    // The nearest probe first, where one reaches this node: a probe is the
    // room the object is actually in, and the scene's environment is the sky
    // it may not be able to see. One per object and no blending — see
    // `_SceneProbes.nearest`.
    //
    // **A lightmapped draw reads no probe**, and that is the same "one term or
    // the other, never both" rule the ambient strength above follows. A
    // lightmap *is* this surface's indirect light, measured per texel and
    // baked; a probe's roughest level is a coarser guess at the same quantity,
    // and the shader adds the lightmap on top of the environment rather than
    // choosing between them, so a wall that took both would count the room's
    // bounce twice. The walls keep the bake, which is finer than a probe can
    // be, and the probe lights everything the bake does not reach: props,
    // enemies, anything skinned or batched — none of which carries a lightmap
    // coordinate, which is why the local `lightmapped` is the one asked here
    // rather than `node.lightmapped`. What a wall gives up is its specular
    // lobe, and a rough dielectric's is very nearly nothing.
    final readsEnvironment = _keepsSampler(
      fragmentShader,
      _kEnvironmentTextureSlot,
      declared: material.lighting.usesEnvironment,
    );
    final probe = readsEnvironment && !lightmapped
        ? probes.nearest(node.worldBoundsCenter)
        : null;
    final environment =
        probe?.texture ?? scene.environment ?? _environmentFallback(device);
    final environmentLevels = probe != null
        ? probe.levels
        : scene.environment == null || environment == null
        ? 0
        : scene.environmentLevels;

    // Which of the scene's lights *this* draw is lit by. The frame's own eight
    // when they are all the scene has, and the eight that reach this object
    // when the scene holds more — the shader is handed eight slots either way,
    // which is why hundreds of lights need no new shader.
    //
    // Asked here rather than at the call sites because every caller draws
    // through this one procedure, and a second copy of the question would
    // eventually answer it differently for the x-ray stage than for the pass.
    final draw = _drawLightsFor(
      frameLights: lights,
      frameShadowSlots: shadowSlots,
      node: node,
      // `L6`: with cells, a light that leaves the slots is still in the
      // tail, so there is no edge to fade at.
      fadeBand: _clustersActive ? 0.0 : settings.lightFadeBand,
    );
    final drawLights = draw.lights;
    final drawShadowSlots = draw.shadowSlots;

    // **What the compiled stage kept decides, not what the model says —
    // `gfx-92n`.** Each gate below asks `ShaderHandle.kept`, which the
    // device fills from the bundle's own table for every stage of the
    // engine's, and falls back to the model's declared flag only for a stage
    // the device cannot answer for: one from an application's own bundle.
    // The flags were kept in step with the shaders by hand, and 0.7.1 was
    // the frame where one was not.
    if (_keepsBlock(
      fragmentShader,
      _kFragInfoBlock,
      declared: material.lighting.usesFragInfo,
    )) {
      if (node.isTinted) {
        // The base colour and the tint are both linear: multiplied where
        // light adds up, and handed over sRGB-encoded for the shader to
        // decode as it always does.
        final base = material.baseColor;
        final tint = node.tint;
        _baseColorData[0] = linearToSrgb(base.r * tint.r);
        _baseColorData[1] = linearToSrgb(base.g * tint.g);
        _baseColorData[2] = linearToSrgb(base.b * tint.b);
        _baseColorData[3] = base.a * tint.a;
      } else {
        final base = material.baseColorEncoded;
        _baseColorData[0] = base.r;
        _baseColorData[1] = base.g;
        _baseColorData[2] = base.b;
        _baseColorData[3] = base.a;
      }
      // `A1.3`: a see-through level part way through a cross-fade fades by
      // its opacity — the size of its share, whichever end it takes.
      if (blend && node.lodFade != 1.0) {
        _baseColorData[3] *= node.lodFade.abs().clamp(0.0, 1.0);
      }

      _emissiveData[0] = material.emissive.r;
      _emissiveData[1] = material.emissive.g;
      _emissiveData[2] = material.emissive.b;
      // A normal map with only x and y has its z rebuilt in the shader: the
      // sampler hands blue as zero, which read as it stands is a normal
      // pointing into the surface. The flag rides in emissive's unused w.
      _emissiveData[3] = switch (material.normal?.format) {
        TextureFormat.bc5RGUNormInt || TextureFormat.r8g8UNormInt => 1.0,
        _ => 0.0,
      };

      _materialData[0] = material.metallic;
      _materialData[1] = material.roughness;
      // The ambient strength, which is also the environment's — the shader
      // scales both by this one number and uses one *or* the other. A probe
      // brings its own: a captured room is read at the strength the frame drew
      // it, and the flat term a scene dims to six per cent is not consulted
      // while a probe is bound. See `ReflectionProbeNode.intensity`.
      _materialData[2] =
          probe?.intensity ?? luxToEngine(scene.ambientIntensity);
      _materialData[3] = settings.specular;

      // `P7`: a masked material's edge as multisample coverage, where the
      // pass and the device allow it, and its hard cutoff where they do not.
      final wantsCoverage =
          override == null &&
          material.alphaMode == MaterialAlphaMode.mask &&
          material.alphaToCoverage;
      final coverage = wantsCoverage && state.coverageAvailable;
      if (wantsCoverage && !coverage) state.coverageDeclined = true;
      if (coverage != state.alphaToCoverage) {
        encoder.setAlphaToCoverage(enabled: coverage);
        state.alphaToCoverage = coverage;
      }

      // A negative cutoff means "not masked". The shader compares against
      // it directly, so encoding the mode in the value keeps a branch and
      // a separate flag out of the uniform block.
      _material2Data[0] = switch (material.alphaMode) {
        // Above one is the cutoff plus one, with coverage — `P7`: the shader
        // keeps the fragment and sharpens its alpha rather than cutting.
        MaterialAlphaMode.mask when coverage => 1.0 + material.alphaCutoff,
        MaterialAlphaMode.mask => material.alphaCutoff,
        // `gfx-16n`'s sentinel. Below -1.5 is "hashed", which the shader
        // reads out of the same component: -1 already meant "not masked" and
        // anything more negative was free, where a second number would have
        // been a member added to a block six shaders share. How far below
        // -2 is the scene's origin — see `_hashedCutoffAt`.
        MaterialAlphaMode.hashed => _hashedCutoff,
        // Not masked either, and the one mode whose colour the shader weights
        // by its alpha: the blend takes its source premultiplied, and glTF's
        // blend is over on straight colour. Opaque keeps -1 and its colour
        // whole. See `g_premultiply` in `color.glsl`.
        MaterialAlphaMode.blend => -0.5,
        // Faded by its node's tint, an opaque material blends as a blended
        // one does.
        _ when node.tint.a < 1.0 => -0.5,
        _ => -1.0,
      };
      // Zero without a normal map of its own. The fallback's 0.5 lands on
      // byte 128, which decodes to 0.0039 rather than 0, so the flat normal
      // tilted every map-less surface by a third of a degree along its
      // tangent and made its shading depend on how the tangent ran.
      // Scaling xy to nothing leaves exactly (0, 0, 1) on every backend.
      _material2Data[1] = material.normal == null ? 0.0 : material.normalScale;
      _material2Data[2] = material.occlusionStrength;
      _material2Data[3] = nitsToEngine(material.emissiveStrength);

      _frameParams[0] = settings.cameraExposure;
      _frameParams[1] = drawLights.count.toDouble();
      // The caster's index in *this draw's* list, which the shader compares
      // its light loop against. A draw that re-gathered its lights — by
      // channel, or out of more than eight — has them in another order, and
      // the frame's index then named some other light or none: the sun's
      // shadow vanished and a lamp at that position was tested against the
      // sun's cascades instead.
      _frameParams[2] = switch (shadows.directional) {
        null => -1.0,
        _ when identical(drawLights, lights) => shadows.casterIndex.toDouble(),
        _
            when shadows.casterIndex < 0 ||
                shadows.casterIndex >= lights.packed.length =>
          -1.0,
        _ =>
          drawLights.packed
              .indexOf(lights.packed[shadows.casterIndex])
              .toDouble(),
      };
      // The slot `surface.glsl` reserved for a frame-wide parameter, now
      // spent: the environment's level count, and zero when there is none.
      // One number carrying both the roughness scale and the "is there one"
      // flag, so the shader needs no second uniform and no second branch.
      _frameParams[3] = environmentLevels.toDouble();

      // `gfx-15n`, and it rides here for the reason `surface.glsl` gives:
      // this is the last unspent component of a block six shaders share, and
      // the slot that was reserved for a frame-wide parameter went to the
      // line above. Zero keeps the 3×3 kernel every recorded golden holds.
      //
      // `S2`: the technique's kernel decides what rides here. Below zero is
      // the moments tap, with the light-bleeding cut as how far under minus
      // one — but only where the frame made the moments; a device that
      // refused them draws the 3×3 kernel rather than nothing. Above zero is
      // the blocker search, by the light's apparent radius.
      _ambientGround[3] = !settings.shadows.enabled
          ? 0.0
          : _shadowKernelSlot(
              settings.shadows.directionalTechnique.kernelFor(settings.shadows),
              hasMoments: shadows.directionalMoments != null,
            );

      // `ShadowSettings.translucentCasters`: whether this draw is shaded by
      // what the see-through casters let through, in the one spare
      // component of `shadow_bias`. Only when the atlas the shader reads is
      // the one that carries it — not the moments — and never for a surface
      // that is itself one of those casters, which would otherwise darken by
      // its own colour wherever it stands in its own shadow. A see-through
      // surface that casts nothing — a glazed floor, a water plane — is
      // shaded like any other.
      final castsThrough =
          node.shadowCasting.casts &&
          (node.material.isTransparent ||
              (node.material.extensions?.transmission ?? 0.0) > 0.0);
      _shadowCascadeBias[3] =
          _shadowTransmits &&
              node.receivesTranslucentShadows &&
              shadows.directional != null &&
              shadows.directionalMoments == null &&
              !castsThrough
          ? 1.0
          : 0.0;

      // Gated on the model, like every other block and sampler here. Unlit
      // declares FragInfo but reaches no lighting loop, so the compiler drops
      // all three of these — and binding a block the compiled shader does not
      // have is a native failure, not a no-op.
      if (_keepsBlock(
        fragmentShader,
        'PointShadow',
        declared: material.lighting.usesPointShadow,
      )) {
        _writePointShadowParams(settings);
        // The slots are this draw's own packing; everything else in the
        // block is the frame's, written where it was worked out.
        _pointShadow.slots.setAll(0, drawShadowSlots);
        encoder.bindBlock(fragmentShader, _pointShadow);
        encoder.bindTexture(
          fragmentShader,
          'point_shadow_texture',
          // Whatever the caller was given by the frame, not the renderer's own
          // field. Two nodes reach this code — the scene and the view model,
          // through `encodeScene` — so there is no single node whose
          // `tryTexture` could be asked *here*; each of them declares its own
          // read and answers with [SceneShadows], which is why that type exists.
          //
          // White where there is no atlas, which reads as "nothing between here
          // and the light", the same answer an unoccupied row gives.
          shadows.point ?? fallbackAlbedo,
          sampler: Renderer._clampSampler,
        );
        encoder.bindTexture(
          fragmentShader,
          'point_shadow_static_texture',
          shadows.pointStatic ?? fallbackAlbedo,
          sampler: Renderer._clampSampler,
        );
      }

      // **The irradiance field, per pixel — `L3`.** It replaces the
      // hemisphere ambient in the shader wherever the scene has a field, and
      // the atlas and its block are bound on every lit draw whether or not it
      // does: a declared sampler nobody binds is a native crash on Metal.
      if (_keepsBlock(
        fragmentShader,
        _irradianceInfo.name,
        declared: material.lighting.usesLightList,
      )) {
        _bindIrradiance(encoder, fragmentShader, scene);
      }

      // **Every lit draw, both halves — `gfx-74n`.** A draw with no tail binds
      // a count of nought and a one-by-one stand-in it never samples, because a
      // declared sampler nobody binds is a native crash on Metal and a declared
      // block nobody writes is the other way this repository has drawn a wrong
      // picture with no error anywhere.
      //
      // **Lit, and only lit.** The reverse is a crash too: an unlit stage
      // keeps neither half, and binding them was the first frame of every
      // unlit scene dying inside Metal's `setFragmentBuffer` on 0.7.0.
      if (_keepsBlock(
        fragmentShader,
        _kLightListBlock,
        declared: material.lighting.usesLightList,
      )) {
        _bindLightList(
          encoder,
          fragmentShader,
          drawLights,
          _buildLightList(lights),
        );
      }
      // The lights are this draw's selection and the cascade matrices are
      // vector_math's; everything else in the block is written in place.
      _fragInfo.lightPosition.setAll(0, drawLights.positions);
      _fragInfo.lightColor.setAll(0, drawLights.colors);
      _fragInfo.lightDirection.setAll(0, drawLights.directions);
      _fragInfo.lightCone.setAll(0, drawLights.cones);
      _fragInfo.shadowMatrix.setAll(0, _shadowMatrix.storage);
      _fragInfo.shadowMatrixFar.setAll(0, _shadowMatrixFar.storage);
      _fragInfo.shadowMatrixFarthest.setAll(0, _shadowMatrixFarthest.storage);
      // `A5.21`: the frame's debug views, or this subtree's own, and this
      // draw's identity for the views that colour by it.
      _writeDebugViewFor(node, material);
      encoder.bindBlock(fragmentShader, _fragInfo);
    }

    // Its own block, bound beside FragInfo rather than folded into it. See
    // the note in color.glsl: appending to a block six shaders share moves
    // offsets nobody expected to move.
    //
    // **Beside it, not inside its gate.** `color.glsl` declares it, so a stage
    // that reads no FragInfo still keeps it, and one that was drawn with it
    // unbound had no fog and a surface depth of nought — `loaded-shader`, on
    // every backend, with only WebGL2 saying so.
    //
    // None for a silhouette. Fog is a property of a surface in air, and a
    // silhouette is a marker: a sensor that lost its monsters to the far
    // end of a corridor would be a sensor with the corridor's own range.
    if (_keepsBlock(
      fragmentShader,
      _fogInfo.name,
      declared: material.lighting.usesFogInfo,
    )) {
      final fog = (override?.fogged ?? material.fogged)
          ? settings.fog
          : const FogSettings();
      _fogData[0] = fog.resolvedColor.r;
      _fogData[1] = fog.resolvedColor.g;
      _fogData[2] = fog.resolvedColor.b;
      _fogInfo.eye.setAll(0, _cameraData);
      // `P5`: the density at the eye, and the falloff in the eye's spare lane,
      // which is all `ApplyFog` needs to integrate a height fog along the ray.
      // A flat fog writes its density and nought, as it always did.
      _fogData[3] = fog.densityAt(_cameraData[1]);
      _fogInfo.eye[3] = fog.resolvedHeightFalloff;
      encoder.bindBlock(fragmentShader, _fogInfo);
    }

    // **The layers, for the one stage that reads them — `M1`.** A material
    // with none drawn with the layered model binds the defaults, which draw
    // plain metal-rough.
    final layered = identical(material.lighting, LightingModel.pbrLayered);
    if (_keepsBlock(fragmentShader, _layerInfo.name, declared: layered)) {
      final layers = material.extensions;
      _layerInfo.specular
        ..[0] = layers?.specularColor.r ?? 1.0
        ..[1] = layers?.specularColor.g ?? 1.0
        ..[2] = layers?.specularColor.b ?? 1.0
        ..[3] = layers?.specular ?? 1.0;
      _layerInfo.coat
        ..[0] = layers?.clearcoat ?? 0.0
        ..[1] = layers?.clearcoatRoughness ?? 0.0
        ..[2] = layers?.ior ?? 1.5;
      _layerInfo.sheen
        ..[0] = layers?.sheenColor.r ?? 0.0
        ..[1] = layers?.sheenColor.g ?? 0.0
        ..[2] = layers?.sheenColor.b ?? 0.0
        ..[3] = layers?.sheenRoughness ?? 0.0;
      final rotation = layers?.anisotropyRotation ?? 0.0;
      _layerInfo.anisotropy
        ..[0] = layers?.anisotropyStrength ?? 0.0
        ..[1] = math.cos(rotation)
        ..[2] = math.sin(rotation);
      // An infinite attenuation distance, the default, is nought here: the
      // stage reads nought as a medium that takes nothing away.
      final distance = layers?.attenuationDistance ?? double.infinity;
      // KHR_materials_volume measures the thickness in the mesh's own space,
      // so a node scaled up is that much thicker: the geometric mean of the
      // node's three axis scales, which is the scale itself for a uniform
      // one. A material shared by nodes of different sizes is bound per draw
      // here, so each refracts at its own.
      final m = modelMatrix.storage;
      final thicknessScale = math
          .pow(
            math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]) *
                math.sqrt(m[4] * m[4] + m[5] * m[5] + m[6] * m[6]) *
                math.sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10]),
            1.0 / 3.0,
          )
          .toDouble();
      _layerInfo.transmission
        ..[0] = layers?.transmission ?? 0.0
        ..[1] = (layers?.thickness ?? 0.0) * thicknessScale
        ..[2] = distance.isFinite ? distance : 0.0
        ..[3] = layers?.dispersion ?? 0.0;
      _layerInfo.attenuation
        ..[0] = layers?.attenuationColor.r ?? 1.0
        ..[1] = layers?.attenuationColor.g ?? 1.0
        ..[2] = layers?.attenuationColor.b ?? 1.0
        // `MaterialExtensions.convexVolume`, in the spare lane.
        ..[3] = (layers?.convexVolume ?? false) ? 1.0 : 0.0;
      _layerInfo.iridescence
        ..[0] = layers?.iridescence ?? 0.0
        ..[1] = layers?.iridescenceIor ?? 1.3
        ..[2] = layers?.iridescenceThicknessMaximum ?? 400.0;
      // `C8`: a matrix per map, the identity where the material names none.
      for (final map in MaterialMap.values) {
        _writeUvTransform(
          _layerInfo.uvTransform,
          map.index * 8,
          material.textureTransforms[map],
        );
      }
      encoder.bindBlock(fragmentShader, _layerInfo);
    }

    // Bound strictly according to the model's declared slots. The
    // compiler drops a sampler the shader never reads, and binding one
    // Metal does not have is a native crash rather than a no-op.
    // **An application's own parameters, bound after everything built in.**
    // Later so that a material cannot displace a block the engine depends on
    // by naming it: the encoder fills a block once, and the last fill wins.
    //
    // Unconditional, and the risk it carries is the material's own. A block
    // the compiled shader does not have is reported rather than bound, so a
    // material naming a block nobody reads costs nothing — but a block that
    // exists without a member the material named now throws, on every backend
    // that can see the difference. That is the contract as of today, and it
    // cuts the way an author wants: a parameter renamed in the GLSL and not in
    // the Dart used to draw with a zero in its place, on Impeller only.
    if (material.parameters.isNotEmpty) {
      encoder.bindUniformBlock(
        fragmentShader,
        material.parameterBlock,
        material.parameters,
      );
    }
    // Not safe in the same way, and the asymmetry is the encoder's: a sampler
    // slot a compiled shader does not have is a native crash. The material
    // that lists these is the same one that names the shader, so keeping the
    // two in step is the author's job — nothing here can check it.
    for (final slot in material.extraTextures.entries) {
      encoder.bindTexture(fragmentShader, slot.key, slot.value);
    }

    if (readsEnvironment && environment != null) {
      encoder.bindTexture(
        fragmentShader,
        _kEnvironmentTextureSlot,
        environment,
        sampler: Renderer._environmentSampler,
      );
    }
    // The material's own samplers, with the setting's anisotropy applied
    // where it applies — see `_anisotropic`. Clamped to the device here,
    // once for the up-to-five binds below. The lightmap and the shadow map
    // are not model textures and keep their clamped samplers as they are.
    final anisotropy = _anisotropyLevel(settings.anisotropy);
    if (_keepsSampler(
      fragmentShader,
      _kAlbedoTextureSlot,
      declared: material.lighting.usesAlbedoTexture,
    )) {
      encoder.bindTexture(
        fragmentShader,
        _kAlbedoTextureSlot,
        material.albedo ?? fallbackAlbedo,
        sampler: _anisotropic(material.albedoSampler, anisotropy),
      );
    }
    if (_keepsSampler(
      fragmentShader,
      _kNormalTextureSlot,
      declared: material.lighting.usesMaterialMaps,
    )) {
      encoder.bindTexture(
        fragmentShader,
        _kNormalTextureSlot,
        material.normal ?? fallbackNormal,
        sampler: _anisotropic(material.normalSampler, anisotropy),
      );
    }
    if (_keepsSampler(
      fragmentShader,
      _kOcclusionTextureSlot,
      declared: material.lighting.usesMaterialMaps,
    )) {
      encoder.bindTexture(
        fragmentShader,
        _kOcclusionTextureSlot,
        material.occlusion ?? fallbackAlbedo,
        sampler: _anisotropic(material.occlusionSampler, anisotropy),
      );
    }
    if (_keepsSampler(
      fragmentShader,
      _kEmissiveTextureSlot,
      declared: material.lighting.usesMaterialMaps,
    )) {
      encoder.bindTexture(
        fragmentShader,
        _kEmissiveTextureSlot,
        material.emissiveTexture ?? fallbackAlbedo,
        sampler: _anisotropic(material.emissiveSampler, anisotropy),
      );
    }
    // Black, not white: the lightmap is added, and a material without one
    // adds nothing. Bound for every lit model because the shader samples
    // the slot unconditionally, which is a texel cheaper than a branch and
    // the same arrangement every other map here uses.
    if (_keepsSampler(
      fragmentShader,
      _kLightmapTextureSlot,
      declared: material.lighting.usesMaterialMaps,
    )) {
      encoder.bindTexture(
        fragmentShader,
        _kLightmapTextureSlot,
        material.lightmap ?? fallbackBlack,
        sampler: material.lightmapSampler ?? Renderer._clampSampler,
      );
    }
    if (_keepsSampler(
      fragmentShader,
      _kShadowTextureSlot,
      declared: material.lighting.usesShadowMap,
    )) {
      encoder.bindTexture(
        fragmentShader,
        _kShadowTextureSlot,
        // With shadows off the slot still has to be satisfied, and a white
        // texture reads as "nothing between here and the light" — which is
        // also what the zero strength above already guarantees. The moments
        // in the map's place under `evsm` (`S2`), which the negative
        // softness packed above tells the shader to expect.
        shadows.directionalMoments ?? shadows.directional ?? fallbackAlbedo,
        sampler: Renderer._clampSampler,
      );
    }
    if (_keepsSampler(
      fragmentShader,
      _kMetallicRoughnessTextureSlot,
      declared: material.lighting.usesMetallicRoughnessMap,
    )) {
      encoder.bindTexture(
        fragmentShader,
        _kMetallicRoughnessTextureSlot,
        material.metallicRoughness ?? fallbackAlbedo,
        sampler: _anisotropic(material.metallicRoughnessSampler, anisotropy),
      );
    }
    // `L7`: the metal-rough model integrates its lobe over a rectangle
    // light from these; filtered, since the fit is smooth between entries.
    if (_keepsSampler(
      fragmentShader,
      _kLtcTextureSlot,
      declared: material.lighting.usesMetallicRoughnessMap,
    )) {
      encoder.bindTexture(
        fragmentShader,
        _kLtcTextureSlot,
        EngineTables.of(device).ltc,
        sampler: Renderer._clampSampler,
      );
    }
    if (_keepsSampler(fragmentShader, _kCoatTextureSlot, declared: layered)) {
      // White where there is no map, which leaves every factor as it is.
      encoder.bindTexture(
        fragmentShader,
        _kCoatTextureSlot,
        material.coatMap ?? fallbackAlbedo,
        sampler: _anisotropic(material.coatMapSampler, anisotropy),
      );
    }
    if (_keepsSampler(fragmentShader, _kSheenTextureSlot, declared: layered)) {
      encoder.bindTexture(
        fragmentShader,
        _kSheenTextureSlot,
        material.sheenMap ?? fallbackAlbedo,
        sampler: _anisotropic(material.sheenMapSampler, anisotropy),
      );
    }
    // `M3`: the scene behind, while the transparent pass lends it, and black
    // otherwise — the stage reads it only when `LayerInfo.scene_colour` says
    // there is one, but a declared sampler nobody binds is a crash on Metal.
    if (_keepsSampler(
      fragmentShader,
      _kSceneColourTextureSlot,
      declared: layered,
    )) {
      encoder.bindTexture(
        fragmentShader,
        _kSceneColourTextureSlot,
        _sceneColourRead?.texture ?? fallbackBlack,
        sampler: SamplerDescriptor.linearClamp,
      );
    }
    // Version 2: the scene behind a translucent surface, for a stage that
    // reads it — the surface buffer while the pass after the transparent
    // half lends it, black (nothing behind) wherever else it is drawn.
    if (material.lighting.usesSceneDepth) {
      _bindSceneDepth(encoder, fragmentShader);
    }

    encoder.draw(instanceCount: instanced?.count ?? 1);
    if (layerBias != null) encoder.setDepthBias(DepthBias.none);
    if (override == null &&
        orderIndependent == null &&
        blend &&
        material.isTransparent &&
        material.effectsDepth &&
        device.features.has(DeviceFeature.independentBlend)) {
      encoder.setBlend(_MaterialStages._blendFor(material), attachment: 1);
    }
    state.drawCalls++;
    state.triangles += (indexCount ~/ 3) * (instanced?.count ?? 1);
    if (instanced != null) state.instances += instanced.count;
    // `P12`: nothing past the `?.` runs unless this frame is being journaled.
    state.journal?.add(
      kind: 'mesh',
      node: node,
      mesh: node.name,
      material: material.name,
      lighting: material.lighting.label,
      vertices: mesh.vertexCount,
      indices: indexCount,
      instances: instanced?.count ?? 1,
      state: <String, Object?>{
        'cull': cull ? 'back' : 'none',
        'blend': orderIndependent != null
            ? 'weighted'
            : override != null
            ? 'override'
            : (blend ? 'alpha' : 'opaque'),
        'depthWrite':
            orderIndependent == null && (material.depthWrite ?? !blend),
        'depthCompare': depthCompare.name,
        'winding': node.isWorldMirrored != mirrored ? 'cw' : 'ccw',
        'skinned': skinned,
        'instanced': batched,
        'lightmapped': lightmapped,
        'clustered': clustered != null,
        'xray': override != null,
      },
      uniforms: <String, Float32List>{
        'mvp': Float32List.fromList(mvp.storage),
        'model': Float32List.fromList(modelMatrix.storage),
        'tint': Float32List.fromList(<double>[
          node.tint.r,
          node.tint.g,
          node.tint.b,
          node.tint.a,
        ]),
        'baseColor': Float32List.fromList(<double>[
          material.baseColorEncoded.r,
          material.baseColorEncoded.g,
          material.baseColorEncoded.b,
          material.baseColorEncoded.a,
        ]),
        'emissive': Float32List.fromList(<double>[
          material.emissive.r,
          material.emissive.g,
          material.emissive.b,
        ]),
        'metallicRoughness': Float32List.fromList(<double>[
          material.metallic,
          material.roughness,
        ]),
        ...material.parameters,
      },
    );
  }

  /// How [node] is drawn through [material] — `A1.2`, `A1.3`.
  ///
  /// **Through the depth pre-draw** when it is cut — a mask without
  /// coverage, or hashed — or part way through a cross-fade, wherever the
  /// pre-draw can make the same cut the lit stage would: the lighting model
  /// has an opaque variant (the engine's six), the bundle has the pre-draw,
  /// the material writes depth and tests it the ordinary way, and its base
  /// colour is read where the pre-draw reads it. The layered model reads it
  /// through a texture transform where the material has one, and a cut made
  /// at the untransformed coordinate would be the wrong shape.
  ///
  /// **Skipped** where a fade cannot be pre-drawn: of the two levels, the one
  /// with the larger share is drawn whole and the other not at all, which is
  /// the switch every release before 1.0 made, moved to the middle of the
  /// band. Two whole levels at once would fight for every pixel.
  ///
  /// **Drawn once** otherwise: opaque, transparent — whose fade is opacity —
  /// coverage, an override, a layer of weighted blended transparency.
  _OpaqueRoute _opaqueRoute(
    MeshNode node,
    RenderMaterial material, {
    required FramePassState state,
    required bool overridden,
    required bool orderIndependent,
  }) {
    if (overridden || orderIndependent) return _OpaqueRoute.draw;
    if (material.alphaMode == MaterialAlphaMode.blend || node.tint.a < 1.0) {
      return _OpaqueRoute.draw;
    }
    final coverage =
        material.alphaMode == MaterialAlphaMode.mask &&
        material.alphaToCoverage &&
        state.coverageAvailable;
    final cut =
        !coverage &&
        (material.alphaMode == MaterialAlphaMode.mask ||
            material.alphaMode == MaterialAlphaMode.hashed);
    final fade = node.lodFade;
    if (!cut && fade == 1.0) return _OpaqueRoute.draw;
    final compare = material.depthCompare;
    final possible =
        _opaqueStageFor(material.lighting) != null &&
        shaders['DepthPredraw'] != null &&
        (material.depthWrite ?? true) &&
        (compare == null ||
            compare == CompareFunction.less ||
            compare == CompareFunction.lessEqual) &&
        !(cut &&
            identical(material.lighting, LightingModel.pbrLayered) &&
            material.textureTransforms.containsKey(MaterialMap.baseColor));
    if (possible) return _OpaqueRoute.predraw;
    if (fade == 1.0) return _OpaqueRoute.draw;
    // The finer level's share is positive and the coarser's negative, and
    // the two add to one: exactly one of them is the larger.
    final larger = fade > 0.0 ? fade > 0.5 : -fade >= 0.5;
    return larger ? _OpaqueRoute.draw : _OpaqueRoute.skip;
  }

  /// Binds the pre-draw's fragment half for [node] — `depth_predraw.frag`:
  /// the cut the lit stage would make, with the same map, sampler and bias,
  /// and the node's share of a cross-fade.
  void _encodePredrawFragment({
    required PassEncoder encoder,
    required MeshNode node,
    required RenderMaterial material,
    required RenderSettings settings,
    required FramePassState state,
  }) {
    final stage = shaders['DepthPredraw']!;
    final coverage =
        material.alphaMode == MaterialAlphaMode.mask &&
        material.alphaToCoverage &&
        state.coverageAvailable;
    _predrawInfo.mask
      // The cutoff in the encoding `FragInfo.material2.x` carries: the mask's
      // own, minus two for hashed, minus one for no cut — and none under
      // coverage, whose edge the lit draw spreads over the samples.
      ..[0] = switch (material.alphaMode) {
        MaterialAlphaMode.mask when !coverage => material.alphaCutoff,
        MaterialAlphaMode.hashed => _hashedCutoff,
        _ => -1.0,
      }
      ..[1] = material.baseColor.a * node.tint.a
      ..[2] = node.lodFade
      // `MaterialLodBias`: what the scene pass set for the lit draws.
      ..[3] = _targetOrigin[1];
    encoder
      ..bindBlock(stage, _predrawInfo)
      ..bindTexture(
        stage,
        _kAlbedoTextureSlot,
        material.albedo ?? fallbackAlbedo,
        sampler: _anisotropic(
          material.albedoSampler,
          _anisotropyLevel(settings.anisotropy),
        ),
      );
  }

  /// The index buffer that draws the clusters of [node]'s split mesh the
  /// current view can see — `C9` — or null to draw [mesh] whole: outside the
  /// scene pass's views, for a mesh with no clusters, and for a node whose
  /// triangles are not where its vertices say (skinned, morphing, instanced)
  /// or whose bounds it asked not to be culled by.
  ///
  /// The cone test only where the draw culls back faces, with the same
  /// expression the cull mode is set from below.
  ({GeometryBuffer buffer, int count})? _clusterIndicesFor(
    MeshNode node,
    DrawableGeometry mesh,
    RenderMaterial material,
    RenderSettings settings,
  ) {
    final view = _clusterView;
    if (view == null || mesh.clusters == null) return null;
    if (node is InstancedMeshNode ||
        node.skeleton != null ||
        node.morph != null ||
        !node.frustumCulled) {
      return null;
    }
    final cullsBackFaces =
        settings.backfaceCulling &&
        !settings.wireframe &&
        !material.doubleSided;
    return (_clusterDraws ??= ClusterDraws(
      device,
      framesInFlight: Renderer._kFramesInFlight,
    )).indicesFor(
      node: node,
      mesh: mesh,
      view: view.view,
      frustum: view.frustum,
      eye: cullsBackFaces
          ? clusterEye(view.viewProjection, node.worldMatrix)
          : null,
      occlusion: view.occlusion,
    );
  }

  /// Binds [scene]'s irradiance field to [stage] — `L3`: the atlas, uploaded
  /// again only when the field's version moved, and the block that says how
  /// to read it. With no field, the block says "off" and a stand-in fills
  /// the sampler.
  void _bindIrradiance(PassEncoder encoder, ShaderHandle stage, Scene scene) {
    final field = scene.irradianceField;
    // The atlas the GPU keeps when the field is updated there (`L4`), the
    // uploaded bake otherwise. Both have the same layout, so the block below
    // is the same either way.
    final gpu = _irradianceGpu;
    final live =
        field != null &&
        gpu != null &&
        identical(gpu.field, field) &&
        gpu.seeded >= 0 &&
        _updatesIrradianceOnGpu(field);
    final atlas = field == null
        ? null
        : live
        ? gpu.atlas.current
        : _irradianceAtlasFor(field);
    final info = _irradianceInfo;
    if (field == null || atlas == null) {
      info.origin[3] = 0.0;
    } else {
      final nearest = math.min(
        field.spacing.x,
        math.min(field.spacing.y, field.spacing.z),
      );
      info.origin
        ..[0] = field.origin.x
        ..[1] = field.origin.y
        ..[2] = field.origin.z
        ..[3] = 1.0;
      // A tenth of the nearest spacing off the surface and towards the eye:
      // enough that a surface is not read as the wall its own probe sees, and
      // too little to carry the read through a wall of any real thickness.
      info.spacing
        ..[0] = field.spacing.x
        ..[1] = field.spacing.y
        ..[2] = field.spacing.z
        ..[3] = nearest * 0.1;
      info.counts
        ..[0] = field.countX.toDouble()
        ..[1] = field.countY.toDouble()
        ..[2] = field.countZ.toDouble()
        ..[3] = nearest * 0.1;
      info.tiles
        ..[0] = field.tile.toDouble()
        ..[1] = field.depthTile.toDouble()
        ..[2] = _irradianceColumns.toDouble()
        ..[3] = _irradianceMomentsTop.toDouble();
      info.atlas
        ..[0] = 1.0 / atlas.width
        ..[1] = 1.0 / atlas.height;
    }
    encoder
      ..bindBlock(stage, info)
      ..bindTexture(
        stage,
        'irradiance_texture',
        atlas ?? fallbackAlbedo,
        // Nearest: the shader filters inside each tile itself.
        sampler: SamplerDescriptor.nearestClamp,
      );
  }

  /// [field]'s atlas on this device, uploaded when the field changed.
  TextureHandle? _irradianceAtlasFor(IrradianceField field) {
    if (identical(field, _irradianceField) &&
        field.version == _irradianceVersion) {
      return _irradianceAtlas;
    }
    final packed = field.toAtlas();
    _destroyAfterFrame(_irradianceAtlas);
    _irradianceAtlas = device.createTextureFromPixels(
      width: packed.width,
      height: packed.height,
      format: TextureFormat.r32g32b32a32Float,
      pixels: ByteData.sublistView(packed.texels),
    );
    _irradianceField = field;
    _irradianceVersion = field.version;
    _irradianceColumns = packed.columns;
    _irradianceMomentsTop = packed.momentsTop;
    return _irradianceAtlas;
  }

  /// The frame's half of the `PointShadow` block: everything in it but the
  /// slot table, which is each draw's own packing.
  ///
  /// Written by every lit draw that binds the block, and by the fog — `S4` —
  /// which reads the atlas with no lit draw of its own to have written it.
  void _writePointShadowParams(RenderSettings settings) {
    // Half a texel, in tile-local uv: what every tap is held inside its
    // tile by, so none of them can reach the next face along.
    final texel = _cubeShadowTile > 0 ? 1.0 / _cubeShadowTile : 0.0;
    _pointShadowParams[0] = texel * 0.5;
    _pointShadowParams[1] = settings.shadows.pointBias;
    _pointShadowParams[2] = _cubeShadowLight < 0
        ? 0.0
        : settings.shadows.strength;
    _pointShadowParams[3] = settings.shadows.pointNormalOffset;
    // Softness is authored in texels and spent in tile-local uv, so a
    // penumbra keeps its width when the atlas resolution changes.
    _pointShadowParams2[0] =
        math.max(settings.shadows.pointSoftness, 0.0) * texel;
    _pointShadowParams2[1] = math.max(settings.shadows.pointLightRadius, 0.0);
    _pointShadowParams2[2] =
        math.max(settings.shadows.pointMaxSoftness, 0.0) * texel;
    _pointShadowParams2[3] = settings.showPointShadowDebug ? 1.0 : 0.0;
    // Asked of the device rather than assumed, like the depth range and the
    // cascade matrices before it. See where it is read in surface.glsl.
    _pointShadowParams3[0] =
        device.framebufferOrigin == FramebufferOrigin.bottomLeft ? 1.0 : 0.0;
    // One over the tile's edge in texels. The shader turns it into the
    // world width of a texel at whatever distance the fragment is, which is
    // the quantity a normal offset has to clear — see `surface.glsl`.
    _pointShadowParams3[1] = _cubeShadowTile > 0 ? 1.0 / _cubeShadowTile : 0.0;
  }
}
