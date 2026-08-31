import 'package:vector_math/vector_math.dart';

import 'collider.dart';

/// Where a ray met something.
final class RayHit {
  double distance = -1.0;
  final Vector3 point = Vector3.zero();
  final Vector3 normal = Vector3.zero();
  Collider? collider;

  bool get hit => distance >= 0.0;

  void reset() {
    distance = -1.0;
    point.setZero();
    normal.setZero();
    collider = null;
  }
}
