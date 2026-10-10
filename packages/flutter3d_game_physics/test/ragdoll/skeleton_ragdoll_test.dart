// A skinned character gone limp — N1: the hero of flutter3d's fixtures, a
// Quaternius rig two centimetres tall under a node that makes it 1.8 m,
// built into scene nodes from its glTF, its skeleton made a ragdoll by the
// profile of names, dropped on a floor, and its bodies written back into
// its joints — the pose kept at once, the figure held together lying down,
// the feet carried by the shins, a blend halfway back to the animation.
import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_game_physics/ragdoll.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The hero, as scene nodes under a root that stands it 1.8 m tall at
/// [at], its skeleton and the skinned mesh's node.
Future<
  ({SceneNode root, Skeleton skeleton, SceneNode mesh, List<SceneNode> nodes})
>
hero({Vector3? at}) async {
  final doc = await decodeModel(
    ModelLoadRequest(
      source: const FileAssetSource('../flutter3d/test/fixtures/hero.glb'),
    ),
  );
  final nodes = <SceneNode>[
    for (final n in doc.nodes)
      SceneNode(name: n.name)
        ..setPositionFrom(n.translation)
        ..setRotation(n.rotation)
        ..setScale(n.scale.x, n.scale.y, n.scale.z),
  ];
  for (var i = 0; i < doc.nodes.length; i++) {
    for (final c in doc.nodes[i].children) {
      nodes[i].add(nodes[c]);
    }
  }
  final root = SceneNode(name: 'hero');
  for (final r in doc.roots) {
    root.add(nodes[r]);
  }
  final skin = doc.skins.first;
  final skeleton = Skeleton(
    joints: <SceneNode>[for (final j in skin.joints) nodes[j]],
    inverseBindMatrices: skin.inverseBindMatrices,
  );
  final meshNode = <int>[
    for (var i = 0; i < doc.nodes.length; i++)
      if (doc.nodes[i].surfaces.any((s) => doc.surfaces[s].skinIndex != null))
        i,
  ].first;
  // As tall as a person, wherever the rig's own units put it.
  final heads = <Vector3>[
    for (var i = 0; i < skeleton.jointCount; i++)
      (nodes[meshNode].worldMatrix * skeleton.bindPoseOf(i) as Matrix4)
          .getTranslation(),
  ];
  final tall =
      heads.map((p) => p.y).reduce((a, b) => a > b ? a : b) -
      heads.map((p) => p.y).reduce((a, b) => a < b ? a : b);
  root
    ..setScale(1.8 / tall, 1.8 / tall, 1.8 / tall)
    ..setPositionFrom(at ?? Vector3.zero());
  return (root: root, skeleton: skeleton, mesh: nodes[meshNode], nodes: nodes);
}

Vector3 worldOf(SceneNode n) => n.worldMatrix.getTranslation();

SceneNode named(Skeleton s, String name) =>
    s.joints.firstWhere((j) => j.name == name);

void main() {
  group("the Quaternius profile's masses are de Leva's (1996)", () {
    final parts = RagdollProfile.quaternius.parts;

    test('they add up to the whole body', () {
      // Mutation: put the old shares back (0.17, 0.27, 0.08, 0.03, 0.02,
      // 0.1, 0.05), which add up to 0.92 — fails.
      final total = parts.values.fold<double>(
        0.0,
        (double sum, RagdollPart p) => sum + p.share,
      );
      expect(total, closeTo(1.0, 1e-9));
      expect(
        SegmentMassShares.wholeBody.values.fold<double>(
          0.0,
          (double sum, double s) => sum + s,
        ),
        closeTo(1.0, 1e-9),
      );
    });

    test('a thigh is 14.16 % of the body, not the 10.9 % it was', () {
      expect(parts['UpperLeg.L']!.share, 0.1416);
      expect(parts['UpperLeg.R']!.share, 0.1416);
    });

    test('a whole body weighs the reference man by default', () {
      expect(referenceBodyMass, 73.0);
    });
  });

  late NativeDynamics dynamics;
  setUp(() {
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    dynamics = NativeDynamics(world: world)..native.substeps = 8;
    addTearDown(dynamics.dispose);
    dynamics.step(1.0 / 60.0);
  });

  test('the hero becomes eleven bodies, and keeps its pose at once', () async {
    final h = await hero(at: Vector3(0.0, 0.3, 0.0));
    final before = <Vector3>[for (final j in h.skeleton.joints) worldOf(j)];
    final ragdoll = SkeletonRagdoll(
      skeleton: h.skeleton,
      meshWorld: h.mesh.worldMatrix,
      world: dynamics.native,
      dynamics: dynamics,
    );
    expect(ragdoll.ragdoll.bones.length, 11);
    // Knees bound bent are hinges; elbows bound in a T-pose fall back.
    expect(
      ragdoll.ragdoll.heldAs(ragdoll.bodyNamed('LowerLeg.L')!),
      isA<RagdollHinge>(),
    );
    expect(
      ragdoll.ragdoll.heldAs(ragdoll.bodyNamed('LowerArm.L')!),
      isA<RagdollBall>(),
    );
    expect(ragdoll.bodyNamed('Torso'), isNotNull);
    expect(ragdoll.bodyNamed('Ear1.L'), isNull);
    ragdoll.apply();
    for (var i = 0; i < h.skeleton.jointCount; i++) {
      expect(
        worldOf(h.skeleton.joints[i]).distanceTo(before[i]),
        lessThan(0.01),
        reason: h.skeleton.joints[i].name,
      );
    }
  });

  test('laid down by hand, it says how it lies before it falls', () async {
    // The figure faces +z. Turned a quarter about x one way it lies on its
    // front, its head along +z; the other way on its back, its head along -z.
    // Mutation: read up and forward off the skinned mesh node's turn, as
    // `lying` did — the hero's mesh node turns its Z-up armature a quarter
    // about x, so even standing it read as lying face up, head along -z.
    Future<RagdollLying> laid(double turn) async {
      final h = await hero(at: Vector3(0.0, 0.5, 0.0));
      h.root.setRotation(Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), turn));
      final ragdoll = SkeletonRagdoll(
        skeleton: h.skeleton,
        meshWorld: h.mesh.worldMatrix,
        world: dynamics.native,
        dynamics: dynamics,
      );
      addTearDown(ragdoll.dispose);
      return ragdoll.lying();
    }

    final front = await laid(math.pi / 2);
    expect(front.faceUp, isFalse);
    expect(front.headward.z, greaterThan(0.99));
    final back = await laid(-math.pi / 2);
    expect(back.faceUp, isTrue);
    expect(back.headward.z, lessThan(-0.99));
  });

  test('the right limbs end at the right joints', () async {
    // One part served both sides, its tail the first of `LowerArm.L`,
    // `LowerArm.R` found: the right upper arm reached to the left elbow.
    // Mutation: take the first name found, whichever side it is on, in
    // `_tailOf` — the right upper arm and thigh end a shoulder's width off.
    final h = await hero(at: Vector3(0.0, 0.3, 0.0));
    final ragdoll = SkeletonRagdoll(
      skeleton: h.skeleton,
      meshWorld: h.mesh.worldMatrix,
      world: dynamics.native,
      dynamics: dynamics,
    );
    addTearDown(ragdoll.dispose);
    for (final (limb, end) in <(String, String)>[
      ('UpperArm.R', 'LowerArm.R'),
      ('UpperArm.L', 'LowerArm.L'),
      ('UpperLeg.R', 'LowerLeg.R'),
      ('UpperLeg.L', 'LowerLeg.L'),
    ]) {
      final bone = ragdoll.ragdoll.bones[ragdoll.bodyNamed(limb)!];
      final at = h.skeleton.joints.indexOf(named(h.skeleton, end));
      final bound = (h.mesh.worldMatrix * h.skeleton.bindPoseOf(at) as Matrix4)
          .getTranslation();
      expect(
        bone.tail.distanceTo(bound),
        lessThan(0.01),
        reason: '$limb ends at $end',
      );
    }
    // And so the two elbows are held alike.
    expect(
      ragdoll.ragdoll.heldAs(ragdoll.bodyNamed('LowerArm.R')!).runtimeType,
      ragdoll.ragdoll.heldAs(ragdoll.bodyNamed('LowerArm.L')!).runtimeType,
    );
  });

  test('dropped, it lies down held together, its feet on its shins', () async {
    final h = await hero(at: Vector3(0.0, 0.5, 0.0));
    // Leaning over, so it falls rather than standing on its own stiffness.
    h.root.setRotation(Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), 0.6));
    final ragdoll = SkeletonRagdoll(
      skeleton: h.skeleton,
      meshWorld: h.mesh.worldMatrix,
      world: dynamics.native,
      dynamics: dynamics,
    );
    final torso = named(h.skeleton, 'Torso'), body = named(h.skeleton, 'Body');
    final apart = worldOf(torso).distanceTo(worldOf(body));
    final foot = named(h.skeleton, 'Foot.L'),
        shin = named(h.skeleton, 'LowerLeg.L');
    final reach = worldOf(foot).distanceTo(worldOf(shin));
    var steps = 0;
    while (!ragdoll.ragdoll.isAsleep && steps < 600) {
      dynamics.step(1.0 / 60.0);
      ragdoll.apply();
      steps++;
    }
    expect(ragdoll.ragdoll.isAsleep, isTrue, reason: 'awake after $steps');
    expect(worldOf(torso).distanceTo(worldOf(body)), closeTo(apart, 0.05));
    expect(worldOf(foot).distanceTo(worldOf(shin)), closeTo(reach, 0.05));
    // Lying: the head no higher than a body's thickness or two.
    expect(worldOf(named(h.skeleton, 'Head')).y, lessThan(0.5));
    for (final j in h.skeleton.joints) {
      expect(worldOf(j).y, greaterThan(-0.1), reason: j.name);
    }
  });

  test('it keeps the motion the animation had', () async {
    final h = await hero(at: Vector3(0.0, 0.1, 0.0));
    // A frame ago every joint stood 5 cm back along x: running at 3 m/s.
    final previous = <Matrix4>[
      for (final j in h.skeleton.joints)
        Matrix4.translation(Vector3(-0.05, 0.0, 0.0)) * j.worldMatrix
            as Matrix4,
    ];
    final ragdoll = SkeletonRagdoll(
      skeleton: h.skeleton,
      meshWorld: h.mesh.worldMatrix,
      world: dynamics.native,
      previous: previous,
    );
    final start = worldOf(named(h.skeleton, 'Body')).x;
    for (var i = 0; i < 20; i++) {
      dynamics.step(1.0 / 60.0);
    }
    ragdoll.apply();
    expect(worldOf(named(h.skeleton, 'Body')).x - start, greaterThan(0.4));
  });

  test('at half weight a joint is halfway between the animation and the '
      'ragdoll', () async {
    final h = await hero(at: Vector3(0.0, 1.0, 0.0));
    final ragdoll = SkeletonRagdoll(
      skeleton: h.skeleton,
      meshWorld: h.mesh.worldMatrix,
      world: dynamics.native,
    );
    for (var i = 0; i < 30; i++) {
      dynamics.step(1.0 / 60.0);
    }
    final hips = named(h.skeleton, 'Body');
    final animated = hips.localMatrix.getTranslation();
    ragdoll.apply();
    final limp = hips.localMatrix.getTranslation();
    hips.setPositionFrom(animated);
    ragdoll.apply(weight: 0.5);
    final half = hips.localMatrix.getTranslation();
    expect(half.distanceTo((animated + limp) * 0.5), lessThan(1e-4));
    expect(limp.distanceTo(animated), greaterThan(1e-4));
  });

  group('getting up', () {
    /// The hero leant by [lean] about x and dropped until it lies still,
    /// with the local matrix each joint stood with.
    Future<
      ({
        ({
          SceneNode root,
          Skeleton skeleton,
          SceneNode mesh,
          List<SceneNode> nodes,
        })
        h,
        SkeletonRagdoll ragdoll,
        List<Matrix4> standing,
        double headHeight,
      })
    >
    fallen(double lean, {double yaw = 0.0}) async {
      final h = await hero(at: Vector3(1.0, 0.5, -2.0));
      final standing = <Matrix4>[
        for (final j in h.skeleton.joints) j.localMatrix.clone(),
      ];
      final headHeight = worldOf(named(h.skeleton, 'Head')).y - 0.5;
      // Turned by [yaw] first, then leant about the world's x.
      h.root.setRotation(
        Quaternion.fromRotation(
          Matrix3.rotationX(lean)..multiply(Matrix3.rotationY(yaw)),
        ),
      );
      final ragdoll = SkeletonRagdoll(
        skeleton: h.skeleton,
        meshWorld: h.mesh.worldMatrix,
        world: dynamics.native,
        dynamics: dynamics,
      );
      var steps = 0;
      while (!ragdoll.ragdoll.isAsleep && steps < 600) {
        dynamics.step(1.0 / 60.0);
        ragdoll.apply();
        steps++;
      }
      expect(ragdoll.ragdoll.isAsleep, isTrue);
      return (
        h: h,
        ragdoll: ragdoll,
        standing: standing,
        headHeight: headHeight,
      );
    }

    test('leant forward it lies on its front, its head ahead', () async {
      final f = await fallen(0.6);
      final lying = f.ragdoll.lying();
      expect(lying.faceUp, isFalse);
      // The model faced +z and fell that way: the head lies further along
      // +z than the pelvis.
      expect(lying.headward.z, greaterThan(0.8));
      expect(lying.pelvis.y, lessThan(0.4));
      expect(
        Vector3(lying.pelvis.x - 1.0, 0.0, lying.pelvis.z + 2.0).length,
        lessThan(1.0),
        reason: 'where it fell',
      );
      // Facing +z is yaw π in an actor's terms, where nought looks along -z.
      expect(lying.headingYaw.abs(), closeTo(math.pi, 0.7));
      f.ragdoll.dispose();
    });

    test('turned round and leant its own way forward, it lies on its front, '
        'its head along -z', () async {
      final f = await fallen(-0.6, yaw: math.pi);
      final lying = f.ragdoll.lying();
      expect(lying.faceUp, isFalse);
      expect(lying.headward.z, lessThan(-0.8));
      expect(lying.headingYaw, closeTo(0.0, 0.7));
      f.ragdoll.dispose();
    });

    test('leant back it lies on its back, its head behind', () async {
      final f = await fallen(-0.6);
      final lying = f.ragdoll.lying();
      expect(lying.faceUp, isTrue);
      expect(lying.headward.z, lessThan(-0.8));
      f.ragdoll.dispose();
    });

    test('placed where it lies, it fades from the ragdoll to the animation '
        'and lets the bodies go', () async {
      final f = await fallen(0.6);
      final joints = f.h.skeleton.joints;
      final lyingAt = <Vector3>[for (final j in joints) worldOf(j)];
      final lying = f.ragdoll.lying();
      // The model stood up where the pelvis lies, facing where the head is;
      // the "clip" here is the pose it stood in.
      f.h.root
        ..setPositionFrom(Vector3(lying.pelvis.x, 0.0, lying.pelvis.z))
        ..setRotation(
          Quaternion.axisAngle(
            Vector3(0.0, 1.0, 0.0),
            math.atan2(lying.headward.x, lying.headward.z),
          ),
        );
      void animate() {
        for (final (i, j) in joints.indexed) {
          j.setLocalMatrix(f.standing[i]);
        }
      }

      final getUp = RagdollGetUp(f.ragdoll, seconds: 0.5);
      final bodies = dynamics.native.bodyCount;
      animate();
      getUp.step(1.0 / 60.0);
      // At first, all ragdoll: every body's joint where it lay.
      for (final i in <int>[
        for (var i = 0; i < joints.length; i++)
          if (f.ragdoll.bodyNamed(joints[i].name ?? '') != null) i,
      ]) {
        expect(
          worldOf(joints[i]).distanceTo(lyingAt[i]),
          lessThan(0.02),
          reason: joints[i].name,
        );
      }
      final head = named(f.h.skeleton, 'Head');
      final heights = <double>[];
      while (!getUp.isDone) {
        animate();
        getUp.step(1.0 / 60.0);
        heights.add(worldOf(head).y);
      }
      // Rising all the way, and done a half second on, the bodies gone.
      expect(heights.length, inInclusiveRange(29, 32));
      for (var i = 1; i < heights.length; i++) {
        expect(heights[i], greaterThanOrEqualTo(heights[i - 1] - 0.02));
      }
      expect(dynamics.native.bodyCount, lessThan(bodies));
      animate();
      expect(worldOf(head).y, closeTo(f.headHeight, 1e-3), reason: 'standing');
      expect(heights.first, lessThan(0.5 * f.headHeight), reason: 'from lying');
      expect(
        Vector3(
          worldOf(head).x - lying.pelvis.x,
          0.0,
          worldOf(head).z - lying.pelvis.z,
        ).length,
        lessThan(0.3),
        reason: 'standing where it lay',
      );
    });
  });
}
