/// The scene pass: every mesh the camera can see, encoded into one draw list.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// The largest of the passes by a wide margin, and the one everything else
/// exists to support: the shadow passes fill what it samples, the post passes
/// work on what it wrote.
part of 'renderer.dart';

extension _ScenePasses on Renderer {
  /// Renders every view into one target and returns the composited image.
  ///
  /// Views share a single render pass and clear: viewports do not overlap in the
  /// split-screen case, and one pass is both cheaper and simpler than a pass per
  /// view. Views are drawn in ascending priority, as in PlayCanvas.
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
    required FramePassState state,
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
      if (state.boundPipeline != material.lighting || state.boundSkinned != skinned) {
        encoder.bindPipeline(
          _pipelineFor(material.lighting, skinned: skinned),
        );
        state.boundPipeline = material.lighting;
        state.boundSkinned = skinned;
        state.pipelineSwitches++;
      }

      // Both matrices are cached on the node and keyed on its transform
      // version, so a static object costs nothing here.
      final modelMatrix = node.worldMatrix;
      final normalMatrix = node.worldNormalMatrix;

      encoder.setWindingOrder(
        node.worldIsMirrored
            ? WindingOrder.clockwise
            : WindingOrder.counterClockwise,
      );
      final cull = settings.backfaceCulling &&
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
      encoder.bindIndexBuffer(
        mesh.indices,
        mesh.indexType,
        mesh.indexCount,
      );

      final activeVertexShader =
          skinned ? skinnedVertexShader : vertexShader;
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
        encoder.bindUniformBlock(
          skinnedVertexShader,
          _kSkinInfoBlock,
          {'joint_matrices': skeleton.matrices},
        );
        state.skinnedDraws++;
      }

      final fragmentShader = _fragmentShaderFor(material.lighting);

      // Gated on model metadata, not reflection: a shader that only DECLARES
      // FragInfo still reports it with a non-zero size while the compiled
      // function binds no buffer, and binding that segfaults inside Metal.
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
        _materialData[2] = scene.ambientIntensity;
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
        _frameParams[2] =
            shadows.directional == null ? -1.0 : shadows.casterIndex.toDouble();

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
        _pointShadowParams[2] =
            _cubeShadowLight < 0 ? 0.0 : settings.shadows.strength;
        _pointShadowParams[3] = settings.shadows.pointNormalOffset;
        // Softness is authored in texels and spent in tile-local uv, so a
        // penumbra keeps its width when the atlas resolution changes.
        _pointShadowParams2[0] =
            math.max(settings.shadows.pointSoftness, 0.0) * texel;
        _pointShadowParams2[1] =
            math.max(settings.shadows.pointLightRadius, 0.0);
        _pointShadowParams2[2] =
            math.max(settings.shadows.pointMaxSoftness, 0.0) * texel;
        _pointShadowParams2[3] = settings.showPointShadowDebug ? 1.0 : 0.0;
        encoder.bindUniformBlock(fragmentShader, 'PointShadow', {
          'faces': _cubeFaceMatrices,
          'lights': _cubeLightData,
          'slots': _shadowSlots,
          'params': _pointShadowParams,
          'params2': _pointShadowParams2,
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

      encoder.draw();
      state.drawCalls++;
  }

  _ScenePass _encodeScene({
    required Scene scene,
    required List<RenderView> ordered,
    required RenderSettings settings,
    required int width,
    required int height,
    required SceneShadows shadows,
    required FramePassState passState,
    required int lightOverflowCount,
    required List<PassContributor> contributors,
    required bool surfaceIsRead,
  }) {
    final hdr = _hdrColor!;
    var culled = 0;
    final debugLines = 0;
    var lightOverflow = 0;
    // No multisampling while the surface buffer is wanted, and that is a
    // correctness matter rather than a budget one. Attachments in one target
    // must agree on sample count, so the surface buffer would be resolved by
    // averaging — and the average of two octahedrally encoded normals is not
    // the encoding of any normal. Every silhouette pixel would decode to a
    // direction belonging to neither face, which a reflection shows as a
    // fringe of wrong angles along every edge.
    //
    // A golden caught this before any reflection did: surface-buffer sat just
    // outside its tolerance, every differing pixel on an edge, and which
    // pixels differed changed between runs.
    final msaa = surfaceIsRead ? null : _hdrMsaa;
    // The clear colour is authored the way a colour picker shows it, but the
    // scene target holds linear light and the composite pass encodes on the way
    // out. Clearing with the sRGB value directly would send it through the
    // encode twice and wash the background out.
    final clear = Renderer._srgbToLinear(ordered.first.clearColor);

    final colorAttachment = msaa == null
        ? ColorTarget(texture: hdr, clearValue: clear)
        : ColorTarget(
            texture: msaa,
            resolveTexture: hdr,
            storeAction: StoreAction.multisampleResolve,
            clearValue: clear,
          );

    // Attached only when something wants it. A pipeline may declare more
    // outputs than the target has attachments — the extra is discarded — so
    // the shaders write the surface unconditionally and this decides whether
    // anyone is listening. See RESEARCH.md.
    final surface = surfaceIsRead ? _surfaceColor : null;
    final surfaceAttachment = surface == null
        ? null
        : (msaa == null
            ? ColorTarget(
                texture: surface,
                clearValue: vm.Vector4.zero(),
              )
            : ColorTarget(
                texture: _surfaceMsaa!,
                resolveTexture: surface,
                storeAction: StoreAction.multisampleResolve,
                clearValue: vm.Vector4.zero(),
              ));

    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[colorAttachment, ?surfaceAttachment],
      // Standard depth: clear to the far plane, nearer fragments win.
      depth: DepthTarget(
        texture: msaa == null
            ? (_depthStencilSingle ?? _depthStencil!)
            : _depthStencil!,
      ),
    ));

    final cameraPosition = vm.Vector3.zero();

    for (final view in ordered) {
      // Per view rather than once: the debug overlay at the end of each view
      // leaves the pass in line-drawing state, so the next view has to
      // re-establish its own.
      //
      // Viewport and scissor are set explicitly because both default to a
      // zero-sized rect, and nothing in the API complains about drawing into one.
      // Asked, not assumed. A backend without glPolygonMode — OpenGL ES has
      // none — refuses the request rather than filling the triangles instead,
      // and a refusal mid-frame is a crash where a declined setting is a
      // picture. Wireframe there needs line primitives from an index buffer
      // built for it, which is geometry work and not a backend's to invent.
      final wireframe = settings.wireframe && device.supportsWireframe;

      final fraction = view.viewportFraction;
      final vx = (fraction.x * width).round();
      final vy = (fraction.y * height).round();
      final vw = math.max(1, (fraction.width * width).round());
      final vh = math.max(1, (fraction.height * height).round());

      final viewRect = ScreenRect(x: vx, y: vy, width: vw, height: vh);
      pass.setState(Renderer._kSceneViewState.copyWith(
        viewport: viewRect,
        scissor: viewRect,
        polygonMode: wireframe ? PolygonMode.line : PolygonMode.fill,
      ));
      // That state names the depth test, so the tracker has to agree with it or
      // the first material of the next view would skip a call it needs. The
      // debug overlay at the end of a view leaves the test on `always`, which
      // is exactly the case this catches.
      passState.depthCompare = CompareFunction.less;

      final camera = view.camera;
      final aspect = vw / vh;
      final viewMatrix = camera.viewMatrix;
      final viewProjection = _viewProjection(camera, aspect);

      // Before the render list is built, because choosing a level changes which
      // nodes are visible and the list is built from what is.
      //
      // Driven here rather than left to the application, which is the fix for a
      // feature that was written, tested and then never actually ran: nothing
      // called select(), so every LOD group sat on its finest level for ever
      // and the whole thing was decoration.
      developer.Timeline.startSync('LodGroup.select');
      for (final group in scene.lodGroups) {
        group.select(camera);
      }
      developer.Timeline.finishSync();
      final frustum = vm.Frustum.matrix(viewProjection);

      final visibleBefore = scene.meshes.length;
      developer.Timeline.startSync('RenderList.build');
      _renderList.build(
        scene,
        view,
        viewMatrix: viewMatrix,
        frustum: frustum,
      );
      developer.Timeline.finishSync();

      developer.Timeline.startSync('RenderList.sort');
      _renderList.sort(view);
      developer.Timeline.finishSync();
      culled += visibleBefore - _renderList.length;

      camera.readWorldPosition(cameraPosition);

      lightOverflow = lightOverflowCount;

      _cameraData[0] = cameraPosition.x;
      _cameraData[1] = cameraPosition.y;
      _cameraData[2] = cameraPosition.z;

      developer.Timeline.startSync('Renderer.encodeDraws');
      void encodeHalf(List<int> indices) {
        for (var i = 0; i < indices.length; i++) {
          final node = _renderList.itemAt(indices[i]).requireNode;
          _encodeNode(
            encoder: pass,
            node: node,
            scene: scene,
            settings: settings,
            viewProjection: viewProjection,
            shadows: shadows,
            state: passState,
          );
        }
      }

      encodeHalf(_renderList.opaque);
      // Between the two halves, which is the one place it can go. After the
      // opaque half, so every pixel already covered by geometry fails the depth
      // test before the sky's fragment stage runs — the software rasteriser
      // tests depth before calling the fragment shader, so this is real work
      // saved on the backend that can least afford it. Before the transparent
      // half, so glass has something behind it to blend with.
      _encodeSky(
        pass: pass,
        settings: settings,
        viewProjection: viewProjection,
        state: passState,
      );
      encodeHalf(_renderList.transparent);
      developer.Timeline.finishSync();

      for (final plugin in contributors) {
        plugin.encode(
          ContributorFrame(
            encoder: pass,
            device: device,
            services: this,
            state: passState,
            settings: settings,
            width: width,
            height: height,
            view: view,
            viewProjection: viewProjection,
          ),
        );
      }

      // The debug overlay is deliberately NOT drawn here. Anything written into
      // the HDR target is scene light: it would be tone mapped, and a bright
      // enough gizmo would bleed into the bloom. The overlay belongs on top of
      // the finished image, so it is drawn in the composite pass below.
    }

    // Submitted before the post passes: they sample this target, and the queue
    // orders command buffers by submission.
    developer.Timeline.startSync('CommandBuffer.submit');
    final stopwatch = Stopwatch()..start();
    pass.submit();
    stopwatch.stop();
    developer.Timeline.finishSync();

    return _ScenePass(
      culled: culled,
      debugLines: debugLines,
      lightOverflow: lightOverflow,
      submitMicros: stopwatch.elapsedMicroseconds,
    );
  }
}
