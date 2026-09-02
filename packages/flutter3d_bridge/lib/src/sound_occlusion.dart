import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// How much of a sound survives the walls between its source and the ear.
///
/// **The dungeon had a wall test since its first commit, and it answered
/// yes or no.** One ray, one raycast, and a hit meant a third of the volume:
/// a torch behind a door and a torch three rooms away were the same torch.
/// This walks the ray on through the level — a hit, a step past it, the next
/// hit — and lets every obstacle take its share, so two walls are quieter
/// than one and a room away is quieter than a corridor's turn. Thickness is
/// not measured, and that is a property of the collision world rather than
/// an omission: a ray that begins inside a box is not stopped by that box,
/// so stepping into a wall's face and casting again finds the *next* wall's
/// face, not this wall's back. Every obstacle counts once, however thick.
///
/// The number is a gain factor for `AudioScene.occlusion`, and it is pure:
/// the same positions against the same walls give the same figure, on every
/// platform, so a replay sounds the way the run did.
///
/// What it does not do: bend round corners. Sound in a real dungeon reaches
/// you down the corridor whether or not a wall is in the straight line, and
/// a game that wanted that would route the sound along the navigation grid
/// and measure the path. This is the straight-line answer, which is the one
/// a player reads as "behind a wall".
final class SoundOcclusion {
  SoundOcclusion(
    this.world, {
    this.perObstacle = 0.5,
    this.maxObstacles = 4,
    this.floor = 0.06,
    this.mask = CollisionLayers.world,
  }) : assert(perObstacle > 0.0 && perObstacle < 1.0),
       assert(maxObstacles >= 1),
       assert(floor >= 0.0 && floor <= 1.0);

  final CollisionWorld world;

  /// What one wall lets through: half, which is roughly the ten decibels a
  /// closed door costs and reads as "muffled" rather than "gone".
  final double perObstacle;

  /// How many walls are counted before the ray gives up. Four walls is
  /// [floor] anyway, and every raycast past that is spent on silence.
  final int maxObstacles;

  /// The least a sound is reduced to while it is in range at all. Zero would
  /// let a wall silence a sound the attenuation still carries, which is a
  /// sound that stops and starts as the player rounds a corner.
  final double floor;

  /// Which collision layers stop sound.
  final int mask;

  final Vector3 _direction = Vector3.zero();
  final Vector3 _origin = Vector3.zero();
  final RayHit _hit = RayHit();

  /// How many obstacles the last [between] crossed.
  int get lastObstacles => _lastObstacles;
  int _lastObstacles = 0;

  /// The share of a sound at [from] that reaches an ear at [to]: 1 clear,
  /// down to [floor].
  ///
  /// Five centimetres past each hit before casting again, which is enough to
  /// be inside the wall it just met and not enough to skip a second wall
  /// standing right behind it.
  double between(Vector3 from, Vector3 to) {
    const step = 0.05;
    _direction
      ..setFrom(to)
      ..sub(from);
    var remaining = _direction.length;
    _lastObstacles = 0;
    if (remaining < 1e-3) return 1.0;
    _direction.scale(1.0 / remaining);
    _origin.setFrom(from);
    var factor = 1.0;
    while (_lastObstacles < maxObstacles && remaining > step) {
      if (!world.raycast(_origin, _direction, remaining, _hit, mask: mask)) {
        break;
      }
      _lastObstacles++;
      factor *= perObstacle;
      final advance = _hit.distance + step;
      _origin.addScaled(_direction, advance);
      remaining -= advance;
    }
    return factor < floor ? floor : factor;
  }
}
