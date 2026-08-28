import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// One thing a shot reached.
///
/// Named for the shot rather than for the ray, because a melee swing produces
/// these as well and it does not cast one.
final class ShotHit {
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

  final Vector3 point;
  final Vector3 normal;
  final double distance;

  /// After falloff. Zero when nothing was hit.
  final double damage;

  bool get struckSomething => collider != null;
}
