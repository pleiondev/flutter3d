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
    final levels = settings.levels.clamp(1, 8);
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
            _kBloomInfoBlock: <String, Float32List>{'params': _bloomParams},
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

      _drawFullscreenAdditive(target: into, source: from);
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
    pass.bindUniformBlock(bloomUpsampleShader, _kBloomInfoBlock, {
      'params': _bloomParams,
    });
    pass.draw();
    pass.submit();
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
      // which maps clip depth to `[-1, 1]` where the device wants it — and
      // what this pass compares against is `gl_FragCoord.z`, the *window*
      // depth, which is `[0, 1]` on every API there is. On a backend whose
      // range is `[0, 1]` the two agree by accident; on one whose range is
      // `[-1, 1]` the shader reconstructed every world point from a depth the
      // inverse matrix did not expect and then compared it against a number
      // from the other convention. The camera's own matrix is already in the
      // engine's `[0, 1]`, which is the convention the buffer is written in.
      view.camera.viewProjection(aspect),
      device.framebufferOrigin,
    );
    final inverse = vm.Matrix4.copy(viewProjection)..invert();

    _ssaoParams[0] = options.radius;
    _ssaoParams[1] = options.samples.toDouble();
    // z is the composite's to apply; see the block's docstring in ssao.frag.
    _ssaoParams[2] = 0.0;
    _ssaoParams[3] = options.bias;
    _ssaoScreen[0] = 1.0 / math.max(target.width, 1);
    _ssaoScreen[1] = 1.0 / math.max(target.height, 1);

    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: ssaoShader,
        textures: <String, TextureHandle>{'surface_texture': surface},
        uniforms: <String, Map<String, Float32List>>{
          _kSsaoInfoBlock: <String, Float32List>{
            'inverse_view_projection': inverse.storage,
            'view_projection': viewProjection.storage,
            'params': _ssaoParams,
            'screen': _ssaoScreen,
          },
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
      // which maps clip depth to `[-1, 1]` where the device wants it — and
      // what this pass compares against is `gl_FragCoord.z`, the *window*
      // depth, which is `[0, 1]` on every API there is. On a backend whose
      // range is `[0, 1]` the two agree by accident; on one whose range is
      // `[-1, 1]` the shader reconstructed every world point from a depth the
      // inverse matrix did not expect and then compared it against a number
      // from the other convention. The camera's own matrix is already in the
      // engine's `[0, 1]`, which is the convention the buffer is written in.
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

    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: reflectionShader,
        textures: <String, TextureHandle>{
          'scene_texture': scene,
          'surface_texture': surface,
        },
        uniforms: <String, Map<String, Float32List>>{
          _kReflectionInfoBlock: <String, Float32List>{
            'view_projection': viewProjection.storage,
            'inverse_view_projection': inverse.storage,
            'camera': _reflectionCameraData,
            'params': _reflectionParams,
            'screen': _reflectionScreen,
          },
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
          _kLuminanceInfoBlock: <String, Float32List>{
            'params': _luminanceParams,
          },
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
  void _meterExposure(TextureHandle target, AutoExposureSettings settings) {
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
          (ByteData bytes) => adapter.meter(bytes, settings),
          // A refused copy leaves the exposure where it was, which is the
          // right picture for a frame, and is counted rather than swallowed
          // so a meter that has stopped hearing back is visible as a number.
          onError: (Object _, StackTrace _) => _meterFailures++,
        )
        .whenComplete(() => _meterInFlight = false);
  }

  /// The final pass: bloom in, tone map, sRGB, then the debug overlay on top.
  ///
  /// One pass for both because the overlay has to land on the finished image
  /// but must not be a separate render target — and because keeping the pass
  /// open is free, while a second one would reload the attachment.
  ///
  /// Returns the number of overlay line segments drawn.
  int _encodeComposite({
    required TextureHandle target,
    required TextureHandle scene,
    required TextureHandle? bloom,
    required TextureHandle? ao,
    required TextureHandle? surface,
    required TextureHandle? shadowView,
    required Scene sceneGraph,
    required List<RenderView> views,
    required RenderSettings settings,
    required int width,
    required int height,
  }) {
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: target, loadAction: LoadAction.dontCare),
        ],
      ),
    );

    final full = ScreenRect(width: width, height: height);
    pass.setState(
      Renderer._kFullscreenState.copyWith(viewport: full, scissor: full),
    );

    final mix = CompositeMix(
      showSurfaceBuffer: settings.showSurfaceBuffer,
      showPointShadowDebug: settings.showPointShadowDebug,
      showShadowMap: settings.showShadowMap || settings.showStaticShadowMap,
      hasShadowView: shadowView != null,
      hasGlow: bloom != null,
      exposure: _exposureFor(settings),
      bloomIntensity: settings.bloom.intensity,
      tonemap: settings.tonemap,
    );
    _compositeParams[0] = mix.exposure;
    _compositeParams[1] = mix.bloomIntensity;
    _compositeParams[2] = mix.tonemap;

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
    _compositeAoTexel[0] = 1.0 / math.max(occlusion?.width ?? 1, 1);
    _compositeAoTexel[1] = 1.0 / math.max(occlusion?.height ?? 1, 1);
    pass.bindTexture(
      compositeShader,
      _kAoTextureSlot,
      occlusion ?? fallbackAlbedo,
      sampler: Renderer._clampSampler,
    );
    // Neutral is (1, 1, 0, 0) and (0, …, 0, aspect), which the shader relies on
    // being exact: every golden in the repository goes through this block, and a
    // default that only nearly cancels moves all of them by a bit each.
    final look = settings.look;
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

    pass.bindUniformBlock(compositeShader, _kCompositeInfoBlock, {
      'params': _compositeParams,
      'ao_texel': _compositeAoTexel,
      'look': _compositeLook,
      'look_more': _compositeLookMore,
    });
    pass.draw();

    if (!settings.debug.anyEnabled && settings.highlighted.isEmpty) {
      pass.submit();
      return 0;
    }

    var lines = 0;
    for (final view in views) {
      final fraction = view.viewportFraction;
      final vw = math.max(1, (fraction.width * width).round());
      final vh = math.max(1, (fraction.height * height).round());
      // The viewport alone, inside a scissor that already covers the whole
      // frame: the overlay is clipped by the pass, not by the view.
      pass.setViewport(
        ScreenRect(
          x: (fraction.x * width).round(),
          y: (fraction.y * height).round(),
          width: vw,
          height: vh,
        ),
      );

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
    return lines;
  }
}
