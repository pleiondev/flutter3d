/// The scene split around a copy of itself — `M3`: glass that shows what
/// stands behind it.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// **Only on a frame that holds a transmissive draw.** A material of the
/// layered model with a transmission factor above nought, visible, in a
/// layer some view draws — see [_TransmissionPasses._holdsTransmission]. Every
/// other frame registers the two nodes this adds, finds them inactive, culls
/// them, and draws the scene in one pass exactly as it did before.
///
/// Such a frame draws in three steps, each a node of its own:
///
/// 1. **The scene** (`'scene'`): the opaque half without its transmissive
///    draws, the sky, and the x-ray silhouettes, into the scene target, with
///    its depth stored — the depth a pass leaves behind is otherwise tile
///    memory that holds nothing once it ends. It keeps each view's
///    transmissive and transparent draws rather than drawing them, as
///    weighted blended transparency keeps its layers (`R8`).
/// 2. **The copy** (`'scene colour copy'`): the scene target as it stands,
///    at its own size and at five halvings of it, side by side in one
///    texture — see `SceneColourChain` for why one texture.
/// 3. **The transparent half** (`'transparent'`): the scene target, the
///    surface buffer and the albedo buffer loaded rather than cleared, and
///    the depth loaded; the transmissive draws, reading the copy where the
///    ray the index bends leaves them, at a level the roughness chooses; then
///    the transparent draws and the contributors as the scene pass would
///    have drawn them — or, under weighted blended transparency, its own
///    passes, after this one.
///
/// **A contributor that reads the scene's depth splits the frame too** —
/// soft particles, `PassContributor.readsSceneDepth`. It needs no copy, so
/// the copy stays off unless glass wants it; what it needs is the surface
/// buffer unattached, so it is drawn in a fourth pass after the transparent
/// half, over the same colour and depth, with the buffer bound.
///
/// **One sample a pixel on such a frame.** The multisampled colour and depth
/// are tile memory as well, and a second pass cannot load what the first
/// left in them; `FrameResult.msaaDeclined` says so.
///
/// Switching `'transparent'` off draws the frame in one pass as before, the
/// glass reading the environment; switching `'scene colour copy'` off keeps
/// the split and leaves the glass reading the environment in the second pass.
part of 'renderer.dart';

/// What the scene pass hands the transparent pass on a frame it split: each
/// view's kept draws, and the answers the scene pass worked out that the
/// second pass has to draw by.
final class _SceneSplit {
  const _SceneSplit({
    required this.views,
    required this.shadows,
    required this.probes,
    required this.surfaceIsRead,
    required this.albedoIsRead,
  });

  final List<_DeferredTransparency> views;
  final SceneShadows shadows;
  final _SceneProbes probes;

  /// Which of the scene pass's attachments were present, so the second pass
  /// loads exactly those.
  final bool surfaceIsRead;
  final bool albedoIsRead;
}

extension _TransmissionPasses on Renderer {
  /// Whether [material] shows what is behind it — `M3`. Only the layered
  /// model reads a transmission; a material that has one and asks for plain
  /// metal-rough is drawn without it.
  static bool _transmits(Material material) =>
      identical(material.lighting, LightingModel.pbrLayered) &&
      (material.extensions?.transmission ?? 0.0) > 0.0;

  /// Whether this frame has a transmissive draw for any of [views] — the
  /// question that decides whether the scene splits.
  ///
  /// Asked before the graph compiles, because that is when a node says
  /// whether it runs, and so of the scene rather than of the render lists,
  /// which the scene pass builds later. A transmissive mesh the frustum then
  /// culls still splits the frame; the picture is the same either way, less
  /// the multisampling.
  static bool _holdsTransmission(Scene scene, List<RenderView> views) {
    final mask = views.fold<int>(0, (all, view) => all | view.layerMask);
    return scene.meshes.any(
      (node) =>
          _transmits(node.material) &&
          node.visibleInHierarchy &&
          node.shadowCasting.drawsColour &&
          (node.layerMask & mask) != 0,
    );
  }

  /// Draws [chain]'s levels of [source] into [target], each into its own
  /// rectangle, in one pass.
  void _encodeSceneColourCopy({
    required TextureHandle source,
    required TextureHandle target,
    required SceneColourChain chain,
  }) {
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          ColorTarget(texture: target, clearValue: vm.Vector4.zero()),
        ],
      ),
    );
    pass
      ..bindPipeline(
        _postPipeline(
          _sceneColourCopyPipeline,
          sceneColourCopyShader,
          (p) => _sceneColourCopyPipeline = p,
        ),
      )
      ..bindVertexBuffer(_fullscreenTriangle, 3)
      ..bindIndexBuffer(_identityIndices(3), IndexType.int32, 3)
      ..bindTexture(
        sceneColourCopyShader,
        'source_texture',
        source,
        sampler: SamplerOptions.linearClamp,
      );
    _sceneCopyInfo.params
      ..[1] = 1.0 / source.width
      ..[2] = 1.0 / source.height;
    for (var level = 0; level < chain.levels; level++) {
      final rect = chain.rect(level);
      _sceneCopyInfo.params[0] = chain.taps(level).toDouble();
      pass
        ..setState(
          Renderer._kFullscreenState.copyWith(viewport: rect, scissor: rect),
        )
        ..bindBlock(sceneColourCopyShader, _sceneCopyInfo)
        ..draw();
      _frameCounters?.drawCalls++;
    }
    pass.submit();
  }

  /// Fills the layered model's view of the copy for [deferred]'s view, or
  /// says there is none while no copy is lent.
  ///
  /// Every rectangle is turned into texture coordinates on the device's own
  /// rows: the engine states them from the top, and a backend whose row zero
  /// is the bottom of the picture keeps its texels that way up too.
  void _aimSceneColour(_DeferredTransparency deferred) {
    final info = _layerInfo;
    final read = _sceneColourRead;
    if (read == null) {
      info.sceneColour[0] = 0.0;
      return;
    }
    final chain = read.chain;
    final fromBottom = device.framebufferOrigin == FramebufferOrigin.bottomLeft;
    double row(ScreenRect rect, int height) => fromBottom
        ? (height - rect.y - rect.height).toDouble()
        : rect.y.toDouble();
    final atlasWidth = chain.atlasWidth;
    final atlasHeight = chain.atlasHeight;
    info.sceneColour
      ..[0] = chain.levels.toDouble()
      ..[1] = 1.0 / atlasWidth
      ..[2] = 1.0 / atlasHeight;
    // Past the last level the table repeats it, so no index reads a zero.
    for (var k = 0; k < SceneColourChain.maxLevels; k++) {
      final rect = chain.rect(math.min(k, chain.levels - 1));
      info.sceneLevels
        ..[k * 4] = rect.x / atlasWidth
        ..[k * 4 + 1] = row(rect, atlasHeight) / atlasHeight
        ..[k * 4 + 2] = rect.width / atlasWidth
        ..[k * 4 + 3] = rect.height / atlasHeight;
    }
    final view = deferred.rect;
    info.sceneViewport
      ..[0] = view.x / chain.width
      ..[1] = row(view, chain.height) / chain.height
      ..[2] = view.width / chain.width
      ..[3] = view.height / chain.height;
    info.sceneViewProjection.setAll(
      0,
      toFramebufferOrigin(
        deferred.viewProjection,
        device.framebufferOrigin,
      ).storage,
    );
  }

  /// The second half of a split scene: every view's transmissive draws over
  /// the scene the first half left, reading [sceneColour] — or the
  /// environment, where the copy was switched off — then the transparent
  /// half and the contributors. See the module comment for the order.
  void _encodeTransparentHalf({
    required Scene scene,
    required _SceneSplit split,
    required RenderSettings settings,
    required int width,
    required int height,
    required FramePassState passState,
    required List<PassContributor> contributors,
    required TextureHandle? sceneColour,
  }) {
    final hdr = _hdrColor!;
    final orderIndependent =
        settings.transparency == TransparencyMode.weightedBlended;
    final views = split.views;
    final multiView = views.length > 1;
    _sceneColourRead = sceneColour == null
        ? null
        : (
            texture: sceneColour,
            chain: SceneColourChain(hdr.width, hdr.height),
          );
    try {
      final surface = split.surfaceIsRead ? _surfaceColor : null;
      // The contributors that read the scene's depth, drawn in a pass of
      // their own after this one, where the surface buffer is bound rather
      // than attached. None without the buffer, and none under `R8`, whose
      // own pass after the resolve has it unattached already.
      final readers = surface == null || orderIndependent
          ? const <PassContributor>[]
          : contributors.where((c) => c.readsSceneDepth).toList();
      final here = readers.isEmpty
          ? contributors
          : contributors.where((c) => !c.readsSceneDepth).toList();
      final pass = device.beginRenderPass(
        RenderPassDescriptor(
          label: _passLabel,
          colors: <ColorTarget>[
            ColorTarget(texture: hdr, loadAction: LoadAction.load),
            if (surface != null)
              ColorTarget(texture: surface, loadAction: LoadAction.load),
            if (split.albedoIsRead && surface != null)
              ColorTarget(texture: _albedoColor!, loadAction: LoadAction.load),
          ],
          // Stored again only for the layers that follow under `R8`, or for
          // the contributors that read the depth.
          depth: DepthTarget(
            texture: _storedSceneDepth(),
            loadAction: LoadAction.load,
            storeAction: orderIndependent || readers.isNotEmpty
                ? StoreAction.store
                : StoreAction.dontCare,
          ),
        ),
      );
      for (final deferred in views) {
        _restoreView(deferred, rebuildClusters: multiView);
        _beginView(pass, deferred, passState);
        void draw(List<MeshNode> nodes) {
          for (final node in nodes) {
            _encodeNode(
              encoder: pass,
              node: node,
              scene: scene,
              settings: settings,
              viewProjection: deferred.viewProjection,
              shadows: split.shadows,
              probes: split.probes,
              lights: lights,
              shadowSlots: _shadowSlots,
              state: passState,
            );
          }
        }

        draw(deferred.transmissive);
        if (orderIndependent) continue;
        draw(deferred.transparent);
        // Handed no depth: the surface buffer is an attachment here, and a
        // contributor that reads it is in [readers] or had none to read.
        _encodeContributors(
          pass: pass,
          deferred: deferred,
          contributors: here,
          settings: settings,
          width: width,
          height: height,
          passState: passState,
        );
      }
      _clustersActive = false;
      pass.submit();

      // The readers, over what the pass above left: the colour and the depth
      // loaded, the surface buffer bound, and nothing else attached — their
      // stages write one colour.
      if (readers.isNotEmpty) {
        final soft = device.beginRenderPass(
          RenderPassDescriptor(
            label: _passLabel,
            colors: <ColorTarget>[
              ColorTarget(texture: hdr, loadAction: LoadAction.load),
            ],
            depth: DepthTarget(
              texture: _storedSceneDepth(),
              loadAction: LoadAction.load,
            ),
          ),
        );
        for (final deferred in views) {
          _restoreView(deferred, rebuildClusters: multiView);
          _beginView(soft, deferred, passState);
          _encodeContributors(
            pass: soft,
            deferred: deferred,
            contributors: readers,
            settings: settings,
            width: width,
            height: height,
            passState: passState,
            sceneDepth: surface,
          );
        }
        _clustersActive = false;
        soft.submit();
      }

      if (orderIndependent) {
        _encodeWeightedBlended(
          scene: scene,
          views: views,
          settings: settings,
          width: width,
          height: height,
          shadows: split.shadows,
          probes: split.probes,
          passState: passState,
          contributors: contributors,
          sceneDepth: surface,
        );
      }
    } finally {
      // Nothing after this pass reads the copy: a probe's capture, the view
      // model and the next frame all see the environment again.
      _sceneColourRead = null;
      _layerInfo.sceneColour[0] = 0.0;
    }
  }
}
