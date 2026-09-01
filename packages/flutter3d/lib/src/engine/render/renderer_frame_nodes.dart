/// The [RenderNode] implementations a [Renderer]'s frame is built from.
///
/// **A part of `renderer.dart`, not a file of its own**, for the same reason
/// the other parts of this library are: every node here holds a `Renderer`
/// by reference and reaches into its private fields and methods —
/// `_ensureCubeAtlas`, `_encodeScene`, `_renderBloom` and the rest — and a
/// `part` is what lets that stay private rather than becoming public API
/// nobody outside this file should call.
///
/// Unlike the pass files beside it, these are not `Renderer` methods split
/// out as an extension: they are already standalone classes — each
/// `extends RenderNode` and is registered into a [FrameGraph] rather than
/// called directly — so moving them cost nothing beyond a `part`. They stay
/// in this library only because the `Renderer` fields they read are private.
part of 'renderer.dart';

/// Textures for a frame, from the pool, released a ring of frames later.
///
/// The deferring is the point — see [FrameTextureSource]. Handing a texture
/// straight back while the GPU is still reading it is a defect that shows up
/// as an intermittent wrong picture and never as an error.
final class _DeferredTextureSource implements FrameTextureSource {
  const _DeferredTextureSource(this._renderer);

  final Renderer _renderer;

  @override
  TextureHandle acquire(RenderTargetSpec spec) =>
      _renderer.targetPool.acquire(spec);

  @override
  void release(TextureHandle texture) => _renderer._releaseAfterFrame(texture);
}

/// The baked half of the point-light atlas, as a graph node.
///
/// The hardest client the graph has, and the pair of nodes the core API was
/// meant to be judged against. Four things about them are unlike every other
/// pass in the frame, and each is what a mechanical migration would have got
/// wrong.
///
/// **Both atlases are external and must stay external.** `cube_shadow_static`
/// is written once and read for many frames; a pooled texture handed back at
/// the end of this node would be lent to somebody else and
/// [ShadowSlotAllocator]'s record of which lights it holds would be an
/// assertion about a picture that no longer exists. `cube_shadow` is worse: it
/// is *loaded* rather than cleared, tiles are blanked by drawing over them, and
/// a tile the scheduler left out deliberately keeps last frame's pixels.
/// [ShadowFaceScheduler] makes a claim per tile about one specific texture.
///
/// **Neither node owns the allocator or the scheduler.** They are renderer
/// fields taken by reference. Nodes are rebuilt every frame — a node that owned
/// either would come into every frame having drawn nothing and never stop
/// re-baking.
///
/// **The atlas is declared as [FrameGraphNode.keeps] rather than as a write**,
/// which is the opposite of [_ShadowMapNode] and the reason that distinction
/// exists at all. The directional map is redrawn from nothing every frame, so a
/// frame that did not draw has no map and a reader must be told so. An atlas is
/// a running total: most frames it draws nothing and the pixels still stand for
/// exactly what the scene is about to sample. Declared as a write that was a
/// half-truth on every frame the pass skipped — and versioning cannot mend it,
/// because versions chain within a frame and this resource is read-modify-write
/// across them. The texture is therefore provided whether or not this frame
/// drew into it, and the graph now holds the node to that rather than trusting
/// this paragraph.
///
/// **[Renderer._ensureCubeAtlas] is called from here rather than from the
/// frame**, and from the dynamic node too. It is idempotent, so the second call
/// costs a comparison; what it buys is that neither node has to assume the
/// other ran. The one thing the graph could not express in this step is that
/// two nodes share a prologue: there is no word for "before either of these",
/// so it is written twice and made cheap instead.
final class _CubeShadowStaticNode extends RenderNode {
  _CubeShadowStaticNode(
    this._renderer, {
    required this.scene,
    required this.settings,
    required this.slotCount,
    required this.staticDirty,
  });

  final Renderer _renderer;
  final Scene scene;
  final ShadowSettings settings;

  /// How many atlas rows are occupied this frame; zero for none.
  final int slotCount;

  /// The allocator's verdict: a row changed hands, or its owner moved far
  /// enough that the walls baked for it are walls seen from somewhere else.
  final bool staticDirty;

  @override
  String get name => 'point shadows (static)';

  @override
  bool get isActive =>
      settings.enabled && settings.strength > 0.0 && slotCount > 0;

  /// Maintained, not written: the bake is valid for many frames and this node
  /// runs on most of them without touching a pixel.
  @override
  List<ResourceId> get keeps => const <ResourceId>[
    FrameResourceIds.cubeShadowStatic,
  ];

  @override
  void execute(NodeFrame frame) {
    _renderer._ensureCubeAtlas(settings);

    // Every occupied row, not just the one that changed hands — a pass clears
    // its whole colour attachment, so redrawing one row erases the rest. The
    // allocator earns this back by changing at most one row per frame and only
    // for a light that clearly deserves it.
    //
    // `!_staticShadowBaked` is the second: it is how a reallocated atlas gets
    // its walls back, since `_ensureCubeAtlas` clears the flag and the very
    // next run of this node bakes whatever the new texture needs.
    //
    // **The third is the settings the bake was drawn with**, and its absence
    // was a setting that could not be changed. See [Renderer._staticBakeKey]:
    // what the *pass* reads — which side of a caster it records, how far the
    // volume is padded, how large a tile is — decides the pixels, so a change
    // to any of it has to redraw them. Everything the *lookup* reads is applied
    // per fragment and needs no bake at all.
    // **The fourth is the casters themselves.** A static caster that changed
    // how it casts — a wall that became double-sided, a proxy that stopped
    // casting — changed pixels only this bake holds, and neither the rows nor
    // the settings moved. `Scene.staticShadowGeneration` counts those, and a
    // change to it is as much a reason to redraw as a change to the key.
    final generation = scene.staticShadowGeneration;
    final castersChanged = _renderer._staticBakeGeneration != generation;
    final key = StaticBakeKey.of(settings);
    if (shouldBakeStatic(
      rowsChanged: staticDirty || castersChanged,
      baked: _renderer._staticShadowBaked,
      was: _renderer._staticBakeKey,
      now: key,
    )) {
      _renderer._renderCubeShadow(
        resources: frame.resources,
        scene: scene,
        settings: settings,
        static: true,
        slotCount: slotCount,
      );
      _renderer._staticShadowBaked = true;
      _renderer._staticBakeKey = key;
      _renderer._staticBakeGeneration = generation;
      // After drawing, not after deciding: a flag cleared by the decision would
      // promise walls that a skipped pass never drew.
      _renderer._shadowSlotAllocator.recordStaticBake();
    }

    // Non-null: `_ensureCubeAtlas` above allocated it if it did not exist.
    frame.resources.provide(
      FrameResourceIds.cubeShadowStatic,
      _renderer._cubeShadowStatic!,
    );
  }
}

/// The moving half of the point-light atlas, as a graph node.
///
/// Everything on [_CubeShadowStaticNode] applies here; this is the one that
/// actually carries pixels between frames. It redraws only the tiles whose
/// contents would come out different, and a tile it leaves alone keeps what it
/// held — which is only safe because a tile is blanked by *drawing* over it
/// rather than by clearing an attachment the viewport does not bound.
///
/// A separate node from the bake rather than one node writing both names,
/// because they run on completely different schedules: the bake fires when a
/// row changes hands, and this one fires when something moves. One node would
/// have had to be active whenever either was, and the profiler would have shown
/// one pass where the frame has two.
///
/// The schedule is chosen *inside* [execute] and not by the frame, and the
/// order matters: `_ensureCubeAtlas` may have thrown the texture away and reset
/// the scheduler, and a selection made before that would be a list of tiles
/// chosen against a texture that no longer exists.
final class _CubeShadowNode extends RenderNode {
  _CubeShadowNode(
    this._renderer, {
    required this.scene,
    required this.settings,
    required this.slotCount,
  });

  final Renderer _renderer;
  final Scene scene;
  final ShadowSettings settings;
  final int slotCount;

  @override
  String get name => 'point shadows';

  @override
  bool get isActive =>
      settings.enabled && settings.strength > 0.0 && slotCount > 0;

  /// The one resource in the frame that literally carries pixels between
  /// frames, and the reason [FrameGraphNode.keeps] exists.
  @override
  List<ResourceId> get keeps => const <ResourceId>[FrameResourceIds.cubeShadow];

  @override
  void execute(NodeFrame frame) {
    _renderer._ensureCubeAtlas(settings);

    // Only the faces where what moves has actually changed. Most frames most
    // casters are standing still, and a face whose picture would come out the
    // same is a face worth leaving alone.
    final scheduled = _renderer._shadowFaceScheduler
        .select(_renderer._computeFaceSignatures(scene, slotCount))
        .toSet();
    if (scheduled.isNotEmpty) {
      _renderer._renderCubeShadow(
        resources: frame.resources,
        scene: scene,
        settings: settings,
        static: false,
        slotCount: slotCount,
        tiles: scheduled,
      );
      _renderer._shadowFaceScheduler.recordDrawn();
    }

    // Even when nothing was drawn. The tiles hold the pictures earlier frames
    // put there, and `_cubeFaceMatrices` holds the matrices that drew them —
    // the two are kept in step precisely so that a frame which draws nothing
    // still has an atlas worth sampling.
    frame.resources.provide(
      FrameResourceIds.cubeShadow,
      _renderer._cubeShadow!,
    );
  }
}

/// The directional light's shadow map, as a graph node.
///
/// The pass that had to move first, and the reason the scene moved with it:
/// a shadow map must be drawn before the scene that samples it, and until the
/// scene was a node there was nothing for the graph to order it against.
///
/// `shadow_map` is **external, not pooled**, and that is deliberate rather than
/// unfinished. [Renderer._shadowMap] outlives the frame and is `devicePrivate`
/// because the lighting pass samples it from a *later* command buffer; a pooled
/// target handed back at the end of this node would be lent to somebody else
/// while the scene was still reading it. So the node declares the write and
/// [FrameResources.provide]s the renderer's own texture, exactly as the
/// composite does with the finished image. What it does allocate — the depth
/// attachment — is scratch, and goes through [FrameResources.transient].
///
/// It is registered whether or not it will draw, and switched off through
/// [isActive]. Leaving it out would make `shadow_map` an unknown name and the
/// scene's optional read of it a compile error, which is the branch moved
/// rather than deleted — the same shape as bloom.
///
/// It **writes**, where the atlas nodes beside it keep, and that is the whole
/// content of the distinction: the map is redrawn from nothing every frame, so
/// the texture is provided only when the pass actually drew and the scene finds
/// out by asking. `_renderShadowMap` gives up on a scene with no bounds or a
/// missing shader, and neither of those is knowable at compile; a node that
/// provided regardless would tell the scene there was a shadow map when the
/// texture still held the last frame that had one. That the texture is
/// long-lived is a fact about who allocates it and says nothing about whose
/// frame the pixels belong to — the two questions are orthogonal, and only the
/// second one is [FrameGraphNode.keeps].
final class _ShadowMapNode extends RenderNode {
  _ShadowMapNode(
    this._renderer, {
    required this.scene,
    required this.settings,
    required this.casterIndex,
    this.camera,
  });

  /// Where the player is looking, for cascade splits. Null for a scene with no
  /// views, which is a scene with nothing to split by.
  final CameraNode? camera;

  final Renderer _renderer;
  final Scene scene;
  final ShadowSettings settings;

  /// Which light in the packed buffer casts, or -1 for none.
  final int casterIndex;

  @override
  String get name => 'directional shadows';

  @override
  bool get isActive =>
      settings.enabled && settings.strength > 0.0 && casterIndex >= 0;

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.shadowMap];

  @override
  void execute(NodeFrame frame) {
    final drew = _renderer._renderShadowMap(
      resources: frame.resources,
      scene: scene,
      settings: settings,
      casterIndex: casterIndex,
      camera: camera,
    );
    if (!drew) return;
    frame.resources.provide(
      FrameResourceIds.shadowMap,
      // Non-null once the pass has drawn: it allocates the map before it opens
      // the render target.
      _renderer._shadowMap!,
    );
  }
}

/// The world, as a graph node — the pass everything else is ordered around.
///
/// It writes `hdr_colour` and `surface_buffer`, which is what took those two
/// names off [FrameGraph.addExternal]: the frame no longer hands the graph a
/// lit scene produced by code beside it. And it *optionally* reads the three
/// shadow maps, which is what lets anything be ordered before it at all.
///
/// Optional rather than hard, and the distinction is the whole reason
/// [FrameGraphNode.optionalReads] exists: a hard read would cull the scene the
/// moment shadows were switched off, and no read at all would cull the shadow
/// passes instead, since nothing would want what they produce.
///
/// All three shadow textures are now written by nodes: `shadow_map` by
/// [_ShadowMapNode] and the two atlases by [_CubeShadowStaticNode] and
/// [_CubeShadowNode]. Nothing about this node changed when they arrived, which
/// is the argument for the socket having been the right shape.
///
/// Unlike [_ReflectionsNode], which is single-view by construction, this draws
/// **every** ordered view in one pass. A viewport per view, one command buffer,
/// one submit — which is why the views are held here rather than derived from
/// [NodeFrame], and why the node cannot be split per view without splitting the
/// pass with it.
final class _SceneNode extends RenderNode {
  _SceneNode(
    this._renderer, {
    required this.scene,
    required this.ordered,
    required this.contributors,
    required this.shadowCaster,
    required this.lightOverflow,
  });

  final Renderer _renderer;
  final Scene scene;

  /// Every view, by priority — all of them drawn by this one pass.
  final List<RenderView> ordered;

  /// Handed in rather than looked up, so a node somebody else supplies can be
  /// given its own set. See [Renderer._encodeScene].
  final List<PassContributor> contributors;

  final int shadowCaster;
  final int lightOverflow;

  /// What the pass counted, for the frame's own report.
  _ScenePass? result;

  @override
  String get name => 'scene';

  @override
  List<ResourceId> get optionalReads => const <ResourceId>[
    FrameResourceIds.shadowMap,
    FrameResourceIds.cubeShadow,
    FrameResourceIds.cubeShadowStatic,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[
    FrameResourceIds.hdrColour,
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  void execute(NodeFrame frame) {
    final resources = frame.resources;

    // Asked of the frame that is running, not of a description of one, and not
    // of a setting: whether the buffer is wanted depends on what some *node*
    // declared, and an application's own node reading it is invisible to
    // `RenderSettings`. It decides both whether the second attachment is
    // present and whether the pass may multisample — attachments in one target
    // must agree on sample count — so a wrong answer here is silent.
    final surfaceIsRead = resources.graph.isConsumed(
      FrameResourceIds.surfaceBuffer,
    );

    // Every map this pass samples, taken from the frame rather than from the
    // renderer, and every one of them is declared above. The directional map is
    // null when the shadow node was culled *and* when it ran and gave up — an
    // absent texture is a fact the graph derived, not a flag this pass was
    // handed. The two atlases are maintained rather than drawn, so a texture
    // here is valid to sample whether or not this frame touched a pixel of it;
    // that difference is now in their declaration and not in a comment.
    // One place, shared with the view model. Both need the same rule and both
    // used to write it out; the copy here was the one with the drawn check, so
    // the other was quietly missing it.
    final shadows = SceneShadows.from(frame, casterIndex: shadowCaster);

    // Before the draw, and in place: the pass writes into the renderer's own
    // targets rather than into anything the pool lent it, so the version it
    // produces stands on a texture nobody may hand back.
    final hdr = _renderer._hdrColor!;
    resources.provide(FrameResourceIds.hdrColour, hdr);
    if (surfaceIsRead) {
      // Only when it was attached. Binding the texture behind the name when
      // nothing filled it would offer a reader last frame's picture, which is
      // exactly the failure `showSurfaceBuffer` was written to catch.
      resources.provide(
        FrameResourceIds.surfaceBuffer,
        _renderer._surfaceColor ?? hdr,
      );
    }

    result = _renderer._encodeScene(
      scene: scene,
      ordered: ordered,
      settings: frame.settings,
      width: frame.width,
      height: frame.height,
      shadows: shadows,
      passState: frame.state,
      lightOverflowCount: lightOverflow,
      contributors: contributors,
      surfaceIsRead: surfaceIsRead,
    );
  }
}

/// Screen-space reflections, as a graph node.
///
/// Internal rather than something an application registers: it is one of the
/// engine's own passes, and the migration is moving them onto the same
/// interface an extension uses. If the interface cannot carry the engine's own
/// work it will not carry anybody else's either.
///
/// It reads the lit scene and writes it back — a link in the chain, not a
/// consumer of one — and it reads the surface buffer, which is what makes the
/// buffer get attached at all. That read is the whole of what
/// `RenderSettings.needsSurfaceBuffer` used to compute by hand.
final class _ReflectionsNode extends RenderNode {
  _ReflectionsNode(this._renderer, this._view);

  final Renderer _renderer;
  final RenderView _view;

  @override
  String get name => 'reflections';

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.hdrColour,
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  void execute(NodeFrame frame) {
    final lit = _renderer._encodeReflections(
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
      settings: frame.settings,
      view: _view,
      width: frame.width,
      height: frame.height,
    );
    // The pass produced a *different* texture rather than editing the one it
    // was given — it samples the scene while it writes, and a texture cannot be
    // both — so the version it wrote has to be told which texture it is. The
    // one it read keeps its own, and every reader registered after this point
    // is already bound to the new one.
    frame.resources.provide(FrameResourceIds.hdrColour, lit);
  }
}

/// The bloom pyramid, as a graph node.
///
/// The first pass in the frame whose output the graph **allocates**: everything
/// before it was handed a texture the renderer already owned. `bloom` is
/// declared as half the frame in the HDR format, the chain's top level is that
/// texture, and the levels below it are scratch — see
/// [FrameResources.transient].
///
/// Switching bloom off is [isActive], not a null return: nothing produces the
/// glow, so the node is culled and costs no pass, no texture and no branch.
/// Ambient occlusion, as a producer of one resource.
///
/// `reads: [surfaceBuffer]` is doing more work than it looks. The scene pass
/// only attaches the surface buffer when somebody consumes it — `isConsumed` on
/// the graph decides — so declaring the read here is what switches the
/// attachment on. No flag is threaded anywhere, which is the thing the frame
/// graph was built for and the first place it has paid for itself twice: the
/// same declaration also turns MSAA off for the scene pass, because the two are
/// the same decision.
final class _SsaoNode extends RenderNode {
  _SsaoNode(this._renderer, this._view, this._settings);

  final Renderer _renderer;
  final RenderView _view;
  final RenderSettings _settings;

  @override
  String get name => 'ssao';

  @override
  bool get isActive =>
      _settings.ambientOcclusion.enabled &&
      _settings.ambientOcclusion.strength > 0.0;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.ao];

  @override
  void execute(NodeFrame frame) {
    final surface = frame.resources.tryTexture(FrameResourceIds.surfaceBuffer);
    // The buffer is a hard read, so this should not happen — but a node that
    // drew occlusion from a texture it did not get would produce plausible
    // darkness out of stale pixels, and that is the kind of wrong that survives
    // review. Fully lit is the honest answer to "no geometry described".
    if (surface == null) return;
    _renderer._encodeSsao(
      target: frame.resources.texture(FrameResourceIds.ao),
      surface: surface,
      options: _settings.ambientOcclusion,
      view: _view,
    );
  }
}

final class _BloomNode extends RenderNode {
  _BloomNode(this._renderer, this._settings);

  final Renderer _renderer;
  final BloomSettings _settings;

  @override
  String get name => 'bloom';

  @override
  bool get isActive => _settings.enabled && _settings.intensity > 0.0;

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.bloom];

  @override
  void execute(NodeFrame frame) {
    _renderer._renderBloom(
      resources: frame.resources,
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
      top: frame.resources.texture(FrameResourceIds.bloom),
      settings: _settings,
    );
  }
}

/// Tone map, sRGB and the debug overlay, as a graph node — the end of the post
/// chain and the only pass that writes what is shown.
///
/// It reads the lit scene, which is a hard read: a composite with no colour has
/// nothing to say. The glow and the surface buffer are **optional**, and that
/// is what this step was for. Bloom switched off is a culled node whose output
/// nobody produced, so [FrameResources.tryTexture] answers null and the pass
/// binds its stand-in — which is a fact the graph derived rather than a flag
/// the composite was handed.
///
/// `frame` is external: the finished image goes into the renderer's own
/// `_ldrColor`, which outlives the frame and is what becomes the `ui.Image`. So
/// the node [FrameResources.provide]s its output instead of allocating one,
/// exactly as reflections does with its own target.
///
/// It holds the frame's scene and views the way [_ReflectionsNode] holds its
/// view. The overlay batch after the tone map needs both, it draws into the
/// same open pass — a second pass would reload the attachment — and [NodeFrame]
/// carries neither.
final class _CompositeNode extends RenderNode {
  _CompositeNode(this._renderer, this._scene, this._views, this._settings);

  final Renderer _renderer;
  final Scene _scene;
  final List<RenderView> _views;
  final RenderSettings _settings;

  /// How many overlay line segments the pass drew, for the frame's counters.
  int overlayLines = 0;

  @override
  String get name => 'composite';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  List<ResourceId> get optionalReads => <ResourceId>[
    FrameResourceIds.bloom,
    // Unconditional, unlike the surface buffer below: the occlusion node
    // decides for itself whether it is active, and reading a resource
    // nobody produced is what `optionalReads` is for. Gating it here as
    // well would put the same switch in two places.
    FrameResourceIds.ao,
    // Only when it is going to show it. An unconditional read would make
    // the buffer look wanted on every frame, and what wants it is what
    // decides whether the scene pass attaches it at all.
    if (_showsSurface) FrameResourceIds.surfaceBuffer,
    // The same rule for the shadow view. This pass can put a shadow map on
    // the screen instead of the lit image, and it used to reach into the
    // renderer's own fields for it — the second half of the hole the view
    // model had, and the same fix: declare the read, then ask the frame.
    // The atlas is preferred where there is one, because that is the map
    // anybody debugging shadows wants to see.
    if (_settings.showShadowMap) ...<ResourceId>[
      FrameResourceIds.cubeShadow,
      FrameResourceIds.shadowMap,
    ],
    // The other cube atlas, and a separate switch for the reason given on
    // `RenderSettings.showStaticShadowMap`: there are two, the lighting
    // shader samples both, and only one of them had ever been looked at.
    if (_settings.showStaticShadowMap) FrameResourceIds.cubeShadowStatic,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  /// Whether this frame will put the surface buffer on the screen.
  ///
  /// One predicate, read by the declaration above and by the fetch below,
  /// because they have to agree: declaring the read on some frames and asking
  /// for it on all of them is asking for something the graph was never told
  /// about. That mismatch was silent until a node reading an undeclared name
  /// became an error, and then it was every frame of every scene.
  bool get _showsSurface =>
      _settings.showSurfaceBuffer || _settings.showPointShadowDebug;

  @override
  void execute(NodeFrame frame) {
    developer.Timeline.startSync('Renderer.composite');
    final target = _renderer._ldrColor!;
    // The renderer's texture, not the pool's, so the name is bound rather than
    // allocated. Before the draw, so anything reading `frame` after this node
    // finds the picture rather than nothing.
    frame.resources.provide(FrameResourceIds.frame, target);
    overlayLines = _renderer._encodeComposite(
      target: target,
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
      bloom: frame.resources.tryTexture(FrameResourceIds.bloom),
      // Optional in the same way the glow is: with the node culled nobody
      // produced it, and the graph answering null is a fact it derived rather
      // than a flag this pass was handed.
      ao: frame.resources.tryTexture(FrameResourceIds.ao),
      surface: _showsSurface
          ? frame.resources.tryTexture(FrameResourceIds.surfaceBuffer)
          : null,
      // Null unless this frame declared the read above — and now the code says
      // so rather than only the comment. The declaration is conditional on
      // `showShadowMap`, so the fetch has to be too: asking on every frame is
      // asking for something the graph was told about on almost none of them.
      // That is what makes the setting fall back to the lit image instead of to
      // whatever a renderer field happened to be holding.
      shadowView: _settings.showStaticShadowMap
          ? frame.resources.tryTexture(FrameResourceIds.cubeShadowStatic)
          : _settings.showShadowMap
          ? frame.resources.tryTexture(FrameResourceIds.cubeShadow) ??
                frame.resources.tryTexture(FrameResourceIds.shadowMap)
          : null,
      sceneGraph: _scene,
      views: _views,
      settings: frame.settings,
      width: frame.width,
      height: frame.height,
    );
    // The composite is a draw, and so is the overlay batch.
    frame.state.drawCalls += 1 + (overlayLines > 0 ? 1 : 0);
    developer.Timeline.finishSync();
  }
}

/// What [Renderer._encodeScene] hands back to the frame.
final class _ScenePass {
  const _ScenePass({
    required this.culled,
    required this.debugLines,
    required this.lightOverflow,
    required this.submitMicros,
  });

  final int culled;
  final int debugLines;
  final int lightOverflow;
  final int submitMicros;
}
