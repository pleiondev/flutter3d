import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'shared_meshes.dart';

/// What a monster is made of, which is the one thing the bridge cannot know.
///
/// Called every frame with the monster's current state, so a game is free to
/// answer with a shared material per kind, a brightened one for a monster that
/// was just hit, or something built on the spot.
abstract interface class ActorAppearance {
  /// The material to draw [monster] with right now.
  Material materialFor(Actor actor);

  /// A key that two actors share exactly when they should share one capsule
  /// mesh. The game's own answer, because the engine has no idea what makes
  /// two of its actors the same kind of thing.
  String meshKeyFor(Actor actor);
}

/// Where the monsters are, and which way they are facing.
///
/// Capsules the size of their own collision shapes, which is deliberate rather
/// than lazy: a placeholder that matches the hitbox exactly means every
/// complaint about a shot that should have landed is a complaint about the
/// aiming and not about the art being the wrong size. When rigged models
/// arrive, the mesh changes here and nothing else does.
///
/// One mesh per kind, uploaded once and shared by every node — the only form of
/// instancing flutter_gpu offers. What colour they are is an [ActorAppearance];
/// this owns the shape, the placement and the death pose.
final class ActorVisuals {
  ActorVisuals(
    this.scene, {
    required this.appearance,
    required GraphicsDevice device,
  }) : _meshes = SharedMeshes(device);

  final Scene scene;

  /// The game's half: one material per monster and per state.
  final ActorAppearance appearance;

  final SharedMeshes _meshes;
  final Map<Actor, MeshNode> _nodes = <Actor, MeshNode>{};

  void add(Actor actor) {
    // Straight off the body, so this works for anything with one. It used to
    // read a `MonsterDef`, which is how the renderer's bridge came to depend on
    // a shooter's idea of what walks about in a level.
    final radius = actor.body.halfExtents.x;
    final height = actor.body.halfExtents.y * 2.0;
    final key = appearance.meshKeyFor(actor);
    final mesh = _meshes.shape(
      'actor:$key',
      () => CapsuleShape(radius: radius, height: height),
    );

    final node = MeshNode(mesh, appearance.materialFor(actor), name: key);
    scene.add(node);
    _nodes[actor] = node;
  }

  /// Moves every node to its actor.
  ///
  /// Called once per frame rather than per simulation step: this is display,
  /// and the simulation does not care where the capsules are.
  void sync() {
    for (final entry in _nodes.entries) {
      final actor = entry.key;
      final node = entry.value;
      final position = actor.position;

      node.material = appearance.materialFor(actor);

      if (!actor.isAlive) {
        // Laid on its side and sunk, which reads as a corpse without needing a
        // death animation. It stays: an emptied corridor should show what
        // happened in it.
        node
          ..setPosition(
            position.x,
            position.y - actor.body.halfExtents.y * 0.64,
            position.z,
          )
          ..setRotation(
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2.0),
          );
        continue;
      }

      node
        ..setPositionFrom(position)
        ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), actor.yaw));
    }
  }
}
