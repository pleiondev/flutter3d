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

  /// The nearest solid thing the query's ray meets, into its
  /// [RayQuery.out]; whether it met one.
  bool raycast(RayQuery query);
}

/// What [WorldRays.raycast] is handed: a ray from [origin] along
/// [direction] within [maxDistance], meeting things on a layer in [mask] but
/// not [ignore], and the hit to write into [out].
///
/// **One object, so a minor can hand the rays more** — a ray's thickness, a
/// filter the core can run — without breaking an implementation written
/// against 1.0. **Reused**: a world owns one and sets it before every
/// query, so a ray allocates nothing for it; the rays read it during the
/// call and do not keep it.
final class RayQuery {
  RayQuery({
    required this.origin,
    required this.direction,
    required this.maxDistance,
    required this.out,
    this.mask = Layers.all,
    this.ignore,
  });

  /// Where the ray starts.
  Vector3 origin;

  /// Which way it goes, a unit vector.
  Vector3 direction;

  /// How far it reaches, m.
  double maxDistance;

  /// The hit, written by the call.
  RayHit out;

  /// The layers it meets.
  int mask;

  /// A collider it passes through: the one casting it, usually.
  Collider? ignore;
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

  /// The first solid thing the query's shape meets, into its
  /// [SweepQuery.out]; whether it met one.
  bool sweep(SweepQuery query);
}

/// What [WorldSweeps.sweep] is handed: [shape] moved from [origin] by
/// [delta], meeting things on a layer in [mask] but not [ignore], and the
/// hit to write into [out].
///
/// One object, reused by the world, for the reasons [RayQuery] gives.
final class SweepQuery {
  SweepQuery({
    required this.shape,
    required this.origin,
    required this.delta,
    required this.out,
    this.mask = Layers.all,
    this.ignore,
  });

  /// The shape moved.
  CollisionShape shape;

  /// Where its center starts.
  Vector3 origin;

  /// How far it moves.
  Vector3 delta;

  /// The hit, written by the call.
  SweepHit out;

  /// The layers it meets.
  int mask;

  /// A collider it passes through: the one moving, usually.
  Collider? ignore;
}
