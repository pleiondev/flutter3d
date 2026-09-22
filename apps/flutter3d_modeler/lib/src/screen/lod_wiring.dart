/// `_ModelerScreenState`'s own levels-of-detail half — `pro-lod-04`, screen
/// 17: opening it from an object's inspector, and what its panel and its
/// zone bar do to the document.
///
/// **Three commands and one amend.** `AddLod`, `SetLodRatio` and
/// `RegenerateLods` are the whole of `lod_commands.dart`, and each press here
/// is one of them through `ModelerCubit.ran` — one step of undo, the same
/// three an agent reaches over MCP under the same names.
///
/// What that file does not have is a command that moves a level's
/// *threshold*, and the zone bar under the three pictures exists to drag
/// one. So a drag is `ModelHistory.amend` where it honestly can be — see
/// [_moveLodThreshold] — and a sentence where it cannot.
// ignore_for_file: invalid_use_of_protected_member
part of 'modeler_screen.dart';

extension _LodWiring on _ModelerScreenState {
  /// The inspector's own "Open…", for the object [id] names. The argument is
  /// not kept: the screen is of whatever is held, the way every other panel
  /// is, and it was the held object whose button this was.
  void _openLods(int id) => setState(() => _lod.open = true);

  void _closeLods() => setState(() => _lod.open = false);

  /// Why a level cannot be added to [object], or null.
  ///
  /// `AddLod` itself accepts any object — a level is two numbers on the
  /// document — but a level of a shape with no triangles is a card with no
  /// count on it and a third of the screen that stays empty, and the reason
  /// is one press away in Object mode.
  String? _lodRefusal(ModelObject object) => switch (object.geometry) {
    EditedGeometry() || ImportedGeometry() => null,
    _ => AppLocalizations.of(context).lodRefusalNoMesh(object.name),
  };

  /// The levels of [object], as `LodPanel` lists them — each with the
  /// triangle count its simplified mesh actually came out at.
  List<LodLevelRow> _lodRowsOf(ModelObject object) => <LodLevelRow>[
    for (var i = 0; i < object.lods.length; i++)
      (
        ratio: object.lods[i].ratio,
        maxScreenFraction: object.lods[i].maxScreenFraction,
        triangles: _lod.cache.meshFor(object, i)?.triangleCount,
      ),
  ];

  /// "Now: 34 % of the screen — LOD 1", measured against the document's own
  /// camera, or null when there is nothing on stage to measure.
  ///
  /// `lod_screen_fraction.dart` is the engine's own arithmetic asked of a
  /// size rather than of a scene node, and this is where it is handed one:
  /// the held object's world bounds, as far from the camera as the camera
  /// is. Without it a threshold is a percentage of something a person has to
  /// imagine; with it, orbiting out until the line changes level *is* the
  /// preview.
  String? _lodNowOf(ModelerReady state, ModelObject object) {
    final vm.Aabb3? bounds = switch (state.stage.sync?.nodeOf(object.id)) {
      final MeshNode node => node.worldBounds,
      _ => null,
    };
    if (bounds == null) return null;
    final double fraction = screenFractionForSize(
      diameterMeters: (bounds.max - bounds.min).length,
      distanceMeters:
          (state.stage.overlayView(_viewportHeight).eye - bounds.center).length,
      projection: state.stage.camera.projection,
    );
    final int percent = (fraction * 100).round();
    final AppLocalizations l = AppLocalizations.of(context);
    return switch (lodLevelAt(<double>[
      for (final LodSpec each in object.lods) each.maxScreenFraction,
    ], fraction)) {
      final int level => l.lodNow(percent, level),
      null => l.lodNowBase(percent),
    };
  }

  void _addLod() {
    final ModelObject? held =
        _history.project[_history.selection.activeObject ?? -1];
    if (held == null) return;
    final next = nextLodAfter(held.lods);
    _cubit.ran(
      AddLod(
        id: held.id,
        ratio: next.ratio,
        maxScreenFraction: next.maxScreenFraction,
      ),
    );
  }

  void _setLodRatio(int lodIndex, double ratio) {
    final int? id = _history.selection.activeObject;
    if (id == null) return;
    _cubit.ran(SetLodRatio(id: id, lodIndex: lodIndex, ratio: ratio));
  }

  /// The panel's own Regenerate. The command moves the object's version on,
  /// which is already enough for `LodMeshCache` to simplify again; the
  /// `invalidate` beside it is for the case the command's own doc comment
  /// names — a build whose simplifier changed under a cache that outlived it
  /// — and costs nothing in the ordinary one.
  void _regenerateLods() {
    final int? id = _history.selection.activeObject;
    if (id == null) return;
    _lod.cache.invalidate(id);
    _cubit.ran(RegenerateLods(id));
  }

  /// A marker on `LodZoneBar` was dragged.
  ///
  /// **An amend of the `AddLod` that made the level, when that is the step
  /// on top.** There is no `SetLodThreshold`: the only command that writes a
  /// `maxScreenFraction` is the one that adds the level. While it is the
  /// last thing that happened, `ModelHistory.amend` re-runs it with the new
  /// number against the document as it was before — which is what that
  /// method is for ("a person dragging that slider is adjusting one step,
  /// not making sixty") and what `LodZoneBar`'s own doc comment asks of its
  /// caller. The stack does not grow, undo takes the whole level back, and
  /// add-then-place is the order a person works in anyway.
  ///
  /// **And a sentence otherwise.** A level added three steps ago cannot be
  /// reached that way without taking the three steps back, so the drag says
  /// what is true — this build has no command that moves one — once, rather
  /// than sixty times a second while the marker is held.
  void _moveLodThreshold(int lodIndex, double maxScreenFraction) {
    final state = _state;
    if (state is! ModelerReady) return;
    final ModelObject? held = state.project[state.selection.activeObject ?? -1];
    if (held == null) return;

    final List<ModelCommand> journal = state.history.journal;
    final ModelCommand? top = journal.isEmpty ? null : journal.last;
    if (top is AddLod &&
        top.id == held.id &&
        lodIndex == held.lods.length - 1 &&
        maxScreenFraction > 0) {
      _amend(
        AddLod(
          id: top.id,
          ratio: top.ratio,
          maxScreenFraction: maxScreenFraction,
        ),
      );
      return;
    }
    final String fixed = AppLocalizations.of(context).lodThresholdFixed;
    if (state.said != fixed) _cubit.say(fixed, important: true, refusal: true);
  }
}
