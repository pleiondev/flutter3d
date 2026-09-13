/// A weight-paint brush stroke — `anim-10`'s own row, the brush that calls
/// `flutter3d_mesh`'s already-built one-vertex primitives
/// (`paintWeight`/`assignSelection`/`mirrorWeights`/`normalizeVertexWeights`,
/// `packages/flutter3d_mesh/lib/src/skin/vertex_weights.dart`) per hit, the
/// sampling and BVH picking that file's own doc comment names as this row's
/// job and not theirs.
///
/// **Hit-tested against the mesh's own CURRENT posed shape, not its bind
/// pose.** A bent elbow's skin has already moved away from where the rest
/// pose put it, and a brush aimed at the elbow has to find vertices where
/// they now are. Posed position is computed the same way `anim-15`'s
/// `IkConstraint` and `anim-20`'s `ShapeDriver` already read "the current
/// pose" — straight off [worldTransformOf] and [ModelObject.transform],
/// with no live engine `Pose`/`SkinBlend` involved, because
/// `flutter3d_model_core` cannot depend on the windowed engine package
/// those live in. Blending itself (`jointWorld * inverseBindMatrix *
/// restPosition`, summed by each vertex's own stored weights) is the same
/// arithmetic the engine's own skinned vertex shader runs, just walked once
/// per stroke in Dart instead of once per frame on a GPU.
///
/// **No BVH.** `mesh_bvh.dart`'s own `MeshBvh` answers face queries against
/// whatever positions it was built from, and rebuilding it from posed
/// (rather than bind-pose) positions for every stroke — or re-deriving a
/// vertex set from its face query — is more machinery than this row's own
/// acceptance asks for: nothing here names a vertex-count budget, and a
/// plain scan over the mesh's own (typically low thousands of) vertices is
/// simple and provably correct where feeding posed positions through a
/// structure built for bind-pose faces would not obviously be. A row that
/// actually needs the speed can reach for the BVH later; this one does not.
///
/// **Not a `ModelCommand`.** `command.dart`'s own sealed set requires a
/// matching MCP tool for every name it adds (`flutter3d_model_mcp`'s
/// `tools_test.dart` fails symmetrically otherwise) — wiring a UI or an
/// agent up to call this is a later, app-integration row's own work, the
/// same scope line `anim-15`'s `IkConstraint` and `anim-20`'s `ShapeDriver`
/// already drew for themselves instead of becoming commands. What this row
/// promises instead — "one drag is one step" — is kept the same low-level
/// way `command.dart`'s own `_asMeshStep` keeps it for every mesh command:
/// one [EditMesh.beginStep] before the first sample, one
/// [EditMesh.endStep] after the last.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'project.dart';
import 'project_animation.dart';
import 'world_transform.dart';

/// One brush hit within a drag: where it landed, in the same space
/// [worldTransformOf] answers in, and how far its influence reaches.
final class BrushSample {
  const BrushSample({required this.center, required this.radius});

  final Vector3 center;

  /// Vertices farther than this from [center] (in their own current, posed
  /// position) are untouched by this sample.
  final double radius;
}

/// How a sample changes a vertex's weight at `paintWeights`' own `joint`.
///
/// A `final class` with `static const` instances rather than an `enum` —
/// the same choice `BlendMode`/`DriverAxis` already make in this package,
/// and for the same reason: a fixed, small domain that does not want a
/// fourth case added by accident.
final class PaintWeightsMode {
  const PaintWeightsMode._(this.name);

  final String name;

  /// Accumulates onto whatever a vertex already has, via [paintWeight] —
  /// several overlapping dabs in one stroke add up rather than each
  /// overwriting the last.
  static const PaintWeightsMode paint = PaintWeightsMode._('paint');

  /// Replaces a vertex's whole influence list with this one joint at full
  /// `paintWeights`' own `strength`, via [assignSelection] — a hard "this belongs
  /// to this bone now" rather than a blend. Falloff plays no part here: a
  /// vertex either is or is not this stroke's, and a partial assign would
  /// leave a vertex whose weights sum to less than one, which is the exact
  /// defect [assignSelection] itself exists to avoid.
  static const PaintWeightsMode assign = PaintWeightsMode._('assign');

  @override
  String toString() => 'PaintWeightsMode.$name';
}

/// Mirrors every vertex a stroke touched across a plane once the stroke
/// itself is done — the same parameters [mirrorWeights] already takes,
/// carried here as one value instead of four loose ones.
final class PaintMirror {
  const PaintMirror({
    required this.axis,
    required this.jointMirror,
    this.plane = 0.0,
    this.tolerance = 1e-4,
  });

  /// `0`=x, `1`=y, `2`=z — [mirrorWeights]' own convention.
  final int axis;

  /// [ModelObject.id]s a mirrored vertex's joints are remapped through; an
  /// id absent here keeps its own joint, the same default [mirrorWeights]
  /// gives a spine or a head bone straddling the plane.
  final Map<int, int> jointMirror;

  final double plane;
  final double tolerance;
}

/// [vertex]'s own current, posed position: [mesh]'s bind-pose position for
/// it, skinned through [jointWorldTransforms] (one per entry of
/// [skeleton]'s own [ProjectSkeleton.joints], already resolved once for the
/// whole stroke rather than re-walked per vertex) and [skeleton]'s own
/// [ProjectSkeleton.inverseBindMatrices].
///
/// A vertex nothing has ever skinned reads as fully bound to joint 0 —
/// [weightsOf]'s own default — so it still poses with the rest of the mesh
/// rather than sitting frozen at its bind-pose position.
Vector3 _posedPositionOf(
  EditMesh mesh,
  int vertex,
  ProjectSkeleton skeleton,
  List<Matrix4> jointWorldTransforms,
) {
  final rest = mesh.positionOf(vertex);
  final pairs = weightsOf(mesh, vertex);
  if (pairs.isEmpty) return rest;

  final blended = Vector3.zero();
  for (final pair in pairs) {
    if (pair.joint < 0 || pair.joint >= skeleton.joints.length) continue;
    final skin = Matrix4.copy(jointWorldTransforms[pair.joint])
      ..multiply(skeleton.inverseBindMatrices[pair.joint]);
    blended.addScaled(skin.transformed3(Vector3.copy(rest)), pair.weight);
  }
  return blended;
}

/// Every live vertex's own [_posedPositionOf], resolved once before a stroke
/// starts writing anything.
///
/// **A snapshot, not a live read — deliberately, and not merely for speed.**
/// [paintWeight] changes a vertex's own stored weights, which is exactly
/// what [_posedPositionOf] reads to place that vertex. Recomputing a
/// vertex's position from its own still-being-painted weights partway
/// through a drag lets a stroke pull its own targets out from under itself:
/// a vertex freshly given some share of a joint that has not moved gets
/// dragged partway toward that joint's own position, which can carry it
/// clean out of a later sample's radius in the same drag — a stroke that
/// starts by finding a vertex and ends by having painted past it. Freezing
/// every position before the first write means every sample in one drag
/// judges "who is under the brush" against the same, real, pre-stroke
/// shape.
Map<int, Vector3> _posedPositions(
  EditMesh mesh,
  ProjectSkeleton skeleton,
  List<Matrix4> jointWorldTransforms,
) => <int, Vector3>{
  for (var v = 0; v < mesh.vertexSlotCount; v++)
    if (mesh.isVertexAlive(v))
      v: _posedPositionOf(mesh, v, skeleton, jointWorldTransforms),
};

/// Paints [joint]'s influence over every vertex [samples] touches, hit-tested
/// against each vertex's current posed position — `anim-10`'s own row:
/// `PaintWeights(joint, samples, strength, mode, mirror, normalize)`.
///
/// [joint] is a [ModelObject.id], the same addressing `IkConstraint` and
/// `ShapeDriver` already use — not the local, vertex-attribute-slot index
/// [WeightPair.joint] stores; this looks that index up itself via
/// `skeleton.joints.indexOf(joint)`. Does nothing when [joint] does not
/// belong to [skeleton], or [samples] is empty.
///
/// The whole drag is one journal step on [mesh]: nothing here refuses
/// midway, so there is nothing to roll back, but the batching itself is
/// still real — a hundred overlapping samples in one drag cost one undo
/// entry, not a hundred.
void paintWeights({
  required ModelProject project,
  required EditMesh mesh,
  required ProjectSkeleton skeleton,
  required int joint,
  required List<BrushSample> samples,
  required double strength,
  PaintWeightsMode mode = PaintWeightsMode.paint,
  PaintMirror? mirror,
  bool normalize = false,
}) {
  final localJoint = skeleton.joints.indexOf(joint);
  if (localJoint < 0 || samples.isEmpty) return;

  final jointWorldTransforms = <Matrix4>[
    for (final id in skeleton.joints) worldTransformOf(project, id),
  ];
  final posedPositions = _posedPositions(mesh, skeleton, jointWorldTransforms);

  final touched = <int>{};

  mesh.beginStep();
  for (final sample in samples) {
    if (sample.radius <= 0) continue;
    for (final entry in posedPositions.entries) {
      final v = entry.key;
      final distance = (entry.value - sample.center).length;
      if (distance > sample.radius) continue;

      if (mode == PaintWeightsMode.assign) {
        assignSelection(mesh, <int>[v], localJoint, strength);
      } else {
        final falloff = 1.0 - (distance / sample.radius);
        paintWeight(mesh, v, localJoint, strength * falloff);
      }
      touched.add(v);
    }
  }
  if (mirror != null && touched.isNotEmpty) {
    // Every live vertex, not just [touched]: `mirrorWeights` finds each
    // vertex's own mirror image by searching within whatever list it is
    // given, and a touched vertex's partner is not itself touched by a
    // stroke on only one side of the mesh — passing [touched] alone would
    // leave a stroke on the left hand finding no right hand to copy onto.
    final everyVertex = <int>[
      for (var v = 0; v < mesh.vertexSlotCount; v++)
        if (mesh.isVertexAlive(v)) v,
    ];
    mirrorWeights(
      mesh,
      everyVertex,
      axis: mirror.axis,
      jointMirror: mirror.jointMirror,
      plane: mirror.plane,
      tolerance: mirror.tolerance,
    );
  }
  if (normalize) {
    for (final v in touched) {
      normalizeVertexWeights(mesh, v);
    }
  }
  mesh.endStep();
}
