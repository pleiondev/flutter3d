import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// What this game's monsters are coloured, until they have models.
///
/// The capsule, the placement, the yaw and the death pose are the bridge's; the
/// three colours are the roster's, and the roster is this game's.
final class DungeonMonsters implements MonsterAppearance {
  const DungeonMonsters();

  @override
  Material materialFor(Monster monster) {
    // Brightened for a moment after a hit, which is the cheapest damage
    // feedback there is and the one whose absence makes a fight feel
    // unresponsive.
    if (monster.state == MonsterState.hurt) return _struck;
    return _materials[monster.def.name] ?? _unknown;
  }

  /// Materials by kind, so a runner and a tank are distinguishable at a glance
  /// in a dark corridor — which is the whole job of a placeholder.
  static final Map<String, Material> _materials = <String, Material>{
    'runner': Material(
      baseColor: Vector4(0.52, 0.20, 0.18, 1.0),
      roughness: 0.7,
    ),
    'shooter': Material(
      baseColor: Vector4(0.22, 0.32, 0.52, 1.0),
      roughness: 0.6,
    ),
    'tank': Material(
      baseColor: Vector4(0.30, 0.28, 0.16, 1.0),
      roughness: 0.85,
    ),
  };

  static final Material _struck = Material(
    baseColor: Vector4(1.4, 0.9, 0.8, 1.0),
    roughness: 0.6,
  );

  /// Shared rather than built per call: [MonsterAppearance.materialFor] runs for
  /// every monster every frame, and a default that allocated would allocate once
  /// a frame per monster.
  static final Material _unknown = Material();
}
