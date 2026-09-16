/// `pro-sc-06`: a whole sculpting stroke as one command, one undo step and
/// one MCP call.
///
/// **A stroke, not a dab.** A brush reports a sample per pointer move, and a
/// finger crossing a tablet reports a few hundred a second; a command per
/// sample would be a few hundred presses of ⌘Z to take back one gesture,
/// which is the single most complained-about behaviour a modelling tool can
/// have. So [SculptStroke] carries the whole polyline — every point and the
/// pressure at each — and runs it inside one journal step, the shape
/// [PaintWeights] already has for the same reason.
///
/// **It edits the document's own mesh, through a sculpt mesh it keeps to one
/// side.** `pro-sc-02`'s [SculptMesh] is what a brush needs — chunked
/// positions, a uniform grid, CSR adjacency — and none of that is what a
/// document stores; converting a mesh in and out per stroke would cost a
/// Morton sort and a retriangulation for two thousand moved vertices out of
/// two hundred thousand. So the sculpt mesh is built once, kept against the
/// [EditMesh] it came from, and the positions a stroke moved are written back
/// through [SculptMesh.sourceVertices] as the step's own writes. What the
/// history keeps is therefore the size of what the brush touched, not the
/// size of the model, which is the row's own acceptance: a hundred strokes at
/// one per cent of a two-hundred-thousand-vertex mesh cost a fraction of a
/// hundred copies of it, and undo is byte-exact because the journal holds the
/// floats that were there.
///
/// **The kept sculpt mesh is dropped the moment anything else touches the
/// document's mesh.** An undo, a loop cut, a modifier bake — anything that
/// moves the [EditMesh]'s own journal by a step this file did not take —
/// leaves the cached positions describing a shape that is no longer there,
/// and a brush run against it would push vertices from where they used to be.
/// [_sculptFor] notices by comparing [EditMesh.undoDepth] against what the
/// last stroke left, and rebuilds rather than guessing.
part of 'command.dart';

/// How many bytes of mesh journal a history may hold before the oldest steps
/// are dropped — `pro-sc-06`'s own number.
///
/// **Half a gigabyte, and the unit is bytes rather than steps because a
/// sculpting step is not a size anybody can predict.** [ModelHistory.depth]
/// caps how many steps are kept and that is the right cap for ordinary edits,
/// where a step is a moved object or a renamed material. A sculpting stroke
/// is a few thousand vertices on a small mesh and a few hundred thousand on a
/// dense one, so sixty-four of them is somewhere between a megabyte and three
/// gigabytes — a number that says nothing about what a machine is being asked
/// to hold. Counting the bytes says exactly that, and 512 MB is what a
/// sculpting session can spend on being able to go back without being the
/// reason the session runs out of memory.
const int kHistoryBudgetBytes = 512 * 1024 * 1024;

/// The sculpt mesh kept for an [EditMesh], and the mesh journal depth it was
/// last known to agree with.
final class _SculptCacheEntry {
  _SculptCacheEntry(this.sculpt, this.atUndoDepth);

  final SculptMesh sculpt;

  /// [EditMesh.undoDepth] as it was when the last stroke finished. A
  /// different depth now means something else has moved the mesh.
  int atUndoDepth;
}

/// Sculpt meshes by the [EditMesh] they were built from.
///
/// An [Expando] rather than a map keyed by object id: a mesh outlives the
/// object wrapper round it (every mesh command hands back a fresh
/// [ModelObject] round the same [EditMesh]), and an entry here should go when
/// the mesh does rather than when a document stops naming it.
final Expando<_SculptCacheEntry> _sculptMeshes = Expando<_SculptCacheEntry>();

/// The sculpt mesh for [mesh] — built now when there is none, or when
/// something other than a stroke has moved the mesh since the last one.
SculptMesh _sculptFor(EditMesh mesh) {
  final _SculptCacheEntry? kept = _sculptMeshes[mesh];
  if (kept != null && kept.atUndoDepth == mesh.undoDepth) return kept.sculpt;
  final SculptMesh built = SculptMesh.fromEditMesh(mesh);
  _sculptMeshes[mesh] = _SculptCacheEntry(built, mesh.undoDepth);
  return built;
}

/// One sculpting stroke: a brush, the points it was dragged through, and the
/// pressure at each of them.
///
/// See this library's own doc comment for why a stroke rather than a dab, and
/// for how a stroke reaches the document's mesh. [pressures] scales
/// [Brush.strength] per point — a tablet's own reading, or a list of ones for
/// a mouse, which is also what an empty [pressures] means.
final class SculptStroke extends ModelCommand {
  const SculptStroke({
    required this.objectId,
    required this.kind,
    required this.radius,
    required this.strength,
    required this.points,
    this.pressures = const <double>[],
    this.falloff = BrushFalloff.smooth,
    this.symmetryX = false,
  });

  /// The object whose mesh the stroke lands on.
  final int objectId;

  /// Which brush — [BrushKind.draw], `clay`, `smooth` and the rest.
  final BrushKind kind;

  final double radius;
  final double strength;

  /// Where the brush was dragged, in the mesh's own space, in order.
  final List<Vector3> points;

  /// Pressure per point, `0..1`, index-aligned with [points]. Empty means
  /// full pressure throughout, which is what a mouse gives.
  final List<double> pressures;

  final BrushFalloff falloff;

  /// Whether the same stroke is applied mirrored across `x = 0` — see
  /// [applyBrushStroke].
  final bool symmetryX;

  @override
  String get name => 'sculptStroke';

  @override
  String get says => 'sculpt';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'objectId': objectId,
    'kind': kind.name,
    'radius': radius,
    'strength': strength,
    'points': <Object?>[
      for (final Vector3 p in points) <double>[p.x, p.y, p.z],
    ],
    if (pressures.isNotEmpty) 'pressures': pressures,
    'falloff': falloff.name,
    'symmetryX': symmetryX,
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'radius': DoubleHint(min: 0.001, max: 10, step: 0.01),
    'strength': DoubleHint(min: 0, max: 1, step: 0.05),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final ModelObject? object = project[objectId];
    if (object == null) return Outcome.refused('there is no object $objectId');
    final EditedGeometry? edited = switch (object.geometry) {
      final EditedGeometry it => it,
      _ => null,
    };
    if (edited == null) {
      return Outcome.refused(
        '"${object.name}" has no mesh to sculpt — bake it to a mesh first',
      );
    }
    if (points.isEmpty) {
      return Outcome.refused('sculptStroke needs at least one point');
    }
    if (pressures.isNotEmpty && pressures.length != points.length) {
      return Outcome.refused(
        'sculptStroke was given ${points.length} points and '
        '${pressures.length} pressures',
      );
    }
    if (radius <= 0) {
      return Outcome.refused('a brush with radius $radius reaches nothing');
    }

    final EditMesh mesh = edited.mesh;
    final SculptMesh sculpt = _sculptFor(mesh);
    if (sculpt.vertexCount == 0) {
      return Outcome.refused('"${object.name}" has no vertices to sculpt');
    }

    // Every vertex any dab moved, so the write-back walks each one once even
    // where a stroke passed over it twenty times.
    final moved = <int>{};
    Vector3? previous;
    for (var i = 0; i < points.length; i++) {
      final double pressure = pressures.isEmpty ? 1.0 : pressures[i];
      if (pressure <= 0) {
        // A sample with no pressure on it is the pen leaving the tablet, not
        // a dab of zero strength: it still moves the brush, so `grab`'s next
        // drag vector starts from here rather than from where the pen last
        // pressed.
        previous = points[i];
        continue;
      }
      final BrushResult result = applyBrushStroke(
        sculpt,
        Brush(
          kind: kind,
          radius: radius,
          strength: strength * pressure,
          falloff: falloff,
        ),
        center: points[i],
        previousCenter: previous,
        symmetryX: symmetryX,
      );
      moved.addAll(result.touchedVertices);
      previous = points[i];
    }
    if (moved.isEmpty) {
      return Outcome.refused('the brush reached no vertices');
    }

    mesh.beginStep();
    final Vector3 at = Vector3.zero();
    for (final int vertex in moved) {
      mesh.moveVertex(
        sculpt.sourceVertices[vertex],
        sculpt.positionOf(vertex, at),
      );
    }
    mesh.endStep();
    _sculptMeshes[mesh] = _SculptCacheEntry(sculpt, mesh.undoDepth);

    // A fresh `ModelObject` round the same, in-place-mutated mesh — see
    // `PaintWeights.apply` for why a stroke that only touches the mesh still
    // has to rewrap: a viewport uploads on a bumped version, and
    // `ModelHistory.endTransaction` throws away a step whose project is
    // `identical` to what it started from.
    return Outcome.done(
      project.withObject(object.copyWith(geometry: EditedGeometry(mesh))),
      meshTouched: mesh,
    );
  }
}

/// The [BrushKind] [name] names, or null — the reader half of
/// [BrushKind.name], kept here rather than in `flutter3d_mesh` because this
/// is the only place a brush arrives as text.
BrushKind? _brushKindNamed(String name) => switch (name) {
  'draw' => BrushKind.draw,
  'clay' => BrushKind.clay,
  'smooth' => BrushKind.smooth,
  'flatten' => BrushKind.flatten,
  'inflate' => BrushKind.inflate,
  'grab' => BrushKind.grab,
  'pinch' => BrushKind.pinch,
  'crease' => BrushKind.crease,
  _ => null,
};

/// The [BrushFalloff] [name] names, or null.
BrushFalloff? _brushFalloffNamed(String name) => switch (name) {
  'linear' => BrushFalloff.linear,
  'smooth' => BrushFalloff.smooth,
  'sharp' => BrushFalloff.sharp,
  _ => null,
};

/// Every point in [json] as a [Vector3], or null on the first one that is not
/// three numbers — the "no half-built command" rule every reader here keeps.
List<Vector3>? _strokePointsFrom(Object? json) {
  if (json is! List<Object?>) return null;
  final out = <Vector3>[];
  for (final Object? each in json) {
    final List<double>? triple = _doubles(each, 3);
    if (triple == null) return null;
    out.add(Vector3(triple[0], triple[1], triple[2]));
  }
  return out;
}
