/// Weighted blended transparency — `R8`: the transparent half of every view,
/// drawn into two targets of its own in any order and laid over the scene by
/// one full-screen resolve.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// **Only when `RenderSettings.transparency` asks.** With the default,
/// [TransparencyMode.sorted], none of this runs: the scene pass draws its
/// transparent half back to front as it always has, and `FogInfo.forward.w`
/// stays nought, which is the value that leaves every stage's output as it
/// was.
///
/// Asked, the scene pass draws the opaque half and the sky, the x-ray stage
/// after them, and stores its depth; it keeps each view's transparent draws
/// rather than drawing them. Then, in passes of their own:
///
/// 1. **The layers.** Every transparent draw adds its weighted colour into
///    the accumulation target and multiplies the revealage target by what it
///    lets through, tested against the stored depth and writing none. One
///    pass with both targets attached where the device can blend them
///    differently (`supportsIndependentBlend`); two passes otherwise, one per
///    target, the list drawn in each.
/// 2. **The resolve and what follows it.** The scene target loaded, the
///    weighted average laid over it with the premultiplied source-over, and
///    the contributors drawn after, against the same depth — so a particle in
///    front of a pane stays in front of it, as it does sorted.
///
/// The x-ray silhouettes stay in the scene pass, under the glass rather than
/// over it: their stencil marks are the scene pass's, and a silhouette seen
/// through a window is behind that window.
part of 'renderer.dart';

/// How a transparent draw blends into the weighted blended targets: the
/// accumulation's equation on attachment zero, and the revealage's on
/// attachment one where both are attached. See `Renderer._encodeNode`.
typedef _OrderIndependentBlend = ({BlendState first, BlendState? second});

/// One view's share of the transparent half, kept by the scene pass for the
/// passes after it. Everything [_TransparencyPasses._restoreView] needs to put
/// the renderer back where it stood when the view was drawn.
typedef _DeferredTransparency = ({
  RenderView view,
  ScreenRect rect,
  vm.Matrix4 viewProjection,
  bool wireframe,
  bool clustered,
  vm.Vector3 eye,
  vm.Vector3 forward,
  List<MeshNode> transparent,
});

extension _TransparencyPasses on Renderer {
  /// What the revealage target is blended with: the destination times one
  /// minus the source, which the stage writes as the layer's alpha in every
  /// channel. Cleared to one, it ends as the product of one minus every
  /// layer's alpha — how much of the scene still shows.
  static const BlendState _revealageBlend = BlendState(
    sourceColorFactor: BlendFactor.zero,
    destinationColorFactor: BlendFactor.oneMinusSourceColor,
    sourceAlphaFactor: BlendFactor.zero,
    destinationAlphaFactor: BlendFactor.oneMinusSourceAlpha,
  );

  /// The resolve: premultiplied source-over, no depth.
  static const PassState _resolveState = PassState(
    primitiveType: PrimitiveType.triangle,
    cullMode: CullMode.none,
    blend: BlendState.alphaBlend,
    depthWrite: false,
    depthCompare: CompareFunction.always,
  );

  /// The accumulation, the revealage and the depth the scene pass stores for
  /// the passes after it, made the first time a frame asks.
  ///
  /// The depth is one-sample, which is why the scene pass does not
  /// multisample while these are in use: every target of a pass must agree
  /// on its sample count, and the layers' targets are read by the resolve,
  /// so they are one-sample themselves.
  ({TextureHandle accumulation, TextureHandle revealage, TextureHandle depth})
  _weightedBlendedTargets() {
    TextureHandle make(TextureFormat format) => device.createTexture(
      RenderTargetSpec(
        width: _targetWidth,
        height: _targetHeight,
        format: format,
        storageMode: StorageMode.devicePrivate,
      ),
    );
    final accumulation = _wboitAccumulation ??= make(hdrFormat);
    final revealage = _wboitRevealage ??= make(hdrFormat);
    final depth = _wboitDepth ??= make(device.defaultDepthStencilFormat);
    return (accumulation: accumulation, revealage: revealage, depth: depth);
  }

  /// Puts back what the scene pass had set for [deferred]'s view when it drew
  /// it: the camera the lit stages read, and the light clusters, rebuilt only
  /// when another view has been cut since.
  void _restoreView(
    _DeferredTransparency deferred, {
    required bool rebuildClusters,
  }) {
    _cameraData[0] = deferred.eye.x;
    _cameraData[1] = deferred.eye.y;
    _cameraData[2] = deferred.eye.z;
    _forwardData[0] = deferred.forward.x;
    _forwardData[1] = deferred.forward.y;
    _forwardData[2] = deferred.forward.z;
    _clustersActive = deferred.clustered;
    if (deferred.clustered && rebuildClusters) {
      final projection = deferred.view.camera.projection;
      _lightClusters.build(
        lights,
        deferred.viewProjection,
        near: projection.near,
        far: projection.far,
      );
    }
  }

  /// Opens [pass] on [deferred]'s viewport, as the scene pass opens a view.
  void _beginView(
    PassEncoder pass,
    _DeferredTransparency deferred,
    FramePassState state,
  ) {
    pass.setState(
      Renderer._kSceneViewState.copyWith(
        viewport: deferred.rect,
        scissor: deferred.rect,
        polygonMode: deferred.wireframe ? PolygonMode.line : PolygonMode.fill,
      ),
    );
    state
      ..depthCompare = CompareFunction.less
      ..invalidatePipeline();
  }

  /// Draws [views]' transparent halves into the weighted blended targets,
  /// resolves them over the scene target, and draws [contributors] after —
  /// the passes the module comment lists, in its order.
  void _encodeWeightedBlended({
    required Scene scene,
    required List<_DeferredTransparency> views,
    required RenderSettings settings,
    required int width,
    required int height,
    required SceneShadows shadows,
    required _SceneProbes probes,
    required FramePassState passState,
    required List<PassContributor> contributors,
  }) {
    final targets = _weightedBlendedTargets();
    final independent = device.supportsIndependentBlend;
    final multiView = views.length > 1;

    // The layers. `forward.w` names what the stages write: both shares at
    // once (3), or the accumulation's (1) and then the revealage's (2).
    void drawLayers({
      required List<ColorTarget> colors,
      required double mode,
      required _OrderIndependentBlend blend,
    }) {
      final pass = device.beginRenderPass(
        RenderPassDescriptor(
          label: _passLabel,
          colors: colors,
          depth: DepthTarget(
            texture: targets.depth,
            loadAction: LoadAction.load,
            storeAction: StoreAction.store,
          ),
        ),
      );
      _forwardData[3] = mode;
      for (final deferred in views) {
        if (deferred.transparent.isEmpty) continue;
        _restoreView(deferred, rebuildClusters: multiView);
        _beginView(pass, deferred, passState);
        for (final node in deferred.transparent) {
          _encodeNode(
            encoder: pass,
            node: node,
            scene: scene,
            settings: settings,
            viewProjection: deferred.viewProjection,
            shadows: shadows,
            probes: probes,
            lights: lights,
            shadowSlots: _shadowSlots,
            state: passState,
            orderIndependent: blend,
          );
        }
      }
      pass.submit();
    }

    final accumulation = ColorTarget(
      texture: targets.accumulation,
      clearValue: vm.Vector4.zero(),
    );
    final revealage = ColorTarget(
      texture: targets.revealage,
      clearValue: vm.Vector4.all(1.0),
    );
    if (independent) {
      drawLayers(
        colors: <ColorTarget>[accumulation, revealage],
        mode: 3.0,
        blend: (first: BlendState.additive, second: _revealageBlend),
      );
    } else {
      drawLayers(
        colors: <ColorTarget>[accumulation],
        mode: 1.0,
        blend: (first: BlendState.additive, second: null),
      );
      drawLayers(
        colors: <ColorTarget>[revealage],
        mode: 2.0,
        blend: (first: _revealageBlend, second: null),
      );
    }
    // Nought again before anything else binds the block: the view model,
    // a probe's capture and the next frame all draw sorted.
    _forwardData[3] = 0.0;

    // The resolve, over the whole target at once — each view's layers are
    // already inside its own viewport — and then the contributors, view by
    // view, as the scene pass would have drawn them.
    final hdr = _hdrColor!;
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          ColorTarget(texture: hdr, loadAction: LoadAction.load),
        ],
        depth: DepthTarget(texture: targets.depth, loadAction: LoadAction.load),
      ),
    );
    pass
      ..setState(
        _resolveState.copyWith(
          viewport: ScreenRect.of(hdr),
          scissor: ScreenRect.of(hdr),
        ),
      )
      ..bindPipeline(
        _postPipeline(
          _wboitResolvePipeline,
          wboitResolveShader,
          (p) => _wboitResolvePipeline = p,
        ),
      )
      ..bindVertexBuffer(_fullscreenTriangle, 3)
      ..bindIndexBuffer(_identityIndices(3), IndexType.int32, 3)
      ..bindTexture(
        wboitResolveShader,
        'accumulation_texture',
        targets.accumulation,
        sampler: SamplerOptions.nearestClamp,
      )
      ..bindTexture(
        wboitResolveShader,
        'revealage_texture',
        targets.revealage,
        sampler: SamplerOptions.nearestClamp,
      )
      ..draw();
    _frameCounters?.drawCalls++;
    passState.invalidatePipeline();

    if (contributors.isNotEmpty) {
      final temporal =
          settings.antiAlias.temporal.enabled && device.maxColorAttachments > 1;
      for (final deferred in views) {
        _restoreView(deferred, rebuildClusters: multiView);
        _beginView(pass, deferred, passState);
        _contributorLights.begin(lights, settings);
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
              view: deferred.view,
              viewProjection: deferred.viewProjection,
              frameIndex: _frameIndex,
              temporal: temporal,
              lights: _contributorLights,
            ),
          );
        }
        _contributorLights.end();
      }
    }
    _clustersActive = false;
    pass.submit();
  }
}
