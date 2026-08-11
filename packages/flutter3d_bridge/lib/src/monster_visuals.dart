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
abstract interface class MonsterAppearance {
  /// The material to draw [monster] with right now.
  Material materialFor(Monster monster);
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
/// instancing flutter_gpu offers. What colour they are is a [MonsterAppearance];
/// this owns the shape, the placement and the death pose.
final class MonsterVisuals {
  MonsterVisuals(
    this.scene, {
    required this.appearance,
    required GraphicsDevice device,
  }) : _meshes = SharedMeshes(device);

  final Scene scene;

  /// The game's half: one material per monster and per state.
  final MonsterAppearance appearance;

  final SharedMeshes _meshes;
  final Map<Monster, MeshNode> _nodes = <Monster, MeshNode>{};

  void add(Monster monster) {
    final def = monster.def;
    final mesh = _meshes.shape(
      'monster:${def.name}',
      () => CapsuleShape(radius: def.radius, height: def.height),
    );

    final node = MeshNode(mesh, appearance.materialFor(monster), name: def.name);
    scene.add(node);
    _nodes[monster] = node;
  }

  /// Moves every node to its monster.
  ///
  /// Called once per frame rather than per simulation step: this is display,
  /// and the simulation does not care where the capsules are.
  void sync() {
    for (final entry in _nodes.entries) {
      final monster = entry.key;
      final node = entry.value;
      final position = monster.position;

      node.material = appearance.materialFor(monster);

      if (monster.state == MonsterState.dead) {
        // Laid on its side and sunk, which reads as a corpse without needing a
        // death animation. It stays: an emptied corridor should show what
        // happened in it.
        node
          ..setPosition(
            position.x,
            position.y - monster.def.height * 0.32,
            position.z,
          )
          ..setRotation(
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2.0),
          );
        continue;
      }

      node
        ..setPositionFrom(position)
        ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), monster.yaw));
    }
  }
}
