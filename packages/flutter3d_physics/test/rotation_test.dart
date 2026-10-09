/// Bodies that turn: inertia per shape, spin from an off-centre impulse, a
/// free body keeping its angular momentum, and a snapshot that resumes the
/// same run.
///
///     dart test test/rotation_test.dart
///
/// The first piece of stage two. No contact turns a body yet, so every scene
/// here is a body in free flight; what is being held is the integrator, not
/// the solver.
library;

import 'dart:convert';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

void main() {
  group('inertia', () {
    test('a unit cube of six kilograms is one about every axis', () {
      // m·s²/6 for a cube of side s. Mutation: the box formula with full
      // widths where it wants half extents is four times this.
      final i = inertiaFor(CollisionBox(Vector3.all(0.5)), 6.0);
      expect(i.x, closeTo(1.0, 1e-6));
      expect(i.y, closeTo(1.0, 1e-6));
      expect(i.z, closeTo(1.0, 1e-6));
    });

    test('a box is heaviest about the axis its two long sides are across', () {
      // Mutation: any two of the three moments swapped.
      final i = inertiaFor(CollisionBox(Vector3(0.5, 1.0, 1.5)), 3.0);
      expect(i.x, closeTo(1.0 * (1.0 + 2.25), 1e-6));
      expect(i.y, closeTo(1.0 * (0.25 + 2.25), 1e-6));
      expect(i.z, closeTo(1.0 * (0.25 + 1.0), 1e-6));
    });

    test('a sphere is two fifths of m r²', () {
      final i = inertiaFor(CollisionSphere(2.0), 5.0);
      expect(i, Vector3.all(8.0));
    });

    test('a capsule with no cylinder is the sphere it is', () {
      // Mutation: the caps' parallel-axis term with `h` where it wants `h²`
      // still passes here, which is why the next test exists.
      final capsule = inertiaFor(
        CollisionCapsule(radius: 0.4, halfHeight: 0.0),
        2.0,
      );
      final sphere = inertiaFor(CollisionSphere(0.4), 2.0);
      expect(capsule.x, closeTo(sphere.x, 1e-6));
      expect(capsule.y, closeTo(sphere.y, 1e-6));
    });

    test('a long capsule agrees with its volume summed point by point', () {
      // A grid of points through the bounding box, kept where they fall
      // inside the capsule, each carrying an equal share of the mass. Half a
      // percent at this resolution; the closed form is exact.
      //
      // Mutation: the capsule treated as a cylinder of its whole height is
      // several percent out on both axes.
      const r = 0.3, h = 0.6, mass = 4.0, n = 80;
      final shape = CollisionCapsule(radius: r, halfHeight: h);
      final step = 2.0 * (h + r) / n;
      var (count, across, axial) = (0, 0.0, 0.0);
      for (var ix = 0; ix < n; ix++) {
        for (var iy = 0; iy < n; iy++) {
          for (var iz = 0; iz < n; iz++) {
            final x = -(h + r) + (ix + 0.5) * step;
            final y = -(h + r) + (iy + 0.5) * step;
            final z = -(h + r) + (iz + 0.5) * step;
            final dy = y.abs() > h ? y.abs() - h : 0.0;
            if (x * x + z * z + dy * dy > r * r) continue;
            count++;
            across += y * y + z * z;
            axial += x * x + z * z;
          }
        }
      }
      final i = inertiaFor(shape, mass);
      expect(i.x, closeTo(mass * across / count, i.x * 0.005));
      expect(i.y, closeTo(mass * axial / count, i.y * 0.005));
      expect(i.z, i.x);
    });

    test('a wedge is its bounding box, as the library says it is', () {
      final wedge = inertiaFor(CollisionWedge(Vector3(1.0, 0.5, 2.0)), 3.0);
      expect(wedge, inertiaFor(CollisionBox(Vector3(1.0, 0.5, 2.0)), 3.0));
    });

    test('and nothing for no mass', () {
      expect(inertiaFor(CollisionSphere(1.0), 0.0), Vector3.zero());
    });
  });

  group('a body that was not asked to turn', () {
    test('does not, whatever it is given', () {
      // The promise every shipped level rests on. Mutation: `canRotate`
      // defaulting to true, or `inverseInertiaLocal` taken from the shape
      // regardless of it.
      final (dynamics, body) = _floating(canRotate: false);
      body
        ..applyTorqueImpulse(Vector3(5.0, 5.0, 5.0))
        ..applyImpulseAt(
          Vector3(0.0, 0.0, 10.0),
          body.position + Vector3(1.0, 0.0, 0.0),
        );
      for (var i = 0; i < 60; i++) {
        dynamics.step(_dt);
      }
      expect(body.angularVelocity, Vector3.zero());
      expect(body.orientation, Quaternion.identity());
      expect(body.inverseInertiaLocal, Vector3.zero());
    });

    test('and its snapshot has the keys it always had', () {
      // Mutation: writing the orientation for every body changes the digest
      // of every saved level holding a crate.
      final (_, body) = _floating(canRotate: false);
      expect(body.save().keys, <String>['at', 'velocity', 'asleep', 'still']);
    });

    test('and an off-centre impulse still moves it as a central one would', () {
      final (_, a) = _floating(canRotate: false);
      final (_, b) = _floating(canRotate: false);
      a.applyImpulse(Vector3(0.0, 0.0, 6.0));
      b.applyImpulseAt(
        Vector3(0.0, 0.0, 6.0),
        b.position + Vector3(1.0, 0.0, 0.0),
      );
      expect(b.velocity, a.velocity);
    });
  });

  group('a body that turns', () {
    test('spins by r × J through the inverse tensor', () {
      // A unit cube of six kilograms has I = 1, so the spin is the angular
      // impulse itself: a push along +z one metre out along +x is a turn
      // about -y. Mutation: the cross product's operands swapped turns it
      // the other way.
      final (_, body) = _floating();
      body.applyImpulseAt(
        Vector3(0.0, 0.0, 2.0),
        body.position + Vector3(1.0, 0.0, 0.0),
      );
      expect(body.velocity.z, closeTo(2.0 / 6.0, 1e-6));
      expect(body.angularVelocity.x, closeTo(0.0, 1e-6));
      expect(body.angularVelocity.y, closeTo(-2.0, 1e-6));
      expect(body.angularVelocity.z, closeTo(0.0, 1e-6));
    });

    test('turns the way a matrix drawn from it turns, by the angle spun', () {
      // A quarter turn about +y in one second takes +x to -z. Held through
      // `asRotationMatrix`, the matrix `Matrix4.compose` builds and a renderer
      // draws with, rather than `Quaternion.rotated`: that one computes
      // `q* v q`, the inverse turn, and would put this body's +x at +z.
      //
      // Mutation: `ω ⊗ q` written as `q ⊗ ω` turns about the body's axes
      // rather than the world's, which agrees here and nowhere else — so the
      // second half starts the body already turned. The sign of `ω` flipped in
      // the update fails the first half.
      final (dynamics, body) = _floating();
      body.applyTorqueImpulse(Vector3(0.0, Portable.atan(1.0) * 2.0, 0.0));
      for (var i = 0; i < 60; i++) {
        dynamics.step(_dt);
      }
      final x = body.orientation.asRotationMatrix().transformed(
        Vector3(1.0, 0.0, 0.0),
      );
      expect(x.x, closeTo(0.0, 1e-3));
      expect(x.z, closeTo(-1.0, 1e-3));

      final (turnedDynamics, turned) = _floating(
        orientation: Quaternion(
          0.0,
          0.0,
          0.7071067811865476,
          0.7071067811865476,
        ),
      );
      turned.applyTorqueImpulse(Vector3(0.0, Portable.atan(1.0) * 2.0, 0.0));
      for (var i = 0; i < 60; i++) {
        turnedDynamics.step(_dt);
      }
      // Body +x was world +y before; a world-axis turn about +y leaves it there.
      final up = turned.orientation.asRotationMatrix().transformed(
        Vector3(1.0, 0.0, 0.0),
      );
      expect(up.y, closeTo(1.0, 1e-3));
    });

    test('has a world tensor that is R · I⁻¹ · Rᵀ', () {
      final (_, body) = _floating(
        shape: CollisionBox(Vector3(0.2, 0.5, 1.0)),
        orientation: Quaternion(0.3, -0.2, 0.5, 0.8),
      );
      final expected = _turned(body.orientation, body.inverseInertiaLocal);
      for (var i = 0; i < 9; i++) {
        expect(
          body.inverseInertiaWorld.storage[i],
          closeTo(expected.storage[i], 1e-4),
        );
      }
    });

    test(
      'keeps its angular momentum, and nearly its energy, spinning free',
      () {
        // Spun about no principal axis, so ω wobbles while L stays put. Ten
        // seconds at sixty steps a second.
        //
        // Mutation: `integrateOrientation` keeping ω and dropping the turn of
        // the tensor — no gyroscopic term — lets L wander by tens of percent
        // within the first second.
        final (dynamics, body) = _floating(
          shape: CollisionBox(Vector3(0.2, 0.5, 1.0)),
        );
        body.applyTorqueImpulse(Vector3(0.4, 0.3, 0.2));
        final l0 = _momentum(body);
        final e0 = 0.5 * body.angularVelocity.dot(l0);
        var worstL = 0.0;
        var worstE = 0.0;
        for (var i = 0; i < 600; i++) {
          dynamics.step(_dt);
          final l = _momentum(body);
          final e = 0.5 * body.angularVelocity.dot(l);
          final dl = (l - l0).length / l0.length;
          final de = (e - e0).abs() / e0;
          if (dl > worstL) worstL = dl;
          if (de > worstE) worstE = de;
        }
        expect(worstL, lessThan(1e-4), reason: 'angular momentum drifted');
        expect(worstE, lessThan(0.02), reason: 'rotational energy drifted');
        expect(body.isAsleep, isFalse);
      },
    );

    test('is not put to sleep for standing still while it spins', () {
      // Mutation: `updateSleep` reading only the linear velocity stops this
      // dead half a second in.
      final (dynamics, body) = _floating();
      body.applyTorqueImpulse(Vector3(0.0, 3.0, 0.0));
      for (var i = 0; i < 120; i++) {
        dynamics.step(_dt);
      }
      expect(body.isAsleep, isFalse);
      expect(body.angularVelocity.y, closeTo(3.0, 1e-5));
    });

    test(
      'loses spin to damping as one over one plus dt times it, per step',
      () {
        final (dynamics, body) = _floating(angularDamping: 2.0);
        body.applyTorqueImpulse(Vector3(0.0, 3.0, 0.0));
        for (var i = 0; i < 60; i++) {
          dynamics.step(_dt);
        }
        var expected = 3.0;
        for (var i = 0; i < 60; i++) {
          expected /= 1.0 + _dt * 2.0;
        }
        expect(body.angularVelocity.y, closeTo(expected, 1e-4));
      },
    );
  });

  group('a snapshot', () {
    test('resumes the same run, bit for bit', () {
      // Through JSON, as a save on disk is. No contacts in the scene: the
      // warm-start impulses `Dynamics` carries between steps are not part of
      // a body's snapshot, and a contact would make this a test of that.
      //
      // Mutation: `restore` renormalising the orientation it reads, or
      // forgetting to refresh the world tensor, changes the last bits.
      final (straight, through) = (_tumbling(), _tumbling());
      for (var i = 0; i < 100; i++) {
        straight.$1.step(_dt);
        through.$1.step(_dt);
      }
      final saved =
          jsonDecode(jsonEncode(through.$2.save())) as Map<String, Object?>;

      final resumed = _tumbling();
      resumed.$2.restore(saved);
      for (var i = 0; i < 100; i++) {
        straight.$1.step(_dt);
        resumed.$1.step(_dt);
      }
      final a = straight.$2, b = resumed.$2;
      expect(b.position.storage, a.position.storage);
      expect(b.velocity.storage, a.velocity.storage);
      expect(b.orientation.storage, a.orientation.storage);
      expect(b.angularVelocity.storage, a.angularVelocity.storage);
    });

    test('without the new keys is a body that is not turning', () {
      // A snapshot written for a body that could not turn says "the identity
      // and no spin" by leaving them out, and that is what it restores to.
      final (_, body) = _floating();
      body
        ..orientation = Quaternion(0.0, 0.0, 1.0, 1.0)
        ..applyTorqueImpulse(Vector3(1.0, 2.0, 3.0));
      body.restore(<String, Object?>{
        'at': <double>[0.0, 10.0, 0.0],
        'velocity': <double>[0.0, 0.0, 0.0],
      });
      expect(body.orientation, Quaternion.identity());
      expect(body.angularVelocity, Vector3.zero());
    });

    test('with a key it cannot read leaves the body as it was', () {
      final (_, body) = _floating();
      body.orientation = Quaternion(0.0, 0.0, 1.0, 1.0);
      final before = body.orientation.clone();
      body.restore(<String, Object?>{
        'at': <double>[0.0, 10.0, 0.0],
        'orientation': <Object?>[0.0, 'up', 0.0, 1.0],
        'spin': <double>[0.0, 1.0, 0.0],
      });
      expect(body.orientation, before);
      expect(body.angularVelocity.y, 1.0);
    });

    test('and an orientation edited by hand is made a rotation', () {
      final out = Quaternion.identity();
      expect(readQuaternion(<double>[0.0, 0.0, 1.0, 1.0], out), isTrue);
      expect(out.length, closeTo(1.0, 1e-6));
      expect(readQuaternion(<double>[0.0, 0.0, 0.0, 0.0], out), isFalse);
    });
  });
}

/// A six-kilogram unit cube, or [shape], hanging in a world with no gravity.
(Dynamics, RigidBody) _floating({
  bool canRotate = true,
  CollisionShape? shape,
  Quaternion? orientation,
  double angularDamping = 0.0,
}) {
  final dynamics = Dynamics(world: CollisionWorld(), gravity: Vector3.zero());
  final body = dynamics.add(
    RigidBody(
      world: dynamics.world,
      shape: shape ?? CollisionBox(Vector3.all(0.5)),
      position: Vector3(0.0, 10.0, 0.0),
      mass: 6.0,
      canRotate: canRotate,
      orientation: orientation,
      angularDamping: angularDamping,
    ),
  );
  return (dynamics, body);
}

/// A long box thrown upwards and tumbling under gravity, far from anything.
(Dynamics, RigidBody) _tumbling() {
  final dynamics = Dynamics(world: CollisionWorld());
  final body = dynamics.add(
    RigidBody(
      world: dynamics.world,
      shape: CollisionBox(Vector3(0.2, 0.5, 1.0)),
      position: Vector3(0.0, 100.0, 0.0),
      mass: 3.0,
      canRotate: true,
      angularDamping: 0.1,
    ),
  );
  body.applyImpulseAt(
    Vector3(0.5, 30.0, 0.2),
    body.position + Vector3(0.3, 0.0, 0.8),
  );
  return (dynamics, body);
}

/// `I_world · ω`, worked out the long way, independently of the body.
Vector3 _momentum(RigidBody body) => _turned(
  body.orientation,
  body.inertiaLocal,
).transformed(body.angularVelocity);

/// `R · diag(d) · Rᵀ` through `vector_math`'s own rotation matrix, so the
/// body's hand-written one is checked against something it did not write.
Matrix3 _turned(Quaternion q, Vector3 d) {
  final r = q.asRotationMatrix();
  return r.multiplied(Matrix3.zero()..setDiagonal(d))..multiply(r.transposed());
}
