import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Gravity that is not the same everywhere: a uniform part, and the pull of
/// every [Attractor] in it, added.
///
/// **Newton's law for each**: g = μ·r̂/r², μ = G·M the attractor's standard
/// gravitational parameter, pointing at it. Inside an attractor of
/// [Attractor.radius], uniform in density, it falls off to nought at the
/// middle as μ·r/R³ (the shell outside pulls equally every way), so a drop
/// that passes through one is not flung off by a pull growing without
/// bound.
///
/// A liquid asks it where it is: each vessel's surface lies across its own
/// local gravity, and each drop and parcel of a stream falls by the gravity
/// at its own place.
final class GravityField {
  GravityField({Vector3? uniform, List<Attractor>? attractors})
    : uniform = uniform ?? Vector3.zero(),
      attractors = attractors ?? [];

  /// Metres per second squared, everywhere.
  final Vector3 uniform;

  final List<Attractor> attractors;

  /// The gravity at [point]: a vector of the caller's own.
  Vector3 at(Vector3 point) {
    final g = uniform.clone();
    for (final a in attractors) {
      final dx = a.position.x - point.x;
      final dy = a.position.y - point.y;
      final dz = a.position.z - point.z;
      final r2 = dx * dx + dy * dy + dz * dz;
      if (r2 <= 0.0) continue;
      final r = math.sqrt(r2);
      final k = r < a.radius
          ? a.mu / (a.radius * a.radius * a.radius)
          : a.mu / (r2 * r);
      g
        ..x += dx * k
        ..y += dy * k
        ..z += dz * k;
    }
    return g;
  }
}

/// A mass that pulls: where it is, how hard, and how big.
final class Attractor {
  Attractor({required this.position, required this.mu, this.radius = 0.0});

  /// An attractor of [mass] kilograms, by Newton's constant.
  factory Attractor.ofMass({
    required Vector3 position,
    required double mass,
    double radius = 0.0,
  }) => Attractor(
    position: position,
    mu: gravitationalConstant * mass,
    radius: radius,
  );

  /// Newton's G, m³/(kg·s²) (CODATA 2018).
  static const double gravitationalConstant = 6.67430e-11;

  /// Where it is; move it and the field moves with it.
  final Vector3 position;

  /// G·M, cubic metres per second squared.
  final double mu;

  /// Metres: inside it the pull falls to nought at the middle.
  final double radius;
}
