import 'package:vector_math/vector_math.dart';

import 'collision_world.dart';
import 'dynamics.dart';
import 'rigid_dynamics.dart';

/// What simulates a run's physics: the bodies, the characters' moves and the
/// rays and sweeps every query asks — one answer for the whole run.
///
/// **Chosen once, not per system.** A world whose characters walk on one
/// engine and whose crates fall on another is two simulations that disagree
/// about where the floor is, and a tape recorded on it replays on neither.
/// So a game sets [PhysicsBackend.current] before it stages anything — the
/// native package's `startPhysics` does it, falling back to this one where
/// the core cannot load — and everything that makes a world asks it.
///
/// The two are not promised to agree with each other, only each with
/// itself: a run recorded on one replays bit for bit on the same one, and
/// a recording says which it was (`Demo.physics`).
///
/// Cloth comes from the same answer, through `cloth` (the
/// `PhysicsBackendCloth` extension), which a backend with a cloth of its
/// own serves by also implementing `ClothPhysics`.
abstract interface class PhysicsBackend {
  /// What a recording calls it: `'native'` or `'dart'`.
  String get name;

  /// A world's rigid bodies, on this backend — and its characters and rays
  /// too, where the backend has its own of those.
  RigidDynamics dynamics(CollisionWorld world, {Vector3? gravity});

  /// Gives [world] this backend's character moves and rays without any
  /// rigid bodies of its own — for a world nothing loose falls in. The
  /// answer is kept alive by the world; [release] lets it go.
  void attach(CollisionWorld world);

  /// Lets go of what [attach] or [dynamics] gave [world]; it goes back to
  /// its own sweeps and walk.
  void release(CollisionWorld world);

  /// The one every world is made with until a game says otherwise: the Dart
  /// reference, which needs nothing loaded.
  static PhysicsBackend current = const DartPhysics();
}

/// The reference: everything in Dart, on every platform, from the first
/// line. What a run falls back to when the core cannot be had.
final class DartPhysics implements PhysicsBackend {
  const DartPhysics();

  @override
  String get name => 'dart';

  @override
  RigidDynamics dynamics(CollisionWorld world, {Vector3? gravity}) =>
      Dynamics(world: world, gravity: gravity);

  /// Nothing: a world's own sweeps and walk are the reference.
  @override
  void attach(CollisionWorld world) {}

  @override
  void release(CollisionWorld world) {}
}
