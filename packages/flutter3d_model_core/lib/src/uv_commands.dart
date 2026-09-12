/// Computing a UV where none was drawn by hand — `pro-uv-06`'s own row.
part of 'command.dart';

/// Which algorithm [UnwrapCommand] hands a face's own island to.
///
/// A `final class` with a `static const` instance rather than an `enum`, the
/// same choice `BlendMode`/`DriverAxis`/`ShapeDriverCurve` already make in
/// this project's own published packages: a second method later is a second
/// instance, not a break in an already-shipped enum.
final class UnwrapMethod {
  const UnwrapMethod._(this.name);

  /// Least Squares Conformal Maps — the only method there is today.
  static const UnwrapMethod lscm = UnwrapMethod._('lscm');

  final String name;

  @override
  String toString() => 'UnwrapMethod.$name';
}

/// Lays out a UV for the selected faces, or the whole mesh when nothing is
/// selected, by [method].
///
/// **One-shot, not a modifier.** This writes directly into the mesh's own
/// corner UVs the way `MarkSeam`/`RecalculateNormals` write directly into its
/// flags and windings — it does not sit on `ModelObject.modifiers` and does
/// not recompute itself when the geometry underneath later changes. Running
/// it again after an edit re-unwraps from scratch, which is what "с
/// переприменением" asks for here: the same re-invokable shape every other
/// mesh command already has through the undo journal, not the modifier
/// stack's own live-recompute machinery — that machinery exists for a
/// different reason (`modifier_commands.dart`'s own doc comment) and nothing
/// about a UV layout needs a person to see it happen before it is baked.
///
/// **Islands are cut by seam, same as `pro-uv-02`'s own [splitIslands]/[lscm].**
/// A selection narrower than the whole mesh restricts which faces
/// [splitIslands] is allowed to walk, so unwrapping one selected patch never
/// reaches past it onto a face nobody chose.
final class UnwrapCommand extends ModelCommand {
  const UnwrapCommand({
    this.method = UnwrapMethod.lscm,
    this.margin = 0.01,
    this.autoPack = true,
  });

  final UnwrapMethod method;

  /// The gap [autoPack] leaves between islands in UV space, in the same
  /// units the packed square's own [0, 1] edge is measured in.
  final double margin;

  /// Whether every island is laid into one shared unit square afterwards.
  /// False leaves each island in its own unnormalized space — its own scale
  /// and position straight out of [lscm] — for a caller meaning to pack later
  /// itself, alongside islands this command never touched.
  final bool autoPack;

  @override
  String get name => 'unwrap';

  @override
  String get says => 'unwrap';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'method': method.name,
    'margin': margin,
    'autoPack': autoPack,
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'margin': DoubleHint(min: 0, step: 0.001),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      _asMeshStep(project, selection, (_MeshTarget target) {
        final requested = target.elements.convertedTo(
          target.mesh,
          ElementLevel.face,
        );
        final faces = requested.isEmpty
            ? Selection.all(target.mesh, ElementLevel.face)
            : requested;
        if (faces.isEmpty) {
          return OpResult.refused(
            'the mesh has no faces to unwrap',
            selection: target.elements,
          );
        }

        final islands = splitIslands(
          target.mesh,
          restrictToFaces: faces.ids.toSet(),
        );
        for (final island in islands) {
          lscm(target.mesh, island);
        }
        if (autoPack) _packIslandsInPlace(target.mesh, islands, margin);

        return OpResult.done(selection: target.elements, topologyChanged: true);
      });
}

/// Reads each of [islands]' own UV bounding box straight back off [mesh],
/// packs those boxes with [packIslands], and rewrites every corner's UV into
/// its packed place — the same "read what [lscm] just wrote, lay it out,
/// write it back" round trip a caller doing this by hand would make, done
/// once so [UnwrapCommand] does not have to carry [lscm]'s own per-triangle
/// bookkeeping to know where an island's corners ended up.
void _packIslandsInPlace(EditMesh mesh, List<List<int>> islands, double margin) {
  if (islands.isEmpty) return;

  final bounds = <(double minU, double minV, double maxU, double maxV)>[];
  for (final island in islands) {
    var minU = double.infinity, minV = double.infinity;
    var maxU = -double.infinity, maxV = -double.infinity;
    for (final face in island) {
      mesh.forEachHalfEdge(face, (half) {
        final uv = mesh.uvOf(half);
        if (uv.x < minU) minU = uv.x;
        if (uv.y < minV) minV = uv.y;
        if (uv.x > maxU) maxU = uv.x;
        if (uv.y > maxV) maxV = uv.y;
      });
    }
    // A degenerate (empty or point) island still gets a real, packable box —
    // the same "cost nothing rather than something wrong" [packIslands]
    // itself asks of its own input.
    if (!minU.isFinite) {
      minU = minV = 0;
      maxU = maxV = 0;
    }
    if (maxU < minU + 1e-6) maxU = minU + 1e-6;
    if (maxV < minV + 1e-6) maxV = minV + 1e-6;
    bounds.add((minU, minV, maxU, maxV));
  }

  final sizes = <Vector2>[
    for (final (minU, minV, maxU, maxV) in bounds) Vector2(maxU - minU, maxV - minV),
  ];
  final packed = packIslands(sizes, margin: margin, allowRotate90: true);
  if (packed == null) return; // Nothing sane to pack into — leave the raw UVs.

  for (var i = 0; i < islands.length; i++) {
    final (minU, minV, _, _) = bounds[i];
    final width = sizes[i].x;
    final placement = packed.islands[i];
    for (final face in islands[i]) {
      mesh.forEachHalfEdge(face, (half) {
        final uv = mesh.uvOf(half);
        final localU = uv.x - minU;
        final localV = uv.y - minV;
        final double rotatedU, rotatedV;
        if (placement.rotated) {
          rotatedU = localV;
          rotatedV = width - localU;
        } else {
          rotatedU = localU;
          rotatedV = localV;
        }
        mesh.setUv(
          half,
          Vector2(
            placement.offset.x + rotatedU * packed.scale,
            placement.offset.y + rotatedV * packed.scale,
          ),
        );
      });
    }
  }
}
