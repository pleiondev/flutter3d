import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_shape.dart';
import 'ray_hit.dart';
import 'sweep_hit.dart';

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
///
/// **Extended outside this package: an `abstract base mixin class`** (decision 5
/// of `tasks/1.0-api-review.md`), so a member added in a minor arrives with a
/// default body and every implementation keeps compiling.
///
/// A mixin class, so a backend's dynamics that also mirrors the world
/// extends `RigidDynamics` and mixes this in.
abstract base mixin class WorldMirror {
  void mirror();
}

/// **Extended outside this package: an `abstract base class`** (decision 5
/// of `tasks/1.0-api-review.md`), so a member added in a minor arrives with a
/// default body and every implementation keeps compiling.
abstract base class WorldRays {
  const WorldRays();

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

/// A world's sweeps, cast elsewhere: the physics core moving a shape
/// through what it mirrors of the world.
///
/// Set as `CollisionWorld.sweeps`, it answers every `CollisionWorld.sweep`
/// that brings no `ContactFilter` — a filter is a Dart function asked about
/// each contact as the sweep finds it, which the core cannot call — and the
/// world's own walk answers those.
///
/// As the reference sweeps it: the shape's bounding box, and a shape that
/// starts inside something meets nothing — getting out is
/// `CollisionWorld.depenetrate`'s job.
///
/// **Extended outside this package: an `abstract base class`** (decision 5
/// of `tasks/1.0-api-review.md`), so a member added in a minor arrives with a
/// default body and every implementation keeps compiling.
abstract base class WorldSweeps {
  const WorldSweeps();

  /// The first solid thing [shape] meets moved from [origin] by [delta], on
  /// a layer in [mask], not [ignore], into [out]; whether it met one.
  bool sweep(
    CollisionShape shape,
    Vector3 origin,
    Vector3 delta,
    SweepHit out, {
    required int mask,
    Collider? ignore,
  });
}
