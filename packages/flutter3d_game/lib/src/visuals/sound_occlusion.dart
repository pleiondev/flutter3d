import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart'
    show MatterState, PropertyLaw;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
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
/// ## What a wall is made of
///
/// An obstacle whose collider has a material with an acoustic group
/// (`Collider.material`, `PhysicalMaterial.acoustic`) lets through what its
/// surface does not reflect, and no more: the share of the sound's energy
/// that is absorbed or passes on is the most that can reach the far side.
///
/// - **A measured absorption** (`AcousticProperties.absorption`) is read as
///   the mean over the 250, 500, 1 000 and 2 000 Hz bands, the speech range
///   the noise reduction coefficient averages (unrounded here): concrete
///   0.016 of the energy, gypsum board 0.065, mineral wool 0.78.
/// - **Without one, its impedance against the air's**: at normal incidence
///   `4·Z·Z₀ / (Z + Z₀)²` of the energy is not reflected, with Z its
///   characteristic impedance (`AcousticProperties.impedance`, or its
///   density times its speed of sound) and Z₀ the air's of the collision
///   world (`WorldProperties.airDensity` times `speedOfSound`). A dense
///   solid reflects nearly all of it: a steel wall leaves 0.004 %, and the
///   [floor] is what is heard.
///
/// Each law is read at the obstacle's state when [stateOf] knows it, and at
/// the material's reference state otherwise. The energy share becomes a
/// gain as its square root, as the units of the mix are amplitudes. An
/// obstacle with no material, or none of these numbers, lets through
/// [perObstacle].
///
/// What it does not do: bend round corners. Sound in a real dungeon reaches
/// you down the corridor whether or not a wall is in the straight line, and
/// a game that wanted that would route the sound along the navigation grid
/// and measure the path. This is the straight-line answer, which is the one
/// a player reads as "behind a wall". Nor does it weigh a wall's thickness
/// or the bands apart: the share is one number per obstacle, and the
/// dulling the scene hands a backend follows from it.
final class SoundOcclusion {
  /// Occlusion measured by rays through [world] against [mask].
  ///
  /// Asserts [perObstacle] is strictly between nought and one,
  /// [maxObstacles] is at least one and [floor] is a fraction from nought
  /// to one.
  SoundOcclusion(
    this.world, {
    this.perObstacle = 0.5,
    this.maxObstacles = 4,
    this.floor = 0.06,
    this.mask = CollisionLayers.world,
    this.stateOf,
  }) : assert(perObstacle > 0.0 && perObstacle < 1.0),
       assert(maxObstacles >= 1),
       assert(floor >= 0.0 && floor <= 1.0);

  /// The world rays are cast through. Its air ([CollisionWorld.properties])
  /// is what an obstacle's acoustic impedance is weighed against.
  final CollisionWorld world;

  /// What one wall of nothing in particular lets through, as a share of the
  /// gain: half, −6 dB, which reads as "muffled" rather than "gone". For an
  /// obstacle with no material or no acoustic numbers; one made of
  /// something lets through what its material says.
  ///
  /// A closed door costs nearer ten decibels, about 0.32; this is gentler,
  /// because a game wall stands for whatever is between, and two of them
  /// already make a quarter.
  final double perObstacle;

  /// The state an obstacle's material is in now — warm, wet — or null when
  /// it is not known, for the laws of its acoustic group to be read at.
  /// Null, the default, reads every obstacle at its material's reference
  /// state.
  final MatterState? Function(Collider obstacle)? stateOf;

  /// How many walls are counted before the ray gives up. Four walls is
  /// [floor] anyway, and every raycast past that is spent on silence.
  final int maxObstacles;

  /// The least a sound is reduced to while it is in range at all. Zero would
  /// let a wall silence a sound the attenuation still carries, which is a
  /// sound that stops and starts as the player rounds a corner. A fraction of
  /// the sound's gain, nought to one.
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
      factor *= _through(_hit.collider);
      final advance = _hit.distance + step;
      _origin.addScaled(_direction, advance);
      remaining -= advance;
    }
    return factor < floor ? floor : factor;
  }

  /// The share of a sound's gain [obstacle] lets through: see the class.
  double _through(Collider? obstacle) {
    final material = obstacle?.material;
    final acoustic = material?.acoustic;
    if (material == null || acoustic == null) return perObstacle;
    final absorption = acoustic.absorption;
    if (absorption != null) {
      // 250, 500, 1 000 and 2 000 Hz of `AcousticProperties.bands`.
      final speech =
          (absorption[1] + absorption[2] + absorption[3] + absorption[4]) / 4.0;
      return math.sqrt(speech);
    }
    final state = stateOf?.call(obstacle!) ?? material.referenceState;
    final impedance =
        acoustic.impedance?.at(state) ??
        switch ((material.mechanical?.density, acoustic.speedOfSound)) {
          (final PropertyLaw density, final PropertyLaw speed) =>
            density.at(state) * speed.at(state),
          _ => null,
        };
    if (impedance == null) return perObstacle;
    final air = world.properties;
    final z0 = air.airDensity * air.speedOfSound;
    final sum = impedance + z0;
    return math.sqrt(4.0 * impedance * z0 / (sum * sum));
  }
}
