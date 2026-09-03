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

extension _MeshEncode on Renderer {
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
    // The probes this draw may reflect, answered by the calling node the way
    // the shadows are. None by default: the view model and a probe's own
    // capture both draw without one.
    _SceneProbes probes = _SceneProbes.none,
    // Whether the view-projection mirrors the picture. A probe's face is drawn
    // through one — see `probeFaceViewProjection` — and a mirror reverses
    // which way every triangle winds, so the winding set below flips with it.
    bool mirrored = false,
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
    final material = node.material;

    final skeleton = node.skeleton;
    final skinned = skeleton != null;
    // A batch draws its instances in one call from a third vertex stage; a
    // batch with nothing in it draws nothing, and binding for it would leave
    // the pass state describing a pipeline no draw used.
    final instanced = node is InstancedMeshNode ? node : null;
    if (instanced != null && instanced.count == 0) return;
    final batched = instanced != null;
    // A level's batches read their colour as a lightmap coordinate; neither
    // a skinned mesh nor an instanced one is a level, so the flag is ignored
    // where it cannot apply rather than asserted against.
    final lightmapped = node.lightmapped && !skinned && !batched;
    if (state.boundPipeline != material.lighting ||
        state.boundSkinned != skinned ||
        state.boundInstanced != batched ||
        state.boundLightmapped != lightmapped) {
      encoder.bindPipeline(
        _pipelineFor(
          material.lighting,
          skinned: skinned,
          instanced: batched,
          lightmapped: lightmapped,
        ),
      );
      state.boundPipeline = material.lighting;
      state.boundSkinned = skinned;
      state.boundInstanced = batched;
      state.boundLightmapped = lightmapped;
      state.pipelineSwitches++;
    }

    // Both matrices are cached on the node and keyed on its transform
    // version, so a static object costs nothing here.
    final modelMatrix = node.worldMatrix;
    final normalMatrix = node.worldNormalMatrix;

    encoder.setWindingOrder(
      node.worldIsMirrored != mirrored
          ? WindingOrder.clockwise
          : WindingOrder.counterClockwise,
    );
    final cull =
        settings.backfaceCulling &&
        !settings.wireframe &&
        !material.doubleSided;
    encoder.setCullMode(cull ? CullMode.backFace : CullMode.none);

    final blend = material.alphaMode == MaterialAlphaMode.blend;
    encoder.setBlend(blend ? BlendState.alphaBlend : null);
    // Transparent surfaces must not occlude what is behind them — unless the
    // material has an opinion, which is how a backdrop says it is drawn but
    // is not there.
    encoder.setDepthWrite(material.depthWrite ?? !blend);

    // Only when it changes. A scene where nothing overrides the test never
    // emits this call, so the pass's own `less` stands and every frame the
    // golden sets were recorded from is byte-identical.
    final depthCompare = material.depthCompare ?? CompareFunction.less;
    if (state.depthCompare != depthCompare) {
      encoder.setDepthCompare(depthCompare);
      state.depthCompare = depthCompare;
    }

    encoder.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
    encoder.bindIndexBuffer(mesh.indices, mesh.indexType, mesh.indexCount);

    if (instanced != null) {
      encoder.bindVertexData(instanced.instanceBytes, instanced.count, slot: 1);
    }
    final activeVertexShader = batched
        ? instancedVertexShader
        : skinned
        ? skinnedVertexShader
        : lightmapped
        ? lightmappedVertexShader
        : vertexShader;
    // Typed, because `Matrix4.operator*` returns `dynamic`: without the
    // annotation `.storage` here is an unchecked call on an untyped value,
    // and a typo in it would compile and fail at the draw.
    final vm.Matrix4 mvp = viewProjection * modelMatrix;
    encoder.bindUniformBlock(activeVertexShader, _kFrameInfoBlock, {
      'mvp': mvp.storage,
      'model': modelMatrix.storage,
      'normal_matrix': normalMatrix.storage,
    });

    if (skeleton != null) {
      // Recomputed here rather than by the caller: the matrices depend on
      // the mesh node's own world transform, which is exactly what the
      // renderer is holding at this point.
      skeleton.update(modelMatrix);
      encoder.bindUniformBlock(skinnedVertexShader, _kSkinInfoBlock, {
        'joint_matrices': skeleton.matrices,
      });
      state.skinnedDraws++;
    }

    final fragmentShader = _fragmentShaderFor(material.lighting);

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
    final probe = material.lighting.usesEnvironment
        ? probes.nearest(node.worldBoundsCentre)
        : null;
    final environment =
        probe?.texture ?? scene.environment ?? _environmentFallback(device);
    final environmentLevels = probe != null
        ? probe.levels
        : scene.environment == null || environment == null
        ? 0
        : scene.environmentLevels;

    if (material.lighting.usesFragInfo) {
      _baseColorData[0] = material.baseColor.x;
      _baseColorData[1] = material.baseColor.y;
      _baseColorData[2] = material.baseColor.z;
      _baseColorData[3] = material.baseColor.w;

      _emissiveData[0] = material.emissive.x;
      _emissiveData[1] = material.emissive.y;
      _emissiveData[2] = material.emissive.z;

      _materialData[0] = material.metallic;
      _materialData[1] = material.roughness;
      // The ambient strength, which is also the environment's — the shader
      // scales both by this one number and uses one *or* the other. A probe
      // brings its own: a captured room is read at the strength the frame drew
      // it, and the flat term a scene dims to six per cent is not consulted
      // while a probe is bound. See `ReflectionProbeNode.intensity`.
      _materialData[2] = probe?.intensity ?? scene.ambientIntensity;
      _materialData[3] = settings.specular;

      // A negative cutoff means "not masked". The shader compares against
      // it directly, so encoding the mode in the value keeps a branch and
      // a separate flag out of the uniform block.
      _material2Data[0] = material.alphaMode == MaterialAlphaMode.mask
          ? material.alphaCutoff
          : -1.0;
      _material2Data[1] = material.normalScale;
      _material2Data[2] = material.occlusionStrength;
      _material2Data[3] = material.emissiveStrength;

      _frameParams[0] = settings.exposure;
      _frameParams[1] = lights.count.toDouble();
      _frameParams[2] = shadows.directional == null
          ? -1.0
          : shadows.casterIndex.toDouble();
      // The slot `surface.glsl` reserved for a frame-wide parameter, now
      // spent: the environment's level count, and zero when there is none.
      // One number carrying both the roughness scale and the "is there one"
      // flag, so the shader needs no second uniform and no second branch.
      _frameParams[3] = environmentLevels.toDouble();

      // Its own block, bound beside FragInfo rather than folded into it. See
      // the note in color.glsl: appending to a block six shaders share moves
      // offsets nobody expected to move.
      final fog = settings.fog;
      _fogData[0] = fog.resolvedColor.x;
      _fogData[1] = fog.resolvedColor.y;
      _fogData[2] = fog.resolvedColor.z;
      _fogData[3] = fog.density;
      // Gated on the model, like every other block and sampler here. Unlit
      // declares FragInfo but reaches no lighting loop, so the compiler drops
      // all three of these — and binding a block the compiled shader does not
      // have is a native failure, not a no-op.
      if (material.lighting.usesPointShadow) {
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
        _pointShadowParams2[1] = math.max(
          settings.shadows.pointLightRadius,
          0.0,
        );
        _pointShadowParams2[2] =
            math.max(settings.shadows.pointMaxSoftness, 0.0) * texel;
        _pointShadowParams2[3] = settings.showPointShadowDebug ? 1.0 : 0.0;
        // Asked of the device rather than assumed, like the depth range and the
        // cascade matrices before it. See where it is read in surface.glsl.
        _pointShadowParams3[0] =
            device.framebufferOrigin == FramebufferOrigin.bottomLeft
            ? 1.0
            : 0.0;
        // One over the tile's edge in texels. The shader turns it into the
        // world width of a texel at whatever distance the fragment is, which is
        // the quantity a normal offset has to clear — see `surface.glsl`.
        _pointShadowParams3[1] = _cubeShadowTile > 0
            ? 1.0 / _cubeShadowTile
            : 0.0;
        encoder.bindUniformBlock(fragmentShader, 'PointShadow', {
          'faces': _cubeFaceMatrices,
          'lights': _cubeLightData,
          'slots': shadowSlots,
          'params': _pointShadowParams,
          'params2': _pointShadowParams2,
          'params3': _pointShadowParams3,
        });
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

      encoder.bindUniformBlock(fragmentShader, _kFogInfoBlock, {
        'fog': _fogData,
        'eye': _cameraData,
      });

      encoder.bindUniformBlock(fragmentShader, _kFragInfoBlock, {
        // Whole arrays written from their reflected base offset. A backend
        // reflects the array, not its elements — `lights[0]` comes back
        // null — but the std140 stride for a vec4 array is a flat 16
        // bytes, so a contiguous write lands each element correctly.
        'light_position': lights.positions,
        'light_color': lights.colors,
        'light_direction': lights.directions,
        'light_cone': lights.cones,
        'base_color': _baseColorData,
        'emissive': _emissiveData,
        'camera_position': _cameraData,
        'material': _materialData,
        'material2': _material2Data,
        'frame_params': _frameParams,
        'shadow_params': _shadowParams,
        'shadow_matrix': _shadowMatrix.storage,
        'shadow_matrix_far': _shadowMatrixFar.storage,
        'shadow_matrix_farthest': _shadowMatrixFarthest.storage,
        'shadow_cascades': _shadowCascades,
        'ambient_sky': _ambientSky,
        'ambient_ground': _ambientGround,
      });
    }

    // Bound strictly according to the model's declared slots. The
    // compiler drops a sampler the shader never reads, and binding one
    // Metal does not have is a native crash rather than a no-op.
    // **An application's own parameters, bound after everything built in.**
    // Later so that a material cannot displace a block the engine depends on
    // by naming it: the encoder fills a block once, and the last fill wins.
    //
    // Unconditional and safe: the encoder skips members a compiled shader
    // does not read and reports an absent block instead of taking the process
    // down. Its own `bindUniformBlock` says so, and that is the difference
    // between this and the textures below.
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

    if (material.lighting.usesEnvironment && environment != null) {
      encoder.bindTexture(
        fragmentShader,
        _kEnvironmentTextureSlot,
        environment,
        sampler: Renderer._environmentSampler,
      );
    }
    if (material.lighting.usesAlbedoTexture) {
      encoder.bindTexture(
        fragmentShader,
        _kAlbedoTextureSlot,
        material.albedo ?? fallbackAlbedo,
        sampler: material.albedoSampler,
      );
    }
    if (material.lighting.usesMaterialMaps) {
      encoder.bindTexture(
        fragmentShader,
        _kNormalTextureSlot,
        material.normal ?? fallbackNormal,
        sampler: material.normalSampler,
      );
      encoder.bindTexture(
        fragmentShader,
        _kOcclusionTextureSlot,
        material.occlusion ?? fallbackAlbedo,
        sampler: material.occlusionSampler,
      );
      encoder.bindTexture(
        fragmentShader,
        _kEmissiveTextureSlot,
        material.emissiveTexture ?? fallbackAlbedo,
        sampler: material.emissiveSampler,
      );
      // Black, not white: the lightmap is added, and a material without one
      // adds nothing. Bound for every lit model because the shader samples
      // the slot unconditionally, which is a texel cheaper than a branch and
      // the same arrangement every other map here uses.
      encoder.bindTexture(
        fragmentShader,
        _kLightmapTextureSlot,
        material.lightmap ?? fallbackBlack,
        sampler: material.lightmapSampler ?? Renderer._clampSampler,
      );
    }
    if (material.lighting.usesShadowMap) {
      encoder.bindTexture(
        fragmentShader,
        _kShadowTextureSlot,
        // With shadows off the slot still has to be satisfied, and a white
        // texture reads as "nothing between here and the light" — which is
        // also what the zero strength above already guarantees.
        shadows.directional ?? fallbackAlbedo,
        sampler: Renderer._clampSampler,
      );
    }
    if (material.lighting.usesMetallicRoughnessMap) {
      encoder.bindTexture(
        fragmentShader,
        _kMetallicRoughnessTextureSlot,
        material.metallicRoughness ?? fallbackAlbedo,
        sampler: material.metallicRoughnessSampler,
      );
    }

    encoder.draw(instanceCount: instanced?.count ?? 1);
    state.drawCalls++;
  }
}
