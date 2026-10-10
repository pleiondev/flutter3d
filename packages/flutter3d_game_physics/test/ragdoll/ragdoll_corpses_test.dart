/// Actors that fall as bodies when they die.
///
///     flutter test test/ragdoll_corpses_test.dart
///
/// The hero of the engine's fixtures, a skinned rig the ragdoll profile
/// knows, dies standing on a floor: its skeleton is taken over, falls and
/// lies down; a push from one side throws it the other way; a model with no
/// skeleton is left to its death clip; and taking a body out lets it go.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game_physics/ragdoll.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The fixtures' hero as an instance standing 1.8 m tall on the origin.
Future<ModelInstance> _hero() async {
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
  final skinned = <int>[
    for (var i = 0; i < doc.nodes.length; i++)
      if (doc.nodes[i].surfaces.any((s) => doc.surfaces[s].skinIndex != null))
        i,
  ].first;
  final heights = <double>[
    for (var i = 0; i < skeleton.jointCount; i++)
      (nodes[skinned].worldMatrix * skeleton.bindPoseOf(i) as Matrix4)
          .getTranslation()
          .y,
  ];
  final tall =
      heights.reduce((a, b) => a > b ? a : b) -
      heights.reduce((a, b) => a < b ? a : b);
  root
    ..setScale(1.8 / tall, 1.8 / tall, 1.8 / tall)
    ..setPositionFrom(Vector3(0.0, 0.3, 0.0));
  final mesh = MeshNode(
    DeviceMesh.upload(FakeBackend(), CuboidShape().build()),
    RenderMaterial(name: 'skin'),
    name: 'body',
  )..skeleton = skeleton;
  nodes[skinned].add(mesh);
  return ModelInstance(
    root: root,
    nodes: nodes,
    meshes: <MeshNode>[mesh],
    skeletons: <Skeleton>[skeleton],
    player: null,
  );
}

/// A floor forty metres square, its top at nought.
CollisionWorld _floor() =>
    CollisionWorld()..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));

Actor _actor(CollisionWorld world) =>
    ActorSystem(world: world, random: GameRandom(1)).spawn(name: 'fallen');

Vector3 _chest(RagdollCorpses corpses, Actor actor) {
  final ragdoll = corpses.ragdollOf(actor)!;
  return ragdoll.ragdoll.poseOf(ragdoll.bodyNamed('Torso')!).position;
}

void main() {
  test('a model with no skeleton is left to its death clip', () {
    final world = _floor();
    final corpses = RagdollCorpses(world);
    addTearDown(corpses.dispose);
    final bare = ModelInstance(
      root: SceneNode(name: 'crate'),
      nodes: const <SceneNode>[],
      meshes: const <MeshNode>[],
      skeletons: const <Skeleton>[],
      player: null,
    );
    // Mutation: take every model over, and a crate that "dies" is handed to
    // a ragdoll it has no bones for.
    expect(corpses.begin(_actor(world), bare), isFalse);
    expect(corpses.count, 0);
  });

  test('a skeleton is taken over, falls and lies down', () async {
    final world = _floor();
    final corpses = RagdollCorpses(world);
    addTearDown(corpses.dispose);
    final actor = _actor(world);
    expect(corpses.begin(actor, await _hero()), isTrue);
    expect(corpses.count, 1);
    final standing = _chest(corpses, actor).y;
    for (var i = 0; i < 180; i++) {
      corpses.step(1.0 / 60.0);
    }
    final lying = _chest(corpses, actor).y;
    // Mutation: step the core only when the frame owes a whole second, and
    // the body stands where it died.
    expect(lying, lessThan(standing - 0.5));
    // Mutation: a world with no floor in it, and the body falls for ever.
    expect(lying, greaterThan(-0.2));
  });

  test('the killing blow throws the body away from where it came', () async {
    Future<double> fallen({Vector3? from}) async {
      final world = _floor();
      final corpses = RagdollCorpses(world, pushedFrom: () => from);
      addTearDown(corpses.dispose);
      final actor = _actor(world);
      corpses.begin(actor, await _hero());
      for (var i = 0; i < 90; i++) {
        corpses.step(1.0 / 60.0);
      }
      return _chest(corpses, actor).x;
    }

    final still = await fallen();
    final pushed = await fallen(from: Vector3(-5.0, 1.0, 0.0));
    // Mutation: push towards where the blow came from, and the body falls
    // into the one who struck it.
    expect(pushed, greaterThan(still + 0.3));
  });

  test('a rewind to before a death takes the body away', () async {
    final world = _floor();
    final corpses = RagdollCorpses(world);
    addTearDown(corpses.dispose);
    final actors = ActorSystem(world: world, random: GameRandom(1));
    final first = actors.spawn(name: 'first');
    final second = actors.spawn(name: 'second');
    corpses.begin(first, await _hero());
    final part = corpses.snapshotPart();
    final saved = part.capture();

    corpses.begin(second, await _hero());
    for (var i = 0; i < 30; i++) {
      corpses.step(1.0 / 60.0);
    }
    part.restore(saved, part.version);

    // Mutation: restore nothing, and the second lies dead beside itself
    // standing again.
    expect(corpses.count, 1);
    expect(corpses.ragdollOf(first), isNotNull);
    expect(corpses.ragdollOf(second), isNull);
  });

  test('a body taken out of the scene is let go', () async {
    final world = _floor();
    final corpses = RagdollCorpses(world);
    addTearDown(corpses.dispose);
    final actor = _actor(world);
    corpses.begin(actor, await _hero());
    corpses.end(actor);
    // Mutation: forget the map entry without disposing, or keep it, and a
    // level of the dead keeps every body it ever had.
    expect(corpses.count, 0);
    expect(corpses.ragdollOf(actor), isNull);
  });
}
