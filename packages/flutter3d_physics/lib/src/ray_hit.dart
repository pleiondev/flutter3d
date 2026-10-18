import 'package:vector_math/vector_math.dart';

import 'collider.dart';

/// Where a ray met something.
///
/// A caller makes one with `RayHit()` for a cast to fill, and reuses it.
final class RayHit {
  /// How far along the ray the hit is, in metres; negative for no hit.
  double distance = -1.0;

  /// Where the ray met the surface, in world metres; zero for no hit.
  final Vector3 point = Vector3.zero();

  /// The surface's outward unit normal at [point]; zero for no hit.
  final Vector3 normal = Vector3.zero();

  /// The collider the ray met, or null for no hit.
  Collider? collider;

  /// Whether the ray met something: [distance] is not negative.
  bool get didHit => distance >= 0.0;

  /// Clears the hit back to no hit, for the next cast.
  void reset() {
    distance = -1.0;
    point.setZero();
    normal.setZero();
    collider = null;
  }
}
