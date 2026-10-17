import 'dart:math' as math;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

/// The colour of the sky in the direction asked about.
typedef SkyColor = LinearColor Function(SkyLook look);

/// Where a [SkyColor] is being asked to look.
///
/// **One object rather than a bare vector, so this can grow.** A function type
/// is frozen the day it is published: telling a sky what time it is, or where
/// the sun is, means widening `LinearColor Function(Vector3)` and breaking every
/// sky anybody has written. Adding a field here does not.
///
/// **Reused between calls, never held.** Painting a dome asks this once per
/// vertex and a per-pixel sky would ask it far more often, so the caller keeps
/// one and rewrites it; [direction] is scratch inside scratch. Read it, do not
/// keep it. `paintSky` is where the one instance lives.
final class SkyLook {
  SkyLook();

  /// One look, allocated. For a caller that asks once — a game tinting its fog
  /// or picking a light off the sky — rather than for a loop over a mesh.
  SkyLook.at(Vector3 direction) {
    this.direction.setFrom(direction);
  }

  /// A unit vector. Normalised before the call, so an implementation cannot
  /// forget to.
  final Vector3 direction = Vector3.zero();
}

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
    this.sunColor = const LinearColor(1.0, 0.95, 0.86),
    this.glowExponent = 6.0,
    this.glowStrength = 0.3,
  }) : directionToSun = (directionToSun ?? Vector3(0.34, 0.56, 0.76))
           .normalized();

  /// Straight up, level with the horizon, and straight down. Linear.
  ///
  /// [nadir] is not the ground: it is what the sky reads as when the camera
  /// looks down at nothing — over the edge of a drop, mostly — which is haze,
  /// and haze is darker.
  final LinearColor zenith;
  final LinearColor horizon;
  final LinearColor nadir;

  /// A unit vector pointing **at** the sun. A directional light points the
  /// other way, so a scene built from one preset negates this for the light.
  final Vector3 directionToSun;
  final LinearColor sunColor;

  /// The wide scattering lobe: how tight it is, and how bright.
  ///
  /// Not a sun disc. A disc is about two degrees across and a dome that could
  /// resolve one would need rings a fraction of a degree apart — at the 24 or
  /// so this uses, the finest thing expressible is about seven degrees. What is
  /// here is the lobe around the sun, which is the part that reads at all.
  final double glowExponent;

  /// A unitless multiplier on [sunColor] at the lobe's peak.
  final double glowStrength;

  /// The gradient as a [SkyColor], ready for `paintSky`.
  SkyColor get color => (SkyLook look) {
    final y = look.direction.y.clamp(-1.0, 1.0);
    final far = y >= 0.0 ? zenith : nadir;
    // Smoothstep rather than linear, so the band near the horizon is wide.
    // Half of what anybody notices about a sky happens in the first fifteen
    // degrees above it, and a straight ramp spends its range on the part
    // nobody looks at.
    final t = y.abs() * y.abs() * (3.0 - 2.0 * y.abs());

    final towards = look.direction.dot(directionToSun);
    final lobe = towards <= 0.0
        ? 0.0
        : glowStrength * math.pow(towards, glowExponent).toDouble();

    return LinearColor(
      horizon.r + (far.r - horizon.r) * t + sunColor.r * lobe,
      horizon.g + (far.g - horizon.g) * t + sunColor.g * lobe,
      horizon.b + (far.b - horizon.b) * t + sunColor.b * lobe,
    );
  };
}
