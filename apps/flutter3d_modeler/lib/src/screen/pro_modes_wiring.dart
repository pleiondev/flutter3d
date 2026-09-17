/// `_ModelerScreenState`'s own phase-four half: what the retopology, paint,
/// simulation and render modes do when something on their panel is pressed.
///
/// **Four modes, one file, because they share a shape.** Each of them is a
/// panel of settings over a command or two — none has a gesture of its own
/// except the paint brush, which rides the same `StrokeEvent` path the
/// sculpting brush already does. Splitting them into four files would put
/// four almost-identical `setState` blocks in four places.
///
/// **The long jobs are awaited on this isolate and say so.** A bake of a
/// 1024² normal map takes seconds, and `pro-job-01`'s own `Job` is what will
/// take it off the frame; until a mode has been used in anger there is no
/// number to size that decision with, so what is here runs it, shows the
/// progress the panel already draws, and leaves the row honest about it.
// ignore_for_file: invalid_use_of_protected_member
part of 'modeler_screen.dart';

extension _ProModesWiring on _ModelerScreenState {
  // ------------------------------------------------------------- retopology

  void _setRetopoQuads(int to) => setState(() => _retopo.quads = to);

  void _setBakeResolution(int to) =>
      setState(() => _retopo.bakeResolution = to);

  void _setBakeMap(String map, bool on) => setState(() {
    if (on) {
      _retopo.bakeMaps.add(map);
    } else {
      _retopo.bakeMaps.remove(map);
    }
  });

  /// Why neither button on the bake panel can run, or null.
  ///
  /// Asked before the press rather than after it, so the button is disabled
  /// and says which of the three it is — the same bargain `_subdivideRefusal`
  /// makes for the sculpting mode's own Subdivide.
  String? _bakeRefusal(ModelerReady state) {
    final int? objectId = state.selection.activeObject;
    final ModelObject? object = objectId == null
        ? null
        : state.project[objectId];
    if (object == null) return 'Select an object to retopologize';
    if (object.geometry is! EditedGeometry) {
      return '"${object.name}" has no mesh yet — bake it to a mesh first';
    }
    if (object.materialSlots.isEmpty) {
      return '"${object.name}" has no material for a baked map to land on';
    }
    return null;
  }

  /// `pro-rt-01`'s own `retopologize`, run over the selected object and
  /// written back as a new mesh.
  void _retopologize() {
    final state = _state;
    if (state is! ModelerReady) return;
    final int? objectId = state.selection.activeObject;
    if (objectId == null) return;
    _cubit.ran(Retopologize(objectId: objectId, targetQuads: _retopo.quads));
  }

  /// The Bake button: one `BakeMaps` over the two objects the mode names —
  /// whatever is selected, onto itself, since a retopology drawn in this
  /// mode replaces the object it came from.
  Future<void> _bakeTheMaps() async {
    final state = _state;
    if (state is! ModelerReady) return;
    final int? objectId = state.selection.activeObject;
    if (objectId == null || _retopo.bakeMaps.isEmpty) return;

    setState(
      () => _retopo.baking = (
        label: AppLocalizations.of(context).bakingMaps(_retopo.bakeMaps.length),
        fraction: null,
      ),
    );
    // A frame, so the progress is on screen before the bake takes the
    // isolate — see this file's own doc comment about where this goes next.
    await Future<void>.delayed(Duration.zero);
    try {
      _cubit.ran(
        BakeMaps(
          sourceId: objectId,
          targetId: objectId,
          maps: _retopo.bakeMaps.toList(),
          resolution: _retopo.bakeResolution,
        ),
      );
    } finally {
      if (mounted) setState(() => _retopo.baking = null);
    }
  }

  void _cancelBake() => setState(() => _retopo.baking = null);

  // ------------------------------------------------------------------ paint

  void _setPaintLayer(int to) => setState(() => _paint.layer = to);
  void _setPaintColour(List<double> to) => setState(() => _paint.colour = to);
  void _setPaintRadius(double to) => setState(() => _paint.diameter = to);
  void _setPaintStrength(double to) => setState(() => _paint.strength = to);
  void _setPaintMask(String? to) => setState(() => _paint.mask = to);

  /// A layer above the ones there are. The stack itself grows when a stroke
  /// lands on a layer past its end (`PaintStroke.layer`), so this only has
  /// to move the selection.
  void _addPaintLayer() =>
      setState(() => _paint.layer = _paintLayersOf(_state).length);

  /// The layers of the selected object's own material, as the panel lists
  /// them — empty for anything with no paint on it yet.
  List<PaintLayerRow> _paintLayersOf(ModelerState state) {
    if (state is! ModelerReady) return const <PaintLayerRow>[];
    final PaintStack? stack = _paintStackOf(state);
    if (stack == null) return const <PaintLayerRow>[];
    return <PaintLayerRow>[
      for (var i = 0; i < stack.layers.length; i++)
        (
          name: 'Layer ${i + 1}',
          blend: stack.layers[i].blendMode.name,
          visible: true,
        ),
    ];
  }

  PaintStack? _paintStackOf(ModelerReady state) {
    final int? objectId = state.selection.activeObject;
    final ModelObject? object = objectId == null
        ? null
        : state.project[objectId];
    if (object == null || object.materialSlots.isEmpty) return null;
    final int at = object.materialSlots.first;
    if (at < 0 || at >= state.project.materials.length) return null;
    return state.project.materials[at].paint;
  }

  /// The baked maps this project has, by the name their image carries —
  /// what the mask dropdown offers.
  List<String> _paintMasksOf(ModelerReady state) => <String>[
    for (final EncodedImage image in state.project.images)
      if (image.name != null && image.name!.endsWith(' bake')) image.name!,
  ];

  String? _paintRefusal(ModelerReady state) {
    final int? objectId = state.selection.activeObject;
    final ModelObject? object = objectId == null
        ? null
        : state.project[objectId];
    if (object == null) return 'Select an object to paint on';
    final EditMesh? mesh = switch (object.geometry) {
      EditedGeometry(:final mesh) => mesh,
      _ => null,
    };
    if (mesh == null) {
      return '"${object.name}" has no mesh yet — bake it to a mesh first';
    }
    if (!mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0)) {
      return '"${object.name}" has no UVs — unwrap it first';
    }
    if (object.materialSlots.isEmpty) {
      return '"${object.name}" has no material to paint onto';
    }
    return null;
  }

  /// `ModelerViewport.onStroke` while the paint brush is armed — the same
  /// shape `_onSculptStroke` has, over `PaintStroke` instead.
  void _onPaintStroke(StrokeEvent event) {
    final state = _state;
    if (state is! ModelerReady) return;
    final int? objectId = state.selection.activeObject;
    if (objectId == null) return;

    switch (event.phase) {
      case StrokePhase.start:
        // `pro-pt-03`: what the stack looked like before the stroke, so the
        // tiles it replaces are the rectangle uploaded when it closes —
        // see `paint_upload.dart` for why a whole upload per stroke is the
        // difference between painting and waiting.
        _paintUpload.opened(
          _paintStackOf(state),
          canvas: _paintCanvasSideOf(state),
        );
        _paintSession.pointerDown(
          view: event.view,
          at: event.at,
          objectId: objectId,
          radiusPixels: _paint.radius,
          colour: _paint.colour,
          strength: _paint.strength * event.force,
          layer: _paint.layer,
          maskImage: _maskImageOf(state),
        );
      case StrokePhase.move:
        _paintSession.pointerMove(
          view: event.view,
          at: event.at,
          radiusPixels: _paint.radius,
          colour: _paint.colour,
          strength: _paint.strength * event.force,
          layer: _paint.layer,
          maskImage: _maskImageOf(state),
        );
      case StrokePhase.end:
        _paintSession.pointerUp();
        unawaited(_uploadPaint());
        unawaited(_refreshPaintCanvas());
    }
  }

  /// Which image the chosen mask is, or null for none.
  int? _maskImageOf(ModelerReady state) {
    final String? wanted = _paint.mask;
    if (wanted == null) return null;
    for (var i = 0; i < state.project.images.length; i++) {
      if (state.project.images[i].name == wanted) return i;
    }
    return null;
  }

  /// The side of the canvas this material paints onto, in texels.
  int _paintCanvasSideOf(ModelerReady state) {
    final PaintStack? stack = _paintStackOf(state);
    if (stack == null || stack.layers.isEmpty) return 1024;
    return stack.layers.first.tilesX * paintTileSize;
  }

  /// `pro-pt-03`: writes the rectangle the stroke changed into the texture
  /// the viewport is already sampling, rather than letting `MaterialPool`
  /// decode and upload the whole image again because its bytes changed.
  Future<void> _uploadPaint() async {
    final state = _state;
    final PaintUpload upload = _paintUpload;
    if (state is! ModelerReady) return;
    final int? objectId = state.selection.activeObject;
    final ModelObject? object = objectId == null
        ? null
        : state.project[objectId];
    if (object == null || object.materialSlots.isEmpty) return;
    final int at = object.materialSlots.first;
    if (at < 0 || at >= state.project.materials.length) return;
    final ProjectMaterial material = state.project.materials[at];
    final int? image = material.surface.baseColorTexture?.imageIndex;
    if (image == null) return;
    final TextureHandle? texture = state.stage.materials?.textureForImage(
      state.project,
      image,
    );
    final PaintStack? stack = material.paint;
    if (texture == null || stack == null) return;
    await upload.flush(texture, stack, stack.flatten());

    // **The mip chain, on completion.** The write above touched level zero
    // and nothing else, which is all `overwriteTexture` will do and all the
    // screen needs while the pointer is down. `PaintStroke` bumped this
    // material's version, so one refresh rebuilds exactly it — decoding the
    // flattened canvas and uploading it with whatever chain its sampling
    // asks for. Awaited after the rectangle rather than instead of it: the
    // decode is the cost the rectangle exists to keep out of the drag, and
    // paying it once when the gesture ends is what the row asked for.
    if (!mounted) return;
    await state.stage.materials?.refresh(state.project);
  }

  /// Decodes the flattened canvas for the panel to draw, after a stroke.
  ///
  /// **Here rather than in the panel**, for the reason `PaintPanel.canvas`'s
  /// own doc comment gives: decoding needs a frame to await, and a widget
  /// that did it would blink blank on every rebuild of its parent.
  Future<void> _refreshPaintCanvas() async {
    final state = _state;
    if (state is! ModelerReady) return;
    final int? objectId = state.selection.activeObject;
    final ModelObject? object = objectId == null
        ? null
        : state.project[objectId];
    if (object == null || object.materialSlots.isEmpty) return;
    final int at = object.materialSlots.first;
    if (at < 0 || at >= state.project.materials.length) return;
    final int? image =
        state.project.materials[at].surface.baseColorTexture?.imageIndex;
    if (image == null || image >= state.project.images.length) return;
    final ui.Codec codec = await ui.instantiateImageCodec(
      state.project.images[image].bytes,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _paint.canvas = frame.image);
  }

  // ------------------------------------------------------------- simulation

  void _setSimKind(String to) => setState(() {
    _sim.kind = to;
    _sim.parameters = _defaultSimParameters(to);
  });

  void _setSimParameter(String name, double to) => setState(
    () => _sim.parameters = <String, double>{..._sim.parameters, name: to},
  );

  void _setSimCollider(String name, bool on) => setState(
    () => on ? _sim.colliders.add(name) : _sim.colliders.remove(name),
  );

  /// Everything else in the scene with a mesh, and whether it is switched on
  /// as something to collide with.
  Map<String, bool> _simCollidersOf(ModelerReady state) {
    final int? objectId = state.selection.activeObject;
    return <String, bool>{
      for (final ModelObject each in state.project.objects)
        if (each.id != objectId && each.geometry is! SocketGeometry)
          each.name: _sim.colliders.contains(each.name),
    };
  }

  void _pinSimSelection(ModelerReady state) => setState(
    () => _sim.pinned = <int>{..._sim.pinned, ...state.selection.elements},
  );

  void _clearSimPins() => setState(() => _sim.pinned = <int>{});

  void _seekSimulation(int to) => setState(() => _sim.frame = to);

  void _toggleSimulation() => setState(() => _sim.playing = !_sim.playing);

  void _bakeSimulation() => setState(() {
    // A real solve is `BakeClothJobRequest`'s own job and has no
    // synchronous shape to wait on — `applySimulationCache`'s own tool
    // description says the same thing to an agent. What this does is mark
    // the cache as being built so the strip says so; the solve lands when
    // `pro-job-01`'s own runner carries it.
    _sim.cache = (
      frames: _sim.cache.frames,
      baked: _sim.cache.baked,
      running: true,
    );
  });

  void _clearSimCache() => setState(() {
    _sim.cache = (frames: 0, baked: 0, running: false);
    _sim.frame = 0;
    _sim.playing = false;
  });

  /// The numbers a kind starts at — a cloth is not a rigid body and the two
  /// have no parameter in common, which is why the chips replace the whole
  /// list rather than relabelling it.
  static Map<String, double> _defaultSimParameters(String kind) =>
      switch (kind) {
        'rigid' => const <String, double>{'mass': 0.5, 'friction': 0.4},
        'particles' => const <String, double>{'rate': 0.3, 'lifetime': 0.5},
        _ => const <String, double>{'stiffness': 0.6, 'damping': 0.1},
      };

  // ----------------------------------------------------------------- render

  void _setRenderPass(String pass, bool on) => setState(() {
    _render.passes = <RenderPassRow>[
      for (final RenderPassRow each in _render.passes)
        if (each.name == pass)
          (name: each.name, enabled: on, fixed: each.fixed)
        else
          each,
    ];
  });

  /// The Render button: `pro-rn-02`'s own tiled job, over the project as it
  /// stands, with the tiles reported as they land.
  Future<void> _renderSnapshot() async {
    final state = _state;
    if (state is! ModelerReady) return;
    if (state.project.objects.isEmpty) return;

    const int tiles = 4;
    setState(() {
      _render.tilesTotal = tiles * tiles;
      _render.tilesDone = 0;
    });
    try {
      final Uint8List png = await renderSnapshotOf(
        state.project,
        width: kRenderResultSize.width.round(),
        height: kRenderResultSize.height.round(),
        tiles: tiles,
        onProgress: (double done) {
          if (!mounted) return;
          setState(() => _render.tilesDone = (done * tiles * tiles).round());
        },
      );
      final ui.Codec codec = await ui.instantiateImageCodec(png);
      final ui.FrameInfo frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _render.result = frame.image;
        _render.tilesDone = tiles * tiles;
      });
    } finally {
      if (mounted) {
        setState(() {
          _render.tilesTotal = 0;
          _render.tilesDone = 0;
        });
      }
    }
  }

  void _cancelRender() => setState(() {
    _render.tilesTotal = 0;
    _render.tilesDone = 0;
  });
}
