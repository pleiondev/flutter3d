/// Everything drawn after the scene: bloom, ambient occlusion, reflections and
/// the composite that puts them together.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why these
/// are extensions on `Renderer` rather than files of their own.
///
/// They come out together because they share what they are: fullscreen passes
/// over a target somebody else filled, each one a pipeline, a uniform block and
/// three vertices. What separates them is which texture they read.
part of 'renderer.dart';

extension _PostPasses on Renderer {
  PipelineHandle _postPipeline(
    PipelineHandle? cached,
    ShaderHandle fragment,
    void Function(PipelineHandle) store,
  ) {
    if (cached != null) return cached;
    final pipeline = device.createPipeline(fullscreenVertexShader, fragment);
    store(pipeline);
    return pipeline;
  }

  /// Builds the bloom chain into [top], the texture the graph allocated for
  /// `FrameResourceIds.bloom`.
  ///
  /// Everything below the top is scratch that no other pass will ever name, so
  /// it comes from [FrameResources.transient] rather than from the pool
  /// directly. That is not tidiness: the upsample command buffers that read
  /// those levels are still in flight when this method returns, and handing
  /// them straight back let the pool lend one out while the GPU was reading it.
  void _renderBloom({
    required FrameResources resources,
    required TextureHandle scene,
    required TextureHandle top,
    required BloomSettings settings,
  }) {
    // `gfx-31n`: the chain is a count of halvings, so its reach is a number
    // of pixels rather than a fraction of the frame. Scaled against the
    // height the count was chosen at, the glow covers the same share of the
    // picture at any resolution. Zero leaves it alone, which is what keeps
    // every frame recorded before this where it was.
    final levels = bloomLevelsFor(
      settings,
      frameHeight: scene.height,
    ).clamp(1, 8);
    final chain = <TextureHandle>[];

    var sourceWidth = scene.width;
    var sourceHeight = scene.height;
    TextureHandle source = scene;

    developer.Timeline.startSync('Bloom.downsample');
    for (var level = 0; level < levels; level++) {
      final spec = RenderTargetSpec(
        width: math.max(1, sourceWidth ~/ 2),
        height: math.max(1, sourceHeight ~/ 2),
        format: hdrFormat,
      );
      // Once a level is a single pixel there is nothing left to halve, and
      // continuing would just re-blur one texel.
      if (level > 0 &&
          spec.width == sourceWidth &&
          spec.height == sourceHeight) {
        break;
      }

      final target = level == 0 ? top : resources.transient(spec);
      _bloomParams[0] = 1.0 / sourceWidth;
      _bloomParams[1] = 1.0 / sourceHeight;
      _bloomParams[2] = level == 0 ? settings.threshold : 0.0;
      _bloomParams[3] = level == 0 ? settings.knee : 0.0;

      final isFirst = level == 0;
      drawFullscreen(
        FullscreenDraw(
          target: target,
          fragment: isFirst ? bloomThresholdShader : bloomDownsampleShader,
          textures: <String, TextureHandle>{_kPostSourceSlot: source},
          uniforms: <String, Map<String, Float32List>>{
            _bloomInfo.name: _bloomInfo.members,
          },
        ),
      );

      chain.add(target);
      source = target;
      sourceWidth = spec.width;
      sourceHeight = spec.height;
    }
    developer.Timeline.finishSync();

    // Back up the chain, each level's blur added into the one above it. The
    // widest level supplies the broad glow and the narrowest the tight core.
    developer.Timeline.startSync('Bloom.upsample');
    for (var level = chain.length - 1; level > 0; level--) {
      final from = chain[level];
      final into = chain[level - 1];

      _bloomParams[0] = 1.0 / from.width;
      _bloomParams[1] = 1.0 / from.height;
      _bloomParams[2] = settings.filterRadius;
      _bloomParams[3] = 0.0;

      // What this step multiplies the level it carries up by. On the way up a
      // level already holds every level below it, so a factor applied here
      // reaches all of them: the step carries only the *ratio* between this
      // level's weight and the one above, and the product down the chain is
      // each level's own weight, applied once.
      //
      // `gfx-30n`'s warmth: the wider the level, the warmer — level zero
      // exactly neutral, the widest carrying the whole [BloomSettings.halation]
      // — and [BloomSettings.scatter] to the power of the level for its
      // weight. Both at their defaults make every factor one, which is the
      // bloom this has always drawn.
      //
      // Halation stops at 2.5, where the blue weight is an eighth: at 1/0.35
      // it reaches zero, the ratio divides by it and the pyramid fills with
      // NaN, and past that the sign alternates from level to level. A
      // negative scatter would alternate the same way.
      (double, double) warmth(int k) {
        final t = chain.length > 1 ? k / (chain.length - 1) : 0.0;
        final h = settings.halation.clamp(0.0, 2.5) * t;
        return (1.0 + h * 0.5, 1.0 - h * 0.35);
      }

      final scatter = math.max(settings.scatter, 0.0);
      final here = warmth(level);
      final above = warmth(level - 1);
      _bloomTint[0] = here.$1 / above.$1 * scatter;
      _bloomTint[1] = scatter;
      _bloomTint[2] = here.$2 / above.$2 * scatter;
      _bloomTint[3] = 1.0;

      _drawFullscreenAdditive(target: into, source: from);
      _frameCounters?.drawCalls++;
    }
    developer.Timeline.finishSync();
  }

  /// The upsample step, which differs from every other post pass by blending
  /// rather than replacing.
  void _drawFullscreenAdditive({
    required TextureHandle target,
    required TextureHandle source,
  }) {
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          ColorTarget(
            texture: target,
            // Load, not clear: the point is to add to what the downsample left.
            loadAction: LoadAction.load,
          ),
        ],
      ),
    );

    pass.setState(
      Renderer._kFullscreenAdditiveState.copyWith(
        viewport: ScreenRect.of(target),
        scissor: ScreenRect.of(target),
      ),
    );

    pass.bindPipeline(
      _postPipeline(
        _bloomUpsamplePipeline,
        bloomUpsampleShader,
        (p) => _bloomUpsamplePipeline = p,
      ),
    );
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
    pass.bindTexture(
      bloomUpsampleShader,
      _kPostSourceSlot,
      source,
      sampler: Renderer._clampSampler,
    );
    pass.bindBlock(bloomUpsampleShader, _bloomInfo);
    pass.draw();
    pass.submit();
  }

  /// Smooths the edges of [source] into [target] — `gfx-04n`.
  ///
  /// One full-screen draw through [drawFullscreen], which counts it, so the
  /// profiler's own breakdown shows what the pass costs without anything here
  /// keeping a number.
  void _encodeFxaa({
    required TextureHandle target,
    required TextureHandle source,
    required AntiAliasSettings settings,
  }) {
    _fxaaParams[0] = 1.0 / math.max(source.width, 1);
    _fxaaParams[1] = 1.0 / math.max(source.height, 1);
    // `R2`: with only the sharpening asked for, no pixel is contrasted
    // enough to be smoothed, and every one takes the sharpen path.
    _fxaaParams[2] = settings.enabled
        ? settings.contrastThreshold.clamp(0.0, 1.0)
        : 1e9;
    _fxaaParams[3] = settings.blend.clamp(0.0, 1.0);
    // `gfx-29n`. Zero exactly when nobody asked: the shader returns the
    // centre untouched at zero rather than running a kernel that rounds to
    // nothing, and forty-four goldens depend on that being the same bytes.
    //
    // After a temporal resolve the robust kernel, at the resolve's own
    // strength — `R2`: what softens a resolved picture is the history, and
    // the kernel that follows one should not ring past what it averaged.
    final temporal = settings.temporal;
    final robust = temporal.enabled && temporal.sharpen > 0.0;
    _fxaaSharpen[0] = (robust ? temporal.sharpen : settings.sharpen).clamp(
      0.0,
      1.0,
    );
    _fxaaSharpen[1] = robust ? 1.0 : 0.0;
    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: fxaaShader,
        textures: <String, TextureHandle>{_kPostSourceSlot: source},
        uniforms: <String, Map<String, Float32List>>{
          _fxaaInfo.name: _fxaaInfo.members,
        },
      ),
    );
  }

  /// `gfx-32n`: smooths the occlusion buffer without crossing a silhouette.
  ///
  /// Draws into a transient of the same shape and hands it back under the
  /// same name, the way `_encodeReflections` does: a texture cannot be
  /// sampled and written in one pass, so a blur over a buffer needs a second
  /// one to land in, and the graph's versioning is what lets both be called
  /// `ao`.
  void _encodeSsaoBlur({
    required TextureHandle source,
    required TextureHandle surface,
    required AmbientOcclusionSettings options,
    required FrameResources resources,
  }) {
    developer.Timeline.startSync('Renderer.ssaoBlur');
    final target = resources.transient(
      RenderTargetSpec(
        width: source.width,
        height: source.height,
        format: source.format,
      ),
    );

    _ssaoBlurParams[0] = 1.0 / math.max(source.width, 1);
    _ssaoBlurParams[1] = 1.0 / math.max(source.height, 1);
    _ssaoBlurParams[2] = options.blurTaps.clamp(0, 8).toDouble();
    _ssaoBlurParams[3] = math.max(options.blurDepthFalloff, 1e-4);

    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: ssaoBlurShader,
        textures: <String, TextureHandle>{
          'ao_texture': source,
          'surface_texture': surface,
        },
        uniforms: <String, Map<String, Float32List>>{
          _ssaoBlurInfo.name: _ssaoBlurInfo.members,
        },
        // Nearest on the surface buffer, as the occlusion pass itself reads
        // it: this pass is at half resolution, so a filtered tap lands on the
        // corner of four full-resolution pixels and averages depths across a
        // silhouette — exactly the edge the depth weight is there to respect.
        samplers: const <String, SamplerOptions>{
          'surface_texture': SamplerOptions.nearestClamp,
        },
      ),
    );
    developer.Timeline.finishSync();

    // The pass wrote a *different* texture from the one it read, so the
    // version it produced has to be told which texture that is — the same
    // hand-off `_ReflectionsNode` makes for the lit colour.
    resources.provide(FrameResourceIds.ao, target);
  }

  /// The contact shadow's own march — `gfx-76n`.
  ///
  /// Everything about the reconstruction is `_encodeSsao`'s below, and for its
  /// reasons: the matrix comes from the surface buffer's own shape, carries the
  /// framebuffer origin and is *not* depth-range adjusted, and the camera's
  /// position and forward axis come with it because the buffer holds metres
  /// along that axis rather than a window depth.
  ///
  /// What differs is one direction instead of a hemisphere, and the target's
  /// size: full resolution rather than the occlusion's half, because the seam
  /// at a join is exactly the detail a half-resolution pass loses.
  void _encodeContactShadow({
    required TextureHandle target,
    required TextureHandle surface,
    required ContactShadowSettings options,
    required RenderView view,
    required vm.Vector3 toLight,
  }) {
    developer.Timeline.startSync('Renderer.contactShadow');

    final aspect = surface.height == 0 ? 1.0 : surface.width / surface.height;
    final viewProjection = toFramebufferOrigin(
      view.camera.viewProjection(aspect),
      device.framebufferOrigin,
    );
    final inverse = vm.Matrix4.copy(viewProjection)..invert();

    view.camera.readWorldPosition(_ssaoCamera);
    _contactCamera[0] = _ssaoCamera.x;
    _contactCamera[1] = _ssaoCamera.y;
    _contactCamera[2] = _ssaoCamera.z;
    view.camera.readForward(_ssaoForward);
    _contactForward[0] = _ssaoForward.x;
    _contactForward[1] = _ssaoForward.y;
    _contactForward[2] = _ssaoForward.z;

    _contactLight[0] = toLight.x;
    _contactLight[1] = toLight.y;
    _contactLight[2] = toLight.z;

    _contactParams[0] = math.max(options.length, 1e-4);
    // `R3`: half the steps while a resolve runs, each frame's offset from the
    // blue noise and a history to carry the rest.
    _contactParams[1] =
        (_temporalEffects ? math.max(4, options.steps ~/ 2) : options.steps)
            .clamp(1, 16)
            .toDouble();
    _contactParams[2] = math.max(options.thickness, 1e-4);
    // The strength is the composite's, for the reason the occlusion's is: "off"
    // has to be a multiplier of exactly one, and that is a property of one
    // `mix` rather than of arithmetic in two places.
    _contactParams[3] = options.bias;

    _contactShadowInfo.inverseViewProjection.setAll(0, inverse.storage);
    _contactShadowInfo.viewProjection.setAll(0, viewProjection.storage);
    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: contactShadowShader,
        textures: <String, TextureHandle>{
          'surface_texture': surface,
          'blue_noise_texture': _blueNoise,
        },
        uniforms: <String, Map<String, Float32List>>{
          _contactShadowInfo.name: _contactShadowInfo.members,
          _noiseInfo.name: _noiseInfo.members,
        },
        // Unfiltered, for `_encodeSsao`'s measured reason below: a filtered tap
        // across a silhouette averages a foreground depth with the cleared
        // background and lands at a depth where nothing stands. Here that reads
        // as an occluder in front of the ray, so every silhouette in the frame
        // would grow its own thin dark outline.
        sampler: SamplerOptions.nearestClamp,
      ),
    );
    developer.Timeline.finishSync();
  }

  /// Writes how far each pixel moved because the camera did — `R1`.
  ///
  /// The reconstruction `_encodeContactShadow` does, carried one step
  /// further through last frame's matrix from [frameHistory]. A camera with
  /// no past — the first frame, a view that just appeared — is given its own
  /// matrix as its past, which is a velocity of zero: the resolve has nothing
  /// to reproject yet either way.
  void _encodeCameraVelocity({
    required TextureHandle target,
    required TextureHandle surface,
    required RenderView view,
  }) {
    developer.Timeline.startSync('Renderer.cameraVelocity');

    final aspect = surface.height == 0 ? 1.0 : surface.width / surface.height;
    final current = view.camera.viewProjection(aspect);
    final previous = frameHistory.viewProjection(view.camera) ?? current;
    final origin = device.framebufferOrigin;
    final inverse = vm.Matrix4.copy(toFramebufferOrigin(current, origin))
      ..invert();

    view.camera.readWorldPosition(_ssaoCamera);
    view.camera.readForward(_ssaoForward);
    _cameraVelocityInfo.inverseViewProjection.setAll(0, inverse.storage);
    _cameraVelocityInfo.previousViewProjection.setAll(
      0,
      toFramebufferOrigin(previous, origin).storage,
    );
    _cameraVelocityInfo.camera
      ..[0] = _ssaoCamera.x
      ..[1] = _ssaoCamera.y
      ..[2] = _ssaoCamera.z;
    _cameraVelocityInfo.forward
      ..[0] = _ssaoForward.x
      ..[1] = _ssaoForward.y
      ..[2] = _ssaoForward.z;

    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: cameraVelocityShader,
        textures: <String, TextureHandle>{'surface_texture': surface},
        uniforms: <String, Map<String, Float32List>>{
          _cameraVelocityInfo.name: _cameraVelocityInfo.members,
        },
        // Unfiltered, for the contact shadow's reason: a filtered depth
        // across a silhouette is a depth where nothing stands, and its motion
        // is the motion of nothing.
        sampler: SamplerOptions.nearestClamp,
      ),
    );
    developer.Timeline.finishSync();
  }

  /// Draws ambient occlusion into [target] from the surface buffer.
  ///
  /// A node that *produces* a resource, the way bloom does, rather than one
  /// that reads the scene and rewrites it, the way reflections does. Two
  /// reasons, and the second is the one that decided it: a full-size HDR target
  /// per frame is a real cost for a signal that is low-frequency by nature, and
  /// multiplying the scene here would put the occlusion *before* bloom, so a
  /// glowing crack in a corner would stop glowing. The composite applies it
  /// after the glow is taken.
  void _encodeSsao({
    required TextureHandle target,
    required TextureHandle surface,
    required AmbientOcclusionSettings options,
    required RenderView view,
    TextureHandle? scene,
    TextureHandle? albedo,
  }) {
    developer.Timeline.startSync('Renderer.ssao');

    // Taken from the surface buffer rather than from the frame, and that is the
    // coupling worth having: the matrix inverted here has to be the one the
    // depths in that buffer were written with, so the shape it assumes should
    // come from the buffer itself. A frame that resized between the scene pass
    // and this one would otherwise reconstruct every point somewhere else.
    final aspect = surface.height == 0 ? 1.0 : surface.width / surface.height;
    // Origin-adjusted, like the matrix the shadow lookup is given and for the
    // same reason: the pass turns clip space into a texture coordinate, and
    // which end of the texture row zero is at is a property of the backend
    // rather than of the shader. Without it the taps landed at the pixel
    // mirrored about the middle of the frame on every backend but the browser.
    final viewProjection = toFramebufferOrigin(
      // **Not depth-range adjusted, and that is the whole of a bug this pass
      // carried on one backend.** `_viewProjection` applies `toDepthRange`,
      // which maps clip depth to `[-1, 1]` where the device wants it. What the
      // shader inverts this matrix for is a *direction*: the ray through a
      // pixel, taken by unprojecting its far corner. Under the other convention
      // `z = 1` is not the far plane, and the reconstructed ray pointed
      // somewhere else — behind the camera, for most of the frame. The camera's
      // own matrix is in the engine's `[0, 1]`, which is what the shader
      // assumes.
      view.camera.viewProjection(aspect),
      device.framebufferOrigin,
    );
    final inverse = vm.Matrix4.copy(viewProjection)..invert();
    // The other half of the reconstruction: the buffer holds how far along the
    // view axis the surface is, in metres, so the pass needs to know where that
    // axis starts and which way it points. See `WorldAtDepth`.
    view.camera.readWorldPosition(_ssaoCamera);
    _ssaoCameraData[0] = _ssaoCamera.x;
    _ssaoCameraData[1] = _ssaoCamera.y;
    _ssaoCameraData[2] = _ssaoCamera.z;
    view.camera.readForward(_ssaoForward);
    _ssaoForwardData[0] = _ssaoForward.x;
    _ssaoForwardData[1] = _ssaoForward.y;
    _ssaoForwardData[2] = _ssaoForward.z;

    _ssaoParams[0] = options.radius;
    // `R3`: half the taps while a resolve runs, with a new rotation each
    // frame and a history to carry the rest.
    _ssaoParams[1] =
        (_temporalEffects ? math.max(4, options.samples ~/ 2) : options.samples)
            .toDouble();
    // `L5`: whether the albedo buffer is the one bound, or a stand-in.
    _ssaoParams[2] = albedo == null ? 0.0 : 1.0;
    _ssaoParams[3] = options.bias;
    _ssaoScreen[0] = 1.0 / math.max(target.width, 1);
    _ssaoScreen[1] = 1.0 / math.max(target.height, 1);
    // `L5`: which method, read by the stage.
    _ssaoScreen[2] = options.method.code;
    _ssaoScreen[3] = math.max(options.thickness, 1e-3);

    _ssaoInfo.inverseViewProjection.setAll(0, inverse.storage);
    _ssaoInfo.viewProjection.setAll(0, viewProjection.storage);
    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: ssaoShader,
        textures: <String, TextureHandle>{
          'surface_texture': surface,
          'blue_noise_texture': _blueNoise,
          // Read only by the indirect method; the other two get the
          // cheapest textures that satisfy the samplers.
          'scene_texture': scene ?? fallbackAlbedo,
          'albedo_texture': albedo ?? fallbackAlbedo,
        },
        uniforms: <String, Map<String, Float32List>>{
          _ssaoInfo.name: _ssaoInfo.members,
          _noiseInfo.name: _noiseInfo.members,
        },
        // **Unfiltered**, unlike every other full-screen read in this renderer,
        // and measured rather than assumed: with linear filtering an isolated
        // convex slab against an empty background darkened by six levels at its
        // edges, which `ssao_test.dart` catches. A filtered tap at a silhouette
        // averages a foreground depth with the cleared background, and the result
        // is a depth at which nothing stands — nearer than the surface, so it
        // counts as an occluder.
        sampler: SamplerOptions.nearestClamp,
      ),
    );
    developer.Timeline.finishSync();
  }

  /// `gfx-33n`: adds volumetric shafts into the lit colour.
  ///
  /// Reuses the shadow pass's own matrices and splits rather than recomputing
  /// them — they describe the map this is about to sample, so a second
  /// derivation is a second thing to disagree with the map.
  TextureHandle _encodeLightShafts({
    required TextureHandle scene,
    required TextureHandle surface,
    required TextureHandle shadow,
    required LightShaftSettings settings,
    required RenderView view,
    required FrameResources resources,
    required int width,
    required int height,
    required vm.Vector3 toLight,
    required vm.Vector3 radiance,
  }) {
    developer.Timeline.startSync('Renderer.lightShafts');
    // A transient of the scene's own shape: a pass cannot sample and write
    // one texture, and nothing outside this frame wants the intermediate.
    final target = resources.transient(
      RenderTargetSpec(
        width: scene.width,
        height: scene.height,
        format: scene.format,
      ),
    );

    final aspect = height == 0 ? 1.0 : width / height;
    // Origin-adjusted and not depth-range adjusted, for the reason
    // `_encodeReflections` writes out at length: the shader inverts this to
    // find the ray through a pixel, and the other convention puts the far
    // corner somewhere else.
    final viewProjection = toFramebufferOrigin(
      view.camera.viewProjection(aspect),
      device.framebufferOrigin,
    );
    final inverse = vm.Matrix4.copy(viewProjection)..invert();

    view.camera.readWorldPosition(_shaftCameraVec);
    _shaftCamera[0] = _shaftCameraVec.x;
    _shaftCamera[1] = _shaftCameraVec.y;
    _shaftCamera[2] = _shaftCameraVec.z;
    _shaftCamera[3] = math.max(settings.distance, 0.0);

    view.camera.readForward(_shaftForwardVec);
    _shaftForward[0] = _shaftForwardVec.x;
    _shaftForward[1] = _shaftForwardVec.y;
    _shaftForward[2] = _shaftForwardVec.z;
    _shaftForward[3] = settings.steps.clamp(0, 64).toDouble();

    // What a lit point in the air sends towards the eye before the phase and
    // the path: the sun's own colour and intensity, tinted by the air's
    // albedo. The density rides in w.
    final colour = settings.color;
    _shaftScatter[0] = (colour?.x ?? 1.0) * radiance.x;
    _shaftScatter[1] = (colour?.y ?? 1.0) * radiance.y;
    _shaftScatter[2] = (colour?.z ?? 1.0) * radiance.z;
    _shaftScatter[3] = math.max(settings.strength, 0.0);

    // Which way the sun is, for the phase, and how forward it scatters.
    _shaftSun[0] = toLight.x;
    _shaftSun[1] = toLight.y;
    _shaftSun[2] = toLight.z;
    _shaftSun[3] = settings.anisotropy.clamp(-0.95, 0.95);

    _shaftCascades[0] = _shadowCascades[0];
    _shaftCascades[1] = _shadowCascades[1];
    _shaftCascades[2] = _shadowCascades[2];
    // The same bias the surface lookup uses, cascade by cascade. A point in
    // the air has no surface to lift off, so this is the only guard against a
    // shaft shadowing itself along the map's own quantisation.

    _shaftInfo.inverseViewProjection.setAll(0, inverse.storage);
    _shaftInfo.shadowMatrix.setAll(0, _shadowMatrix.storage);
    _shaftInfo.shadowMatrixFar.setAll(0, _shadowMatrixFar.storage);
    _shaftInfo.shadowMatrixFarthest.setAll(0, _shadowMatrixFarthest.storage);
    _shaftInfo.bias.setAll(0, _shadowCascadeBias);
    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: lightShaftsShader,
        textures: <String, TextureHandle>{
          'scene_texture': scene,
          'surface_texture': surface,
          'shadow_texture': shadow,
          'blue_noise_texture': _blueNoise,
        },
        uniforms: <String, Map<String, Float32List>>{
          _shaftInfo.name: _shaftInfo.members,
          _noiseInfo.name: _noiseInfo.members,
        },
        // Nearest on the surface buffer, as every other reader of it takes: a
        // filtered depth at a silhouette against the sky averages with the
        // cleared zero, halves, and stops the march early along the edge.
        samplers: const <String, SamplerOptions>{
          'surface_texture': SamplerOptions.nearestClamp,
        },
      ),
    );
    developer.Timeline.finishSync();
    return target;
  }

  /// `gfx-34n`: defocuses the lit colour through a thin lens.
  ///
  /// **Everything about scale is taken from the scene texture rather than
  /// from the frame**, which is what keeps `gfx-35n`'s resolution lever
  /// honest. Half the width is half the texels per metre and half the radius
  /// in texels, so the blur covers the same share of the picture: the lever
  /// spends less on the same photograph rather than taking a different one,
  /// and `gfx-36n` pulling it while the camera holds still does not change
  /// what is in focus.
  TextureHandle _encodeDepthOfField({
    required TextureHandle scene,
    required TextureHandle surface,
    required DepthOfFieldSettings settings,
    required FrameResources resources,
    required int width,
    required int height,
  }) {
    developer.Timeline.startSync('Renderer.depthOfField');
    // A transient of the scene's own shape, for the reason the shafts take
    // one: a pass cannot sample and write a single texture, and nothing
    // outside this frame wants the intermediate.
    final target = resources.transient(
      RenderTargetSpec(
        width: scene.width,
        height: scene.height,
        format: scene.format,
      ),
    );

    _dofLens[0] = math.max(settings.focusDistance, 1e-3);
    _dofLens[1] = math.max(settings.focalLength, 1e-4);
    _dofLens[2] = math.max(settings.aperture, 1e-3);
    _dofLens[3] = settings.samples.clamp(0, 64).toDouble();

    _dofParams[0] = scene.width == 0 ? 0.0 : 1.0 / scene.width;
    _dofParams[1] = scene.height == 0 ? 0.0 : 1.0 / scene.height;
    _dofParams[2] = math.max(settings.maxRadius, 0.0);
    // Texels per metre across the sensor. The scene texture's width rather
    // than the frame's, so that under `renderScale` the lens keeps blurring
    // the same fraction of the picture: the resolution lever is there to
    // spend less on the same photograph, not to take a different one.
    _dofParams[3] = scene.width / math.max(settings.sensorWidth, 1e-4);

    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: depthOfFieldShader,
        textures: <String, TextureHandle>{
          'scene_texture': scene,
          'surface_texture': surface,
        },
        uniforms: <String, Map<String, Float32List>>{
          _dofInfo.name: _dofInfo.members,
        },
        // Nearest on the depth: a filtered tap at a silhouette against the
        // sky mixes the object's depth with the sky's zero into a nearer
        // point that belongs to neither, and the gather then counts it as a
        // blurred foreground — a halo of the sharp object spread into the sky.
        samplers: const <String, SamplerOptions>{
          'surface_texture': SamplerOptions.nearestClamp,
        },
      ),
    );
    developer.Timeline.finishSync();
    return target;
  }

  /// `gfx-43n`/`44n`/`45n`: shades the picture from the surface buffer.
  ///
  /// [surface] is nullable and a null is not an error: the buffer is an
  /// *optional* read, so a frame that could not produce one — a device with a
  /// single colour attachment, per `gfx-50n` — gets the lit picture back
  /// untouched rather than a mode that silently did nothing.
  TextureHandle _encodeViewportShade({
    required TextureHandle scene,
    required TextureHandle? surface,
    required ViewportShadingSettings settings,
    required RenderView view,
    required FrameResources resources,
  }) {
    if (surface == null) return scene;
    developer.Timeline.startSync('Renderer.viewportShade');
    final target = resources.transient(
      RenderTargetSpec(
        width: scene.width,
        height: scene.height,
        format: scene.format,
      ),
    );

    _shadeParams[0] = settings.mode.code;
    _shadeParams[1] = settings.amount.clamp(0.0, 1.0);
    // Two meanings per slot, by mode, which is what keeps this to one block —
    // see the shader, where the same comment is the contract.
    _shadeParams[2] = switch (settings.mode) {
      ViewportShading.clay => settings.ambient.clamp(0.0, 1.0),
      ViewportShading.outline => math.max(settings.depthEdge, 1e-4),
      ViewportShading.curvature => math.max(settings.curvatureGain, 0.0),
      _ => 0.0,
    };
    _shadeParams[3] = switch (settings.mode) {
      ViewportShading.outline => settings.normalEdge.clamp(0.0, 2.0),
      ViewportShading.curvature => settings.cavity.clamp(0.0, 1.0),
      _ => 0.0,
    };

    _shadeScreen[0] = scene.width == 0 ? 0.0 : 1.0 / scene.width;
    _shadeScreen[1] = scene.height == 0 ? 0.0 : 1.0 / scene.height;
    _shadeScreen[2] = math.max(settings.outlineWidth, 1.0);

    // Over the camera's shoulder unless the caller said otherwise: a studio
    // light behind the viewer is the one arrangement where every surface a
    // modeller can see is lit, which is what clay is for.
    final aim = settings.lightDirection;
    if (aim == null) {
      view.camera.readForward(_shadeLightVec);
      _shadeLight[0] = -_shadeLightVec.x;
      _shadeLight[1] = -_shadeLightVec.y;
      _shadeLight[2] = -_shadeLightVec.z;
    } else {
      _shadeLight[0] = aim.x;
      _shadeLight[1] = aim.y;
      _shadeLight[2] = aim.z;
    }

    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: viewportShadeShader,
        textures: <String, TextureHandle>{
          'scene_texture': scene,
          'surface_texture': surface,
        },
        uniforms: <String, Map<String, Float32List>>{
          _shadeInfo.name: _shadeInfo.members,
        },
        // **Nearest on the surface buffer, for the reason the occlusion pass
        // gives at length**: a filtered tap at a silhouette averages a
        // foreground normal with the cleared background and decodes to a
        // direction belonging to neither, which an outline would draw as a
        // second edge just inside the first.
        samplers: const <String, SamplerOptions>{
          'surface_texture': SamplerOptions.nearestClamp,
        },
      ),
    );
    developer.Timeline.finishSync();
    return target;
  }

  /// Adds screen-space reflections, returning the texture the rest of the
  /// chain should treat as the scene.
  ///
  /// Its own target rather than in place: the pass samples the scene while it
  /// writes, and a texture cannot be both. Returns [scene] untouched when the
  /// effect is off, so the chain downstream never branches.
  TextureHandle _encodeReflections({
    required TextureHandle scene,
    required RenderSettings settings,
    required RenderView view,
    required int width,
    required int height,
  }) {
    final surface = _surfaceColor;
    if (!settings.reflections.enabled || surface == null) return scene;
    developer.Timeline.startSync('Renderer.reflections');

    final target = _reflectionColor!;
    final aspect = height == 0 ? 1.0 : width / height;
    // Origin-adjusted, for the reason written on `_encodeSsao`'s: the march
    // reads the surface buffer at a coordinate it derives from clip space, and
    // that derivation depends on where the backend puts row zero. Marching
    // against a vertically mirrored buffer is what made this effect look like
    // it did not work.
    final viewProjection = toFramebufferOrigin(
      // **Not depth-range adjusted, and that is the whole of a bug this pass
      // carried on one backend.** `_viewProjection` applies `toDepthRange`,
      // which maps clip depth to `[-1, 1]` where the device wants it, and the
      // shader inverts this matrix to find the ray through a pixel — taken by
      // unprojecting the pixel's far corner, which under the other convention
      // is not the far corner at all. See `_encodeSsao`, which reconstructs the
      // same way.
      view.camera.viewProjection(aspect),
      device.framebufferOrigin,
    );
    final inverse = vm.Matrix4.copy(viewProjection)..invert();
    view.camera.readWorldPosition(_reflectionCamera);

    final options = settings.reflections;
    _reflectionParams[0] = options.steps.toDouble();
    _reflectionParams[1] = options.stride;
    _reflectionParams[2] = options.thickness;
    _reflectionParams[3] = options.intensity;
    _reflectionScreen[0] = 1.0 / width;
    _reflectionScreen[1] = 1.0 / height;
    _reflectionScreen[3] = options.debugOnly ? 1.0 : 0.0;

    _reflectionCameraData[0] = _reflectionCamera.x;
    _reflectionCameraData[1] = _reflectionCamera.y;
    _reflectionCameraData[2] = _reflectionCamera.z;
    // With the position, the axis the buffer measures its depths along; see
    // `WorldAt`.
    view.camera.readForward(_reflectionForward);
    _reflectionForwardData[0] = _reflectionForward.x;
    _reflectionForwardData[1] = _reflectionForward.y;
    _reflectionForwardData[2] = _reflectionForward.z;

    _reflectionInfo.viewProjection.setAll(0, viewProjection.storage);
    _reflectionInfo.inverseViewProjection.setAll(0, inverse.storage);
    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: reflectionShader,
        textures: <String, TextureHandle>{
          'scene_texture': scene,
          'surface_texture': surface,
          'blue_noise_texture': _blueNoise,
        },
        uniforms: <String, Map<String, Float32List>>{
          _reflectionInfo.name: _reflectionInfo.members,
          _noiseInfo.name: _noiseInfo.members,
        },
        // Nearest on the surface buffer, as every other reader of it takes:
        // a filtered tap at a silhouette averages the object's depth with the
        // background behind it and reports a surface where there is none,
        // which the march then "hits".
        samplers: const <String, SamplerOptions>{
          'surface_texture': SamplerOptions.nearestClamp,
        },
      ),
    );
    developer.Timeline.finishSync();
    return target;
  }

  /// Writes the scene's log luminance into [target], the small texture the
  /// exposure meter reads back.
  void _encodeLuminance({
    required TextureHandle target,
    required TextureHandle scene,
  }) {
    developer.Timeline.startSync('Renderer.luminance');
    final shader = shaders['Luminance'];
    if (shader == null) {
      throw StateError(
        'The bundle has no "Luminance" fragment shader, which auto exposure '
        'meters with. Rebuild it with tool/build_shaders.sh.',
      );
    }
    // One texel of the *target*, which is the footprint each of its texels
    // averages over — see luminance.frag — and the two ends of the encoding
    // the meter decodes with.
    _luminanceParams[0] = 1.0 / math.max(target.width, 1);
    _luminanceParams[1] = 1.0 / math.max(target.height, 1);
    _luminanceParams[2] = ExposureMeter.floorStops;
    _luminanceParams[3] = 1.0 / ExposureMeter.rangeStops;
    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: shader,
        textures: <String, TextureHandle>{_kSceneTextureSlot: scene},
        uniforms: <String, Map<String, Float32List>>{
          _luminanceInfo.name: _luminanceInfo.members,
        },
      ),
    );
    developer.Timeline.finishSync();
  }

  /// Asks for the luminance target's bytes and hands them to the adapter when
  /// they arrive. Returns at once; the answer is a frame or two away.
  ///
  /// Not while the last ask is still unanswered — see [_meterInFlight]. The
  /// pass that wrote the target has run either way; what is skipped is the
  /// copy and the download behind it, and the frame is metered again the
  /// frame after the answer lands.
  /// [views] is what each per-view adapter meters its own rectangle of —
  /// `gfx-22n`. Empty, or per-view metering switched off, and there is one
  /// adapter reading the whole histogram, as there always was.
  void _meterExposure(
    TextureHandle target,
    AutoExposureSettings settings, {
    List<RenderView> views = const <RenderView>[],
  }) {
    final adapter = _autoExposure;
    if (adapter == null || _meterInFlight) return;
    _meterInFlight = true;
    // **`Future.sync`, and it is what makes the sentence above true.** A
    // refusal is synchronous by contract — `readbackRegionOf` throws an
    // `ArgumentError` before any future exists, which is exactly what the
    // conformance check tests for — and the backends throw on their own
    // account too: WebGL2 refuses a fence when the context has been lost,
    // flutter_gpu throws rather than returning false when a copy or a submit
    // is refused. Called bare, every one of those would leave the handler
    // below untouched and come out of this node, so a lost context would
    // take the whole frame down. Wrapped, the throw is the future's failure,
    // where it is counted — and `whenComplete` clears the flag, without which
    // the meter would never ask the device again.
    Future<ByteData>.sync(() => device.readback(target))
        .then(
          (ByteData bytes) {
            // The frame's own exposure first: it is what a single-view frame
            // uses, what `FrameResult.exposure` reports, and where a view
            // joining later starts from.
            adapter.meter(bytes, settings);
            if (!settings.perView) return;
            // Then each view's own rectangle of the same bytes. One readback,
            // several histograms — see `ExposureMeter._histogram`, which is
            // why this costs no extra pass and no extra download.
            for (var i = 0; i < _viewExposure.length && i < views.length; i++) {
              final rect = views[i].viewportFraction;
              _viewExposure[i].meter(
                bytes,
                settings,
                within: (
                  x: rect.x,
                  y: rect.y,
                  width: rect.width,
                  height: rect.height,
                ),
              );
            }
          },
          // A refused copy leaves the exposure where it was, which is the
          // right picture for a frame, and is counted rather than swallowed
          // so a meter that has stopped hearing back is visible as a number.
          onError: (Object _, StackTrace _) {
            _meterFailures++;
          },
        )
        .whenComplete(() => _meterInFlight = false);
  }

  /// Reduces [surface] into [target], the small grid the occlusion readback
  /// takes — `C3`, `depth_pyramid.frag`.
  void _encodeDepthPyramid({
    required TextureHandle target,
    required TextureHandle surface,
    required double far,
  }) {
    developer.Timeline.startSync('Renderer.depthPyramid');
    final shader = shaders['DepthPyramid'];
    if (shader == null) {
      throw StateError(
        'The bundle has no "DepthPyramid" fragment shader, which hi-Z '
        'occlusion reads the depth back through. Rebuild it with '
        'tool/build_shaders.sh.',
      );
    }
    final block = _depthPyramidInfo.block;
    block[0] = 1.0 / math.max(target.width, 1);
    block[1] = 1.0 / math.max(target.height, 1);
    block[2] = surface.width / math.max(target.width, 1);
    block[3] = surface.height / math.max(target.height, 1);
    _depthPyramidInfo.range[0] = far > 0.0 ? 1.0 / far : 0.0;
    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: shader,
        textures: <String, TextureHandle>{'surface_texture': surface},
        uniforms: <String, Map<String, Float32List>>{
          _depthPyramidInfo.name: _depthPyramidInfo.members,
        },
        // Nearest: a depth filtered across a silhouette is the depth of
        // neither surface, and the reduction wants the ones that are there.
        samplers: const <String, SamplerOptions>{
          'surface_texture': SamplerOptions.nearestClamp,
        },
      ),
    );
    developer.Timeline.finishSync();
  }

  /// Asks for the depth pyramid's bytes and hands them to [_hiZ] with the
  /// view they were seen through. Returns at once; the reading lands a frame
  /// or two later, and until then the occlusion test answers "visible".
  ///
  /// One ask at a time, and a refused copy costs nothing but the reading —
  /// the same shape as [_meterExposure], for its reasons.
  void _readDepthPyramid(
    TextureHandle target, {
    required CameraNode camera,
    required double aspect,
  }) {
    final hiZ = _hiZ;
    if (hiZ == null || _pyramidInFlight) return;
    _pyramidInFlight = true;
    final epoch = _hiZEpoch;
    final viewProjection = camera.viewProjection(aspect);
    final eye = camera.readWorldPosition();
    final forward = camera.readForward();
    final far = camera.projection.far;
    Future<ByteData>.sync(() => device.readback(target))
        .then((ByteData bytes) {
          // Thrown away while it was in the air: a frame since has run
          // without hi-Z, and the scene this saw is not one to trust.
          if (epoch != _hiZEpoch) return;
          hiZ.accept(
            bytes,
            viewProjection: viewProjection,
            eye: eye,
            forward: forward,
            far: far,
            camera: camera,
          );
        }, onError: (Object _, StackTrace _) {})
        .whenComplete(() => _pyramidInFlight = false);
  }

  /// The final pass: bloom in, tone map, sRGB, then the debug overlay on top.
  ///
  /// One pass for both because the overlay has to land on the finished image
  /// but must not be a separate render target — and because keeping the pass
  /// open is free, while a second one would reload the attachment.
  ///
  /// Returns the number of overlay line segments drawn, and how many draws
  /// the composite itself made — one, or one per view when `gfx-22n`'s
  /// per-view exposure is on. Counted rather than assumed: the node used to
  /// add a hardcoded one, which was true for as long as there was one draw
  /// and silently wrong the moment there were two.
  ({int lines, int draws}) _encodeComposite({
    required TextureHandle target,
    required TextureHandle scene,
    required TextureHandle? bloom,
    required TextureHandle? ao,
    required TextureHandle? contactShadow,
    required TextureHandle? surface,
    required TextureHandle? shadowView,
    TextureHandle? velocity,
    required Scene sceneGraph,
    required List<RenderView> views,
    required RenderSettings settings,
    required int width,
    required int height,
  }) {
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          ColorTarget(texture: target, loadAction: LoadAction.dontCare),
        ],
      ),
    );

    final full = ScreenRect(width: width, height: height);
    pass.setState(
      Renderer._kFullscreenState.copyWith(viewport: full, scissor: full),
    );

    // `gfx-22n`. One draw covering everything, unless each view is exposing
    // itself — then one draw per view, scissored to its own rectangle, so the
    // exposure in the uniform is the one that view metered. With per-view
    // metering off, or with a single view, this is the one full-frame draw it
    // has always been and the bytes are the bytes forty-four goldens hold.
    final perView =
        settings.autoExposure.enabled &&
        settings.autoExposure.perView &&
        views.length > 1;

    final mix = CompositeMix(
      showSurfaceBuffer: settings.showSurfaceBuffer,
      showPointShadowDebug: settings.showPointShadowDebug,
      showShadowMap: settings.showShadowMap || settings.showStaticShadowMap,
      hasShadowView: shadowView != null,
      hasGlow: bloom != null,
      exposure: _exposureFor(settings),
      bloomIntensity: settings.bloom.intensity,
      tonemap: settings.tonemap,
      curve: settings.tonemapCurve,
      showVelocity: settings.showVelocity,
      hasVelocity: velocity != null,
    );
    _compositeParams[0] = mix.exposure;
    _compositeParams[1] = mix.bloomIntensity;
    // `L2`: a display transform in place of the curve, when one is set or
    // the curve is the table the engine ships — and never for a raw view,
    // which the mix has already told to leave the colour alone.
    final display = mix.tonemap == 0.0
        ? null
        : settings.look.displayTransform ??
              (settings.tonemapCurve == TonemapCurve.aces2
                  ? DisplayTransform(
                      texture: EngineTables.of(device).aces2Display,
                      size: EngineTables.aces2DisplaySize,
                    )
                  : null);
    _compositeParams[2] = display != null ? 6.0 : mix.tonemap;
    _compositeContact[1] = display?.size.toDouble() ?? 0.0;

    pass.bindPipeline(
      _postPipeline(
        _compositePipeline,
        compositeShader,
        (p) => _compositePipeline = p,
      ),
    );
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
    pass.bindTexture(compositeShader, _kSceneTextureSlot, switch (mix.view) {
      // Non-null by construction: [CompositeMix] only picks these when it was
      // told the texture exists.
      CompositeView.shadowMap => shadowView!,
      CompositeView.surfaceBuffer => surface ?? scene,
      CompositeView.scene => scene,
      CompositeView.velocity => velocity!,
    }, sampler: Renderer._clampSampler);
    // With bloom culled there is still a sampler to satisfy, and the scene
    // itself is the cheapest texture to hand it — [CompositeMix] set the
    // intensity to zero for exactly this case, so its contribution is
    // multiplied out. The two knobs come from one object because nothing in the
    // shader would notice them disagreeing.
    pass.bindTexture(
      compositeShader,
      _kBloomTextureSlot,
      mix.usesGlow ? bloom! : scene,
      sampler: Renderer._clampSampler,
    );
    // The same shape as the glow above, with the opposite neutral: unoccluded
    // is white, and `fallbackAlbedo` is a 1×1 opaque white that already exists
    // for exactly this kind of "a sampler must have something in it". The
    // strength is zeroed alongside it, so the stand-in is multiplied out rather
    // than relied upon — either alone would do, and having both means a
    // mismatch between them cannot darken anything.
    final occlusion = ao != null && settings.ambientOcclusion.enabled
        ? ao
        : null;
    _compositeParams[3] = occlusion == null
        ? 0.0
        : settings.ambientOcclusion.strength;
    // `L5`: the buffer's rgb is light only when the indirect method drew it;
    // otherwise it is the occlusion again, or the white stand-in.
    _compositeContact[2] =
        occlusion != null &&
            settings.ambientOcclusion.method == AmbientOcclusionMethod.ssil
        ? 1.0
        : 0.0;
    _compositeAoTexel[0] = 1.0 / math.max(occlusion?.width ?? 1, 1);
    _compositeAoTexel[1] = 1.0 / math.max(occlusion?.height ?? 1, 1);
    pass.bindTexture(
      compositeShader,
      _kAoTextureSlot,
      occlusion ?? fallbackAlbedo,
      sampler: Renderer._clampSampler,
    );
    // `gfx-76n`, the same pairing once more: unoccluded is white, the 1×1 white
    // stands in when the node was culled, and the strength is zeroed beside it
    // so the stand-in is multiplied out rather than trusted. Its own strength
    // and not the occlusion's — a scene may want a seam at a join without
    // wanting ambient occlusion, and folding the two would make one of those
    // settings silently govern the other.
    final contact = contactShadow != null && settings.contactShadows.enabled
        ? contactShadow
        : null;
    _compositeContact[0] = contact == null
        ? 0.0
        : settings.contactShadows.strength.clamp(0.0, 1.0);
    pass.bindTexture(
      compositeShader,
      _kContactShadowTextureSlot,
      contact ?? fallbackAlbedo,
      sampler: Renderer._clampSampler,
    );

    // The colour table, or nothing — `gfx-18n`. The same pairing as the two
    // samplers above: a texture is always bound because a declared sampler
    // with nothing in it is a native crash on Metal, and the strength is
    // zeroed alongside it so the stand-in is never read. Its size comes off
    // the texture rather than from a field: a strip is N² by N, so the height
    // *is* N, and a table whose two dimensions disagree about that is a table
    // the engine should not be guessing about.
    final look = settings.look;
    final lut = look.gradesThroughLut ? look.lut : null;
    _compositeAoTexel[2] = lut == null ? 0.0 : look.lutStrength.clamp(0.0, 1.0);
    _compositeAoTexel[3] = (lut?.height ?? 2).toDouble();
    pass.bindTexture(
      compositeShader,
      _kLutTextureSlot,
      lut ?? fallbackAlbedo,
      sampler: Renderer._clampSampler,
    );
    // `L2`, the same pairing: the table when the curve reads one, the
    // stand-in otherwise, never unbound.
    pass.bindTexture(
      compositeShader,
      'display_texture',
      display?.texture ?? fallbackAlbedo,
      sampler: Renderer._clampSampler,
    );

    // Neutral is (1, 1, 0, 0) and (0, …, 0, aspect), which the shader relies on
    // being exact: every golden in the repository goes through this block, and a
    // default that only nearly cancels moves all of them by a bit each.
    _compositeLook[0] = look.contrast;
    _compositeLook[1] = look.saturation;
    _compositeLook[2] = look.temperature;
    _compositeLook[3] = math.max(look.chromaticAberration, 0.0);
    _compositeLookMore[0] = look.vignette.clamp(0.0, 1.0);
    _compositeLookMore[1] = look.vignetteRoundness.clamp(0.0, 1.0);
    _compositeLookMore[2] = math.max(look.grain, 0.0);
    // The vignette is computed in UV space, which is square while the frame is
    // not — without this the falloff is an ellipse on screen.
    _compositeLookMore[3] = height <= 0 ? 1.0 : width / height;

    // `gfx-24n`. Zero exactly, and every golden depends on it: the shader
    // skips the whole branch at zero rather than adding a noise that rounds
    // to nothing, because "rounds to nothing" is a claim about the target's
    // bit depth and not about the arithmetic.
    _compositeOutputEncode[0] = math.max(look.dither, 0.0);
    _compositeOutputEncode[1] = look.whiteBalance.clamp(-1.0, 1.0);
    _compositeOutputEncode[2] = look.tint.clamp(-1.0, 1.0);

    // `gfx-27n`. Written every frame rather than only when set, because the
    // buffers are reused across frames and a grade left in one would apply to
    // the next scene that did not ask for it.
    final lift = look.lift;
    _compositeLift[0] = lift?.x ?? 0.0;
    _compositeLift[1] = lift?.y ?? 0.0;
    _compositeLift[2] = lift?.z ?? 0.0;
    final gamma = look.gamma;
    // Guarded away from zero: the shader raises to one over this, and an
    // exponent of infinity is a black frame rather than a loud failure.
    _compositeGamma[0] = math.max(gamma?.x ?? 1.0, 1e-3);
    _compositeGamma[1] = math.max(gamma?.y ?? 1.0, 1e-3);
    _compositeGamma[2] = math.max(gamma?.z ?? 1.0, 1e-3);
    final gain = look.gain;
    _compositeGain[0] = gain?.x ?? 1.0;
    _compositeGain[1] = gain?.y ?? 1.0;
    _compositeGain[2] = gain?.z ?? 1.0;

    // The whole block, every member at once, because a bind replaces the
    // block rather than patching it: rebinding with `params` alone would
    // leave a per-view frame with no look, no grade and an occlusion texel of
    // zero.
    pass.bindBlock(compositeShader, _compositeInfo);
    _bindFragCoord(pass, compositeShader, target);
    var draws = 1;
    if (!perView) {
      pass.draw();
    } else {
      draws = views.length;
      for (var i = 0; i < views.length; i++) {
        final rect = Renderer._viewportPixels(
          views[i].viewportFraction,
          width,
          height,
        );
        // The scissor as well as the viewport: the covering triangle is
        // oversized on purpose, so a viewport alone would leave each draw
        // painting the whole attachment with that view's exposure and the
        // last one would win.
        pass
          ..setViewport(rect)
          ..setScissor(rect);
        _compositeParams[0] = _exposureForView(settings, i);
        pass
          ..bindBlock(compositeShader, _compositeInfo)
          ..draw();
      }
      // Back to the whole frame, because the overlay loop below sets its own
      // viewport and trusts the scissor to be the pass's.
      pass
        ..setViewport(full)
        ..setScissor(full);
    }

    if (!settings.debug.anyEnabled && settings.highlighted.isEmpty) {
      pass.submit();
      return (lines: 0, draws: draws);
    }

    var lines = 0;
    for (final view in views) {
      final rect = Renderer._viewportPixels(
        view.viewportFraction,
        width,
        height,
      );
      final vw = rect.width;
      final vh = rect.height;
      // The viewport alone, inside a scissor that already covers the whole
      // frame: the overlay is clipped by the pass, not by the view.
      pass.setViewport(rect);

      if (_encodeDebugLines(
        encoder: pass,
        scene: sceneGraph,
        view: view,
        viewProjection: _viewProjection(view.camera, vw / vh),
        aspect: vw / vh,
        settings: settings,
      )) {
        lines += debugDraw.lineCount;
      }
    }
    pass.submit();
    return (lines: lines, draws: draws);
  }
}
