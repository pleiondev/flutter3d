import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'blast.dart';

/// A rocket in flight: where it is, where it is going, and how long it has.
///
/// **The first component in this repository**, and the first thing to move out
/// of a hand-written pool. It was a `Projectile` with an `alive` flag in a
/// fixed array, which is a pool emulating what spawn and despawn already are.
///
/// Everything on it is saved, which is the rule a component earns its place
/// by: a type either writes itself down or says why it does not.
final class InFlight {
  InFlight({
    required Vector3 position,
    required Vector3 velocity,
    required this.blast,
    required this.life,
  }) : position = position.clone(),
       velocity = velocity.clone();

  final Vector3 position;
  final Vector3 velocity;

  /// What it does when it arrives.
  final Blast blast;

  /// Seconds left before it gives up and detonates.
  double life;

  Map<String, Object?> toJson() => <String, Object?>{
    'at': <double>[position.x, position.y, position.z],
    'velocity': <double>[velocity.x, velocity.y, velocity.z],
    'life': life,
    'blast': <String, double>{
      'radius': blast.radius,
      'damage': blast.damage,
      'minimumFraction': blast.minimumFraction,
      'knockback': blast.knockback,
    },
  };

  /// Reads one rocket back, or nothing if the row cannot be read.
  ///
  /// **This used to throw**, alone in the repository: `row['life']! as num` on
  /// a save written before the field existed is a `TypeError` out of a restore,
  /// which is a game that will not load rather than a game that loads without
  /// one rocket. `Snapshot`'s own rule says the opposite — a missing field
  /// takes its default — and `SnapshotFields` is now where that rule lives.
  static InFlight? fromJson(Object? data) {
    if (data is! Map) return null;
    final row = data.cast<String, Object?>();
    final blast = row.object('blast');
    if (blast == null) return null;

    final at = Vector3.zero();
    final velocity = Vector3.zero();
    if (!row.vectorInto('at', at)) return null;
    row.vectorInto('velocity', velocity);

    return InFlight(
      position: at,
      velocity: velocity,
      life: row.number('life'),
      blast: Blast(
        radius: blast.number('radius'),
        damage: blast.number('damage'),
        minimumFraction: blast.number('minimumFraction'),
        knockback: blast.number('knockback'),
      ),
    );
  }
}

/// Who fired it, so the sweep can ignore the muzzle it came out of.
///
/// **The example `EcsWorld.exclude` exists for.** A `Collider` is a live object
/// in one process's collision world; writing it into a save would mean
/// inventing an identity scheme for every body in the level to serve a field
/// that stops mattering the moment the rocket has cleared its own launcher.
/// So it is declared as not saved, with the reason, rather than quietly left
/// out of a codec — which is what the hand-written version did.
final class FiredBy {
  const FiredBy(this.collider);
  final Collider collider;
}

/// Where and what an explosion was.
final class Detonation {
  Detonation({
    required Vector3 position,
    required Vector3 normal,
    required this.blast,
    required Map<Collider, double> damage,
    required this.owner,
  }) : position = position.clone(),
       normal = normal.clone(),
       damage = Map<Collider, double>.unmodifiable(damage);

  final Vector3 position;

  /// Surface the rocket struck, or the direction it came from when it timed
  /// out in the open. Effects need somewhere to face.
  final Vector3 normal;

  final Blast blast;

  /// Everything hurt, and by how much. Includes the shooter.
  final Map<Collider, double> damage;

  final Collider? owner;
}
