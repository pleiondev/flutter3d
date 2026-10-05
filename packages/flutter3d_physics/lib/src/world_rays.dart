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
/// Something that keeps a copy of a world — the physics core's mirror — told
/// at the end of every step, in [CollisionWorld.update], to bring its copy to
/// where everything now is.
///
/// **So a snapshot does not depend on what was asked between steps.** A
/// mover moved after the core stepped was put in place by whichever query
/// came first — a camera's ray between two frames, or the next step's
/// character — and a run that drew frames saved other bytes than one that
/// did not. Brought in place here, inside the step, it is in place in every
/// run before anything saves or asks.
abstract interface class WorldMirror {
  void mirror();
}

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
