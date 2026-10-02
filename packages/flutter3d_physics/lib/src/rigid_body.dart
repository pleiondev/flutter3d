/// Something the world pushes around.
///
/// ## No rotation unless asked for, and that is not a shortcut
///
/// Stage one of the specification's two was mass, gravity, impulses, being
/// pushed, and coming to rest, with no orientation at all. Its consequence is
/// what keeps it tractable: **a box that never rotates stays axis-aligned.**
/// Contact between two of them is then exact and cheap — the overlap on each
/// axis, and the normal is the axis of least overlap — where the general case
/// needs a separating-axis search and a manifold with several points.
///
/// Stage two starts here, and it starts switched off. Every body now has an
/// [RigidBody.orientation], an [RigidBody.angularVelocity] and an inertia
/// tensor, but only a body built with `canRotate: true` turns; the rest have
/// an inverse inertia of zero, which is what "cannot be turned" means to the
/// arithmetic, and step exactly as they did. **Off by default because every
/// crate in every shipped level was tuned against bodies that do not tip**,
/// and a platformer's crate tumbling off the ledge it was placed on is a
/// broken level rather than a better simulation.
///
/// **What a turning body does not do yet: collide as a turned shape.** Its
/// collider is still the axis-aligned one, and no contact turns it — torque
/// comes from [RigidBody.applyImpulseAt] and [RigidBody.applyTorqueImpulse]
/// and nothing else. Contacts that tip a crate are the next piece of the same
/// work, and until they land a spinning box is drawn turning inside a
/// collision box that is not.
///
/// ## It lives in the collision world everything else lives in
///
/// A rigid body's collider is [ColliderKind.kinematic] as far as the collision
/// world is concerned, because from that world's point of view the only
/// questions are "does it move" and "does it block", and the answer to both is
/// yes. That is what makes the character controller ride a floating crate and a
/// door refuse to close on one without a line of new code anywhere.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_shape.dart';
import 'collision_world.dart';
import 'inertia.dart';
import 'snapshot.dart';

final class RigidBody {
  RigidBody({
    required CollisionWorld world,
    required CollisionShape shape,
    required Vector3 position,
    this.mass = 1.0,
    this.restitution = 0.0,
    this.friction = 0.6,
    this.canRotate = false,
    Quaternion? orientation,
    this.angularDamping = 0.0,
    int layer = 1 << 0,
    int mask = Layers.all,
    Object? userData,
  }) : inverseMass = mass <= 0.0 ? 0.0 : 1.0 / mass,
       inertiaLocal = inertiaFor(shape, mass),
       inverseInertiaLocal = _inverted(
         inertiaFor(shape, mass),
         canRotate && mass > 0.0,
       ) {
    if (orientation != null) _setUnit(orientation);
    refreshInertia();
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

  /// Whether anything may turn this body. Fixed at construction, because the
  /// inverse tensor below is.
  final bool canRotate;

  /// Whether it actually turns: allowed to, and movable at all.
  bool get rotates => canRotate && isMovable;

  /// How the body is turned, from its own axes into the world's.
  ///
  /// In the convention of `asRotationMatrix` and `Matrix4.compose`, which is
  /// what a renderer draws with. `Quaternion.rotated` applies the inverse
  /// turn, `q* v q`, and is the wrong way to carry a point out of this body.
  ///
  /// For a body that does not [rotates], whatever it was built or set with,
  /// and nothing a step does changes it. **Assign
  /// rather than edit in place:** the setter normalises and refreshes
  /// [inverseInertiaWorld], and a quaternion changed through this getter
  /// leaves that tensor describing the old turn until [refreshInertia] is
  /// called.
  Quaternion get orientation => _orientation;
  set orientation(Quaternion value) {
    _setUnit(value);
    refreshInertia();
  }

  final Quaternion _orientation = Quaternion.identity();

  /// Radians per second about each world axis. Zero, always, for a body that
  /// does not [rotates].
  final Vector3 angularVelocity = Vector3.zero();

  /// Per second, the fraction of spin taken away, as `1 / (1 + dt · this)`.
  ///
  /// **Zero by default, because a free body keeping its spin is the right
  /// answer** and a damping that hides a solver bug is not one. It is here
  /// for the game that wants a thrown object to settle sooner than friction
  /// alone would make it. Rational rather than `exp(-dt · this)`, which is
  /// the same to first order and asks the machine nothing.
  double angularDamping;

  /// The principal moments of inertia in the body's own axes — see
  /// `inertia.dart` for why three numbers are the whole tensor.
  ///
  /// The shape's real answer whether or not the body may turn; it is
  /// [inverseInertiaLocal] that says whether it does.
  final Vector3 inertiaLocal;

  /// One over each of [inertiaLocal], or zero for a body that does not
  /// [rotates] — infinite inertia, which is the whole of how "does not turn"
  /// reaches the arithmetic.
  final Vector3 inverseInertiaLocal;

  /// The inverse tensor in world axes: `R · diag(inverseInertiaLocal) · Rᵀ`.
  ///
  /// What a solver multiplies a torque by. Refreshed whenever [orientation] is
  /// assigned, restored or stepped, rather than computed per use: a contact
  /// solver asks for it twenty times a step for every pair. Symmetric, so
  /// reading it by rows or by columns is the same.
  final Matrix3 inverseInertiaWorld = Matrix3.zero();

  /// [inverseInertiaWorld] at full precision, which is what the arithmetic
  /// reads. The matrix above is for a caller; `vector_math` stores it in
  /// single precision.
  _Symmetric _inverseWorld = _Symmetric.zero;

  /// Brings [inverseInertiaWorld] up to date with [orientation].
  ///
  /// Called by the setter, by [restore] and by the step. A caller that turned
  /// the quaternion in place rather than assigning it calls this.
  void refreshInertia() {
    _inverseWorld = _Symmetric.turned(_orientation, inverseInertiaLocal);
    final m = _inverseWorld;
    inverseInertiaWorld.setValues(
      m.xx,
      m.xy,
      m.xz,
      m.xy,
      m.yy,
      m.yz,
      m.xz,
      m.yz,
      m.zz,
    );
  }

  void _setUnit(Quaternion value) {
    final length = value.length;
    // A zero quaternion turns nothing into nothing; the identity is the only
    // honest reading of "no rotation was given".
    if (length == 0.0 || !length.isFinite) {
      _orientation.setValues(0.0, 0.0, 0.0, 1.0);
      return;
    }
    _orientation.setValues(
      value.x / length,
      value.y / length,
      value.z / length,
      value.w / length,
    );
  }

  static Vector3 _inverted(Vector3 inertia, bool turns) => turns
      ? Vector3(
          inertia.x > 0.0 ? 1.0 / inertia.x : 0.0,
          inertia.y > 0.0 ? 1.0 / inertia.y : 0.0,
          inertia.z > 0.0 ? 1.0 / inertia.z : 0.0,
        )
      : Vector3.zero();

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
    angularVelocity.setZero();
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

  /// An impulse delivered at [worldPoint] rather than through the centre.
  ///
  /// The same change of velocity as [applyImpulse] — where it lands does not
  /// change how far the centre is thrown — plus the spin of `r × impulse`,
  /// with `r` from the centre to the point. A body that does not [rotates]
  /// takes the first half only, which is what infinite inertia means.
  void applyImpulseAt(Vector3 impulse, Vector3 worldPoint) {
    if (!isMovable) return;
    wake();
    velocity.addScaled(impulse, inverseMass);
    if (!rotates) return;
    final rx = worldPoint.x - position.x;
    final ry = worldPoint.y - position.y;
    final rz = worldPoint.z - position.z;
    _spin(
      ry * impulse.z - rz * impulse.y,
      rz * impulse.x - rx * impulse.z,
      rx * impulse.y - ry * impulse.x,
    );
  }

  /// Changes the spin by an angular impulse, in newton-metre-seconds about
  /// world axes. Nothing, for a body that does not [rotates].
  void applyTorqueImpulse(Vector3 impulse) {
    if (!rotates) return;
    wake();
    _spin(impulse.x, impulse.y, impulse.z);
  }

  void _spin(double x, double y, double z) {
    final (wx, wy, wz) = _inverseWorld.times(x, y, z);
    angularVelocity.setValues(
      angularVelocity.x + wx,
      angularVelocity.y + wy,
      angularVelocity.z + wz,
    );
  }

  /// Turns the body through one step of its spin. Called by `Dynamics`, not
  /// by a game.
  ///
  /// ## Angular momentum is what is kept, not angular velocity
  ///
  /// A free body's momentum `L = I·ω` is constant in the world; its velocity
  /// is not, because `I` turns with the body. A rod spun about a tilted axis
  /// wobbles, and that wobble is `ω` changing while `L` does not. So the step
  /// is: take `L` with the old orientation, turn the body by `ω`, and read `ω`
  /// back out of `L` with the new one. That *is* the gyroscopic term of
  /// Euler's equations, taken implicitly — written out explicitly as
  /// `ω × Iω` it is the part of a rigid body integrator that blows up first,
  /// and here there is nothing to blow up: `L` is carried through unchanged.
  ///
  /// The turn itself is `q += ½·dt·(ω ⊗ q)` and a normalisation — first
  /// order, and correct to that order for any `ω` because the
  /// normalisation is what keeps `q` a rotation. The cost of first order is
  /// a slow drift in rotational energy for a body spun off its principal
  /// axes; `rotation_test.dart` measures it, and a body spun about one of
  /// them keeps both exactly.
  void integrateOrientation(double dt) {
    if (!rotates) return;
    final wx = angularVelocity.x;
    final wy = angularVelocity.y;
    final wz = angularVelocity.z;
    if (wx == 0.0 && wy == 0.0 && wz == 0.0) return;

    final (lx, ly, lz) = _Symmetric.turned(
      _orientation,
      inertiaLocal,
    ).times(wx, wy, wz);

    final x = _orientation.x;
    final y = _orientation.y;
    final z = _orientation.z;
    final s = _orientation.w;
    final h = 0.5 * dt;
    final nx = x + h * (s * wx + wy * z - wz * y);
    final ny = y + h * (s * wy + wz * x - wx * z);
    final nz = z + h * (s * wz + wx * y - wy * x);
    final ns = s - h * (wx * x + wy * y + wz * z);
    final length = math.sqrt(nx * nx + ny * ny + nz * nz + ns * ns);
    _orientation.setValues(nx / length, ny / length, nz / length, ns / length);
    refreshInertia();

    final keep = 1.0 / (1.0 + dt * angularDamping);
    final (ox, oy, oz) = _inverseWorld.times(lx, ly, lz);
    angularVelocity.setValues(ox * keep, oy * keep, oz * keep);
  }

  /// Everything a snapshot has to carry.
  ///
  /// **The orientation and spin only for a body that can turn.** One that
  /// cannot has no spin and an orientation no step changes, and writing them
  /// anyway would change the digest of every saved level that holds a crate —
  /// the simulation's run digests fold these maps in — for no information.
  Map<String, Object?> save() => <String, Object?>{
    'at': <double>[position.x, position.y, position.z],
    'velocity': <double>[velocity.x, velocity.y, velocity.z],
    'asleep': _asleep,
    'still': _still,
    if (canRotate) ...<String, Object?>{
      'orientation': <double>[
        _orientation.x,
        _orientation.y,
        _orientation.z,
        _orientation.w,
      ],
      'spin': <double>[angularVelocity.x, angularVelocity.y, angularVelocity.z],
    },
  };

  void restore(Map<String, Object?> from) {
    readVector(from['at'], collider.position);
    readVector(from['velocity'], velocity);
    collider.refreshBounds();
    collider.clearDelta();
    _asleep = from['asleep'] == true;
    _still = (from['still'] as num?)?.toDouble() ?? 0.0;

    // A body that cannot turn wrote neither key, and nothing a step does moves
    // its orientation, so there is nothing to put back.
    if (!canRotate) return;

    // **Absent is not the same as unreadable.** A snapshot without the keys
    // was written for a body that did not turn, and what it says is "the
    // identity and no spin" — so that is what is restored, rather than
    // whatever this body happens to be doing. A key that is there and cannot
    // be read leaves the body as it is, as `readVector` does.
    if (from.containsKey('orientation')) {
      readQuaternion(from['orientation'], _orientation);
    } else {
      _orientation.setValues(0.0, 0.0, 0.0, 1.0);
    }
    if (from.containsKey('spin')) {
      readVector(from['spin'], angularVelocity);
    } else {
      angularVelocity.setZero();
    }
    refreshInertia();
  }

  /// Advances the sleep clock. Called by the world, not by a game.
  ///
  /// Spin counts as moving, in radians per second against the same number:
  /// a body turning on the spot is not at rest, and putting it to sleep would
  /// stop it dead.
  void updateSleep(double dt, double speedThreshold, double after) {
    if (_asleep) return;
    final threshold = speedThreshold * speedThreshold;
    if (velocity.length2 > threshold || angularVelocity.length2 > threshold) {
      _still = 0.0;
      return;
    }
    _still += dt;
    if (_still >= after) sleep();
  }
}

/// A symmetric 3×3 matrix, in doubles: the six numbers that are not mirrors.
///
/// What an inertia tensor is once it has been turned into world axes. Doubles
/// rather than `vector_math`'s `Matrix3`, which stores single precision — a
/// tensor rounded to seven digits between every use is a body whose angular
/// momentum leaks out through the rounding.
final class _Symmetric {
  const _Symmetric(this.xx, this.yy, this.zz, this.xy, this.xz, this.yz);

  static const _Symmetric zero = _Symmetric(0.0, 0.0, 0.0, 0.0, 0.0, 0.0);

  /// `R · diag(d) · Rᵀ`, with `R` the rotation of the unit quaternion [q].
  factory _Symmetric.turned(Quaternion q, Vector3 d) {
    final x = q.x, y = q.y, z = q.z, w = q.w;
    final r00 = 1.0 - 2.0 * (y * y + z * z);
    final r01 = 2.0 * (x * y - z * w);
    final r02 = 2.0 * (x * z + y * w);
    final r10 = 2.0 * (x * y + z * w);
    final r11 = 1.0 - 2.0 * (x * x + z * z);
    final r12 = 2.0 * (y * z - x * w);
    final r20 = 2.0 * (x * z - y * w);
    final r21 = 2.0 * (y * z + x * w);
    final r22 = 1.0 - 2.0 * (x * x + y * y);
    final dx = d.x, dy = d.y, dz = d.z;
    return _Symmetric(
      r00 * r00 * dx + r01 * r01 * dy + r02 * r02 * dz,
      r10 * r10 * dx + r11 * r11 * dy + r12 * r12 * dz,
      r20 * r20 * dx + r21 * r21 * dy + r22 * r22 * dz,
      r00 * r10 * dx + r01 * r11 * dy + r02 * r12 * dz,
      r00 * r20 * dx + r01 * r21 * dy + r02 * r22 * dz,
      r10 * r20 * dx + r11 * r21 * dy + r12 * r22 * dz,
    );
  }

  final double xx, yy, zz, xy, xz, yz;

  (double, double, double) times(double x, double y, double z) => (
    xx * x + xy * y + xz * z,
    xy * x + yy * y + yz * z,
    xz * x + yz * y + zz * z,
  );
}
