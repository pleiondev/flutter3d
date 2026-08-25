import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The colour of the sky in [direction], which is a unit vector.
///
/// Normalised before the call so an implementation cannot forget to.
typedef SkyColour = Vector4 Function(Vector3 direction);

/// The cheapest description of a sky that still reads as one: three stops and a
/// scattering lobe around the sun.
///
/// The arithmetic lives in a class of its own rather than inside the dome
/// because it is the part that outlives it — a per-pixel sky would evaluate
/// exactly this, and a game that wants to know what colour the air is (to tint
/// its fog, to pick a light) wants to ask without owning a mesh.
final class SkyGradient {
  SkyGradient({
    required this.zenith,
    required this.horizon,
    required this.nadir,
    Vector3? directionToSun,
    Vector3? sunColour,
    this.glowExponent = 6.0,
    this.glowStrength = 0.3,
  })  : directionToSun =
            (directionToSun ?? Vector3(0.34, 0.56, 0.76)).normalized(),
        sunColour = sunColour ?? Vector3(1.0, 0.95, 0.86);

  /// Straight up, level with the horizon, and straight down. Linear.
  ///
  /// [nadir] is not the ground: it is what the sky reads as when the camera
  /// looks down at nothing — over the edge of a drop, mostly — which is haze,
  /// and haze is darker.
  final Vector3 zenith;
  final Vector3 horizon;
  final Vector3 nadir;

  /// A unit vector pointing **at** the sun. A directional light points the
  /// other way, so a scene built from one preset negates this for the light.
  final Vector3 directionToSun;
  final Vector3 sunColour;

  /// The wide scattering lobe: how tight it is, and how bright.
  ///
  /// Not a sun disc. A disc is about two degrees across and a dome that could
  /// resolve one would need rings a fraction of a degree apart — at the 24 or
  /// so this uses, the finest thing expressible is about seven degrees. What is
  /// here is the lobe around the sun, which is the part that reads at all.
  final double glowExponent;
  final double glowStrength;

  /// The gradient as a [SkyColour], ready for `paintSky`.
  SkyColour get colour => (Vector3 direction) {
        final y = direction.y.clamp(-1.0, 1.0);
        final far = y >= 0.0 ? zenith : nadir;
        // Smoothstep rather than linear, so the band near the horizon is wide.
        // Half of what anybody notices about a sky happens in the first fifteen
        // degrees above it, and a straight ramp spends its range on the part
        // nobody looks at.
        final t = y.abs() * y.abs() * (3.0 - 2.0 * y.abs());

        final towards = direction.dot(directionToSun);
        final lobe = towards <= 0.0
            ? 0.0
            : glowStrength * math.pow(towards, glowExponent).toDouble();

        return Vector4(
          horizon.x + (far.x - horizon.x) * t + sunColour.x * lobe,
          horizon.y + (far.y - horizon.y) * t + sunColour.y * lobe,
          horizon.z + (far.z - horizon.z) * t + sunColour.z * lobe,
          1.0,
        );
      };
}
