/// Case 4 — "A character from a bare mesh": what both
/// `tool/make_case4_fixtures.dart` (which writes the fixtures beside this
/// file) and `tutorial_scenarios_test.dart` (which drives it against a live
/// [ModelSession]) need to agree on.
///
/// **Starts from `RobotExpressive.glb`, genuinely unskinned — not stripped,
/// just never carried across.** The file itself has two real glTF skins
/// (confirmed once by hand while writing this file: `GltfLoader().load` on
/// the raw asset reports `document.skins.length == 2`), but
/// [case4StartingProject] brings it in the same way `session.import` (and so
/// any agent over MCP) actually would: through [importInto], and
/// `import_into.dart`'s own doc comment says plainly "skeletons are not
/// carried across yet" — confirmed here too: [case4StartingProject] asserts
/// `project.skeletons.isEmpty` before returning. So this project starts with
/// 79 plain objects (the file's own node count — mesh shells and bare
/// bones alike, all [SocketGeometry] or [ImportedGeometry], none of it
/// skinned) and nothing to strip.
///
/// **The real T4/T5 pipeline, not a stand-in.** [runCase4Scenario] calls
/// exactly the functions `apps/flutter3d_modeler`'s own auto-rig dialog does
/// (`autorig_markers.dart`'s `createRig`, proven headlessly already by that
/// package's own `autorig_frame_test.dart`) — `buildSkeleton`
/// (`anim-33d`'s `RigBuildOptions`), then [bindWeightsJobRequestFor] run
/// directly (`await request.run()` — the "synchronous enough for a headless
/// case" the job's own doc comment describes: no `ModelerCubit`, no job
/// button, just the same `Future` a core-package test would await), then
/// [mirrorSkinWeights], then one [SetRig] — the exact sequence, restated
/// locally rather than imported from the app package, since
/// `flutter3d_model_mcp` cannot depend on `flutter3d_modeler` (apps depend on
/// packages, never the other way). [_boneSegmentsOf] below is that
/// package's own `boneSegmentsOf`, copied rather than shared, for the same
/// reason `tool/make_case3_fixtures.dart`'s own font table gives for its own
/// restated constant: no shared library sits between the two today, and one
/// twelve-line function copied once costs less to read than a package built
/// only to hold it.
///
/// **A weight-paint touch-up, a short clip, a real morph and a real
/// driver — every one of them the actual command, not a simplified
/// stand-in.** Two [PaintWeights] strokes retouch the shoulder seam the
/// distance-and-visibility bind leaves rough; a "chest puff" shape key is
/// captured with [AddShapeFromMesh] the ordinary "sculpt it, then capture
/// it" way (scale a vertex selection out with [TransformElements], capture,
/// then scale the same selection back by the exact inverse — the median
/// [TransformElements] transforms about is the arithmetic mean of the
/// selected vertices, which a symmetric scale about its own mean leaves
/// exactly where it started, so the second call is an exact inverse of the
/// first, not an approximation); [PoseJoint] keys the left elbow's own
/// rotation at rest and mid-bend on one clip, [KeyShape] keys the puff
/// shape's weight alongside it, and [AddShapeDriver] ties the same shape to
/// the same joint's own bend angle — `anim-20`'s "a face that flinches when
/// an elbow locks," on a chest instead of a face, since this mesh has no
/// separate face geometry to sculpt a flinch onto.
///
/// **Bending a joint for a headless case is `select` + [RotateBy] on the
/// joint's own [ModelObject], not `BendSliderBar`.** `ui/bend_slider_bar.dart`
/// is explicit that a live bend drags a [SceneNode] directly and "never
/// touches `ModelHistory`" — there is no `ModelCommand` an agent or a
/// headless case could call to reach the same live-preview effect, only the
/// document-level equivalent: turning the joint's own persisted
/// [ModelObject.transform] the same way case 3 turns the imported box, then
/// [PoseJoint] keying whatever that transform now reads. Both end at the
/// same document state a "Reset pose" click never touches, but an agent
/// reaches it by a different door than a person dragging the slider does —
/// worth a line in the gaps journal (`tut-09`), not a defect this file works
/// around.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart'
    show EditMesh, WeightPair, importMeshData, toVertexAttributes, weightsOf;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:flutter3d_rig/flutter3d_rig.dart'
    show BoneSegment, mirrorSkinWeights;
import 'package:vector_math/vector_math.dart';

/// `RobotExpressive.glb`, merged into an empty project through the free
/// [importInto] function directly — the same reason case 1's own STL import
/// and case 3's own `BoxTextured.glb` merge both bypass `ModelSession`:
/// `ReplaceDocument`, what `session.import` would run for a fresh project,
/// is deliberately not journalable (`command.dart`'s own doc comment), so
/// this case's journal — like theirs — starts after import, not on it.
///
/// **[importInto] over [fromModelDocument] is the point, not an accident.**
/// [fromModelDocument] itself *does* read `document.skins` into
/// `ModelProject.skeletons` (`project_document.dart`'s own `_skeletonsOf`,
/// confirmed once by hand while writing this file: calling it directly on
/// this exact file reads back two skeletons) — [importInto] is the one that
/// does not, per its own doc comment's "skeletons are not carried across
/// yet." Since `session.import`/an agent's own real import path calls
/// [importInto], not [fromModelDocument], calling the same function here is
/// what makes this project unskinned *the same way a real import would
/// leave it*, not a test-only workaround bolted on afterward.
Future<ModelProject> case4StartingProject({
  String glbPath = '../flutter3d_samples/assets/RobotExpressive.glb',
}) async {
  final bytes = File(glbPath).readAsBytesSync();
  final document = await GltfLoader().load(bytes);
  final report = importInto(const ModelProject(), document);
  var project = report.project;

  if (project.objects.length != 79) {
    throw StateError(
      'expected RobotExpressive.glb to import as 79 objects (its own node '
      'count), got ${project.objects.length}',
    );
  }
  if (project.skeletons.isNotEmpty) {
    throw StateError(
      'expected RobotExpressive.glb to import with no skeleton at all — '
      'importInto does not carry glTF skins across (see this file\'s own '
      'library comment) — but this project already has '
      '${project.skeletons.length}',
    );
  }

  for (final object in project.objects) {
    if (object.geometry case ImportedGeometry(:final data)) {
      final (mesh, _, _) = importMeshData(data);
      project = project.withObject(
        object.copyWith(geometry: EditedGeometry(mesh)),
      );
    }
  }

  final body = project[case4BodyId];
  if (body == null ||
      body.name != 'Torso' ||
      body.geometry is! EditedGeometry) {
    throw StateError(
      'expected object $case4BodyId to be the robot\'s own main "Torso" '
      'mesh; got ${body?.name} (${body?.geometry.runtimeType})',
    );
  }
  return project;
}

/// The object id [case4StartingProject] gives the robot's own main body
/// shell — checked once by hand while writing this file (`RobotExpressive
/// .glb`'s own node walk: `fromModelDocument`/[importInto] number objects
/// in the file's own node order, starting at 1) and asserted again on every
/// call to [case4StartingProject] itself, the same "derive once, assert
/// forever" shape [case3BoxId] already uses. It is the larger of two
/// same-named "Torso" objects the file's own multi-primitive node produces
/// (345 vertices against the other's 176) — the outer shell a weight brush
/// and a shape key both actually want, not the inner one.
const int case4BodyId = 9;

/// The world-space AABB of every *body* mesh in [project] — every
/// [EditedGeometry] object except the two stray "Hand.L"/"Hand.R" objects
/// the file itself carries, parented straight to the root rather than to
/// either arm, sitting well outside the character's own silhouette (checked
/// once by hand: with them included, this box is nearly twice as wide as it
/// is tall). Scaling a marker layout to this box, the same "fraction of the
/// bounding box" scheme `rig_pipeline_mcp_test.dart`'s own `anim-30`
/// scenario already uses for this exact file, is what lets one marker set
/// work without hand-tuning it to this one export's own units.
Aabb3 _bodyBounds(ModelProject project) {
  var min = Vector3(double.infinity, double.infinity, double.infinity);
  var max = Vector3(
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  for (final object in project.objects) {
    if (object.name.startsWith('Hand.')) continue;
    if (object.geometry case EditedGeometry(:final mesh)) {
      final world = worldTransformOf(project, object.id);
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        final p = world.transformed3(mesh.positionOf(v));
        min = Vector3(
          p.x < min.x ? p.x : min.x,
          p.y < min.y ? p.y : min.y,
          p.z < min.z ? p.z : min.z,
        );
        max = Vector3(
          p.x > max.x ? p.x : max.x,
          p.y > max.y ? p.y : max.y,
          p.z > max.z ? p.z : max.z,
        );
      }
    }
  }
  return Aabb3.minMax(min, max);
}

/// [RigTemplate.humanoid]'s own eleven [requiredMarkers], laid out as a
/// fraction of [bounds] — the identical layout
/// `rig_pipeline_mcp_test.dart`'s own `anim-30` scenario already uses for
/// this same file, restated here rather than shared across two test-only
/// fixtures in the same package for the reason this file's own library
/// comment gives for [_boneSegmentsOf].
Map<String, Vector3> _humanoidMarkers(Aabb3 bounds) {
  final size = bounds.max - bounds.min;
  final cx = (bounds.min.x + bounds.max.x) / 2;
  final cz = (bounds.min.z + bounds.max.z) / 2;
  final baseY = bounds.min.y;
  final halfWidth = size.x / 2;

  Vector3 at(double xFrac, double yFrac, {double zFrac = 0}) => Vector3(
    cx + xFrac * halfWidth,
    baseY + yFrac * size.y,
    cz + zFrac * (size.z / 2),
  );

  return <String, Vector3>{
    'hips': at(0, 0.5),
    'spine': at(0, 0.6),
    'chest': at(0, 0.7),
    'neck': at(0, 0.85),
    'head': at(0, 0.95),
    'leftShoulder': at(0.3, 0.7),
    'leftElbow': at(0.5, 0.55),
    'leftWrist': at(0.6, 0.4),
    'leftHip': at(0.15, 0.48),
    'leftKnee': at(0.15, 0.25),
    'leftAnkle': at(0.15, 0.02),
  };
}

/// [built]'s own joints as [BoneSegment]s — `apps/flutter3d_modeler`'s own
/// `autorig_markers.dart` names this exact function `boneSegmentsOf`; see
/// this file's own library comment for why it is copied here rather than
/// imported. Head at each joint's own parent (the controller, another
/// joint, or itself for the root) and tail at the joint itself: every
/// [ModelObject.transform] [buildSkeleton] writes is a plain translation, so
/// a joint's world position is nothing but its own translation plus its
/// parent's, walked all the way up.
List<BoneSegment> _boneSegmentsOf(BuiltRig built) {
  final byId = <int, ModelObject>{
    for (final object in built.objects) object.id: object,
  };
  Vector3 worldOf(int id) {
    final object = byId[id]!;
    final local = object.transform.getTranslation();
    final parent = object.parent;
    return parent == null ? local : worldOf(parent) + local;
  }

  return <BoneSegment>[
    for (final id in built.skeleton.joints)
      BoneSegment(
        byId[id]!.parent == null ? worldOf(id) : worldOf(byId[id]!.parent!),
        worldOf(id),
        name: byId[id]!.name,
      ),
  ];
}

/// Every step case 4's own page (`cloud/server/content/learn/modeler/
/// 04-character-from-a-bare-mesh.md`) walks through, run against
/// [session] once it holds [case4StartingProject]'s result.
///
/// **Async, unlike cases 1–3's own scenario functions.** Every other case
/// only ever calls synchronous [ModelSession.run]/`select`; this one awaits
/// a real [BindWeightsJobRequest.run] partway through, the same `Future` a
/// live app would hand to `ModelerCubit.runJob` instead — see this file's
/// own library comment.
Future<void> runCase4Scenario(ModelSession session) async {
  void must(Answer answer, String step) {
    if (!answer.did) throw StateError('$step refused: ${answer.says}');
  }

  final bounds = _bodyBounds(session.project);
  final markers = _humanoidMarkers(bounds);

  // 1. Auto-rig: buildSkeleton -> bindWeightsJobRequestFor -> the real bind,
  // run directly -> mirrorSkinWeights -> one SetRig. The exact pipeline
  // `createRig` (`apps/flutter3d_modeler/lib/src/autorig_markers.dart`)
  // wraps for the app's own auto-rig dialog, restated here at the command
  // layer directly rather than through that app package.
  Vector3 min = Vector3(double.infinity, double.infinity, double.infinity);
  Vector3 max = Vector3(
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  for (final v in markers.values) {
    min = Vector3(
      v.x < min.x ? v.x : min.x,
      v.y < min.y ? v.y : min.y,
      v.z < min.z ? v.z : min.z,
    );
    max = Vector3(
      v.x > max.x ? v.x : max.x,
      v.y > max.y ? v.y : max.y,
      v.z > max.z ? v.z : max.z,
    );
  }
  final rigBounds = Aabb3.minMax(
    min - Vector3.all(1.0),
    max + Vector3.all(1.0),
  );

  final built = buildSkeleton(
    RigTemplate.humanoid,
    markers,
    bounds: rigBounds,
    firstObjectId: session.project.nextId,
    skeletonName: 'auto',
  );

  final segments = _boneSegmentsOf(built);
  final bindRequest = bindWeightsJobRequestFor(
    project: session.project,
    objectId: case4BodyId,
    bones: segments,
  );
  if (bindRequest == null) {
    throw StateError('object $case4BodyId has no mesh to bind weights to');
  }
  final bound = await bindRequest.run();

  final boundMesh = EditMesh.fromBytes(bound.meshBytes);
  final positions = <Vector3>[
    for (var v = 0; v < boundMesh.vertexSlotCount; v++)
      boundMesh.isVertexAlive(v) ? boundMesh.positionOf(v) : Vector3.zero(),
  ];
  Map<int, List<WeightPair>> weights = <int, List<WeightPair>>{
    for (var v = 0; v < boundMesh.vertexSlotCount; v++)
      v: weightsOf(boundMesh, v),
  };
  weights = mirrorSkinWeights(weights, positions, segments);

  final data = Float32List(boundMesh.vertexSlotCount * 8);
  for (var v = 0; v < boundMesh.vertexSlotCount; v++) {
    final attrs = toVertexAttributes(weights[v] ?? const <WeightPair>[]);
    final base = v * 8;
    data[base] = attrs.joints.x;
    data[base + 1] = attrs.joints.y;
    data[base + 2] = attrs.joints.z;
    data[base + 3] = attrs.joints.w;
    data[base + 4] = attrs.weights.x;
    data[base + 5] = attrs.weights.y;
    data[base + 6] = attrs.weights.z;
    data[base + 7] = attrs.weights.w;
  }

  must(
    session.run(
      SetRig(
        jointObjects: built.objects,
        skeleton: built.skeleton,
        skinObjectId: case4BodyId,
        weights: SkinWeightsBlob(baseVersion: bound.baseVersion, data: data),
        label: 'auto-rig humanoid (${built.skeleton.jointCount} joints)',
      ),
    ),
    'setRig',
  );

  final skeleton = session.project.skeletons.single;
  int jointNamed(String name) =>
      skeleton.joints.firstWhere((id) => session.project[id]!.name == name);
  final leftShoulderId = jointNamed('leftShoulder');
  final leftElbowId = jointNamed('leftElbow');

  // 2. A weight-paint touch-up: two strokes retouching the shoulder seam
  // the distance-and-visibility bind leaves rough — a real brush, not the
  // deepest possible paint session.
  must(
    session.run(
      PaintWeights(
        objectId: case4BodyId,
        skeletonIndex: 0,
        joint: leftShoulderId,
        samples: <BrushSample>[
          BrushSample(center: markers['leftShoulder']!, radius: 0.35),
          BrushSample(
            center: markers['leftShoulder']! + Vector3(0.05, -0.05, 0),
            radius: 0.35,
          ),
        ],
        strength: 0.6,
      ),
    ),
    'paintWeights(leftShoulder)',
  );
  must(
    session.run(
      PaintWeights(
        objectId: case4BodyId,
        skeletonIndex: 0,
        joint: leftElbowId,
        samples: <BrushSample>[
          BrushSample(center: markers['leftElbow']!, radius: 0.3),
        ],
        strength: 0.5,
      ),
    ),
    'paintWeights(leftElbow)',
  );

  // 3. A "chest puff" shape key: scale a vertex selection out from its own
  // mean, capture it, then scale the identical selection back by the exact
  // inverse — this file's own library comment explains why the second call
  // is an exact inverse of the first rather than an approximation.
  final bodyMesh =
      (session.project[case4BodyId]!.geometry as EditedGeometry).mesh;
  var localMin = Vector3(double.infinity, double.infinity, double.infinity);
  var localMax = Vector3(
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  for (var v = 0; v < bodyMesh.vertexSlotCount; v++) {
    if (!bodyMesh.isVertexAlive(v)) continue;
    final p = bodyMesh.positionOf(v);
    localMin = Vector3(
      p.x < localMin.x ? p.x : localMin.x,
      p.y < localMin.y ? p.y : localMin.y,
      p.z < localMin.z ? p.z : localMin.z,
    );
    localMax = Vector3(
      p.x > localMax.x ? p.x : localMax.x,
      p.y > localMax.y ? p.y : localMax.y,
      p.z > localMax.z ? p.z : localMax.z,
    );
  }
  final upperThreshold = localMin.y + 0.6 * (localMax.y - localMin.y);
  final upperVertices = <int>[
    for (var v = 0; v < bodyMesh.vertexSlotCount; v++)
      if (bodyMesh.isVertexAlive(v) &&
          bodyMesh.positionOf(v).y > upperThreshold)
        v,
  ];
  if (upperVertices.isEmpty) {
    throw StateError('no vertices above the chest threshold to sculpt');
  }

  must(
    session.select(
      object: case4BodyId,
      level: 'vertex',
      elements: upperVertices,
    ),
    'select the upper chest shell',
  );
  const puffScale = 1.12;
  must(
    session.run(
      TransformElements(
        Matrix4.diagonal3Values(puffScale, puffScale, puffScale),
        what: 'scale',
      ),
    ),
    'puff the chest out',
  );
  must(
    session.run(
      const AddShapeFromMesh(id: case4BodyId, shapeName: 'chestPuff'),
    ),
    'addShapeFromMesh(chestPuff)',
  );
  must(
    session.run(
      TransformElements(
        Matrix4.diagonal3Values(1 / puffScale, 1 / puffScale, 1 / puffScale),
        what: 'scale',
      ),
    ),
    'settle the chest back to its base shape',
  );

  // 4. One short clip: the elbow's own rotation, keyed at rest and
  // mid-bend, and the chest-puff shape's weight keyed alongside it.
  must(session.run(const AddClip(clipName: 'wave')), 'addClip');
  const clipIndex = 0;

  must(
    session.run(
      PoseJoint(
        joint: leftElbowId,
        path: AnimationPath.rotation,
        clipIndex: clipIndex,
        frame: 0,
      ),
    ),
    'poseJoint(rest)',
  );

  must(
    session.run(
      const KeyShape(id: case4BodyId, clipIndex: clipIndex, time: 0.0),
    ),
    'keyShape(rest)',
  );

  must(session.select(objects: <int>[leftElbowId]), 'select the left elbow');
  must(
    session.run(
      RotateBy(
        axis: Vector3(0, 0, 1),
        radians: radians(60),
        pivot: TransformPivot.individual,
        space: TransformSpace.local,
      ),
    ),
    'bend the left elbow',
  );
  must(
    session.run(
      PoseJoint(
        joint: leftElbowId,
        path: AnimationPath.rotation,
        clipIndex: clipIndex,
        frame: 12,
      ),
    ),
    'poseJoint(bent)',
  );

  must(
    session.run(
      const SetShapeWeight(id: case4BodyId, shapeIndex: 0, weight: 1.0),
    ),
    'setShapeWeight(chestPuff, 1.0)',
  );
  must(
    session.run(
      const KeyShape(id: case4BodyId, clipIndex: clipIndex, time: 0.4),
    ),
    'keyShape(bent)',
  );

  // 5. A real shape driver: the same "flinch when a joint locks" shape
  // `anim-20`'s own row describes, tying the chest puff to the elbow's own
  // bend angle — `anim-34d`'s document-side descriptor, not baked here.
  must(
    session.run(
      AddShapeDriver(
        id: case4BodyId,
        driver: ShapeDriver(
          shapeIndex: 0,
          jointId: leftElbowId,
          axis: DriverAxis.z,
          from: 0.0,
          to: radians(60),
        ),
      ),
    ),
    'addShapeDriver',
  );
}
