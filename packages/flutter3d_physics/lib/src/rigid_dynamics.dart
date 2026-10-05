/// What steps a world's bodies: the seam a game and `WorldStep` hold.
///
/// ## Two of them
///
/// [Dynamics] in this package is the reference: plain Dart, in doubles, on
/// every platform including the browser, and the bits a run's digest folds
/// in. `flutter3d_physics_native` has the other, a C core underneath the
/// same bodies, with contacts that turn them, joints, continuous collision
/// and threads, stepping in f32 to bits of its own — the same bits on every
/// platform, but not these. A game chooses one when it builds the world and
/// holds it as this, so nothing past that line knows which.
///
/// Either way the bodies are [RigidBody] objects on a [CollisionWorld]: their
/// colliders are what the broadphase, the sweeps and the character
/// controller see, and after [step] they are where the bodies are.
library;

import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_world.dart';
import 'dynamics.dart';
import 'rigid_body.dart';

abstract interface class RigidDynamics {
  /// The world the bodies' colliders are in.
  CollisionWorld get world;

  /// Metres per second squared.
  Vector3 get gravity;

  /// Every body added, in the order it was.
  List<RigidBody> get bodies;

  /// Starts stepping [body], whose collider is already in [world].
  RigidBody add(RigidBody body);

  /// Stops stepping [body] and takes its collider out of [world].
  void remove(RigidBody body);

  /// The body a collider belongs to, or null for level geometry.
  RigidBody? bodyOf(Collider collider);

  /// One fixed step of [dt] seconds.
  void step(double dt);

  /// Shoves whatever [by] is walking into, horizontally, at most at the speed
  /// it is walking into it: how a kinematic character pushes a crate.
  void push(Collider by, Vector3 velocity, {double strength = 1.0});

  /// What a save must carry beyond the bodies' own `save()` for a run
  /// restored from it to step on to the same bits: null when there is
  /// nothing, as for [Dynamics], whose state is its bodies'. A value JSON
  /// can hold, so a simulation puts it in its snapshot as it is.
  Object? saveState();

  /// Back to what [saveState] gave, after the bodies' own `restore`; null
  /// changes nothing.
  void restoreState(Object? saved);
}
