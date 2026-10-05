// A ragdoll through the binding — N1: eleven bones built at rest, placed
// in a pose and read back from it, dropped on a floor of the level the
// mirror stands in the core, carried by the pose's momentum, held together
// at every joint, asleep at the end; and kept through the dynamics'
// restores.
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A figure standing at the origin, its feet on the ground: the hips, a
/// chest, a head, arms down and legs, each bone's frame unturned.
List<RagdollBone> figure({Vector3? at}) {
  final o = at ?? Vector3.zero();
  RagdollBone bone(
    String name,
    int parent,
    List<double> head,
    List<double> tail,
    double radius,
    double mass, [
    RagdollJoint? joint,
  ]) => RagdollBone(
    name: name,
    parent: parent,
    head: o + Vector3.array(head),
    tail: o + Vector3.array(tail),
    orientation: Quaternion.identity(),
    radius: radius,
    mass: mass,
    joint: joint,
  );
  const spine = RagdollBall(cone: 0.5, twistLower: -0.4, twistUpper: 0.4);
  const shoulder = RagdollBall(cone: 1.5, twistLower: -1.0, twistUpper: 1.0);
  const hip = RagdollBall(cone: 1.2, twistLower: -0.5, twistUpper: 0.5);
  final elbow = RagdollHinge(
    axis: Vector3(1.0, 0.0, 0.0),
    lower: 0,
    upper: 2.4,
  );
  final knee = RagdollHinge(
    axis: Vector3(1.0, 0.0, 0.0),
    lower: -2.4,
    upper: 0,
  );
  return <RagdollBone>[
    bone('hips', -1, <double>[0, 0.92, 0], <double>[0, 1.1, 0], 0.13, 10),
    bone(
      'chest',
      0,
      <double>[0, 1.1, 0],
      <double>[0, 1.55, 0],
      0.15,
      15,
      spine,
    ),
    bone('head', 1, <double>[0, 1.58, 0], <double>[0, 1.82, 0], 0.11, 4, spine),
    bone(
      'arm.L',
      1,
      <double>[-0.25, 1.5, 0],
      <double>[-0.25, 1.2, 0],
      0.05,
      2,
      shoulder,
    ),
    bone(
      'arm.R',
      1,
      <double>[0.25, 1.5, 0],
      <double>[0.25, 1.2, 0],
      0.05,
      2,
      shoulder,
    ),
    bone(
      'forearm.L',
      3,
      <double>[-0.25, 1.2, 0],
      <double>[-0.25, 0.92, 0],
      0.045,
      1.5,
      elbow,
    ),
    bone(
      'forearm.R',
      4,
      <double>[0.25, 1.2, 0],
      <double>[0.25, 0.92, 0],
      0.045,
      1.5,
      elbow,
    ),
    bone(
      'thigh.L',
      0,
      <double>[-0.1, 0.92, 0],
      <double>[-0.1, 0.5, 0],
      0.07,
      7,
      hip,
    ),
    bone(
      'thigh.R',
      0,
      <double>[0.1, 0.92, 0],
      <double>[0.1, 0.5, 0],
      0.07,
      7,
      hip,
    ),
    bone(
      'shin.L',
      7,
      <double>[-0.1, 0.5, 0],
      <double>[-0.1, 0.06, 0],
      0.055,
      4,
      knee,
    ),
    bone(
      'shin.R',
      8,
      <double>[0.1, 0.5, 0],
      <double>[0.1, 0.06, 0],
      0.055,
      4,
      knee,
    ),
  ];
}

/// [rest] turned by [turn] about the origin and lifted by [lift]: a pose.
List<BonePose> posed(
  List<RagdollBone> rest,
  Quaternion turn,
  Vector3 lift,
) => <BonePose>[
  for (final b in rest)
    (position: turnBy(turn, b.head) + lift, orientation: turn * b.orientation),
];

void main() {
  late CollisionWorld world;
  late NativeDynamics dynamics;
  setUp(() {
    world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    dynamics = NativeDynamics(world: world)..native.substeps = 8;
    addTearDown(dynamics.dispose);
    // The floor stands in the core from the first step.
    dynamics.step(1.0 / 60.0);
  });

  test('a pose placed is the pose read back', () {
    final rest = figure();
    final turn = Quaternion.axisAngle(Vector3(0.3, 1.0, 0.2).normalized(), 1.1);
    final pose = posed(rest, turn, Vector3(1.0, 2.0, -3.0));
    final ragdoll = NativeRagdoll(dynamics.native, rest, pose: pose);
    for (var i = 0; i < rest.length; i++) {
      final read = ragdoll.poseOf(i);
      expect(read.position.distanceTo(pose[i].position), lessThan(1e-4));
      final d = read.orientation * pose[i].orientation.conjugated();
      expect(d.w.abs(), closeTo(1.0, 1e-5), reason: rest[i].name);
    }
  });

  test('dropped on its side it falls, holds together and sleeps', () {
    final rest = figure();
    final ragdoll = NativeRagdoll(
      dynamics.native,
      rest,
      pose: posed(
        rest,
        Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), 1.4),
        Vector3(0.0, 1.0, 0.0),
      ),
      dynamics: dynamics,
    );
    final lengths = <double>[
      for (final b in rest)
        b.parent < 0 ? 0.0 : b.head.distanceTo(rest[b.parent].head),
    ];
    var worst = 0.0;
    var steps = 0;
    while (!ragdoll.isAsleep && steps < 600) {
      dynamics.step(1.0 / 60.0);
      steps++;
      for (var i = 1; i < rest.length; i++) {
        final apart = ragdoll
            .poseOf(i)
            .position
            .distanceTo(ragdoll.poseOf(rest[i].parent).position);
        worst = worst > (apart - lengths[i]).abs()
            ? worst
            : (apart - lengths[i]).abs();
      }
    }
    expect(ragdoll.isAsleep, isTrue, reason: 'awake after $steps steps');
    expect(worst, lessThan(0.03));
    for (var i = 0; i < rest.length; i++) {
      final y = ragdoll.poseOf(i).position.y;
      expect(y, inInclusiveRange(-0.05, 0.6), reason: rest[i].name);
    }
  });

  test('a pose given momentum carries it', () {
    final rest = figure();
    final ragdoll = NativeRagdoll(
      dynamics.native,
      rest,
      pose: posed(rest, Quaternion.identity(), Vector3(0.0, 0.05, 0.0)),
      velocity: <Vector3>[for (final _ in rest) Vector3(3.0, 0.0, 0.0)],
    );
    for (var i = 0; i < 30; i++) {
      dynamics.step(1.0 / 60.0);
    }
    expect(ragdoll.poseOf(0).position.x, greaterThan(0.5));
  });

  test('the dynamics keep it through a restore, and let it go after', () {
    final rest = figure();
    final saved = dynamics.saveState();
    final ragdoll = NativeRagdoll(
      dynamics.native,
      rest,
      pose: posed(rest, Quaternion.identity(), Vector3(0.0, 0.5, 0.0)),
      dynamics: dynamics,
    );
    final count = dynamics.native.bodyCount;
    final after = dynamics.saveState();
    dynamics.restoreState(after);
    expect(dynamics.native.bodyCount, count);
    ragdoll.dispose();
    expect(dynamics.native.bodyCount, count - rest.length);
    dynamics.restoreState(saved);
    expect(dynamics.native.bodyCount, count - rest.length);
  });

  test('a bone that comes before its parent is refused', () {
    final rest = figure();
    final wrong = <RagdollBone>[rest[1], rest[0]];
    expect(() => NativeRagdoll(dynamics.native, wrong), throwsArgumentError);
  });
}
