import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// What the monsters look like, until they have models.
///
/// Capsules the size of their own collision shapes, which is deliberate rather
/// than lazy: a placeholder that matches the hitbox exactly means every
/// complaint about a shot that should have landed is a complaint about the
/// aiming and not about the art being the wrong size. When rigged models
/// arrive, the mesh changes here and nothing else does.
///
/// One mesh per kind, uploaded once and shared by every node — the only form of
/// instancing flutter_gpu offers.
final class MonsterVisuals {
  MonsterVisuals(this.scene);

  final Scene scene;

  final Map<String, GpuMesh> _meshes = <String, GpuMesh>{};
  final Map<Monster, MeshNode> _nodes = <Monster, MeshNode>{};

  /// Materials by kind, so a runner and a tank are distinguishable at a glance
  /// in a dark corridor — which is the whole job of a placeholder.
  static final Map<String, engine.Material> _materials =
      <String, engine.Material>{
    'runner': engine.Material(
      baseColor: Vector4(0.52, 0.20, 0.18, 1.0),
      roughness: 0.7,
    ),
    'shooter': engine.Material(
      baseColor: Vector4(0.22, 0.32, 0.52, 1.0),
      roughness: 0.6,
    ),
    'tank': engine.Material(
      baseColor: Vector4(0.30, 0.28, 0.16, 1.0),
      roughness: 0.85,
    ),
  };

  /// Brightened for a moment after a hit, which is the cheapest damage feedback
  /// there is and the one whose absence makes a fight feel unresponsive.
  static final engine.Material _struck = engine.Material(
    baseColor: Vector4(1.4, 0.9, 0.8, 1.0),
    roughness: 0.6,
  );

  void add(Monster monster) {
    final mesh = _meshes.putIfAbsent(
      monster.def.name,
      () => GpuMesh.upload(
        CapsuleShape(
          radius: monster.def.radius,
          height: monster.def.height,
        ).build(),
      ),
    );

    final node = MeshNode(
      mesh,
      _materials[monster.def.name] ?? engine.Material(),
      name: monster.def.name,
    );
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

      if (monster.state == MonsterState.dead) {
        // Laid on its side and sunk, which reads as a corpse without needing a
        // death animation. It stays: an emptied corridor should show what
        // happened in it.
        node
          ..setPosition(position.x, position.y - monster.def.height * 0.32, position.z)
          ..setRotation(
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2.0),
          );
        node.material = _materials[monster.def.name] ?? engine.Material();
        continue;
      }

      node
        ..setPositionFrom(position)
        ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), monster.yaw));
      node.material = monster.state == MonsterState.hurt
          ? _struck
          : (_materials[monster.def.name] ?? engine.Material());
    }
  }
}
