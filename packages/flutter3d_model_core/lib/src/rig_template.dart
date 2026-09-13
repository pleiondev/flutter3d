/// A skeleton built from a template and a handful of marker positions,
/// rather than one joint at a time through [AddJoint] — `anim-21`'s own
/// row.
///
/// **The plan names no bone table, so this file is the table.** The row's
/// own acceptance ("bone count matches a table") presumes one exists
/// somewhere; none of `doc/model-editor-plan.md`'s own text supplies it, so
/// [_humanoidBones] and [_quadrupedBones] below are this row's own
/// documented choice — a standard-depth humanoid chain (spine through
/// wrists and ankles, no fingers or toes) and a quadruped equivalent (spine,
/// tail, four legs), both comfortably under the row's own 64-bone cap.
///
/// **Symmetry is guaranteed by construction, not checked after the fact.**
/// [buildSkeleton] only ever reads a *left*-side (or centerline) marker
/// position from [markers]; every right-side joint's own position is the
/// mirror of its left counterpart, reflected across [RigBuildOptions
/// .mirrorAxis], and every centerline joint is snapped exactly onto that
/// same plane. A caller cannot hand this function an asymmetric rig by
/// accident — the row's own "с симметрией" is an invariant of the
/// algorithm, not a property that happens to hold when the input already
/// was symmetric.
///
/// **Every bone is a translation, so `inverseBind·worldRest = I` holds by
/// construction too.** A joint's own rest transform is nothing but "where
/// its marker sits, relative to its parent" — no rotation — so its world
/// rest transform is `Matrix4.translation(worldPosition)` and its inverse
/// bind matrix is that same matrix's own [Matrix4.inverted]. Composing the
/// two is `T⁻¹·T`, the identity, for every joint, for the same reason two
/// numbers multiplied by each other's reciprocal are always one — the test
/// suite checks this against the actual returned objects rather than
/// trusting the algebra on paper, the same discipline `MirrorJoints`' own
/// test suite already holds itself to.
library;

import 'package:vector_math/vector_math.dart';

import 'project.dart';
import 'project_animation.dart';

/// A stock rig shape [buildSkeleton] knows how to lay out.
///
/// **A value class rather than an enum, for the reason `LightingModel`'s own
/// class comment gives: this list is not closed.** A published package's own
/// enum breaks every switch written against it the day a third template
/// (a biped digitigrade, a bird) is added; a value class only grows.
final class RigTemplate {
  const RigTemplate._(this.name);

  final String name;

  static const RigTemplate humanoid = RigTemplate._('humanoid');
  static const RigTemplate quadruped = RigTemplate._('quadruped');

  /// The templates [buildSkeleton] knows today.
  static const List<RigTemplate> values = <RigTemplate>[humanoid, quadruped];

  @override
  String toString() => 'RigTemplate.$name';
}

/// Which axis is the left/right mirror plane. [x] (the default) matches
/// this engine's own left/right convention elsewhere — see `MirrorJoints`'
/// own `axis` parameter in `joint_commands.dart`, which this row's own
/// reflection math mirrors. A value class rather than an enum for the same
/// reason [RigTemplate] is one.
final class RigMirrorAxis {
  const RigMirrorAxis._(this.name);

  final String name;

  static const RigMirrorAxis x = RigMirrorAxis._('x');
  static const RigMirrorAxis y = RigMirrorAxis._('y');
  static const RigMirrorAxis z = RigMirrorAxis._('z');

  static const List<RigMirrorAxis> values = <RigMirrorAxis>[x, y, z];

  @override
  String toString() => 'RigMirrorAxis.$name';
}

/// Knobs [buildSkeleton] reads beyond the template and the markers
/// themselves.
class RigBuildOptions {
  const RigBuildOptions({this.mirrorAxis = RigMirrorAxis.x});

  final RigMirrorAxis mirrorAxis;
}

/// What [buildSkeleton] hands back: the joints as freshly-made socket
/// objects, ready to append to a project, and the [ProjectSkeleton] that
/// addresses them.
///
/// **Two things rather than one**, because [ProjectSkeleton] only ever
/// addresses joints by [ModelObject.id] — see its own class comment — and an
/// id means nothing until the object it names actually exists in a project.
/// A caller adds [objects] first (in order; each one's own [ModelObject
/// .parent] already names an earlier one in this same list) and then the
/// project holds [skeleton]'s own claims about them.
class BuiltRig {
  const BuiltRig({required this.objects, required this.skeleton});

  final List<ModelObject> objects;
  final ProjectSkeleton skeleton;
}

/// One row of a rig's own bone table: a joint's name, its parent's name (or
/// none, for the root), and where its rest position comes from.
///
/// Exactly one of [markerKey] and [mirrorOfMarkerKey] is set. [markerKey]
/// reads a position straight out of [buildSkeleton]'s own `markers` — the
/// ordinary case for a centerline joint or the *left* half of a mirrored
/// pair. [mirrorOfMarkerKey] instead reflects the position *another* row
/// (its left counterpart) already read, across the build's own mirror
/// plane — the only way a right-side joint's position is ever produced,
/// which is what makes symmetry unconditional rather than incidental.
class _BoneSpec {
  const _BoneSpec(
    this.name,
    this.parent, {
    this.markerKey,
    this.mirrorOfMarkerKey,
    this.centerline = false,
  }) : assert(
         (markerKey == null) != (mirrorOfMarkerKey == null),
         'exactly one of markerKey/mirrorOfMarkerKey',
       );

  final String name;
  final String? parent;
  final String? markerKey;
  final String? mirrorOfMarkerKey;

  /// True for a joint that sits ON the mirror plane rather than to one
  /// side of it (a spine, not a shoulder) — its own marker is snapped
  /// exactly onto the plane rather than trusted as-given, since a
  /// centerline joint even fractionally off the plane is what would make
  /// [buildSkeleton]'s own symmetry guarantee false for everything hung
  /// under it.
  final bool centerline;
}

/// **Humanoid, 17 joints**: hips/spine/chest/neck/head on the centerline
/// (5), shoulder/elbow/wrist mirrored (6), hip/knee/ankle mirrored (6). No
/// fingers, toes or a jaw — a deeper rig than this is a different template
/// or a future `RigBuildOptions` knob, not this row's own base case.
List<_BoneSpec> _humanoidBones() => const <_BoneSpec>[
  _BoneSpec('hips', null, markerKey: 'hips', centerline: true),
  _BoneSpec('spine', 'hips', markerKey: 'spine', centerline: true),
  _BoneSpec('chest', 'spine', markerKey: 'chest', centerline: true),
  _BoneSpec('neck', 'chest', markerKey: 'neck', centerline: true),
  _BoneSpec('head', 'neck', markerKey: 'head', centerline: true),
  _BoneSpec('leftShoulder', 'chest', markerKey: 'leftShoulder'),
  _BoneSpec('rightShoulder', 'chest', mirrorOfMarkerKey: 'leftShoulder'),
  _BoneSpec('leftElbow', 'leftShoulder', markerKey: 'leftElbow'),
  _BoneSpec('rightElbow', 'rightShoulder', mirrorOfMarkerKey: 'leftElbow'),
  _BoneSpec('leftWrist', 'leftElbow', markerKey: 'leftWrist'),
  _BoneSpec('rightWrist', 'rightElbow', mirrorOfMarkerKey: 'leftWrist'),
  _BoneSpec('leftHip', 'hips', markerKey: 'leftHip'),
  _BoneSpec('rightHip', 'hips', mirrorOfMarkerKey: 'leftHip'),
  _BoneSpec('leftKnee', 'leftHip', markerKey: 'leftKnee'),
  _BoneSpec('rightKnee', 'rightHip', mirrorOfMarkerKey: 'leftKnee'),
  _BoneSpec('leftAnkle', 'leftKnee', markerKey: 'leftAnkle'),
  _BoneSpec('rightAnkle', 'rightKnee', mirrorOfMarkerKey: 'leftAnkle'),
];

/// **Quadruped, 15 joints**: pelvis/spine1/chest/neck/head/tailBase/tailTip
/// on the centerline (7), front shoulder/paw mirrored (4), back hip/paw
/// mirrored (4). One spine segment and no separate elbow/knee joint on
/// either pair of legs — the same "base case, not the deepest rig
/// possible" choice the humanoid table makes.
List<_BoneSpec> _quadrupedBones() => const <_BoneSpec>[
  _BoneSpec('pelvis', null, markerKey: 'pelvis', centerline: true),
  _BoneSpec('spine1', 'pelvis', markerKey: 'spine1', centerline: true),
  _BoneSpec('chest', 'spine1', markerKey: 'chest', centerline: true),
  _BoneSpec('neck', 'chest', markerKey: 'neck', centerline: true),
  _BoneSpec('head', 'neck', markerKey: 'head', centerline: true),
  _BoneSpec('tailBase', 'pelvis', markerKey: 'tailBase', centerline: true),
  _BoneSpec('tailTip', 'tailBase', markerKey: 'tailTip', centerline: true),
  _BoneSpec('leftFrontShoulder', 'chest', markerKey: 'leftFrontShoulder'),
  _BoneSpec(
    'rightFrontShoulder',
    'chest',
    mirrorOfMarkerKey: 'leftFrontShoulder',
  ),
  _BoneSpec('leftFrontPaw', 'leftFrontShoulder', markerKey: 'leftFrontPaw'),
  _BoneSpec(
    'rightFrontPaw',
    'rightFrontShoulder',
    mirrorOfMarkerKey: 'leftFrontPaw',
  ),
  _BoneSpec('leftBackHip', 'pelvis', markerKey: 'leftBackHip'),
  _BoneSpec('rightBackHip', 'pelvis', mirrorOfMarkerKey: 'leftBackHip'),
  _BoneSpec('leftBackPaw', 'leftBackHip', markerKey: 'leftBackPaw'),
  _BoneSpec('rightBackPaw', 'rightBackHip', mirrorOfMarkerKey: 'leftBackPaw'),
];

List<_BoneSpec> _tableFor(RigTemplate template) {
  if (template == RigTemplate.humanoid) return _humanoidBones();
  if (template == RigTemplate.quadruped) return _quadrupedBones();
  throw ArgumentError('unknown rig template: ${template.name}');
}

/// The marker keys [buildSkeleton] reads for [template] — every
/// [_BoneSpec.markerKey] in its own table, in table order. Exposed so a
/// caller (or a test) can ask what a template needs without hand-copying
/// the table.
List<String> requiredMarkers(RigTemplate template) => <String>[
  for (final bone in _tableFor(template))
    if (bone.markerKey != null) bone.markerKey!,
];

/// [v], reflected across [axis] through the origin.
Vector3 _mirrored(Vector3 v, RigMirrorAxis axis) {
  if (axis == RigMirrorAxis.x) return Vector3(-v.x, v.y, v.z);
  if (axis == RigMirrorAxis.y) return Vector3(v.x, -v.y, v.z);
  if (axis == RigMirrorAxis.z) return Vector3(v.x, v.y, -v.z);
  throw ArgumentError('unknown mirror axis: ${axis.name}');
}

/// [v], with its [axis] component zeroed — where a centerline joint's own
/// marker is snapped to sit exactly on the mirror plane.
Vector3 _onPlane(Vector3 v, RigMirrorAxis axis) {
  if (axis == RigMirrorAxis.x) return Vector3(0, v.y, v.z);
  if (axis == RigMirrorAxis.y) return Vector3(v.x, 0, v.z);
  if (axis == RigMirrorAxis.z) return Vector3(v.x, v.y, 0);
  throw ArgumentError('unknown mirror axis: ${axis.name}');
}

/// Builds a [template]-shaped rig out of [markers], each a world-space
/// position named by [requiredMarkers]`(template)`.
///
/// [bounds] is a sanity bound rather than a fallback: every marker actually
/// used must fall inside it, since a marker far outside the model's own
/// bounding box is almost always a mistaken unit or axis rather than a rig
/// somebody actually wants, and refusing early here is cheaper than a
/// distorted rig discovered later. [options] currently carries only
/// [RigBuildOptions.mirrorAxis].
///
/// The returned objects take consecutive ids starting at [firstObjectId] —
/// handed in rather than read off a project, for the reason [ModelProject
/// .added]'s own doc comment gives: the caller is the one that knows which
/// id is actually free.
///
/// Throws [ArgumentError] if a required marker is missing or a marker lies
/// outside [bounds].
BuiltRig buildSkeleton(
  RigTemplate template,
  Map<String, Vector3> markers, {
  required Aabb3 bounds,
  RigBuildOptions options = const RigBuildOptions(),
  required int firstObjectId,
  String? skeletonName,
}) {
  final table = _tableFor(template);
  final required = requiredMarkers(template);
  final missing = required.where((key) => !markers.containsKey(key)).toList();
  if (missing.isNotEmpty) {
    throw ArgumentError(
      'buildSkeleton(${template.name}) is missing markers: '
      '${missing.join(', ')}',
    );
  }
  for (final key in required) {
    final position = markers[key]!;
    if (!bounds.containsVector3(position)) {
      throw ArgumentError(
        'marker "$key" ($position) lies outside the given bounds '
        '(${bounds.min}..${bounds.max})',
      );
    }
  }

  final worldPositions = <String, Vector3>{};
  final idOf = <String, int>{};
  final objects = <ModelObject>[];
  var nextId = firstObjectId;

  for (final bone in table) {
    var world = bone.markerKey != null
        ? markers[bone.markerKey]!
        : _mirrored(markers[bone.mirrorOfMarkerKey]!, options.mirrorAxis);
    if (bone.centerline) world = _onPlane(world, options.mirrorAxis);
    worldPositions[bone.name] = world;

    final parentWorld = bone.parent == null
        ? Vector3.zero()
        : worldPositions[bone.parent]!;
    final id = nextId++;
    idOf[bone.name] = id;
    objects.add(
      ModelObject(
        id: id,
        name: bone.name,
        geometry: const SocketGeometry(),
        transform: Matrix4.translation(world - parentWorld),
        parent: bone.parent == null ? null : idOf[bone.parent],
      ),
    );
  }

  final joints = <int>[for (final bone in table) idOf[bone.name]!];
  final inverseBindMatrices = <Matrix4>[
    for (final bone in table)
      Matrix4.inverted(Matrix4.translation(worldPositions[bone.name]!)),
  ];

  return BuiltRig(
    objects: objects,
    skeleton: ProjectSkeleton(
      joints: joints,
      inverseBindMatrices: inverseBindMatrices,
      name: skeletonName,
    ),
  );
}
