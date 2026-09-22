/// A skeleton built from a template and a handful of marker positions,
/// rather than one joint at a time through [AddJoint] — `anim-21`'s own
/// row, extended by `anim-33d` (`RigBuildOptions`) to compose fingers,
/// toes, an extra spine, a face, IK and a rig controller onto the same
/// template rather than shipping a deeper fixed table for each.
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
/// position, or computes a *left*-side (or centerline) position from
/// markers alone ([_BoneSpec.derive]), from [markers]/its own already-built
/// neighbours; every right-side joint's own position is the mirror of its
/// left counterpart's own already-*computed* position, reflected across
/// [RigBuildOptions.mirrorAxis], and every centerline joint is snapped
/// exactly onto that same plane. A caller cannot hand this function an
/// asymmetric rig by accident, and `anim-33d`'s own derived bones (finger
/// phalanges, extra spine segments, jaw and eyes) do not weaken that: the
/// row's own "с симметрией" is an invariant of the algorithm, not a
/// property that happens to hold when the input already was symmetric.
///
/// **Every bone is a translation, so `inverseBind = worldRest⁻¹·meshWorld`
/// holds by construction too.** A joint's own rest transform is nothing
/// but "where its marker sits, relative to its parent" — no rotation — so
/// its world rest transform is `Matrix4.translation(worldPosition)`, and
/// its inverse bind matrix is that same matrix's own [Matrix4.inverted]
/// with [buildSkeleton]'s own `meshWorld` parameter composed onto it —
/// that parameter's own doc comment explains why the second factor has to
/// be there (`tut-21`'s own fix: every rig this function built before it
/// carried a `meshWorld` of exactly the identity no matter what the mesh
/// object being skinned actually carried, which is silently correct for
/// an identity mesh transform and silently wrong for anything else).
/// `meshWorld` left at its own default (the identity) is the case every
/// caller before `tut-21` was in, and reduces the claim above to
/// `inverseBind·worldRest = I`, `T⁻¹·T`, for the same reason two numbers
/// multiplied by each other's reciprocal are always one — the test suite
/// checks this against the actual returned objects rather than trusting
/// the algebra on paper, the same discipline `MirrorJoints`' own test
/// suite already holds itself to.
library;

import 'dart:math' as math;

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
/// themselves — `anim-33d`'s own row, screen 16's rig-composition switches
/// given a backend.
class RigBuildOptions {
  const RigBuildOptions({
    this.mirrorAxis = RigMirrorAxis.x,
    this.spineCount = 1,
    this.fingers = false,
    this.toes = false,
    this.faceBones = false,
    this.ikChains = false,
    this.controllers = false,
  });

  final RigMirrorAxis mirrorAxis;

  /// How many segments the spine chain between `hips`/`pelvis` and `chest`
  /// is built from. Documented range is 1 through 3 — screen 16's own
  /// switch offers exactly that — but nothing here enforces it as a type:
  /// [buildSkeleton]'s own `deformingCount > 64` refusal is what actually
  /// stops a caller who hands this an unreasonable value, the same way an
  /// out-of-bounds marker is stopped by the bounds check rather than by a
  /// type. Humanoid only; the quadruped template keeps its own single
  /// `spine1` regardless.
  final int spineCount;

  /// Five fingers, three phalanges each, laid out from `leftWrist` along
  /// `leftWrist − leftElbow` — 30 joints, mirrored onto the right hand by
  /// construction (see [_mirroredPairs]). Humanoid only.
  final bool fingers;

  /// One `toes` joint per foot, laid out from `leftAnkle` along
  /// `leftAnkle − leftKnee` — 2 joints, mirrored onto the right foot.
  /// Humanoid only.
  final bool toes;

  /// A centerline `jaw` and a mirrored `leftEye`/`rightEye`, derived from
  /// `head`/`neck` and the shoulder line — 3 joints. The eyes are not
  /// [_BoneSpec.deforming]: nothing skins a mesh to a look-at bone, the
  /// same reason [previewRig]'s own `deformingCount` can read lower than
  /// its `jointCount` once this is on. Humanoid only.
  final bool faceBones;

  /// Two-bone [IkConstraint]s on both arms and both legs, appended to the
  /// built skeleton's own [ProjectSkeleton.constraints] — pole vectors
  /// planted "forward" of the elbow/knee (see [_forwardFor]). Humanoid
  /// only: the quadruped template has no elbow/knee joint for a two-bone
  /// chain to bend around, so this is a no-op there.
  final bool ikChains;

  /// A socket parent above the template's own root joint (`hips` for the
  /// humanoid, `pelvis` for the quadruped) — a place a rig controller can
  /// hang from without itself being a deforming joint, so it never counts
  /// toward [previewRig]'s own `deformingCount` or the skinning shader's
  /// budget. See [BuiltRig] for where the extra object ends up.
  final bool controllers;
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
///
/// **[objects] can hold one more object than [skeleton.jointCount]
/// accounts for**: [RigBuildOptions.controllers]' own socket parent, when
/// asked for. It is a perfectly ordinary [ModelObject] — the first one in
/// [objects], so every joint's own [ModelObject.parent] that names it is
/// still naming an earlier list entry — it is simply never one of
/// [skeleton]'s own [ProjectSkeleton.joints].
class BuiltRig {
  const BuiltRig({required this.objects, required this.skeleton});

  final List<ModelObject> objects;
  final ProjectSkeleton skeleton;
}

/// [buildSkeleton]'s own preview — [previewRig] — of what a [template] and
/// [RigBuildOptions] combination would build, without building it: how many
/// joints, how many of them actually deform a mesh, how many rig
/// controllers, how many IK chains. `anim-33d`'s own row, for the
/// composition-card UI screen 16 draws ("N bones · M deforming").
typedef RigPreview = ({
  int jointCount,
  int deformingCount,
  int controllerCount,
  int ikChainCount,
});

/// One row of a rig's own bone table: a joint's name, its parent's name (or
/// none, for the root), and where its rest position comes from.
///
/// Exactly one of [markerKey], [mirrorOf] and [derive] is set. [markerKey]
/// reads a position straight out of [buildSkeleton]'s own `markers` — the
/// ordinary case for a centerline joint or the *left* half of a mirrored
/// pair. [derive] computes a position from `markers` alone — `anim-33d`'s
/// own new case, for a bone with no marker of its own (a finger phalanx, an
/// extra spine segment, a jaw or an eye) — always from LEFT/CENTRE markers
/// only, per this file's own class comment, never from another bone's own
/// *derived* position, so nothing here can accidentally chain one
/// approximation on top of another. [mirrorOf] instead reflects *another*
/// row's own already-computed world position (its left counterpart, by
/// name, already present in `buildSkeleton`'s own `worldPositions`) — the
/// only way a right-side joint's position is ever produced, whether that
/// counterpart was itself [markerKey]- or [derive]-driven, which is what
/// makes symmetry unconditional rather than incidental.
class _BoneSpec {
  const _BoneSpec(
    this.name,
    this.parent, {
    this.markerKey,
    this.mirrorOf,
    this.derive,
    this.centerline = false,
    this.deforming = true,
  }) : assert(
         (markerKey == null ? 0 : 1) +
                 (mirrorOf == null ? 0 : 1) +
                 (derive == null ? 0 : 1) ==
             1,
         'exactly one of markerKey/mirrorOf/derive',
       );

  final String name;
  final String? parent;
  final String? markerKey;

  /// The name of the [_BoneSpec] (earlier in the same table) whose own
  /// computed world position this bone mirrors across the build's own
  /// mirror plane.
  final String? mirrorOf;

  /// Computes this bone's own world position straight from `markers` —
  /// left/centre marker positions only, per this file's own class comment.
  final Vector3 Function(Map<String, Vector3> markers)? derive;

  /// True for a joint that sits ON the mirror plane rather than to one
  /// side of it (a spine, not a shoulder) — its own computed position is
  /// snapped exactly onto the plane rather than trusted as-given, since a
  /// centerline joint even fractionally off the plane is what would make
  /// [buildSkeleton]'s own symmetry guarantee false for everything hung
  /// under it.
  final bool centerline;

  /// False for a joint that exists to be aimed or posed but never skins a
  /// mesh — today, only a [RigBuildOptions.faceBones] eye. Everything else
  /// this file builds deforms. [buildSkeleton]'s own `deformingCount > 64`
  /// refusal counts only these; [previewRig]'s own `jointCount` counts
  /// every joint regardless.
  final bool deforming;
}

/// [leftBones]' own left-side (or, for a table that ever needed it here,
/// otherwise-unmirrored) specs, each immediately followed by its own
/// mirror image: the same name with its `left` prefix swapped for `right`,
/// parented under whatever [_BoneSpec.parent] a same-swap gives (another
/// `left…` bone mirrors to the matching `right…` one already built two
/// entries earlier; a shared centerline parent like `chest` or `hips`
/// passes through unchanged), and [_BoneSpec.mirrorOf] naming the left
/// bone itself.
///
/// **Built here once rather than typed out twice per pair**, the same
/// reasoning [_humanoidBones]' own hand-written pairs already followed one
/// row at a time; this is that same pattern turned into a function so
/// `anim-33d`'s own, much longer, finger and toe tables do not have to
/// repeat it thirty times over.
List<_BoneSpec> _mirroredPairs(List<_BoneSpec> leftBones) => <_BoneSpec>[
  for (final left in leftBones) ...<_BoneSpec>[
    left,
    _BoneSpec(
      _mirroredName(left.name),
      _mirroredName(left.parent!),
      mirrorOf: left.name,
      centerline: left.centerline,
      deforming: left.deforming,
    ),
  ],
];

/// `leftX` → `rightX`; anything not `left`-prefixed (a shared centerline
/// parent such as `chest` or `hips`) passes through unchanged.
String _mirroredName(String name) =>
    name.startsWith('left') ? 'right${name.substring(4)}' : name;

/// [a], moved [t] of the way to [b] — plain linear interpolation, used by
/// every `derive` in this file that reads two markers rather than one.
Vector3 _lerp(Vector3 a, Vector3 b, double t) => a + (b - a) * t;

/// Any unit vector perpendicular to [v] — the same construction
/// `ik_constraint.dart`'s own `_arbitraryPerpendicular` uses for the same
/// reason: reimplemented here rather than shared, since ten lines is
/// cheaper than a coupling between two otherwise-unrelated rows.
Vector3 _perpendicularTo(Vector3 v) {
  final reference = v.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
  final axis = v.cross(reference);
  return axis.length2 > 1e-12 ? axis.normalized() : Vector3(0, 0, 1);
}

/// The spine chain from `hips` to (but not including) `chest`: always at
/// least the one `spine` joint the base template already had, driven by
/// the `spine` marker itself for backward compatibility with every rig
/// built before `anim-33d`; [spineCount] beyond 1 adds `spine2`, `spine3`,
/// … evenly spaced between the `hips` and `chest` markers themselves
/// (`derive`, never the already-placed `spine` joint) — the plan's own
/// "lerp(hips, chest) at even fractions".
List<_BoneSpec> _spineChain(int spineCount) => <_BoneSpec>[
  const _BoneSpec('spine', 'hips', markerKey: 'spine', centerline: true),
  for (var i = 2; i <= spineCount; i++)
    _BoneSpec(
      'spine$i',
      i == 2 ? 'spine' : 'spine${i - 1}',
      centerline: true,
      derive: (markers) =>
          _lerp(markers['hips']!, markers['chest']!, i / (spineCount + 1)),
    ),
];

const List<String> _fingerNames = <String>[
  'Thumb',
  'Index',
  'Middle',
  'Ring',
  'Pinky',
];

/// One hand's own left-side fingers: five, three phalanges each, every
/// phalanx `derive`d from `leftWrist` and `leftElbow` alone — "laid out
/// along wrist→(wrist−elbow)", spread sideways per finger by a fraction of
/// the forearm's own length so five fingers do not collapse onto one line.
/// [_mirroredPairs] gives the right hand.
List<_BoneSpec> _leftFingerBones() => <_BoneSpec>[
  for (var f = 0; f < _fingerNames.length; f++)
    for (var phalanx = 1; phalanx <= 3; phalanx++)
      _BoneSpec(
        'left${_fingerNames[f]}$phalanx',
        phalanx == 1 ? 'leftWrist' : 'left${_fingerNames[f]}${phalanx - 1}',
        derive: (markers) => _fingerJoint(markers, f, phalanx),
      ),
];

Vector3 _fingerJoint(Map<String, Vector3> markers, int finger, int phalanx) {
  final wrist = markers['leftWrist']!;
  final elbow = markers['leftElbow']!;
  final along = wrist - elbow;
  final forearmLength = along.length;
  final alongDir = along.length2 > 1e-12
      ? along.normalized()
      : Vector3(0, -1, 0);
  final spread = _perpendicularTo(alongDir);
  final lateral =
      (finger - (_fingerNames.length - 1) / 2) * forearmLength * 0.06;
  final base = wrist + spread * lateral;
  return base + alongDir * (forearmLength * 0.12 * phalanx);
}

/// One foot's own left-side toe — a single `leftToes` joint `derive`d from
/// `leftAnkle` and `leftKnee` alone, "laid out along ankle→(ankle−knee)".
/// [_mirroredPairs] gives the right foot.
List<_BoneSpec> _leftToeBones() => <_BoneSpec>[
  _BoneSpec(
    'leftToes',
    'leftAnkle',
    derive: (markers) {
      final ankle = markers['leftAnkle']!;
      final knee = markers['leftKnee']!;
      final along = ankle - knee;
      final dir = along.length2 > 1e-12 ? along.normalized() : Vector3(0, 0, 1);
      return ankle + dir * (along.length * 0.6);
    },
  ),
];

/// The face: a centerline `jaw` between `neck` and `head`, and a mirrored
/// `leftEye`/`rightEye` offset sideways from `head` by a fraction of the
/// shoulder line (`leftShoulder − chest`, the same empirical "which way is
/// sideways" this file otherwise only knows through [RigBuildOptions
/// .mirrorAxis]) — both `derive`d from markers alone. The eyes are not
/// [_BoneSpec.deforming]: they aim, they do not skin.
List<_BoneSpec> _faceBones() => <_BoneSpec>[
  _BoneSpec(
    'jaw',
    'head',
    centerline: true,
    derive: (markers) => _lerp(markers['neck']!, markers['head']!, 0.85),
  ),
  ..._mirroredPairs(<_BoneSpec>[
    _BoneSpec(
      'leftEye',
      'head',
      deforming: false,
      derive: (markers) {
        final sideways = markers['leftShoulder']! - markers['chest']!;
        return markers['head']! + sideways * 0.25;
      },
    ),
  ]),
];

/// **Humanoid, 17 joints at [RigBuildOptions]' own defaults**: hips/spine
/// (×[RigBuildOptions.spineCount])/chest/neck/head on the centerline,
/// shoulder/elbow/wrist mirrored, hip/knee/ankle mirrored — plus, per
/// option, five-fingered hands (+30), extra spine segments (+`spineCount
/// − 1`), toes (+2) and a face (+3). See this file's own class comment for
/// the acceptance table `anim-33d` builds these against.
List<_BoneSpec> _humanoidBones(RigBuildOptions options) {
  final spineChain = _spineChain(math.max(1, options.spineCount));

  final arm = <_BoneSpec>[
    const _BoneSpec('leftShoulder', 'chest', markerKey: 'leftShoulder'),
    const _BoneSpec('leftElbow', 'leftShoulder', markerKey: 'leftElbow'),
    const _BoneSpec('leftWrist', 'leftElbow', markerKey: 'leftWrist'),
  ];
  final leg = <_BoneSpec>[
    const _BoneSpec('leftHip', 'hips', markerKey: 'leftHip'),
    const _BoneSpec('leftKnee', 'leftHip', markerKey: 'leftKnee'),
    const _BoneSpec('leftAnkle', 'leftKnee', markerKey: 'leftAnkle'),
  ];

  return <_BoneSpec>[
    const _BoneSpec('hips', null, markerKey: 'hips', centerline: true),
    ...spineChain,
    _BoneSpec(
      'chest',
      spineChain.last.name,
      markerKey: 'chest',
      centerline: true,
    ),
    const _BoneSpec('neck', 'chest', markerKey: 'neck', centerline: true),
    const _BoneSpec('head', 'neck', markerKey: 'head', centerline: true),
    ..._mirroredPairs(arm),
    if (options.fingers) ..._mirroredPairs(_leftFingerBones()),
    ..._mirroredPairs(leg),
    if (options.toes) ..._mirroredPairs(_leftToeBones()),
    if (options.faceBones) ..._faceBones(),
  ];
}

/// **Quadruped, 15 joints**: pelvis/spine1/chest/neck/head/tailBase/tailTip
/// on the centerline (7), front shoulder/paw mirrored (4), back hip/paw
/// mirrored (4). One spine segment and no separate elbow/knee joint on
/// either pair of legs — the same "base case, not the deepest rig
/// possible" choice the humanoid table makes. `anim-33d`'s own new
/// [RigBuildOptions] fields (fingers, toes, an extra spine, a face, IK) are
/// humanoid-only — this table's own bone names have no elbow/knee/wrist to
/// hang any of them from — so this generator takes no options at all;
/// [buildSkeleton]'s own `mirrorAxis` and `controllers` still apply, since
/// both are handled once, uniformly, outside any one template's table.
List<_BoneSpec> _quadrupedBones() => const <_BoneSpec>[
  _BoneSpec('pelvis', null, markerKey: 'pelvis', centerline: true),
  _BoneSpec('spine1', 'pelvis', markerKey: 'spine1', centerline: true),
  _BoneSpec('chest', 'spine1', markerKey: 'chest', centerline: true),
  _BoneSpec('neck', 'chest', markerKey: 'neck', centerline: true),
  _BoneSpec('head', 'neck', markerKey: 'head', centerline: true),
  _BoneSpec('tailBase', 'pelvis', markerKey: 'tailBase', centerline: true),
  _BoneSpec('tailTip', 'tailBase', markerKey: 'tailTip', centerline: true),
  _BoneSpec('leftFrontShoulder', 'chest', markerKey: 'leftFrontShoulder'),
  _BoneSpec('rightFrontShoulder', 'chest', mirrorOf: 'leftFrontShoulder'),
  _BoneSpec('leftFrontPaw', 'leftFrontShoulder', markerKey: 'leftFrontPaw'),
  _BoneSpec('rightFrontPaw', 'rightFrontShoulder', mirrorOf: 'leftFrontPaw'),
  _BoneSpec('leftBackHip', 'pelvis', markerKey: 'leftBackHip'),
  _BoneSpec('rightBackHip', 'pelvis', mirrorOf: 'leftBackHip'),
  _BoneSpec('leftBackPaw', 'leftBackHip', markerKey: 'leftBackPaw'),
  _BoneSpec('rightBackPaw', 'rightBackHip', mirrorOf: 'leftBackPaw'),
];

List<_BoneSpec> _tableFor(RigTemplate template, RigBuildOptions options) {
  if (template == RigTemplate.humanoid) return _humanoidBones(options);
  if (template == RigTemplate.quadruped) return _quadrupedBones();
  throw ArgumentError('unknown rig template: ${template.name}');
}

/// The marker keys [buildSkeleton] reads for [template] — every
/// [_BoneSpec.markerKey] in its own table, in table order. Exposed so a
/// caller (or a test) can ask what a template needs without hand-copying
/// the table.
///
/// **Independent of [RigBuildOptions] on purpose** — `anim-33d`'s own
/// row states it plainly: "this option set only adds derived bones, it
/// never asks for new input markers." Every [_BoneSpec.derive] in this
/// file reads only markers already in this list, so the set is the same
/// whichever options end up building the skeleton; this reads it off the
/// options-free table rather than accepting an `options` parameter nobody
/// needs, so the promise is true by construction and not just by
/// convention.
List<String> requiredMarkers(RigTemplate template) => <String>[
  for (final bone in _tableFor(template, const RigBuildOptions()))
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

/// "Forward" for an IK chain's own pole vector — whichever axis is not
/// [RigMirrorAxis.y] (this engine's own up axis — `groundY` elsewhere in
/// this package, a rig standing spine-up along Y in every marker fixture
/// this file's own tests use) and not [axis] itself, the ordinary
/// left/right mirror plane. Only [RigMirrorAxis.z] as the mirror axis
/// actually changes the answer; the ordinary [RigMirrorAxis.x] rig (and
/// the unusual [RigMirrorAxis.y] one) both point their poles along Z.
Vector3 _forwardFor(RigMirrorAxis axis) =>
    axis == RigMirrorAxis.z ? Vector3(1, 0, 0) : Vector3(0, 0, 1);

/// The four two-bone [IkConstraint]s [RigBuildOptions.ikChains] asks for on
/// a humanoid — both arms, both legs — targets set to each chain's own
/// effector's own *rest* position (so solving one right after
/// [buildSkeleton] moves nothing) and poles planted [_forwardFor] of the
/// elbow/knee, half the chain's own upper-segment length out.
List<IkConstraint> _humanoidIkConstraints(
  Map<String, int> idOf,
  Map<String, Vector3> worldPositions,
  RigMirrorAxis mirrorAxis,
) {
  final forward = _forwardFor(mirrorAxis);
  IkConstraint chain(String root, String mid, String effector) {
    final rootPos = worldPositions[root]!;
    final midPos = worldPositions[mid]!;
    final poleDistance = (midPos - rootPos).length * 0.5;
    return IkConstraint(
      rootJointId: idOf[root]!,
      midJointId: idOf[mid]!,
      effectorJointId: idOf[effector]!,
      target: worldPositions[effector]!,
      pole: midPos + forward * poleDistance,
    );
  }

  return <IkConstraint>[
    chain('leftShoulder', 'leftElbow', 'leftWrist'),
    chain('rightShoulder', 'rightElbow', 'rightWrist'),
    chain('leftHip', 'leftKnee', 'leftAnkle'),
    chain('rightHip', 'rightKnee', 'rightAnkle'),
  ];
}

/// How many [IkConstraint]s [buildSkeleton] would add for [template] under
/// [options] — shared between [previewRig] and [buildSkeleton] itself so
/// the two can never disagree.
int _ikChainCountFor(RigTemplate template, RigBuildOptions options) {
  if (!options.ikChains) return 0;
  // The quadruped template has no elbow/knee joint — no middle joint for a
  // two-bone chain to bend around — so there is nothing to build there.
  return template == RigTemplate.humanoid ? 4 : 0;
}

/// [buildSkeleton]'s own preview: [template] and [options], without
/// building either the objects or the skeleton — cheap enough to call on
/// every keystroke of screen 16's own composition card, since it is
/// nothing but counting [_BoneSpec]s.
RigPreview previewRig(
  RigTemplate template, {
  RigBuildOptions options = const RigBuildOptions(),
}) {
  final table = _tableFor(template, options);
  return (
    jointCount: table.length,
    deformingCount: table.where((bone) => bone.deforming).length,
    controllerCount: options.controllers ? 1 : 0,
    ikChainCount: _ikChainCountFor(template, options),
  );
}

/// Builds a [template]-shaped rig out of [markers], each a world-space
/// position named by [requiredMarkers]`(template)`.
///
/// [bounds] is a sanity bound rather than a fallback: every marker actually
/// used must fall inside it, since a marker far outside the model's own
/// bounding box is almost always a mistaken unit or axis rather than a rig
/// somebody actually wants, and refusing early here is cheaper than a
/// distorted rig discovered later.
///
/// The returned objects take consecutive ids starting at [firstObjectId] —
/// handed in rather than read off a project, for the reason [ModelProject
/// .added]'s own doc comment gives: the caller is the one that knows which
/// id is actually free.
///
/// [meshWorld] is the world transform, at bind time, of the object
/// [markers] were placed against — the object a caller means to skin with
/// the returned [BuiltRig.skeleton], left out (or null) when nothing is
/// being skinned yet, in which case this defaults to the identity.
/// **Every [markers] position is a world-space pick** (`autorig_markers
/// .dart`'s own screen-to-world raycast, or the identical world-space
/// scaling `case4_scenario.dart`/`rig_pipeline_mcp_test.dart` both use for
/// a headless rig), but [inverseBindMatrices] has to undo a vertex's
/// bind-time position in the *mesh's own local space* — the glTF
/// convention `Skeleton.update`'s own doc comment states outright
/// (`jointMatrix = inverse(meshWorld) * jointWorld * inverseBind`) and the
/// one every consumer of a [ProjectSkeleton] already assumes: the live
/// viewport's GPU pipeline (`SceneSync`), the shadow and object-pick
/// passes, and `render_project.dart`'s own headless picture alike. A
/// world-space marker folded straight into `worldRest⁻¹` with no
/// [meshWorld] term is only correct for a mesh object whose own world
/// transform happens to be the identity — every other mesh, any import
/// that carries a scale or an axis swap among them (`RobotExpressive.glb`
/// is a real one: a ~100× scale and an axis swap, both from the file's own
/// node hierarchy, confirmed directly), gets a skeleton that skins
/// correctly nowhere at all. This was `tut-10`'s own finding, worked
/// around there by composing the missing term back in at render time
/// instead of fixing it here (`render_project.dart`'s `_withSkin`, before
/// `tut-21`); it never touched the live viewport, which had no such
/// workaround and simply skinned wrong.
///
/// Throws [ArgumentError] if [options] would build more than 64 deforming
/// joints (the skinning shader's own per-draw joint budget — see
/// `ProjectProfile.hardMaxJoints`, `rig_issues.dart`'s own `> 64` check),
/// a required marker is missing, or a marker lies outside [bounds].
BuiltRig buildSkeleton(
  RigTemplate template,
  Map<String, Vector3> markers, {
  required Aabb3 bounds,
  RigBuildOptions options = const RigBuildOptions(),
  required int firstObjectId,
  String? skeletonName,
  Matrix4? meshWorld,
}) {
  final table = _tableFor(template, options);

  final deformingCount = table.where((bone) => bone.deforming).length;
  if (deformingCount > 64) {
    throw ArgumentError(
      'buildSkeleton(${template.name}) would deform $deformingCount '
      'joints; the skinning shader holds 64',
    );
  }

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

  // `RigBuildOptions.controllers`: a socket parent above the template's
  // own root joint, built first so every joint below it (starting with the
  // root itself) already has somewhere valid to point `parent` at. Its own
  // world position is the root's own (`_onPlane`-snapped, matching what
  // the root's own loop iteration below computes for itself), so the
  // root's own local transform relative to it comes out as a zero
  // translation rather than an arbitrary offset.
  final rootBone = table.firstWhere((bone) => bone.parent == null);
  final controllerWorld = options.controllers
      ? _onPlane(markers[rootBone.markerKey!]!, options.mirrorAxis)
      : Vector3.zero();
  final controllerId = options.controllers ? nextId++ : null;
  if (controllerId != null) {
    objects.add(
      ModelObject(
        id: controllerId,
        name: '${rootBone.name}Control',
        geometry: const SocketGeometry(),
        transform: Matrix4.translation(controllerWorld),
        parent: null,
      ),
    );
  }

  for (final bone in table) {
    final rawWorld = switch (bone) {
      _BoneSpec(:final markerKey?) => markers[markerKey]!,
      _BoneSpec(:final derive?) => derive(markers),
      _BoneSpec(:final mirrorOf?) => _mirrored(
        worldPositions[mirrorOf]!,
        options.mirrorAxis,
      ),
      _ => throw StateError(
        '_BoneSpec always sets exactly one of markerKey/mirrorOf/derive',
      ),
    };
    final world = bone.centerline
        ? _onPlane(rawWorld, options.mirrorAxis)
        : rawWorld;
    worldPositions[bone.name] = world;

    final parentWorld = bone.parent == null
        ? controllerWorld
        : worldPositions[bone.parent]!;
    final id = nextId++;
    idOf[bone.name] = id;
    objects.add(
      ModelObject(
        id: id,
        name: bone.name,
        geometry: const SocketGeometry(),
        transform: Matrix4.translation(world - parentWorld),
        parent: bone.parent == null ? controllerId : idOf[bone.parent]!,
      ),
    );
  }

  final joints = <int>[for (final bone in table) idOf[bone.name]!];
  // `worldRest⁻¹ · meshWorld` — see this function's own `meshWorld`
  // parameter doc for why the second factor has to be composed in here
  // rather than left for a caller to work around later (`tut-21`).
  final Matrix4 mesh = meshWorld ?? Matrix4.identity();
  final inverseBindMatrices = <Matrix4>[
    for (final bone in table)
      Matrix4.inverted(Matrix4.translation(worldPositions[bone.name]!))
        ..multiply(mesh),
  ];

  final constraints = options.ikChains && template == RigTemplate.humanoid
      ? _humanoidIkConstraints(idOf, worldPositions, options.mirrorAxis)
      : const <IkConstraint>[];

  return BuiltRig(
    objects: objects,
    skeleton: ProjectSkeleton(
      joints: joints,
      inverseBindMatrices: inverseBindMatrices,
      name: skeletonName,
      constraints: constraints,
    ),
  );
}
