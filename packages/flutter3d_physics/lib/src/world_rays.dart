import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'ray_hit.dart';

/// A world's rays, cast elsewhere — P9: the physics core answers them
/// through what it mirrors of the world.
///
/// Set as `CollisionWorld.rays`, it answers every `CollisionWorld.raycast`
/// that does not ask for triggers — a shot, a monster's line of sight, a
/// foot's floor — which the core does not hold and the world's own walk
/// still answers.
abstract interface class WorldRays {
  /// The nearest solid thing a ray from [origin] along [direction] meets
  /// within [maxDistance], on a layer in [mask], not [ignore], into [out].
  bool raycast(
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    RayHit out, {
    required int mask,
    Collider? ignore,
  });
}
