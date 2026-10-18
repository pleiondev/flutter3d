import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

/// One thing a shot reached.
///
/// Named for the shot rather than for the ray, because a melee swing produces
/// these as well and it does not cast one.
final class ShotHit {
  /// A hit on [collider] at [point], [distance] metres along, for [damage];
  /// [point] and [normal] are copied.
  ShotHit({
    required this.collider,
    required Vector3 point,
    required Vector3 normal,
    required this.distance,
    required this.damage,
  }) : point = point.clone(),
       normal = normal.clone();

  /// What was struck. Null when the ray reached its range without meeting
  /// anything, which still matters: a tracer has to end somewhere.
  final Collider? collider;

  /// Where the shot struck, in world metres, or where it ran out of range
  /// when nothing was hit.
  final Vector3 point;

  /// The surface's normal where it was struck, for a decal or a spark to
  /// face; back along the shot when nothing was struck.
  final Vector3 normal;

  /// How far along the ray it was struck, in metres.
  final double distance;

  /// After falloff. Zero when nothing was hit.
  /// In hit points (unitless).
  final double damage;

  /// Whether the shot met anything before its range ran out.
  bool get didStrikeSomething => collider != null;
}
