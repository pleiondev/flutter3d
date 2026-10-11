/// Bodies with mass, and what happens when they meet.
///
/// ## Sequential impulses
///
/// The standard shape, and it is standard because the alternatives are worse
/// for a game: gather every contact, then solve them one after another several
/// times over, each pass correcting what the last one broke. It converges
/// quickly on the piles a game actually builds and it degrades into "slightly
/// soft" rather than "explodes" when it does not.
///
/// Two details are what separate a stack that stands from one that hums:
///
/// * **Accumulated impulses, clamped at zero.** Solving a contact in isolation
///   can pull bodies together — the correction for one contact is a violation
///   of another. The running total per contact is clamped instead of each
///   increment, so the solver may take back what it gave and never ends up
///   sucking.
/// * **A slop, and a fraction.** Penetration is corrected by a proportion of
///   the excess over a small tolerance, not all of it and not immediately.
///   Correcting it exactly makes a resting box bounce on the floating-point
///   error of its own weight.
///
/// ## What it does not do
///
/// No contact that turns a body — a body built with `canRotate` spins from the
/// impulses a game gives it and keeps its angular momentum, but the solver
/// below pushes only along the normal, through the centre. No joints, no
/// continuous collision. A body moving fast enough
/// to cross a wall between two steps will cross it; the sweep that stops that
/// happening for the character controller is not applied here, and stage two is
/// where it belongs. Stated rather than discovered, and the numbers are in
/// `ARCHITECTURE.md` §10.
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_shape.dart';
import 'collision_world.dart';
import 'contact.dart';
import 'push.dart';
import 'rigid_body.dart';
import 'rigid_dynamics.dart';
import 'tolerances.dart';

/// What a contact needed last step.
final class _Held {
  _Held(this.normal);

  /// The normal impulse it ended with, in newton-seconds.
  final double normal;
}

/// One pair that has to be pushed apart, and how hard it has been pushed so
/// far.
final class _Pair {
  _Pair(this.a, this.b);

  /// Always a body.
  RigidBody a;

  /// The other body, or null when the other side is the level.
  RigidBody? b;

  /// The immovable side, when [b] is null.
  Collider? against;

  final Vector3 normal = Vector3.zero();

  /// How far the pair overlaps along [normal], in metres.
  double depth = 0.0;

  /// Halfway between the two surfaces when the pair was found: where the
  /// step's report says they touch.
  final Vector3 point = Vector3.zero();

  /// [a]'s point against the other side's when the pair was found, before
  /// this step's gravity: what the report says they met at.
  final Vector3 meet = Vector3.zero();

  /// Identifies this contact between steps, so its impulses can be carried
  /// over. Two colliders that met last step are the same contact now.
  Object key = 0;

  /// The running total, so the clamp is on the sum rather than on each
  /// increment. This is the difference between a stack that stands and a stack
  /// that is pulled into the floor. In newton-seconds.
  double normalImpulse = 0.0;

  /// The friction impulse so far, in newton-seconds.
  double tangentImpulse = 0.0;

  /// The pair's friction coefficient, a unitless ratio of tangential to
  /// normal impulse.
  double friction = 0.0;

  /// The speed the solver is aiming to *end* with, from restitution.
  ///
  /// Worked out once, from the approach speed before any impulse is applied,
  /// and then held. Recomputing it each iteration is what killed the first
  /// version of this solver: the first pass turns the approach into a bounce,
  /// the second sees a separating velocity and takes the bounce back out, and
  /// eight passes later a ball dropped from three metres lies still.
  double bounce = 0.0;
}

/// The reference [RigidDynamics]: sequential impulses in Dart doubles.
final class Dynamics extends RigidDynamics {
  /// Steps [world]'s bodies under [world]'s gravity
  /// (`CollisionWorld.properties`).
  ///
  /// [gravity], when given, is the world's from now on: it sets
  /// `world.properties` to the same world with that gravity, as a game
  /// setting its world would. A convenience for a world made only to drop
  /// something in; a game sets its world where it stages it.
  Dynamics({required this.world, Vector3? gravity, this.iterations = 20}) {
    if (gravity != null) {
      world.properties = world.properties.copyWith(gravity: gravity);
    }
  }

  @override
  final CollisionWorld world;

  /// Metres per second squared: the world's (`world.properties.gravity`),
  /// read every step, so a level set on the Moon drops its crates as it
  /// drops its runner. A fresh vector each call; a world's gravity is
  /// changed through `world.properties`, never by scaling this in place.
  ///
  /// It was a field of its own, 22 down when nobody said, under characters
  /// falling at 24 and sparks at 9.81: three gravities in one game. One
  /// gravity per game now (decision 1 of `tasks/1.0-physics-audit.md`).
  @override
  Vector3 get gravity => world.properties.gravity;

  /// How many times the velocity solver goes round.
  final int iterations;

  /// How many times the penetration is corrected per step.
  ///
  /// One pass moves each pair a fraction of the way out, and in a tall stack
  /// the fraction that the crate below moves is a new overlap for the crate
  /// above. Several cheap passes converge where one aggressive pass overshoots
  /// and throws the pile apart.
  int positionIterations = 6;

  @override
  final List<RigidBody> bodies = <RigidBody>[];

  /// Below this speed for [sleepAfter] seconds, a body stops being simulated.
  /// In metres per second.
  double sleepSpeed = 0.08;

  /// How long a body must stay below [sleepSpeed] to sleep, in seconds.
  double sleepAfter = 0.5;

  /// How much overlap is tolerated before it is corrected, in metres.
  /// Correcting the last millimetre is what makes a resting box hum.
  ///
  /// [contactSlop] unless a game tunes it; what this step says is in
  /// contact ([contacts]) reads [contactSlop] whatever this is, as the
  /// native core does.
  double slop = contactSlop;

  /// What fraction of the excess penetration is corrected per step.
  double correction = 0.35;

  /// How close counts as touching.
  ///
  /// Two centimetres, which is small enough that nothing is stopped visibly
  /// short of what it hits and large enough that a resting pile never loses
  /// contact between steps. See `Contact.depth`.
  double margin = 0.02;

  /// Below this approach speed, a bounce is not a bounce. Without it a crate
  /// resting on the floor re-bounces on its own settling velocity for ever.
  /// In metres per second.
  double restitutionThreshold = 1.0;

  final List<_Pair> _pairs = <_Pair>[];

  /// What each contact needed last step, kept so this step can start there.
  ///
  /// **Warm starting, and a stack does not stand without it.** Beginning every
  /// step from zero means the solver rediscovers the weight of nine crates from
  /// scratch sixty times a second, and never quite finishes before gravity adds
  /// the next step's worth — so the pile creeps downwards until the position
  /// correction happens to balance it, about ten centimetres in. Seeded from
  /// the previous step it converges in a handful of iterations, because the
  /// answer barely changed.
  final Map<Object, _Held> _held = <Object, _Held>{};
  final Map<Object, _Held> _heldNext = <Object, _Held>{};
  final List<Collider> _nearby = <Collider>[];
  final Contact _contact = Contact();
  final Vector3 _scratch = Vector3.zero();

  @override
  RigidBody add(RigidBody body) {
    bodies.add(body);
    _byCollider[body.collider] = body;
    return body;
  }

  @override
  void remove(RigidBody body) {
    bodies.remove(body);
    _byCollider.remove(body.collider);
    world.remove(body.collider);
  }

  /// The body a collider belongs to, or null for level geometry.
  ///
  /// Public because a game holding a `Collider` off a sweep had no way back to
  /// its `RigidBody` — and constant-time because this is called from inside the
  /// broadphase loop, where a linear scan makes the cost of a step quadratic in
  /// the number of bodies. The platformer's shipped level has thirty-four
  /// crates in it, which is where that stopped being theoretical.
  @override
  RigidBody? bodyOf(Collider collider) {
    _lookups++;
    return _byCollider[collider];
  }

  /// How many collider-to-body lookups the last step made.
  ///
  /// A counter rather than a timing, so the test that guards the cost cannot
  /// go flaky on a busy machine. The same shape as
  /// `CharacterController.contactsLastStep`, and for the same reason.
  int get bodyLookupsLastStep => _lookupsLastStep;
  int _lookups = 0;
  int _lookupsLastStep = 0;

  final Map<Collider, RigidBody> _byCollider = <Collider, RigidBody>{};

  /// One fixed step.
  @override
  void step(double dt) {
    if (dt <= 0.0) return;
    _lookupsLastStep = _lookups;
    _lookups = 0;

    // **Before gravity, and that ordering is the whole of it.** Asked after,
    // every awake body looks as though it is moving at a third of a metre a
    // second — one step of gravity that the solver has not taken back yet — so
    // every sleeper beside one was woken on every step and nothing in a pile
    // ever slept. The decision is made on last step's settled velocities,
    // which is the same thing `updateSleep` reads.
    for (final body in bodies) {
      if (body.isAsleep && body.isMovable && _shouldWake(body)) body.wake();
    }

    final gravity = world.properties.gravity;
    _fell.clear();
    for (final body in bodies) {
      if (body.isAsleep || !body.isMovable) continue;
      body.velocity.addScaled(gravity, dt);
      _fell.add(body);
    }

    _collect(gravity, dt);
    _solveVelocities(dt);
    _report();

    for (final body in bodies) {
      if (body.isAsleep || !body.isMovable) continue;
      _scratch
        ..setFrom(body.velocity)
        ..scale(dt);
      body.collider.moveTo(body.position + _scratch);
      // After the solve, like the position: the spin this step ends with is
      // the one the body turns by. Nothing for a body that cannot turn.
      body.integrateOrientation(dt);
    }

    _separate();

    for (final body in bodies) {
      if (!body.isMovable) continue;
      body.updateSleep(dt, sleepSpeed, sleepAfter);
    }

    // The broadphase is holding every body where it was before this step, and
    // whatever queries the world next — a character sweeping, a door checking
    // whether it is blocked — has to see where they are now.
    world.reindex();
  }

  /// Shoves whatever [by] is walking into, as [Pusher] says.
  @override
  void push(Collider by, Vector3 velocity, {double strength = 1.0}) =>
      _pusher.push(by, velocity, strength: strength, margin: margin);

  late final Pusher _pusher = Pusher(this);

  /// The world it steps in, `world.properties`, as JSON, and what the last
  /// step was in contact as: the warm starts held between steps were never
  /// part of a save, and the bodies step to the same bits without them —
  /// but the world's gravity and air are part of what the next step
  /// computes, so a run rewound across a change of gravity steps on under
  /// the gravity it was saved with; and the contacts are what the next
  /// step tells its own phases against, so a run rewound reports the
  /// contacts the run it was saved from would, as the native core does
  /// from its snapshot.
  @override
  Object? saveState() => <String, Object?>{
    'world': world.properties.toJson(),
    'contacts': _ledger.save(),
  };

  /// Puts the world's properties and the last step's contacts back as
  /// [saveState] wrote them, after the bodies' own restore; a save from
  /// before they were saved leaves the world as it is, and begins every
  /// contact the next step finds.
  @override
  void restoreState(Object? saved) {
    if (saved case {'world': final Map<String, Object?> properties}) {
      world.properties = WorldProperties.fromJson(properties);
    }
    _ledger.restore(saved is Map ? saved['contacts'] : null, world);
  }

  /// What the last step found in contact, begun, persisting or ended.
  ///
  /// A pair is in contact when it is within [contactSlop] of touching or
  /// the solver pushed on it, as the core says it, whatever [slop] this
  /// solver corrects to; a pair of a sleeping body
  /// that this solver did not ask about — against the level, or against
  /// another sleeper — persists as it was, with no impulse, as the core
  /// keeps a sleeping pair's manifold.
  @override
  List<StepContact> get contacts => _ledger.contacts;

  final ContactLedger _ledger = ContactLedger();

  /// The bodies this step's gravity was added to, so a contact's velocity
  /// can be told as it was before it.
  final Set<RigidBody> _fell = <RigidBody>{};

  /// This step's pairs in contact, kept to be cleared rather than made
  /// again.
  final List<StepContact> _inContact = <StepContact>[];

  /// This step's pairs in contact, to the ledger.
  void _report() {
    final inContact = _inContact..clear();
    for (final pair in _pairs) {
      if (pair.depth < -contactSlop && pair.normalImpulse <= 0.0) continue;
      final a = pair.a.collider;
      final b = pair.b?.collider ?? pair.against!;
      final idA = world.idOf(a);
      final idB = world.idOf(b);
      if (idA == null || idB == null) continue;
      inContact.add(
        StepContact(
          a: a,
          b: b,
          idA: idA,
          idB: idB,
          phase: ContactPhase.persist,
          point: pair.point,
          normal: pair.normal,
          impulse: pair.normalImpulse,
          relativeVelocity: pair.meet,
        ),
      );
    }
    _ledger.record(inContact, heldWhileResting: _resting);
  }

  /// Whether a contact of the step before, not found this step, was left
  /// alone because both of its sides rest: each still in the world, and
  /// either a sleeping body or not a body at all.
  bool _resting(StepContact before) =>
      _restingSide(before.a) && _restingSide(before.b);

  bool _restingSide(Collider side) {
    if (world.idOf(side) == null) return false;
    final body = bodyOf(side);
    return body == null || body.isAsleep;
  }

  /// [body]'s velocity at [point] as the step found it, before [gravity]
  /// over [dt] was added to it, into [out].
  void _velocityAt(
    RigidBody body,
    Vector3 point,
    Vector3 gravity,
    double dt,
    Vector3 out,
  ) {
    out.setFrom(body.velocity);
    if (_fell.contains(body)) out.addScaled(gravity, -dt);
    final w = body.angularVelocity;
    final rx = point.x - body.position.x;
    final ry = point.y - body.position.y;
    final rz = point.z - body.position.z;
    out.x += w.y * rz - w.z * ry;
    out.y += w.z * rx - w.x * rz;
    out.z += w.x * ry - w.y * rx;
  }

  final Vector3 _otherVelocity = Vector3.zero();

  /// Everything overlapping, as pairs the solver can work on.
  void _collect(Vector3 gravity, double dt) {
    _pairs.clear();
    _heldNext.clear();
    for (var i = 0; i < bodies.length; i++) {
      final body = bodies[i];
      if (!body.isMovable) continue;

      // A sleeping body is resting on something and has nothing to solve. It
      // is **not** woken by being in contact with the floor — that was the
      // first version, and it meant nothing ever slept: every settled crate
      // touches something, so every settled crate woke itself up again on the
      // next step for ever.

      // Against the level: a sleeping body is already resting on it and has
      // nothing to solve. **Only this pass is skipped** — the body-to-body pass
      // below is not, because a sleeping crate is what the crate above it is
      // standing on. Skipping the whole body was the first version, and the
      // upper crate fell straight through the lower one the instant it slept.
      if (!body.isAsleep) {
        // Against the level and anything else that moves but is not a body.
        // **Queried with an inflated box, not with the body's own shape.** The
        // world's `overlap` answers about actual overlap, so a crate the
        // corrector has pushed a millimetre clear of the floor finds nothing,
        // gets a free step of gravity, and the whole pile above it drops a
        // third of a metre a second once every sixteen steps. Measured: the
        // margin has to reach the broadphase, not only the narrow test.
        world.overlap(
          _inflated(body.collider.shape),
          body.position,
          _nearby,
          mask: body.collider.mask,
          ignore: body.collider,
          includeTriggers: false,
        );
        for (final other in _nearby) {
          final otherBody = bodyOf(other);
          // Body-against-body is handled once, below, rather than twice here.
          if (otherBody != null) continue;
          contactBetween(
            body.collider.shape,
            body.position,
            other.shape,
            other.position,
            _contact,
          );
          if (!_contact.isTouching) continue;
          final pair = _Pair(body, null)
            ..against = other
            ..normal.setFrom(_contact.normal)
            ..depth = _contact.depth;
          contactPointBetween(
            body.collider.shape,
            body.position,
            other.shape,
            other.position,
            pair.normal,
            pair.depth,
            pair.point,
          );
          _velocityAt(body, pair.point, gravity, dt, pair.meet);
          _pairs.add(
            pair
              ..key = _keyOf(body.collider, other)
              ..bounce = _bounceFor(
                _pairOf(body.collider, other)?.restitution ?? body.restitution,
                body.velocity.dot(_contact.normal),
              )
              ..friction =
                  _pairOf(body.collider, other)?.friction ?? body.friction,
          );
        }
      }

      // Against other bodies, each pair once. A pair with one side asleep is
      // still solved: the sleeper is an anchor, which is exactly what a crate
      // resting on it needs.
      for (var j = i + 1; j < bodies.length; j++) {
        final other = bodies[j];
        if (!body.isMovable && !other.isMovable) continue;
        if (body.isAsleep && other.isAsleep) continue;
        contactBetween(
          body.collider.shape,
          body.position,
          other.collider.shape,
          other.position,
          _contact,
          margin: margin,
        );
        if (!_contact.isTouching) continue;
        // Something actually *moving* wakes what it hits, or a crate shoved
        // into a sleeping pile passes straight through it. Something merely
        // settling does not, or nothing in a stack ever sleeps: each crate
        // would wake the one below it every step for ever.
        // Only the later one: this body's own waking happened before its
        // static pass, above. `other` comes after `body` in the list, so its
        // own passes have not run yet and waking it here is in time.
        if (other.isAsleep && body.velocity.length2 > sleepSpeed * sleepSpeed) {
          other.wake();
        }
        var approach = body.velocity.dot(_contact.normal);
        approach -= other.velocity.dot(_contact.normal);
        final pair = _Pair(body, other)
          ..normal.setFrom(_contact.normal)
          ..depth = _contact.depth;
        contactPointBetween(
          body.collider.shape,
          body.position,
          other.collider.shape,
          other.position,
          pair.normal,
          pair.depth,
          pair.point,
        );
        _velocityAt(body, pair.point, gravity, dt, pair.meet);
        _velocityAt(other, pair.point, gravity, dt, _otherVelocity);
        pair.meet.sub(_otherVelocity);
        _pairs.add(
          pair
            ..key = _keyOf(body.collider, other.collider)
            ..bounce = _bounceFor(
              _pairOf(body.collider, other.collider)?.restitution ??
                  math.max(body.restitution, other.restitution),
              approach,
            )
            ..friction =
                _pairOf(body.collider, other.collider)?.friction ??
                math.sqrt(body.friction * other.friction),
        );
      }
    }
  }

  /// The pair measured between [a]'s and [b]'s materials in the world's
  /// catalogue, or null — and null without asking when either has none, so a
  /// world of bodies without materials steps to the bits it always did.
  ///
  /// **Only a measured pair overrides the bodies' own numbers.** Without one,
  /// a body made of a material already holds the material's friction and
  /// restitution, and the solver combines them by the catalogue's rule
  /// (`MaterialCatalog.contact`: the geometric mean of μ, the larger e), so
  /// a number a game set on the body itself still counts.
  MaterialPair? _pairOf(Collider a, Collider b) {
    final ma = a.material, mb = b.material;
    if (ma == null || mb == null) return null;
    return world.materials.pairOf(ma.id, mb.id);
  }

  /// Whether a sleeping body has any business waking up.
  ///
  /// Two reasons, and neither of them is "it is touching something": a settled
  /// pile touches things by definition, and waking on contact means nothing
  /// ever sleeps.
  bool _shouldWake(RigidBody body) {
    world.overlap(
      body.collider.shape,
      body.position,
      _nearby,
      mask: body.collider.mask,
      ignore: body.collider,
      includeTriggers: false,
    );
    for (final other in _nearby) {
      final otherBody = bodyOf(other);
      if (otherBody != null) {
        // Something actually moving, rather than a neighbour being nudged a
        // fraction of a millimetre by the penetration corrector.
        if (otherBody.velocity.length2 > sleepSpeed * sleepSpeed) return true;
        continue;
      }
      if (other.delta.length2 <= Nearly.parallel) continue;
      // Other bodies do not count, and that is the whole subtlety. A settled
      // stack still moves a fraction of a millimetre every step — gravity
      // pushes it in, the penetration correction pushes it out — so a crate
      // that fell asleep was woken by its neighbour's twitch on the very next
      // step, for ever, and nothing in a pile ever slept. Body-to-body waking
      // is the mutual rule in `_collect`, which asks whether the other one is
      // actually *moving* rather than merely being corrected.
      if (bodyOf(other) != null) continue;
      return true;
    }
    return false;
  }

  /// The body's bounds grown by the contact margin, for the broadphase.
  CollisionShape _inflated(CollisionShape shape) {
    final half = shape.boundsHalfExtents;
    return CollisionBox(
      Vector3(half.x + margin, half.y + margin, half.z + margin),
    );
  }

  /// Names a contact so the next step can recognise it.
  ///
  /// **By the world's own ids, not by `identityHashCode`**, which this used
  /// until it was read carefully. That hash is neither stable between two runs
  /// of the same program nor injective, and both matter here: the first makes
  /// a warm start something a replay cannot reproduce, and the second seeds a
  /// contact with an impulse that belonged to a different pair — which shows
  /// up as a stack of crates that behaved differently that one time and cannot
  /// be made to do it again.
  ///
  /// Order-independent, so a pair collected the other way round on the next
  /// step is still the same pair. Packed by multiplication for the reason
  /// `CollisionWorld` gives beside its own key: a shift past bit 31 is
  /// discarded on the web.
  Object _keyOf(Collider a, Collider b) {
    final ia = world.idOf(a) ?? -1;
    final ib = world.idOf(b) ?? -1;
    final lo = ia < ib ? ia : ib;
    final hi = ia < ib ? ib : ia;
    return lo * 0x100000000 + (hi & 0xFFFFFFFF);
  }

  void _solveVelocities(double dt) {
    // Start where the last step finished. The impulse that held a crate up a
    // sixtieth of a second ago is very nearly the one that holds it up now.
    for (final pair in _pairs) {
      final held = _held[pair.key];
      if (held == null) continue;
      // The normal only. Friction is warm-started by real engines too, but
      // they store the tangent *direction* with it; carrying the magnitude
      // alone means the solver computes its increments against a total it never
      // applied, and the energy that appears out of that sends a pushed crate
      // off at twelve metres a second. Measured, not guessed.
      pair
        ..normalImpulse = held.normal
        ..tangentImpulse = 0.0;
      _scratch
        ..setFrom(pair.normal)
        ..scale(held.normal);
      if (!pair.a.isAsleep) {
        pair.a.velocity.addScaled(_scratch, pair.a.inverseMass);
      }
      final b = pair.b;
      if (b != null && !b.isAsleep) {
        b.velocity.addScaled(_scratch, -b.inverseMass);
      }
    }

    for (var pass = 0; pass < iterations; pass++) {
      for (final pair in _pairs) {
        final a = pair.a;
        final b = pair.b;
        final invA = a.isAsleep ? 0.0 : a.inverseMass;
        final invB = b == null || b.isAsleep ? 0.0 : b.inverseMass;
        final inverseSum = invA + invB;
        if (inverseSum <= 0.0) continue;

        // Approach speed along the normal. The level and anything kinematic
        // count as motionless: a lift carrying a crate moves it by pushing it
        // out of itself, which is what the separation pass below does.
        var vn = a.velocity.dot(pair.normal);
        if (b != null) vn -= b.velocity.dot(pair.normal);

        // A gap is allowed to close, and no faster. That is the whole of
        // speculative contact: a pair a few millimetres apart is still solved,
        // but only down to the speed that just closes the distance in one
        // step — so nothing is frozen in mid-air and nothing gets a free step
        // of gravity because the corrector had pushed it clear.
        final separation = -pair.depth;
        final target = separation > 0.0 ? -separation / dt : pair.bounce;
        var lambda = (target - vn) / inverseSum;

        // Clamp the *total*, not the increment.
        final before = pair.normalImpulse;
        pair.normalImpulse = math.max(0.0, before + lambda);
        lambda = pair.normalImpulse - before;

        _scratch
          ..setFrom(pair.normal)
          ..scale(lambda);
        a.velocity.addScaled(_scratch, invA);
        b?.velocity.addScaled(_scratch, -invB);

        // Friction along whatever is left of the relative velocity once the
        // normal part is taken out.
        _scratch.setFrom(a.velocity);
        if (b != null) _scratch.sub(b.velocity);
        final along = _scratch.dot(pair.normal);
        _scratch.addScaled(pair.normal, -along);
        final speed = _scratch.length;
        if (speed < Nearly.still) continue;
        _scratch.scale(1.0 / speed);

        var jt = -speed / inverseSum;
        final limit = pair.friction * pair.normalImpulse;
        final beforeT = pair.tangentImpulse;
        pair.tangentImpulse = (beforeT + jt).clamp(-limit, limit);
        jt = pair.tangentImpulse - beforeT;

        _scratch.scale(jt);
        a.velocity.addScaled(_scratch, invA);
        b?.velocity.addScaled(_scratch, -invB);
      }
    }

    for (final pair in _pairs) {
      _heldNext[pair.key] = _Held(pair.normalImpulse);
    }
    _held
      ..clear()
      ..addAll(_heldNext);
  }

  /// How much speed a contact should end with, from restitution.
  ///
  /// Zero below the threshold, because a crate settling under its own weight
  /// approaches the floor at a few centimetres a second every step, and
  /// bouncing off that is how a resting body hums for ever.
  double _bounceFor(double restitution, double approach) {
    if (approach >= 0.0) return 0.0;
    if (-approach <= restitutionThreshold) return 0.0;
    return restitution * -approach;
  }

  /// Pushes overlapping bodies apart, a fraction at a time.
  ///
  /// Recomputed rather than reusing the depths from [_collect]: the velocity
  /// solve and the integration have both moved things since, and correcting a
  /// penetration that is no longer there is how a stack climbs.
  void _separate() {
    for (var pass = 0; pass < positionIterations; pass++) {
      _separateOnce();
    }
  }

  void _separateOnce() {
    for (final pair in _pairs) {
      final a = pair.a;
      final b = pair.b;
      final invA = a.isAsleep ? 0.0 : a.inverseMass;
      final invB = b == null || b.isAsleep ? 0.0 : b.inverseMass;
      final inverseSum = invA + invB;
      if (inverseSum <= 0.0) continue;

      final otherShape = b?.collider.shape ?? pair.against!.shape;
      final otherAt = b?.position ?? pair.against!.position;
      contactBetween(
        a.collider.shape,
        a.position,
        otherShape,
        otherAt,
        _contact,
        margin: margin,
      );
      if (!_contact.isTouching) continue;

      final excess = _contact.depth - slop;
      if (excess <= 0.0) continue;

      final push = correction * excess / inverseSum;
      _scratch
        ..setFrom(_contact.normal)
        ..scale(push);
      if (invA > 0.0) a.collider.moveTo(a.position + (_scratch * invA));
      if (b != null && invB > 0.0) {
        b.collider.moveTo(b.position - (_scratch * invB));
      }
    }
  }
}
