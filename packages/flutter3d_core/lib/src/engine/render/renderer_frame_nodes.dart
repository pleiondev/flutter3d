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
/// **Both atlases are the renderer's own textures and must stay so — kept,
/// never pooled.** `cube_shadow_static`
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
    // A material that became double-sided changes which faces a static caster
    // records too, and a material is not a node: it reaches neither the
    // generation nor the rows. Hashed here over the static casters rather than
    // counted in a setter, because the x-ray pass writes `doubleSided` on its
    // override materials every frame and would re-bake every frame with it.
    final generation = scene.staticShadowGeneration;
    var faces = 0;
    for (final node in scene.meshes) {
      if (!node.shadowIsStatic || !node.shadowCasting.casts) continue;
      faces = 0x1fffffff & (faces * 31 + identityHashCode(node));
      faces =
          0x1fffffff & (faces * 31 + (node.castsShadowFromEveryFace ? 1 : 0));
    }
    final castersChanged =
        _renderer._staticBakeGeneration != generation ||
        _renderer._staticBakeFaces != faces;
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
      _renderer._staticBakeFaces = faces;
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
        .select(_renderer._computeFaceSignatures(scene, slotCount, settings))
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

/// One reflection probe, as a graph node: six captures and a chain.
///
/// **Maintained, not written**, like the cube atlases and for the same
/// reason: a probe that is not [ReflectionProbeNode.refreshFaceEveryFrame] is
/// drawn once and then stands, and one that is redraws a face a frame while
/// the other five keep what an earlier frame put there. The filtered cube is
/// therefore provided whether or not this frame drew into it, and the graph
/// holds the node to that.
///
/// It optionally reads the three shadow maps, which is what puts it after the
/// shadow passes: a probe's picture is lit and shadowed the way the world is,
/// through the same `_encodeNode`, so it wants what the world wants. And the
/// scene optionally reads what this provides, which is what puts it before
/// the scene. Neither ordering is written down as an order.
///
/// Inactive on a device that cannot draw into a mip level, and the scene then
/// reads nothing for this probe and reflects what it reflected before. A
/// probe with a base level only would be a mirror at every roughness, which
/// is a picture nobody asked for.
final class _ReflectionProbeNode extends RenderNode {
  _ReflectionProbeNode(
    this._renderer, {
    required this.scene,
    required this.probe,
    required this.index,
    required this.shadowCaster,
    required this.clearColor,
  });

  final Renderer _renderer;
  final Scene scene;
  final ReflectionProbeNode probe;

  /// Which probe of the scene's this is, which names the resource.
  final int index;

  /// Which light in the packed buffer the directional map belongs to.
  final int shadowCaster;

  /// What the primary view clears to: what a probe sees where nothing was
  /// drawn, so a reflection of the empty sky is the same colour the world's is.
  final vm.Vector4 clearColor;

  /// Every face, in order: what a first capture and an invalidated one draw.
  static const List<int> _kWholeCube = <int>[0, 1, 2, 3, 4, 5];

  @override
  String get name => 'reflection probe $index';

  @override
  bool get isActive =>
      probe.visibleInHierarchy &&
      ReflectionProbeNode.supportedOn(_renderer.device);

  @override
  List<ResourceId> get optionalReads => const <ResourceId>[
    FrameResourceIds.shadowMap,
    FrameResourceIds.cubeShadow,
    FrameResourceIds.cubeShadowStatic,
  ];

  @override
  List<ResourceId> get keeps => <ResourceId>[
    FrameResourceIds.reflectionProbe(index),
  ];

  @override
  void execute(NodeFrame frame) {
    final state = _renderer._probeStateFor(probe);

    // Which faces this frame would draw. All six the first time, because a
    // cube with faces nobody drew holds whatever the allocation held; all six
    // again when a kept probe was invalidated; one, in turn, for a probe that
    // rolls — and nothing at all for a kept probe that is current.
    final wanted = !state.whole
        ? _kWholeCube
        : probe.refreshFaceEveryFrame
        ? <int>[state.nextFace]
        : state.generation != probe.generation
        ? _kWholeCube
        : const <int>[];

    // And which it may. One whole cube a frame across the scene, so a level
    // whose every room holds a probe stands over as many frames as it has
    // rooms rather than in one very long one — see `_claimWholeProbeCapture`,
    // which is where the argument for that is written down. A probe that
    // waits keeps `whole` false and `isCaptured` false, so nothing binds its
    // unfilled cube and the level goes on drawing every batch until it stands.
    final faces = wanted.length == _kWholeCube.length
        ? (_renderer._claimWholeProbeCapture() ? wanted : const <int>[])
        : wanted;

    if (faces.isNotEmpty) {
      developer.Timeline.startSync('Renderer.reflectionProbe');
      final shadows = SceneShadows.from(frame, casterIndex: shadowCaster);
      for (final face in faces) {
        _renderer._captureProbeFace(
          resources: frame.resources,
          scene: scene,
          probe: probe,
          state: state,
          face: face,
          settings: frame.settings,
          shadows: shadows,
          passState: frame.state,
          clearColor: clearColor,
        );
      }
      state
        ..whole = true
        ..nextFace = (state.nextFace + faces.length) % 6
        ..generation = probe.generation;
      _renderer._prefilterProbe(state);
      // Every face now stands at this generation — all six were just drawn,
      // or one was and the other five already stood — which is what a level
      // waits for before it hides the rooms the probe cannot see from the
      // player's cell.
      probe.markCaptured();
      developer.Timeline.finishSync();
    }

    // Even when nothing was drawn: the chain holds what an earlier frame put
    // there, which is exactly what keeping means.
    frame.resources.provide(
      FrameResourceIds.reflectionProbe(index),
      state.filtered,
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
  List<ResourceId> get optionalReads => <ResourceId>[
    FrameResourceIds.shadowMap,
    FrameResourceIds.cubeShadow,
    FrameResourceIds.cubeShadowStatic,
    // Every probe the scene holds, by index. Optional for the reason the maps
    // are: a probe on a device that cannot filter one is a culled node, and
    // the world still draws.
    for (var i = 0; i < scene.probes.length; i++)
      FrameResourceIds.reflectionProbe(i),
    // `L4`: the irradiance atlas the GPU keeps, for the same reason — the
    // lit draws read it when it is there and the bake when it is not.
    FrameResourceIds.irradianceAtlas,
  ];

  /// **Both names always, including on a device that cannot attach the
  /// second** — `gfx-50n`.
  ///
  /// Withholding `surface_buffer` here was tried and is wrong: the graph
  /// refuses a read of a name nothing declares, deliberately, because a name
  /// nothing writes is a misspelling or a missing pass and both look
  /// identical at runtime. A device that cannot open a second attachment is
  /// neither — the pass exists and the name is spelled right — so the refusal
  /// belongs on the *consumers*, where it is one more reason a pass did not
  /// run. See `RenderNode.supported` and `PassSkip.unsupported`.
  @override
  List<ResourceId> get writes => <ResourceId>[
    FrameResourceIds.hdrColour,
    FrameResourceIds.surfaceBuffer,
    // `L5`: always named, as the surface buffer is, and provided only where
    // the device attached it — a reader that can do without takes it as an
    // optional read and gets null on a device that opens two.
    FrameResourceIds.albedoBuffer,
  ];

  /// The probes this frame produced, out of the resources this node declared.
  ///
  /// Only the names declared above are asked for, and a probe whose node was
  /// culled answers null and is left out — the same shape [SceneShadows.from]
  /// has, for the same reason.
  ///
  /// A probe whose cube has never been drawn whole is left out too, and that
  /// is what makes staggering safe: a probe waiting its turn still *provides*
  /// its texture, because a node that keeps a resource provides it on every
  /// frame it runs, and an allocation nobody has drawn into holds whatever was
  /// in that memory. Read `_ProbeState.whole` rather than `isCaptured`: an
  /// invalidated probe waiting to redraw has a stale chain, and a stale
  /// reflection is a far better answer than none.
  _SceneProbes _probesFrom(FrameResources resources) =>
      _SceneProbes(<_ProbeBinding>[
        for (var i = 0; i < scene.probes.length; i++)
          if (_renderer._probeStates[scene.probes[i]]
              case final _ProbeState state when state.whole)
            if (resources.tryTexture(FrameResourceIds.reflectionProbe(i))
                case final TextureHandle texture)
              _ProbeBinding(
                position: scene.probes[i].readWorldPosition(),
                radius: scene.probes[i].radius,
                intensity: scene.probes[i].intensity,
                texture: texture,
                levels: state.levels,
              ),
      ]);

  @override
  void execute(NodeFrame frame) {
    final resources = frame.resources;

    // Asked of the frame that is running, not of a description of one, and not
    // of a setting: whether the buffer is wanted depends on what some *node*
    // declared, and an application's own node reading it is invisible to
    // `RenderSettings`. It decides both whether the second attachment is
    // present and whether the pass may multisample — attachments in one target
    // must agree on sample count — so a wrong answer here is silent.
    //
    // **And of the device, which `gfx-50n` did not finish.** Hard readers of
    // the buffer are culled where the device cannot attach it, so they cannot
    // reach here — but an *optional* reader is never culled, by definition,
    // and `isConsumed` counts it. A frame with a viewport-shading mode on a
    // one-attachment device therefore asked for an attachment the device
    // refuses, which the refusal turned into a throw. The pass attaches what
    // the device can open; the optional reader gets null and declines, which
    // is what optional means.
    // `L5`: the third attachment on the same terms. The stages write it at
    // location two, so reading it attaches the surface buffer as well, which
    // keeps the attachments consecutive.
    final albedoIsRead =
        resources.graph.isConsumed(FrameResourceIds.albedoBuffer) &&
        _renderer.device.maxColorAttachments > 2;
    final surfaceIsRead =
        (resources.graph.isConsumed(FrameResourceIds.surfaceBuffer) ||
            albedoIsRead) &&
        _renderer.device.maxColorAttachments > 1;

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
    if (albedoIsRead) {
      resources.provide(FrameResourceIds.albedoBuffer, _renderer._albedoColor!);
    }

    result = _renderer._encodeScene(
      scene: scene,
      ordered: ordered,
      settings: frame.settings,
      width: frame.width,
      height: frame.height,
      shadows: shadows,
      probes: _probesFrom(resources),
      passState: frame.state,
      lightOverflowCount: lightOverflow,
      contributors: contributors,
      surfaceIsRead: surfaceIsRead,
      albedoIsRead: albedoIsRead,
    );
  }
}

/// A pass that cannot run without the surface buffer — `gfx-50n`.
///
/// **Five nodes read that buffer unconditionally, and every one of them needs
/// the same sentence**: the buffer is the scene pass's second colour
/// attachment, and a device that opens one attachment cannot have it. Written
/// once here rather than five times, so a sixth reader joins by mixing this in
/// and cannot join by forgetting.
///
/// The refusal is [FrameGraphNode.supported] rather than
/// [FrameGraphNode.isActive], because a caller who switched occlusion on and
/// got nothing deserves to be told that their device cannot, rather than to go
/// looking through settings they already set correctly.
base mixin _NeedsSurfaceBuffer on RenderNode {
  /// The renderer whose device this asks. Each node already holds one
  /// privately; this is the one line that makes it reachable from here.
  Renderer get owner;

  @override
  bool get supported => owner.device.maxColorAttachments > 1;
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
///
/// **Switched off through [isActive], like every other post node, and it was
/// the last one that was not.** Until `gfx-38n` the renderer registered this
/// node inside `if (s.reflections.enabled)`, which is the branch the
/// registration block beside it argues against twice: a name has to be known
/// for a read of it to compile, and leaving the node out when the setting is
/// off moves the branch rather than deleting it. Nothing read `hdrColour`
/// *conditionally* on reflections, so the inconsistency never produced a
/// wrong frame — it produced a node that could not be addressed. A caller
/// asking why reflections did not run got no answer, because with the
/// setting off there was no node to have an answer about.
final class _ReflectionsNode extends RenderNode with _NeedsSurfaceBuffer {
  _ReflectionsNode(this._renderer, this._view, this._settings);

  @override
  Renderer get owner => _renderer;

  final Renderer _renderer;
  final RenderView _view;
  final RenderSettings _settings;

  @override
  String get name => 'reflections';

  @override
  bool get isActive => _settings.reflections.enabled;

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

/// Ambient occlusion, as a producer of one resource.
///
/// `reads: [surfaceBuffer]` is doing more work than it looks. The scene pass
/// only attaches the surface buffer when somebody consumes it — `isConsumed` on
/// the graph decides — so declaring the read here is what switches the
/// attachment on. No flag is threaded anywhere, which is the thing the frame
/// graph was built for and the first place it has paid for itself twice: the
/// same declaration also turns MSAA off for the scene pass, because the two are
/// the same decision.
final class _SsaoNode extends RenderNode with _NeedsSurfaceBuffer {
  _SsaoNode(this._renderer, this._view, this._settings);

  @override
  Renderer get owner => _renderer;

  final Renderer _renderer;
  final RenderView _view;
  final RenderSettings _settings;

  @override
  String get name => 'ssao';

  @override
  bool get isActive =>
      _settings.ambientOcclusion.enabled &&
      _settings.ambientOcclusion.strength > 0.0;

  bool get _indirect =>
      _settings.ambientOcclusion.method == AmbientOcclusionMethod.ssil;

  // `L5`: the indirect method bounces the lit scene, so it reads it.
  @override
  List<ResourceId> get reads => _indirect
      ? const <ResourceId>[
          FrameResourceIds.surfaceBuffer,
          FrameResourceIds.hdrColour,
        ]
      : const <ResourceId>[FrameResourceIds.surfaceBuffer];

  // And the albedo buffer, which a device with two attachments cannot give:
  // there the bounce takes a neutral grey instead.
  @override
  List<ResourceId> get optionalReads => _indirect
      ? const <ResourceId>[FrameResourceIds.albedoBuffer]
      : const <ResourceId>[];

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
      scene: _indirect
          ? frame.resources.tryTexture(FrameResourceIds.hdrColour)
          : null,
      albedo: _indirect
          ? frame.resources.tryTexture(FrameResourceIds.albedoBuffer)
          : null,
    );
  }
}

/// `gfx-76n`'s short march toward the sun, as a producer of one resource.
///
/// **A second producer rather than a link in the occlusion chain**, although
/// the composite ends up multiplying both into the same ambient term. The
/// occlusion has a strength of its own, and folding the contact shadow into
/// `ao` would mean a scene with occlusion switched off — strength zero, node
/// culled, buffer at one — has nowhere to put a contact shadow. Two resources
/// and two strengths is what lets either be off without deciding for the other.
///
/// Declines the same way the shafts do: with no directional light there is
/// nothing to march toward, and the node is inactive rather than marching
/// toward a direction it made up.
final class _ContactShadowNode extends RenderNode with _NeedsSurfaceBuffer {
  _ContactShadowNode(this._renderer, this._view, this._settings, this._toLight);

  @override
  Renderer get owner => _renderer;

  final Renderer _renderer;
  final RenderView _view;
  final RenderSettings _settings;

  /// Which way the sun lies from a surface, or null for a scene with no
  /// directional light.
  final vm.Vector3? _toLight;

  @override
  String get name => 'contact shadows';

  @override
  bool get isActive =>
      _settings.contactShadows.enabled &&
      _settings.contactShadows.strength > 0.0 &&
      _settings.contactShadows.length > 0.0 &&
      _settings.contactShadows.steps > 0 &&
      _toLight != null;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[
    FrameResourceIds.contactShadow,
  ];

  @override
  void execute(NodeFrame frame) {
    final surface = frame.resources.tryTexture(FrameResourceIds.surfaceBuffer);
    final toLight = _toLight;
    // Both are hard conditions of the node running at all, so neither should
    // happen — and a march over stale pixels would draw plausible seams where
    // nothing meets, which is the kind of wrong that survives review.
    if (surface == null || toLight == null) return;
    _renderer._encodeContactShadow(
      target: frame.resources.texture(FrameResourceIds.contactShadow),
      surface: surface,
      options: _settings.contactShadows,
      view: _view,
      toLight: toLight,
    );
  }
}

/// `L4`: the irradiance field's probes, a few a frame, drawn and folded into
/// the atlas the lit stages read.
///
/// After the shadows, which the capture samples, and before the scene, which
/// reads the atlas — the same place a reflection probe stands, for the same
/// reasons.
final class _IrradianceUpdateNode extends RenderNode {
  _IrradianceUpdateNode(
    this._renderer, {
    required this.scene,
    required this.shadowCaster,
    required this.clearColor,
  });

  final Renderer _renderer;
  final Scene scene;
  final int shadowCaster;
  final vm.Vector4 clearColor;

  @override
  String get name => 'irradiance update';

  @override
  bool get isActive {
    final field = scene.irradianceField;
    return field != null && _renderer._updatesIrradianceOnGpu(field);
  }

  @override
  List<ResourceId> get optionalReads => const <ResourceId>[
    FrameResourceIds.shadowMap,
    FrameResourceIds.cubeShadow,
    FrameResourceIds.cubeShadowStatic,
  ];

  @override
  List<ResourceId> get keeps => const <ResourceId>[
    FrameResourceIds.irradianceAtlas,
  ];

  @override
  void execute(NodeFrame frame) {
    final field = scene.irradianceField!;
    developer.Timeline.startSync('Renderer.irradianceUpdate');
    _renderer._updateIrradiance(
      field: field,
      resources: frame.resources,
      scene: scene,
      settings: frame.settings,
      shadows: SceneShadows.from(frame, casterIndex: shadowCaster),
      passState: frame.state,
      clearColor: clearColor,
    );
    developer.Timeline.finishSync();
    frame.resources.provide(
      FrameResourceIds.irradianceAtlas,
      _renderer._irradianceGpu!.atlas.current,
    );
  }
}

/// `R1`'s camera velocity, as the producer of the velocity resource.
///
/// Active only while temporal anti-aliasing is on, and reading the surface
/// buffer is what switches that buffer on — and multisampling off — for a
/// frame that asked for the resolve.
final class _CameraVelocityNode extends RenderNode with _NeedsSurfaceBuffer {
  _CameraVelocityNode(this._renderer, this._view, this._settings);

  @override
  Renderer get owner => _renderer;

  final Renderer _renderer;
  final RenderView _view;
  final RenderSettings _settings;

  @override
  String get name => 'camera velocity';

  @override
  bool get isActive => _settings.antiAlias.temporal.enabled;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.velocity];

  @override
  void execute(NodeFrame frame) {
    final surface = frame.resources.tryTexture(FrameResourceIds.surfaceBuffer);
    if (surface == null) return;
    _renderer._encodeCameraVelocity(
      target: frame.resources.texture(FrameResourceIds.velocity),
      surface: surface,
      view: _view,
    );
  }
}

/// `R1`'s object velocity: the nodes that moved, drawn over the camera's.
///
/// A link in the velocity chain rather than a second producer: it reads the
/// camera's version and writes the next into the same texture, loading what
/// is there. The surface buffer is its depth test — see
/// `renderer_velocity_pass.dart`.
final class _ObjectVelocityNode extends RenderNode with _NeedsSurfaceBuffer {
  _ObjectVelocityNode(this._renderer, this._view, this._settings, this._scene);

  @override
  Renderer get owner => _renderer;

  final Renderer _renderer;
  final RenderView _view;
  final RenderSettings _settings;
  final Scene _scene;

  @override
  String get name => 'object velocity';

  @override
  bool get isActive => _settings.antiAlias.temporal.enabled;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.velocity,
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.velocity];

  @override
  void execute(NodeFrame frame) {
    final velocity = frame.resources.texture(FrameResourceIds.velocity);
    // The same texture carries on as the next version: this pass draws over
    // it rather than into a new one.
    frame.resources.provide(FrameResourceIds.velocity, velocity);
    final surface = frame.resources.tryTexture(FrameResourceIds.surfaceBuffer);
    if (surface == null) return;
    _renderer._encodeObjectVelocity(
      target: velocity,
      surface: surface,
      scene: _scene,
      view: _view,
      settings: _settings,
      width: frame.width,
      height: frame.height,
    );
  }
}

/// `R3`: a noisy effect carried into its own history, as a link in that
/// effect's chain.
///
/// Reads the effect's version so far and the velocity, and writes the next
/// version: the blend, which is the renderer's own history texture. With
/// the effect off, nothing produced the version it reads and the graph
/// culls this too.
final class _AccumulateNode extends RenderNode {
  _AccumulateNode(
    this._renderer,
    this._view,
    this._settings,
    this._resource,
    this.name,
  );

  final Renderer _renderer;
  final RenderView _view;
  final RenderSettings _settings;
  final ResourceId _resource;

  @override
  final String name;

  @override
  bool get isActive =>
      _settings.antiAlias.temporal.enabled &&
      _renderer.device.maxColorAttachments > 1;

  @override
  List<ResourceId> get reads => <ResourceId>[
    _resource,
    FrameResourceIds.velocity,
  ];

  @override
  List<ResourceId> get writes => <ResourceId>[_resource];

  @override
  void execute(NodeFrame frame) {
    final blended = _renderer._encodeAccumulate(
      resource: _resource,
      current: frame.resources.texture(_resource),
      velocity: frame.resources.texture(FrameResourceIds.velocity),
      view: _view,
    );
    frame.resources.provide(_resource, blended);
  }
}

/// `R2`'s temporal resolve, as a link in the lit-colour chain.
///
/// Reads this frame's scene, its velocity and its surface buffer, and writes
/// the next version of the lit colour — the resolved picture, at the output's
/// size, which is also the history the next frame reads. So the history is
/// provided under both names: as the lit colour for bloom and the composite,
/// and as [FrameResourceIds.temporalHistory], which it keeps.
final class _TemporalResolveNode extends RenderNode with _NeedsSurfaceBuffer {
  _TemporalResolveNode(this._renderer, this._view, this._settings);

  @override
  Renderer get owner => _renderer;

  final Renderer _renderer;
  final RenderView _view;
  final RenderSettings _settings;

  @override
  String get name => 'temporal resolve';

  @override
  bool get isActive => _settings.antiAlias.temporal.enabled;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.hdrColour,
    FrameResourceIds.velocity,
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  List<ResourceId> get keeps => const <ResourceId>[
    FrameResourceIds.temporalHistory,
  ];

  @override
  void execute(NodeFrame frame) {
    final resolved = _renderer._encodeTemporalResolve(
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
      velocity: frame.resources.texture(FrameResourceIds.velocity),
      surface: frame.resources.texture(FrameResourceIds.surfaceBuffer),
      view: _view,
      settings: _settings,
      outputWidth: frame.width,
      outputHeight: frame.height,
    );
    frame.resources
      ..provide(FrameResourceIds.hdrColour, resolved)
      ..provide(FrameResourceIds.temporalHistory, resolved);
  }
}

/// `gfx-33n`'s volumetric shafts, as a link in the lit-colour chain.
///
/// **Reads the shadow map optionally, which is the whole of how it declines.**
/// The shafts are a shadow-map product: with no caster there is no map, the
/// optional read comes back null, and the node returns having drawn nothing.
/// That is the honest answer rather than an error — a light being added later
/// is the ordinary case, and a frame that threw because a scene had no
/// directional caster would be a worse engine.
///
/// Reads the surface buffer too, for how far along each ray there is still
/// air. Declaring it is what attaches the buffer, the same way the occlusion
/// pass's own declaration does.
final class _LightShaftsNode extends RenderNode with _NeedsSurfaceBuffer {
  _LightShaftsNode(
    this._renderer,
    this._view,
    this._settings,
    this._toLight,
    this._radiance,
  );

  @override
  Renderer get owner => _renderer;

  final Renderer _renderer;
  final RenderView _view;
  final RenderSettings _settings;

  /// Towards the shadow-casting sun, and its colour times intensity — what
  /// the air scatters. Null when no directional light casts, and then there
  /// is no shadow map to march either.
  final vm.Vector3? _toLight;
  final vm.Vector3? _radiance;

  @override
  String get name => 'light shafts';

  @override
  bool get isActive =>
      _settings.lightShafts.enabled &&
      _settings.lightShafts.strength > 0.0 &&
      _settings.lightShafts.steps > 0;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.hdrColour,
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get optionalReads => const <ResourceId>[
    FrameResourceIds.shadowMap,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  void execute(NodeFrame frame) {
    final surface = frame.resources.tryTexture(FrameResourceIds.surfaceBuffer);
    final shadow = frame.resources.tryTexture(FrameResourceIds.shadowMap);
    final toLight = _toLight;
    final radiance = _radiance;
    if (surface == null || shadow == null) return;
    if (toLight == null || radiance == null) return;
    final lit = _renderer._encodeLightShafts(
      toLight: toLight,
      radiance: radiance,
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
      surface: surface,
      shadow: shadow,
      settings: _settings.lightShafts,
      view: _view,
      resources: frame.resources,
      width: frame.width,
      height: frame.height,
    );
    // A different texture from the one it read — a pass cannot sample and
    // write one — so the version it produced is told which texture it is, the
    // hand-off `_ReflectionsNode` makes for the same reason.
    frame.resources.provide(FrameResourceIds.hdrColour, lit);
  }
}

/// `gfx-34n`'s lens, as a link in the lit-colour chain.
///
/// **Placed after the shafts and before the bloom, which is an order with a
/// reason.** A lens is in front of the scene, so anything the scene emits goes
/// through it — including the shafts, which are light in the air and are
/// blurred by a lens exactly as the geometry behind them is. Bloom comes
/// after, because a glow is what the *sensor* does with light that already
/// went through the lens: blooming first and defocusing the glow afterwards
/// would soften the one part of the picture a wide aperture makes more
/// pronounced, not less.
///
/// Reads the surface buffer for depth, which is what the circle of confusion
/// is computed from. Declaring it is what attaches the buffer, the same way
/// the occlusion pass's declaration does.
final class _DepthOfFieldNode extends RenderNode with _NeedsSurfaceBuffer {
  _DepthOfFieldNode(this._renderer, this._settings);

  @override
  Renderer get owner => _renderer;

  final Renderer _renderer;
  final RenderSettings _settings;

  @override
  String get name => 'depth of field';

  @override
  bool get isActive =>
      _settings.depthOfField.enabled &&
      _settings.depthOfField.samples > 0 &&
      _settings.depthOfField.maxRadius > 0.0;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.hdrColour,
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  void execute(NodeFrame frame) {
    final surface = frame.resources.tryTexture(FrameResourceIds.surfaceBuffer);
    // A hard read, so this should not happen — but a lens with no depth would
    // focus on whatever the alpha channel last held, and a plausible blur out
    // of stale pixels is the kind of wrong that survives review.
    if (surface == null) return;
    final focused = _renderer._encodeDepthOfField(
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
      surface: surface,
      settings: _settings.depthOfField,
      resources: frame.resources,
      width: frame.width,
      height: frame.height,
    );
    // A different texture from the one it read — a pass cannot sample and
    // write one — so the version it produced is told which texture it is.
    frame.resources.provide(FrameResourceIds.hdrColour, focused);
  }
}

/// `gfx-43n`/`44n`/`45n`'s viewport shading, as a link in the finished
/// picture.
///
/// **After the composite, and the first draft of this had it before —
/// wrongly.** A normal mapped into `[0, 1]` is not a quantity of light, and
/// the engine already says so: `normals.frag` writes through
/// `WriteDisplayColor`, and `display_modes.dart` carries the sentence "a
/// normals view is not a picture of light, and the composite has to be told".
/// Registered before the composite, every mode here would have been exposed,
/// tone mapped and graded — a pale blue pushed through a filmic shoulder is
/// not the pale blue anybody recognises. So it reads and writes `frame`, in
/// the phase whose own documentation asks for exactly this: things that are
/// honestly about the finished image.
///
/// **It reads the surface buffer optionally**, and that is what makes a mode
/// degrade rather than break: on a device that cannot attach the buffer the
/// read comes back null and the pass hands the picture straight through. The
/// cost of the declaration is a frame the scene pass did not multisample —
/// see `anchor_identity_test.dart`, where that trade is pinned, and
/// `FrameResult.antiAliasing`, which reports it.
final class _ViewportShadeNode extends RenderNode {
  _ViewportShadeNode(this._renderer, this._view, this._settings);

  final Renderer _renderer;
  final RenderView _view;
  final RenderSettings _settings;

  @override
  String get name => 'viewport shading';

  @override
  FramePhase get preferredPhase => FramePhase.present;

  @override
  bool get isActive =>
      _settings.viewportShading.mode != ViewportShading.off &&
      _settings.viewportShading.amount > 0.0;

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.frame];

  @override
  List<ResourceId> get optionalReads => const <ResourceId>[
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    final shaded = _renderer._encodeViewportShade(
      scene: frame.resources.texture(FrameResourceIds.frame),
      surface: frame.resources.tryTexture(FrameResourceIds.surfaceBuffer),
      settings: _settings.viewportShading,
      view: _view,
      resources: frame.resources,
    );
    frame.resources.provide(FrameResourceIds.frame, shaded);
  }
}

/// `gfx-32n`'s depth-aware blur, as a link in the occlusion chain.
///
/// **Reads `ao` and writes `ao`, which is what makes it skippable for free.**
/// A node that consumed the occlusion and produced something else would make
/// the composite's read conditional on whether the blur ran. As a
/// read-modify-write link it produces the next version of the same name, so
/// switching it off leaves the composite bound to the version before it with
/// nothing to branch on — the semantics `frame_graph_compile.dart` argues for
/// and `frame_graph_test.dart` holds.
///
/// It reads the surface buffer too, which is where the depth comes from. That
/// read costs nothing extra: the occlusion pass already declared it, so the
/// buffer is attached either way.
final class _SsaoBlurNode extends RenderNode with _NeedsSurfaceBuffer {
  _SsaoBlurNode(this._renderer, this._settings);

  @override
  Renderer get owner => _renderer;

  final Renderer _renderer;
  final RenderSettings _settings;

  @override
  String get name => 'ssao blur';

  @override
  bool get isActive =>
      _settings.ambientOcclusion.enabled &&
      _settings.ambientOcclusion.strength > 0.0 &&
      _settings.ambientOcclusion.blurTaps > 0;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.ao,
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.ao];

  @override
  void execute(NodeFrame frame) {
    final surface = frame.resources.tryTexture(FrameResourceIds.surfaceBuffer);
    if (surface == null) return;
    _renderer._encodeSsaoBlur(
      source: frame.resources.texture(FrameResourceIds.ao),
      surface: surface,
      options: _settings.ambientOcclusion,
      resources: frame.resources,
    );
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
    // And the contact shadow beside it, for the same reason and with the same
    // unconditional read: its node knows whether it is on, and the graph
    // answering null is what "nobody produced it" looks like — `gfx-76n`.
    FrameResourceIds.contactShadow,
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
    // `R1`'s debug view, declared only when it is asked for, for the reason
    // the surface buffer is.
    if (_settings.showVelocity) FrameResourceIds.velocity,
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
    // **Where the picture lands depends on whether anything runs after it.**
    // Ordinarily this is the renderer's own finished-frame texture — the one
    // that outlives the frame and that Flutter samples — bound by name rather
    // than allocated. With `gfx-04n`'s pass on, the smoothing needs to read a
    // finished picture and write another, and the *presented* texture has to
    // stay the renderer's: a pooled one would be handed back while the
    // compositor was still reading it. So the composite draws into scratch
    // and the pass after it draws into the frame.
    // The antialias node's own condition, sharpening after a resolve
    // included — `R2`.
    final temporal = _settings.antiAlias.temporal;
    final smoothing =
        _settings.antiAlias.enabled ||
        (temporal.enabled && temporal.sharpen > 0.0);
    final target = smoothing
        ? frame.resources.transient(
            RenderTargetSpec(
              width: frame.width,
              height: frame.height,
              format: _renderer.device.defaultColorFormat,
            ),
          )
        : _renderer._ldrColor!;
    // Before the draw, so anything reading `frame` after this node finds the
    // picture rather than nothing.
    frame.resources.provide(FrameResourceIds.frame, target);
    final composited = _renderer._encodeComposite(
      target: target,
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
      bloom: frame.resources.tryTexture(FrameResourceIds.bloom),
      // Optional in the same way the glow is: with the node culled nobody
      // produced it, and the graph answering null is a fact it derived rather
      // than a flag this pass was handed.
      ao: frame.resources.tryTexture(FrameResourceIds.ao),
      contactShadow: frame.resources.tryTexture(FrameResourceIds.contactShadow),
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
      velocity: _settings.showVelocity
          ? frame.resources.tryTexture(FrameResourceIds.velocity)
          : null,
      sceneGraph: _scene,
      views: _views,
      settings: frame.settings,
      width: frame.width,
      height: frame.height,
    );
    overlayLines = composited.lines;
    // The composite's own draws — one, or one per view — and the overlay
    // batch, which is one more when it drew anything.
    frame.state.drawCalls += composited.draws + (overlayLines > 0 ? 1 : 0);
    developer.Timeline.finishSync();
  }
}

/// Edges smoothed on the composited picture — `gfx-04n`'s own row.
///
/// **Registered after the composite, which is the whole of how it knows what
/// to read.** Registration order is the version chain: this node reads the
/// version the composite wrote and produces the next one, and the frame's own
/// result takes whichever version is last. Nothing is threaded, nothing is
/// branched on outside this file.
///
/// It draws into the renderer's finished-frame texture and reads the pooled
/// one the composite drew into — the opposite way round from every other post
/// pass, and deliberately: the texture that leaves the frame has to be the
/// renderer's, because a pooled one would be handed back to the pool while
/// the compositor was still sampling it.
final class _FxaaNode extends RenderNode {
  _FxaaNode(this._renderer, this._settings);

  final Renderer _renderer;
  final AntiAliasSettings _settings;

  @override
  String get name => 'antialias';

  /// On for the edges, or for the sharpening a temporal resolve asks for —
  /// `R2` — which rides in this pass for the four taps it shares.
  @override
  bool get isActive =>
      _settings.enabled ||
      (_settings.temporal.enabled && _settings.temporal.sharpen > 0.0);

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.frame];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    developer.Timeline.startSync('Renderer.antialias');
    final source = frame.resources.texture(FrameResourceIds.frame);
    final target = _renderer._ldrColor!;
    frame.resources.provide(FrameResourceIds.frame, target);
    _renderer._encodeFxaa(target: target, source: source, settings: _settings);
    developer.Timeline.finishSync();
  }
}

/// The scene's brightness, as a graph node, and the readback that meters it.
///
/// Reads the lit scene as everything before bloom left it — reflections in,
/// glow not yet added, exposure not yet applied — because that is the light
/// the exposure is a decision about. Writes a fixed 64×64 target the graph
/// allocates, and then asks the device for its bytes; the answer arrives a
/// frame or two later and lands in the renderer's [ExposureAdapter], which the
/// composite reads at the top of every frame. Nothing here waits.
///
/// A frame output while it is on — see [Renderer._compileFrameGraph] — because
/// no node reads the target and a node whose output nobody reads is culled.
/// The consumer is the readback, which the graph cannot see, exactly as an
/// application reading the surface buffer is a consumer it cannot see.
final class _LuminanceNode extends RenderNode {
  _LuminanceNode(
    this._renderer,
    this._settings, [
    this._views = const <RenderView>[],
  ]);

  final Renderer _renderer;
  final AutoExposureSettings _settings;

  /// The frame's views, for `gfx-22n`: each meters its own rectangle of the
  /// one readback this node asks for. Empty is the frame metering itself,
  /// which is what a single-view frame and every frame before this row did.
  final List<RenderView> _views;

  @override
  String get name => 'luminance';

  @override
  bool get isActive => _settings.enabled;

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.luminance];

  @override
  void execute(NodeFrame frame) {
    final target = frame.resources.texture(FrameResourceIds.luminance);
    _renderer._encodeLuminance(
      target: target,
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
    );
    _renderer._meterExposure(target, _settings, views: _views);
    frame.state.drawCalls++;
  }
}

/// The picking pass, as a graph node. Active only on a frame somebody asked
/// [Renderer.pickPixel] on; see `renderer_pick_pass.dart`.
///
/// A frame output while it is active, for the reason the luminance node is:
/// its consumer is a readback, not a node.
final class _ObjectIdNode extends RenderNode {
  _ObjectIdNode(
    this._renderer, {
    required this.scene,
    required this.ordered,
    required this.picks,
  });

  final Renderer _renderer;
  final Scene scene;
  final List<RenderView> ordered;

  /// This frame's questions, taken off the renderer when the node was built
  /// so a question asked mid-frame waits for the next one.
  final List<_PickRequest> picks;

  @override
  String get name => 'object ids';

  @override
  bool get isActive => picks.isNotEmpty;

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.objectIds];

  @override
  void execute(NodeFrame frame) {
    final drawn = _renderer._encodeObjectIds(
      resources: frame.resources,
      target: frame.resources.texture(FrameResourceIds.objectIds),
      scene: scene,
      ordered: ordered,
      settings: frame.settings,
      width: frame.width,
      height: frame.height,
      picks: picks,
    );
    frame.state.drawCalls += drawn;
    // Its own pipelines, so the tracker's answer about the mesh pipelines is
    // stale for whatever draws next.
    frame.state.invalidatePipeline();
  }
}

/// What [Renderer._encodeScene] hands back to the frame.
final class _ScenePass {
  const _ScenePass({
    required this.culled,
    required this.debugLines,
    required this.lightOverflow,
    required this.submitMicros,
    this.msaaSamples = 1,
    this.msaaDeclined,
  });

  final int culled;
  final int debugLines;
  final int lightOverflow;
  final int submitMicros;

  /// `gfx-20n`: samples the pass actually drew with, and why not more.
  final int msaaSamples;
  final String? msaaDeclined;
}
