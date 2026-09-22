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
void _packIslandsInPlace(
  EditMesh mesh,
  List<List<int>> islands,
  double margin,
) {
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
    for (final (minU, minV, maxU, maxV) in bounds)
      Vector2(maxU - minU, maxV - minV),
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

/// `pro-uv-08n`: several objects' UVs packed into one shared square, and
/// their materials pointed at one material.
///
/// **Nine props with one texture is one draw call instead of nine.** That is
/// the whole reason an atlas exists, and it is why this is a command over a
/// *set* of objects rather than something each of them could do alone: the
/// packing only means anything if every one of them agrees about which part
/// of the square is theirs.
///
/// **Each object keeps its own island layout and is scaled into a cell.**
/// Re-unwrapping everything into one square would throw away seams somebody
/// chose; what happens instead is that each object's existing UVs are
/// measured, the set of bounding boxes is packed by `packIslands`, and every
/// object's UVs are mapped into the box it was given. A person who laid a
/// face out carefully keeps that layout, smaller.
///
/// **The materials are merged onto the first object's own.** An atlas whose
/// objects still pointed at nine materials would be nine draw calls with one
/// texture — all of the packing and none of the gain. The other materials
/// are left in the project rather than deleted: a material nothing draws
/// with is a few hundred bytes, and deleting one out from under a `SetRig`
/// or a keyframe that names it by index is a document that no longer opens.
final class PackAtlas extends ModelCommand {
  const PackAtlas({required this.objectIds, this.margin = 0.01});

  /// Which objects share the atlas, in the order their cells are packed.
  final List<int> objectIds;

  /// Empty space between two objects' cells and around the square's edge,
  /// as a fraction of the square — what keeps one object's bilinear filter
  /// from reading the next one's texels.
  final double margin;

  @override
  String get name => 'packAtlas';

  @override
  String get says => 'pack ${objectIds.length} objects into one atlas';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'objectIds': objectIds,
    'margin': margin,
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'margin': DoubleHint(min: 0, max: 0.1, step: 0.005),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (objectIds.length < 2) {
      return Outcome.refused(
        'an atlas is shared, and ${objectIds.length} object is not a share',
      );
    }
    if (margin < 0 || margin > 0.25) {
      return Outcome.refused('a margin of $margin is not a fraction of a side');
    }

    final meshes = <int, EditMesh>{};
    final boxes = <int, (Vector2 min, Vector2 max)>{};
    for (final int id in objectIds) {
      final ModelObject? object = project[id];
      if (object == null) return Outcome.refused('there is no object $id');
      final EditMesh? mesh = switch (object.geometry) {
        EditedGeometry(:final mesh) => mesh,
        _ => null,
      };
      if (mesh == null) {
        return Outcome.refused('"${object.name}" has no mesh to pack');
      }
      if (!mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0)) {
        return Outcome.refused(
          '"${object.name}" has no UVs to pack — unwrap it first',
        );
      }
      final (Vector2, Vector2)? box = _uvBounds(mesh);
      if (box == null) {
        return Outcome.refused('"${object.name}" has no UVs to pack');
      }
      meshes[id] = mesh;
      boxes[id] = box;
    }

    final PackResult? packed = packIslands(<Vector2>[
      for (final int id in objectIds)
        Vector2(
          math.max(boxes[id]!.$2.x - boxes[id]!.$1.x, 1e-6),
          math.max(boxes[id]!.$2.y - boxes[id]!.$1.y, 1e-6),
        ),
    ], margin: margin);
    if (packed == null) {
      return Outcome.refused('nothing here packs into a square');
    }

    final Vector2 uv = Vector2.zero();
    for (var i = 0; i < objectIds.length; i++) {
      final EditMesh mesh = meshes[objectIds[i]]!;
      final (Vector2 min, Vector2 max) = boxes[objectIds[i]]!;
      final PackedIsland cell = packed.islands[i];
      mesh.beginStep();
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (!mesh.isFaceAlive(face)) continue;
        mesh.forEachHalfEdge(face, (int half) {
          mesh.uvOf(half, uv);
          // Into the cell: the object's own layout, scaled by whatever the
          // packer scaled its box by and moved to where the box landed.
          mesh.setUv(
            half,
            Vector2(
              cell.offset.x + (uv.x - min.x) * packed.scale,
              cell.offset.y + (uv.y - min.y) * packed.scale,
            ),
          );
        });
      }
      mesh.endStep();
    }

    final ModelObject first = project[objectIds.first]!;
    final int material = first.materialSlots.isEmpty
        ? -1
        : first.materialSlots.first;
    if (material < 0 || material >= project.materials.length) {
      return Outcome.refused(
        '"${first.name}" has no material for the atlas to be shared through '
        '— assign one first',
      );
    }

    var next = project;
    for (final int id in objectIds) {
      final ModelObject object = next[id]!;
      next = next.withObject(
        object.copyWith(
          geometry: EditedGeometry(meshes[id]!),
          materialSlots: <int>[
            for (
              var slot = 0;
              slot < math.max(object.materialSlots.length, 1);
              slot++
            )
              material,
          ],
        ),
      );
    }
    return Outcome.done(
      next,
      // Three meshes took a journal step each, and a history that rolled one
      // of them back would leave a document disagreeing with itself.
      meshesTouched: <EditMesh>[for (final int id in objectIds) meshes[id]!],
    );
  }
}

/// The corner UVs of [mesh], as one box — or null when it has none.
(Vector2, Vector2)? _uvBounds(EditMesh mesh) {
  final Vector2 min = Vector2.all(double.infinity);
  final Vector2 max = Vector2.all(double.negativeInfinity);
  final Vector2 uv = Vector2.zero();
  var any = false;
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) {
      mesh.uvOf(half, uv);
      Vector2.min(min, uv, min);
      Vector2.max(max, uv, max);
      any = true;
    });
  }
  return any ? (min, max) : null;
}
