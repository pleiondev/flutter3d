// A skinned character gone limp — N1: the hero of flutter3d's fixtures, a
// Quaternius rig two centimetres tall under a node that makes it 1.8 m,
// built into scene nodes from its glTF, its skeleton made a ragdoll by the
// profile of names, dropped on a floor, and its bodies written back into
// its joints — the pose kept at once, the figure held together lying down,
// the feet carried by the shins, a blend halfway back to the animation.
import 'package:flutter3d_core/flutter3d_core.dart';
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
}
