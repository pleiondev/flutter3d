/// Screen 16's own eight on-screen markers, and what they turn into once
/// `flutter3d_model_core`'s `buildSkeleton` gets a hold of them — `anim-23`'s
/// app half, leaning on `anim-33d`'s `RigBuildOptions`/`previewRig` and
/// `doc-36d`'s `SetRig`.
///
/// **Eight handles, eleven required keys — [deriveMarkers] is the bridge.**
/// `requiredMarkers(RigTemplate.humanoid)` still names eleven positions
/// (`rig_template.dart`), but a person only ever places eight: `spine` sits
/// halfway between `hips` and `chest`, and each arm/leg's own middle joint
/// (`leftElbow`/`leftKnee`) sits halfway between the two markers either side
/// of it — the exact shape `_BoneSpec.derive` already uses inside
/// `buildSkeleton` for a phalanx or an extra spine segment, reused here
/// rather than invented a second time, per this row's own instruction not
/// to. The quadruped template has no such middle joint on either leg (no
/// elbow, no knee bone at all — see `_quadrupedBones`'s own class comment),
/// so all eleven of its own required keys are on-screen there instead of
/// eight.
///
/// **[createRig] is the whole "Create" button, land as one journal step.**
/// `buildSkeleton` first (synchronous, cheap enough to also back
/// `previewRig`'s own live card); [bindWeightsJobRequestFor] next, run
/// through whatever background-job runner the caller hands in as [bind] —
/// `ModelerCubit.runJob` in the real dialog, a plain `await request.run()`
/// in a test that has no cubit to spare; [mirrorSkinWeights] over the raw
/// result when asked; and finally one [SetRig], so undo takes back the
/// joints, the skeleton and the weights together or not at all — `anim-23`'s
/// own "SetSkeleton + SetWeights as a transaction".
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter3d_core/geometry.dart' show Ray;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

import 'element_picking.dart';

/// The on-screen marker keys for [template] — a person places these by hand;
/// [deriveMarkers] fills in whatever else `requiredMarkers(template)` names.
///
/// Order matters only for display: this is the order screen 16's own marker
/// list (and [markerConnections]' own pairs) reads them in.
List<String> onScreenMarkerKeys(RigTemplate template) {
  if (template == RigTemplate.humanoid) {
    return const <String>[
      'hips',
      'chest',
      'neck',
      'head',
      'leftShoulder',
      'leftWrist',
      'leftHip',
      'leftAnkle',
    ];
  }
  // The quadruped template has no elbow/knee bone to derive a middle marker
  // for (see this file's own library comment) — every required key is a
  // handle on screen.
  return requiredMarkers(template);
}

/// A short label for [key], for the marker list a right-hand panel might
/// draw — every key [onScreenMarkerKeys] ever names, across both templates.
const Map<String, String> markerLabels = <String, String>{
  'hips': 'Hips',
  'chest': 'Chest',
  'neck': 'Neck',
  'head': 'Head',
  'leftShoulder': 'L. shoulder',
  'leftWrist': 'L. wrist',
  'leftHip': 'L. hip',
  'leftAnkle': 'L. ankle',
  'pelvis': 'Pelvis',
  'spine1': 'Spine',
  'tailBase': 'Tail base',
  'tailTip': 'Tail tip',
  'leftFrontShoulder': 'L. front shoulder',
  'leftFrontPaw': 'L. front paw',
  'leftBackHip': 'L. back hip',
  'leftBackPaw': 'L. back paw',
};

/// Dotted connective-line pairs screen 16 draws between markers — always
/// between two keys [onScreenMarkerKeys] itself names, so the lines draw
/// straight from whatever a person actually dragged rather than through a
/// derived point they never touched.
List<(String, String)> markerConnections(RigTemplate template) {
  if (template == RigTemplate.humanoid) {
    return const <(String, String)>[
      ('hips', 'chest'),
      ('chest', 'neck'),
      ('neck', 'head'),
      ('chest', 'leftShoulder'),
      ('leftShoulder', 'leftWrist'),
      ('hips', 'leftHip'),
      ('leftHip', 'leftAnkle'),
    ];
  }
  return const <(String, String)>[
    ('pelvis', 'spine1'),
    ('spine1', 'chest'),
    ('chest', 'neck'),
    ('neck', 'head'),
    ('pelvis', 'tailBase'),
    ('tailBase', 'tailTip'),
    ('chest', 'leftFrontShoulder'),
    ('leftFrontShoulder', 'leftFrontPaw'),
    ('pelvis', 'leftBackHip'),
    ('leftBackHip', 'leftBackPaw'),
  ];
}

/// A plausible marker layout over [bounds] — the same "fraction of the
/// bounding box" scheme `rig_pipeline_mcp_test.dart`'s own `anim-30`
/// scenario already scales a RobotExpressive-sized model with, so the two
/// land on the same numbers where both name a marker (`leftKnee` at `(0.15,
/// 0.25)`, `spine` at `(0, 0.6)` once [deriveMarkers] takes its own
/// midpoint). A first guess a person then drags into place, not a claim
/// about the mesh underneath it.
///
/// Every marker starts at [bounds]' own centre depth (`z`) — the one
/// coordinate this dialog's frontal view cannot show a person at all, so
/// there is nothing truer to place it at than the model's own middle, and
/// [markerFromScreen] leaves it there for exactly the same reason.
Map<String, Vector3> startingMarkers(RigTemplate template, Aabb3 bounds) {
  final Vector3 size = bounds.max - bounds.min;
  final double cx = (bounds.min.x + bounds.max.x) / 2;
  final double cz = (bounds.min.z + bounds.max.z) / 2;
  final double baseY = bounds.min.y;
  final double halfWidth = size.x / 2;

  Vector3 at(double xFrac, double yFrac) =>
      Vector3(cx + xFrac * halfWidth, baseY + yFrac * size.y, cz);

  if (template == RigTemplate.humanoid) {
    return <String, Vector3>{
      'hips': at(0, 0.5),
      'chest': at(0, 0.7),
      'neck': at(0, 0.85),
      'head': at(0, 0.95),
      'leftShoulder': at(0.3, 0.7),
      'leftWrist': at(0.6, 0.4),
      'leftHip': at(0.15, 0.48),
      'leftAnkle': at(0.15, 0.02),
    };
  }

  // Quadruped: spread front-to-back along Z (the animal's own spine) rather
  // than up a torso, legs hanging from the flanks.
  final double halfLength = size.z / 2;
  Vector3 along(double zFrac, double yFrac, {double xFrac = 0}) => Vector3(
    cx + xFrac * halfWidth,
    baseY + yFrac * size.y,
    cz + zFrac * halfLength,
  );
  return <String, Vector3>{
    'pelvis': along(-0.35, 0.5),
    'spine1': along(0.0, 0.55),
    'chest': along(0.35, 0.55),
    'neck': along(0.6, 0.6),
    'head': along(0.85, 0.65),
    'tailBase': along(-0.6, 0.55),
    'tailTip': along(-0.9, 0.5),
    'leftFrontShoulder': along(0.35, 0.55, xFrac: 0.3),
    'leftFrontPaw': along(0.35, 0.02, xFrac: 0.3),
    'leftBackHip': along(-0.35, 0.5, xFrac: 0.3),
    'leftBackPaw': along(-0.35, 0.02, xFrac: 0.3),
  };
}

Vector3 _mid(Vector3 a, Vector3 b) => (a + b) * 0.5;

/// Every `requiredMarkers(template)` key, from [onScreen] (which must carry
/// every key [onScreenMarkerKeys] names) plus whatever [template] lets this
/// derive as the midpoint of two already-placed markers — see this file's
/// own library comment for why that is the same shape `buildSkeleton`'s own
/// `_BoneSpec.derive` already uses.
Map<String, Vector3> deriveMarkers(
  RigTemplate template,
  Map<String, Vector3> onScreen,
) {
  final Map<String, Vector3> markers = Map<String, Vector3>.of(onScreen);
  if (template == RigTemplate.humanoid) {
    markers['spine'] = _mid(markers['hips']!, markers['chest']!);
    markers['leftElbow'] = _mid(
      markers['leftShoulder']!,
      markers['leftWrist']!,
    );
    markers['leftKnee'] = _mid(markers['leftHip']!, markers['leftAnkle']!);
  }
  return markers;
}

/// Where a click at [at] lands in world space, for this dialog's own frontal
/// orthographic view.
///
/// [view.rayThrough] already answers a marker's `(x, y)` in full — that is
/// what makes the lens orthographic — and cannot answer its depth, since
/// every point along the ray shares the same `(x, y)`. [depthZ] supplies
/// that missing coordinate directly: [startingMarkers]' own choice, the
/// model's own centre depth, carried across a drag rather than reset to
/// some new guess every time a person moves a marker.
Vector3 markerFromScreen(PickingView view, Offset at, double depthZ) {
  final Ray ray = view.rayThrough(at);
  final double dz = ray.direction.z;
  final double t = dz.abs() < 1e-9 ? 0.0 : (depthZ - ray.origin.z) / dz;
  return ray.origin + ray.direction * t;
}

/// [built]'s own joints as [BoneSegment]s, head at each joint's own parent
/// (the controller, another joint, or itself for the root) and tail at the
/// joint itself — [bindWeightsJobRequestFor]'s own `bones` argument, built
/// from nothing but what [buildSkeleton] already handed back.
///
/// Every [ModelObject.transform] [buildSkeleton] writes is a plain
/// translation (see `rig_template.dart`'s own class comment), so a joint's
/// world position is nothing but its own translation plus its parent's,
/// walked all the way up — no rotation to compose.
List<BoneSegment> boneSegmentsOf(BuiltRig built) {
  final Map<int, ModelObject> byId = <int, ModelObject>{
    for (final ModelObject object in built.objects) object.id: object,
  };
  Vector3 worldOf(int id) {
    final ModelObject object = byId[id]!;
    final Vector3 local = object.transform.getTranslation();
    final int? parent = object.parent;
    return parent == null ? local : worldOf(parent) + local;
  }

  return <BoneSegment>[
    for (final int id in built.skeleton.joints)
      BoneSegment(
        byId[id]!.parent == null ? worldOf(id) : worldOf(byId[id]!.parent!),
        worldOf(id),
        name: byId[id]!.name,
      ),
  ];
}

int _mirrorAxisIndex(RigMirrorAxis axis) {
  if (axis == RigMirrorAxis.x) return 0;
  if (axis == RigMirrorAxis.y) return 1;
  return 2;
}

/// Builds [template] from [markers] (every `requiredMarkers(template)` key —
/// [deriveMarkers]'s own answer) and lands it on [history] as one journal
/// step, through [SetRig] — see this file's own library comment for the
/// whole pipeline.
///
/// [bind] runs a [BindWeightsJobRequest] and answers its [JobResult], or
/// null when the job was cancelled before it finished — the real dialog
/// hands in `ModelerCubit.runJob`'s own answer, unwrapped; a test with no
/// cubit to spare hands in `(request) => request.run()` directly.
///
/// Answers a refusal message the way [ModelHistory.run] itself does — null
/// once the rig actually landed.
Future<String?> createRig({
  required ModelHistory history,
  required RigTemplate template,
  required Map<String, Vector3> markers,
  RigBuildOptions options = const RigBuildOptions(),
  int? skinObjectId,
  bool bindPrimaryWeights = true,
  bool mirrorWeights = true,
  String? skeletonName,
  required Future<JobResult?> Function(BindWeightsJobRequest request) bind,
}) async {
  final ModelProject project = history.project;
  final List<String> required = requiredMarkers(template);
  final List<String> missing = <String>[
    for (final String key in required)
      if (!markers.containsKey(key)) key,
  ];
  if (missing.isNotEmpty) {
    return 'auto-rig is missing markers: ${missing.join(', ')}';
  }
  if (skinObjectId != null && project[skinObjectId] == null) {
    return 'there is no object $skinObjectId to skin';
  }

  Vector3 min = Vector3(double.infinity, double.infinity, double.infinity);
  Vector3 max = Vector3(
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  for (final String key in required) {
    final Vector3 v = markers[key]!;
    min = Vector3(
      math.min(min.x, v.x),
      math.min(min.y, v.y),
      math.min(min.z, v.z),
    );
    max = Vector3(
      math.max(max.x, v.x),
      math.max(max.y, v.y),
      math.max(max.z, v.z),
    );
  }
  final Aabb3 bounds = Aabb3.minMax(
    min - Vector3.all(1.0),
    max + Vector3.all(1.0),
  );

  final BuiltRig built;
  try {
    built = buildSkeleton(
      template,
      markers,
      bounds: bounds,
      options: options,
      firstObjectId: project.nextId,
      skeletonName: skeletonName,
      // `tut-21`: markers are world-space picks, so the object actually
      // being skinned has to fold its own world transform back into the
      // inverse bind matrices — see `buildSkeleton`'s own `meshWorld` doc.
      meshWorld: skinObjectId == null
          ? null
          : worldTransformOf(project, skinObjectId),
    );
  } on ArgumentError catch (error) {
    return 'auto-rig refused: ${error.message}';
  }

  final String label =
      'auto-rig ${template.name} (${built.skeleton.jointCount} joints)';

  if (skinObjectId == null || !bindPrimaryWeights) {
    return history.run(
      SetRig(
        jointObjects: built.objects,
        skeleton: built.skeleton,
        skinObjectId: skinObjectId,
        label: label,
      ),
    );
  }

  final List<BoneSegment> segments = boneSegmentsOf(built);
  final BindWeightsJobRequest? request = bindWeightsJobRequestFor(
    project: project,
    objectId: skinObjectId,
    bones: segments,
  );
  if (request == null) {
    final String name = project[skinObjectId]?.name ?? '$skinObjectId';
    return '"$name" has no mesh to bind weights to';
  }

  final JobResult? result = await bind(request);
  if (result == null) return 'binding weights was cancelled';

  final EditMesh mesh = EditMesh.fromBytes(result.meshBytes);
  final List<Vector3> positions = <Vector3>[
    for (var v = 0; v < mesh.vertexSlotCount; v++)
      mesh.isVertexAlive(v) ? mesh.positionOf(v) : Vector3.zero(),
  ];
  Map<int, List<WeightPair>> weights = <int, List<WeightPair>>{
    for (var v = 0; v < mesh.vertexSlotCount; v++) v: weightsOf(mesh, v),
  };
  if (mirrorWeights) {
    weights = mirrorSkinWeights(
      weights,
      positions,
      segments,
      axis: _mirrorAxisIndex(options.mirrorAxis),
    );
  }

  final Float32List data = Float32List(mesh.vertexSlotCount * 8);
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    final VertexAttributes attrs = toVertexAttributes(
      weights[v] ?? const <WeightPair>[],
    );
    final int base = v * 8;
    data[base] = attrs.joints.x;
    data[base + 1] = attrs.joints.y;
    data[base + 2] = attrs.joints.z;
    data[base + 3] = attrs.joints.w;
    data[base + 4] = attrs.weights.x;
    data[base + 5] = attrs.weights.y;
    data[base + 6] = attrs.weights.z;
    data[base + 7] = attrs.weights.w;
  }

  return history.run(
    SetRig(
      jointObjects: built.objects,
      skeleton: built.skeleton,
      skinObjectId: skinObjectId,
      weights: SkinWeightsBlob(baseVersion: result.baseVersion, data: data),
      label: label,
    ),
  );
}
