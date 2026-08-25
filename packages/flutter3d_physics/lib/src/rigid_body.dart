/// Something the world pushes around.
///
/// ## No rotation, and it is not a shortcut
///
/// Stage one of the specification's two: mass, gravity, impulses, being pushed,
/// and coming to rest. A body has a velocity and no angular velocity, no
/// inertia tensor and no orientation.
///
/// The consequence is worth stating because it is what makes stage one
/// tractable: **a box that never rotates stays axis-aligned.** Contact between
/// two of them is then exact and cheap — the overlap on each axis, and the
/// normal is the axis of least overlap — where the general case needs a
/// separating-axis search and a manifold with several points. Nothing here
/// approximates a rotating box; there simply are none.
///
/// What that costs, stated rather than discovered: a crate you push into a
/// corner will not tip, a barrel will not roll, and a ragdoll is out of the
/// question. Those are stage two, and stage two is a separate decision — see
/// `ARCHITECTURE.md` §10, which says to port a solver rather than write one if it
/// is ever needed.
///
/// ## It lives in the collision world everything else lives in
///
/// A rigid body's collider is [ColliderKind.kinematic] as far as the collision
/// world is concerned, because from that world's point of view the only
/// questions are "does it move" and "does it block", and the answer to both is
/// yes. That is what makes the character controller ride a floating crate and a
/// door refuse to close on one without a line of new code anywhere.
library;

import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_shape.dart';
import 'collision_world.dart';
import 'snapshot.dart';

final class RigidBody {
  RigidBody({
    required CollisionWorld world,
    required CollisionShape shape,
    required Vector3 position,
    this.mass = 1.0,
    this.restitution = 0.0,
    this.friction = 0.6,
    int layer = 1 << 0,
    int mask = Layers.all,
    Object? userData,
  }) : inverseMass = mass <= 0.0 ? 0.0 : 1.0 / mass {
    collider = world.add(
      Collider(
        shape: shape,
        position: position,
        kind: ColliderKind.kinematic,
        layer: layer,
        mask: mask,
        userData: userData,
      ),
    );
  }

  /// This body's entry in the collision world, which owns its position.
  ///
  /// One place a position lives, rather than a copy here kept in step with a
  /// copy there. Two copies of where something is are two answers to the
  /// question, and the disagreement shows up as a crate drawn beside the hole
  /// it is actually in.
  late final Collider collider;

  Vector3 get position => collider.position;

  final Vector3 velocity = Vector3.zero();

  /// Kilograms. Zero or less means immovable — infinite mass, which is what a
  /// crate bolted to the floor is.
  final double mass;

  /// 1/mass, or zero for immovable. Kept because every line of the solver wants
  /// it and none of them wants the division.
  final double inverseMass;

  /// How much of the approach speed comes back. Zero is a crate, which is what
  /// most things are.
  double restitution;

  /// Coulomb friction, roughly. One is grippy, zero is ice.
  double friction;

  /// Whether the solver may skip this body.
  ///
  /// A stack of ten crates that has settled costs nothing to leave alone, and
  /// leaving it alone is also what stops the bottom one from being jittered
  /// out of the pile by the accumulated error of nine contacts being solved
  /// sixty times a second for ever.
  bool get isAsleep => _asleep;
  bool _asleep = false;

  /// Seconds spent below the sleep threshold.
  double _still = 0.0;

  bool get isMovable => inverseMass > 0.0;

  /// Wakes it, and resets the clock that would put it back to sleep.
  void wake() {
    _asleep = false;
    _still = 0.0;
  }

  void sleep() {
    _asleep = true;
    _still = 0.0;
    velocity.setZero();
  }

  /// Changes the velocity by an impulse, in newton-seconds.
  ///
  /// The one thing a game does to a body directly: an explosion, a jump pad,
  /// a bullet. Mass is applied here so a caller says how hard rather than how
  /// fast, which is the difference between a rocket that throws a crate and a
  /// rocket that throws a crate and a mountain equally.
  void applyImpulse(Vector3 impulse) {
    if (!isMovable) return;
    wake();
    velocity.addScaled(impulse, inverseMass);
  }

  /// Everything a snapshot has to carry.
  Map<String, Object?> save() => <String, Object?>{
    'at': <double>[position.x, position.y, position.z],
    'velocity': <double>[velocity.x, velocity.y, velocity.z],
    'asleep': _asleep,
    'still': _still,
  };

  void restore(Map<String, Object?> from) {
    readVector(from['at'], collider.position);
    readVector(from['velocity'], velocity);
    collider.refreshBounds();
    collider.clearDelta();
    _asleep = from['asleep'] == true;
    _still = (from['still'] as num?)?.toDouble() ?? 0.0;
  }

  /// Advances the sleep clock. Called by the world, not by a game.
  void updateSleep(double dt, double speedThreshold, double after) {
    if (_asleep) return;
    if (velocity.length2 > speedThreshold * speedThreshold) {
      _still = 0.0;
      return;
    }
    _still += dt;
    if (_still >= after) sleep();
  }
}
