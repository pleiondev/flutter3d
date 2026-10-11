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
/// below pushes only along the normal, through the centre. No joints, and
/// no continuous collision beyond the speculative contact: a pair is looked
/// for as far as its bodies move in the step, so a body stops at a wall it
/// would reach this step, as the native core's does; the sweep the
/// character controller makes is not applied here. Stated rather than
/// discovered, and the numbers are in `ARCHITECTURE.md` §10.
///
/// ## Two profiles
///
/// Under `SimulationProfile.deterministic`, the default, a step is the
/// sequence above in float32 vectors, to the bits the native core's parity
/// tests compare against. Under `SimulationProfile.accurate` each body's
/// position and velocity are also kept in doubles, and a body nothing
/// pushed on this step flies the step as its laws say: under gravity alone
/// exactly (the parabola), and under [BodyForce]s by an adaptive
/// Runge–Kutta integrator held to a relative error of 1e-10 inside the
/// fixed step. A body in contact is solved as above and carried on in
/// doubles; the contacts themselves, and a body's turning, are not held to
/// analytic tests under either profile.
///
/// The contacts read the *world's* profile (`WorldProperties.profile`, the
/// one a loop binds): in a world that is not bit-exact a contact bounces
/// with no more than the lossier side's material lets come back
/// (`InelasticProperties.lossFactor`, [restitutionOfLossFactor]), as the
/// native core's contacts do; in a bit-exact one the loss factor is not
/// read, and a run's tapes are what they were.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:vector_math/vector_math.dart';

import 'adaptive.dart';
import 'body_force.dart';
import 'collider.dart';
import 'collision_shape.dart';
import 'collision_world.dart';
import 'contact.dart';
import 'impact_loss.dart';
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
  ///
  /// [profile] is what its steps promise about their numbers, the
  /// deterministic profile unless a run asks for another (the library's
  /// "Two profiles").
  Dynamics({
    required this.world,
    Vector3? gravity,
    this.iterations = 20,
    this.profile = SimulationProfile.deterministic,
  }) {
    if (gravity != null) {
      world.properties = world.properties.copyWith(gravity: gravity);
    }
  }

  @override
  final CollisionWorld world;

  /// What these steps promise about their numbers.
  ///
  /// Read by its capabilities, never by its name: a profile that
  /// `usesDoublePrecision` keeps every body's state in doubles beside its
  /// float32 collider, and one that also `allowsAdaptiveSteps` integrates a
  /// body nothing pushes on through [forces] with steps of its own inside
  /// the fixed one. A profile that allows adaptive steps but keeps float32
  /// steps as the deterministic one does: adaptivity needs the doubles.
  @override
  final SimulationProfile profile;

  /// Forces that are laws of a body's state, beside gravity: a planet's
  /// pull, a spring, a field. Empty by default, and a world without any
  /// steps to the bits it did before they existed.
  final List<BodyForce> forces = <BodyForce>[];

  bool get _exact => profile.usesDoublePrecision;

  /// Each body's position and velocity in doubles, kept under a profile
  /// that [_exact]: `x, y, z, vx, vy, vz`.
  final Map<RigidBody, Float64List> _state = <RigidBody, Float64List>{};

  /// Each body's integrator, which keeps the step it last took as the next
  /// one's first guess.
  final Map<RigidBody, DormandPrince> _integrators =
      <RigidBody, DormandPrince>{};

  /// [body]'s position and velocity in doubles, origin-local: `x, y, z,
  /// vx, vy, vz` in a fresh list. Under a profile that keeps doubles, what
  /// the body's float32 collider and velocity were rounded from; otherwise,
  /// and for a body moved by hand since the last step, those float32
  /// values widened.
  Float64List exactStateOf(RigidBody body) {
    final held = _exact ? _held32(body) : null;
    if (held != null) return Float64List.fromList(held);
    final p = body.position, v = body.velocity;
    return Float64List.fromList(<double>[p.x, p.y, p.z, v.x, v.y, v.z]);
  }

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
    _state.remove(body);
    _integrators.remove(body);
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

    if (_exact) _syncState();
    final gravity = world.properties.gravity;
    _fell.clear();
    for (final body in bodies) {
      if (body.isAsleep || !body.isMovable) continue;
      if (forces.isNotEmpty) _pushByForces(body, dt);
      body.velocity.addScaled(gravity, dt);
      _fell.add(body);
    }

    _collect(gravity, dt);
    _solveVelocities(dt, gravity);

    _pushed.clear();
    for (final pair in _pairs) {
      if (pair.normalImpulse <= 0.0) continue;
      _pushed.add(pair.a);
      if (pair.b case final b?) _pushed.add(b);
    }
    for (final body in bodies) {
      if (body.isAsleep || !body.isMovable) continue;
      if (_exact) {
        _moveExactly(body, gravity, dt);
      } else {
        _scratch
          ..setFrom(body.velocity)
          ..scale(dt);
        // A body nothing pushed on falls as the native core's four substeps
        // have it fall, gravity added a quarter of the step at a time: three
        // eighths of a step of gravity less than the whole of it at once. So
        // the two cores reach a floor on the same step, and catch it there.
        if (_fell.contains(body) && !_pushed.contains(body)) {
          _scratch.addScaled(gravity, -_fallShortfall * dt * dt);
        }
        (_moved[body] ??= Vector3.zero()).setFrom(_scratch);
        body.collider.moveTo(body.position + _scratch);
      }
      // After the solve, like the position: the spin this step ends with is
      // the one the body turns by. Nothing for a body that cannot turn.
      body.integrateOrientation(dt);
    }
    _lookAhead(dt);
    _report();

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

  /// [value] as a float32 holds it.
  static double _f32(double value) {
    _rounding[0] = value;
    return _rounding[0];
  }

  static final Float32List _rounding = Float32List(1);

  /// [body]'s doubles, each half of them taken again from the body's
  /// float32 position or velocity where those no longer round from it: the
  /// body was placed, pushed or given an impulse by something other than
  /// this step, and what it was given is the state now.
  Float64List _synced(RigidBody body) {
    final p = body.position, v = body.velocity;
    final s = _state[body];
    if (s == null) {
      return _state[body] = Float64List.fromList(<double>[
        p.x,
        p.y,
        p.z,
        v.x,
        v.y,
        v.z,
      ]);
    }
    if (_f32(s[0]) != p.x || _f32(s[1]) != p.y || _f32(s[2]) != p.z) {
      s
        ..[0] = p.x
        ..[1] = p.y
        ..[2] = p.z;
    }
    if (_f32(s[3]) != v.x || _f32(s[4]) != v.y || _f32(s[5]) != v.z) {
      s
        ..[3] = v.x
        ..[4] = v.y
        ..[5] = v.z;
    }
    return s;
  }

  /// Every body's doubles, brought up to whatever was done to it since the
  /// last step.
  void _syncState() {
    for (final body in bodies) {
      _synced(body);
    }
  }

  /// [body]'s doubles when this world keeps them and they still round to
  /// its float32 values; null otherwise.
  Float64List? _held32(RigidBody body) =>
      _state.containsKey(body) ? _synced(body) : null;

  /// The step's velocity change from [forces], where [body] stands at the
  /// start of it: the whole of what they do under the deterministic
  /// profile, and what the solver sees of them under the accurate one.
  void _pushByForces(RigidBody body, double dt) {
    final p = body.position, v = body.velocity;
    final s = _exact ? _state[body] : null;
    final context = BodyForceContext(body, step: dt)
      ..moveTo(
        0.0,
        s?[0] ?? p.x,
        s?[1] ?? p.y,
        s?[2] ?? p.z,
        s?[3] ?? v.x,
        s?[4] ?? v.y,
        s?[5] ?? v.z,
      );
    for (final force in forces) {
      force.addForce(context);
    }
    final w = body.inverseMass * dt;
    v.setValues(
      v.x + context.forceX * w,
      v.y + context.forceY * w,
      v.z + context.forceZ * w,
    );
  }

  /// Moves [body] through the step in doubles: along its laws when nothing
  /// pushed on it, at the velocity the solver left it with when something
  /// did.
  void _moveExactly(RigidBody body, Vector3 gravity, double dt) {
    final s = _state[body] ?? _synced(body);
    if (_pushed.contains(body)) {
      final v = body.velocity;
      s
        ..[3] = v.x
        ..[4] = v.y
        ..[5] = v.z
        ..[0] += v.x * dt
        ..[1] += v.y * dt
        ..[2] += v.z * dt;
    } else if (forces.isEmpty || !profile.allowsAdaptiveSteps) {
      // Under a constant acceleration the parabola is the answer, to the
      // rounding of the doubles: no integrator to hold to a tolerance.
      final m = body.inverseMass;
      final context = BodyForceContext(body, step: dt)
        ..moveTo(0.0, s[0], s[1], s[2], s[3], s[4], s[5]);
      for (final force in forces) {
        force.addForce(context);
      }
      final ax = gravity.x + context.forceX * m;
      final ay = gravity.y + context.forceY * m;
      final az = gravity.z + context.forceZ * m;
      final half = 0.5 * dt * dt;
      s
        ..[0] += s[3] * dt + ax * half
        ..[1] += s[4] * dt + ay * half
        ..[2] += s[5] * dt + az * half
        ..[3] += ax * dt
        ..[4] += ay * dt
        ..[5] += az * dt;
    } else {
      _fly(body, s, gravity, dt);
    }
    final p = body.position;
    (_moved[body] ??= Vector3.zero()).setValues(
      _f32(s[0]) - p.x,
      _f32(s[1]) - p.y,
      _f32(s[2]) - p.z,
    );
    body.velocity.setValues(s[3], s[4], s[5]);
    body.collider.moveTo(Vector3(s[0], s[1], s[2]));
  }

  /// Integrates [state] of [body] through [dt] under [gravity] and
  /// [forces], adaptively.
  void _fly(RigidBody body, Float64List state, Vector3 gravity, double dt) {
    final m = body.inverseMass;
    final gx = gravity.x, gy = gravity.y, gz = gravity.z;
    final context = BodyForceContext(body, step: dt);
    (_integrators[body] ??= DormandPrince()).integrate(state, 0.0, dt, (
      double t,
      Float64List y,
      Float64List dy,
    ) {
      context.moveTo(t, y[0], y[1], y[2], y[3], y[4], y[5]);
      for (final force in forces) {
        force.addForce(context);
      }
      dy
        ..[0] = y[3]
        ..[1] = y[4]
        ..[2] = y[5]
        ..[3] = gx + context.forceX * m
        ..[4] = gy + context.forceY * m
        ..[5] = gz + context.forceZ * m;
    });
  }

  /// The world it steps in, `world.properties`, as JSON, what the last
  /// step was in contact as, and the warm starts it held for the next one.
  ///
  /// **The warm starts are state.** The solver begins each contact from the
  /// impulse the step before ended it with. Left out of the save, a step
  /// taken again after a restore began from whatever the undone step had
  /// left there, so the first contact after a rollback (an oak ball on
  /// granite, at its fifteenth step) ended in other last bits than the run
  /// it rewound. Written as `[key, impulse, …]` in key order, and only when
  /// there are any, so a save out of contact is what it was.
  ///
  /// The world's gravity and air are part of what the next step
  /// computes, so a run rewound across a change of gravity steps on under
  /// the gravity it was saved with; and the contacts are what the next
  /// step tells its own phases against, so a run rewound reports the
  /// contacts the run it was saved from would, as the native core does
  /// from its snapshot.
  ///
  /// Under a profile that keeps doubles, each body's doubles too, in the
  /// order of [bodies]: a run restored from them goes on from the state it
  /// was saved in, not from its float32 rounding. The deterministic
  /// profile's save is what it always was.
  @override
  Object? saveState() => <String, Object?>{
    'world': world.properties.toJson(),
    'contacts': _ledger.save(),
    if (_held.isNotEmpty)
      'held': <Object?>[
        for (final key
            in _held.keys.toList()..sort(
              (a, b) => (a as num).compareTo(b as num),
            )) ...<Object?>[key, _held[key]!.normal],
      ],
    if (_exact)
      'exact': <Object?>[
        for (final body in bodies) _state[body]?.toList(growable: false),
      ],
  };

  /// Puts the world's properties and the last step's contacts back as
  /// [saveState] wrote them, after the bodies' own restore; a save from
  /// before they were saved leaves the world as it is, and begins every
  /// contact the next step finds. Doubles saved for bodies this world does
  /// not hold the same number of are left out, and the bodies go on from
  /// their float32 state.
  @override
  void restoreState(Object? saved) {
    if (saved case {'world': final Map<String, Object?> properties}) {
      world.properties = WorldProperties.fromJson(properties);
    }
    _ledger.restore(saved is Map ? saved['contacts'] : null, world);
    // A save without warm starts was out of contact, or written before they
    // were saved: either way the next step starts every contact from zero.
    _held.clear();
    if (saved case {'held': final List<Object?> held}) {
      for (var i = 0; i + 1 < held.length; i += 2) {
        if ((held[i], held[i + 1]) case (final num key, final num normal)) {
          _held[key.toInt()] = _Held(normal.toDouble());
        }
      }
    }
    _state.clear();
    _integrators.clear();
    if (saved case {
      'exact': final List<Object?> exact,
    } when exact.length == bodies.length) {
      for (var i = 0; i < exact.length; i++) {
        if (exact[i] case final List<Object?> values when values.length == 6) {
          _state[bodies[i]] = Float64List.fromList(<double>[
            for (final value in values) (value! as num).toDouble(),
          ]);
        }
      }
    }
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
    _readsLoss = contactsReadLoss(world.properties);
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
      final reach = _reach(body, gravity, dt);
      if (!body.isAsleep) {
        // Against the level and anything else that moves but is not a body.
        // **Queried with an inflated box, not with the body's own shape.** The
        // world's `overlap` answers about actual overlap, so a crate the
        // corrector has pushed a millimetre clear of the floor finds nothing,
        // gets a free step of gravity, and the whole pile above it drops a
        // third of a metre a second once every sixteen steps. Measured: the
        // margin has to reach the broadphase, not only the narrow test.
        world.overlap(
          _inflated(body.collider.shape, reach),
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
            margin: margin + reach,
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
                _lossy(
                  _pairOf(body.collider, other)?.restitution ??
                      body.restitution,
                  body.collider,
                  other,
                ),
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
          margin: margin + reach + _reach(other, gravity, dt),
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
              _lossy(
                _pairOf(body.collider, other.collider)?.restitution ??
                    math.max(body.restitution, other.restitution),
                body.collider,
                other.collider,
              ),
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
  /// Whether this step's contacts read their materials' loss factors: in a
  /// world whose profile is not bit-exact, set once a step.
  bool _readsLoss = false;

  /// [restitution], the pair's, held to what the lossier of [a]'s and
  /// [b]'s materials lets come back (`restitutionOfLossFactor`), in a world
  /// that reads loss factors; [restitution] itself in one that does not, so
  /// a deterministic run steps to the bits it always did.
  double _lossy(double restitution, Collider a, Collider b) {
    if (!_readsLoss) return restitution;
    final eta = math.max(lossFactorOf(a.material), lossFactorOf(b.material));
    if (eta <= 0.0) return restitution;
    return math.min(restitution, restitutionOfLossFactor(eta));
  }

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

  /// The body's bounds grown by the contact margin and [reach], for the
  /// broadphase.
  CollisionShape _inflated(CollisionShape shape, double reach) {
    final half = shape.boundsHalfExtents;
    final grow = margin + reach;
    return CollisionBox(Vector3(half.x + grow, half.y + grow, half.z + grow));
  }

  /// How much further than [margin] a contact of [body] is looked for this
  /// step: as far as it moves in the step, at the speed it had before this
  /// step's gravity and turning at its bounds' corners — the native core's
  /// speculative reach, held to ten metres as it is.
  ///
  /// **A speculative contact.** The solver lets a gap close and no more, so
  /// a pair found a step's travel apart stops where they touch: a falling
  /// ball is caught on the step it would reach the floor, the step the core
  /// catches it, and the two say the impact on the same step. Nothing for a
  /// body that sleeps or does not move.
  double _reach(RigidBody body, Vector3 gravity, double dt) {
    if (body.isAsleep || !body.isMovable) return 0.0;
    _before.setFrom(body.velocity);
    if (_fell.contains(body)) _before.addScaled(gravity, -dt);
    final reach =
        _before.length * dt +
        body.angularVelocity.length *
            dt *
            body.collider.shape.boundsHalfExtents.length;
    return math.min(reach, 10.0);
  }

  final Vector3 _before = Vector3.zero();

  /// How far each body moved this step, kept between steps.
  final Map<RigidBody, Vector3> _moved = <RigidBody, Vector3>{};

  /// The step's last look ahead, as the native core's last substep has it:
  /// a pair still apart once the bodies have moved, closing faster than it
  /// can in a quarter of a step without meeting, is slowed to the speed
  /// that just closes the gap in that quarter. Pushed on, it is in contact
  /// this step — the step the core says so.
  void _lookAhead(double dt) {
    final h = dt / 4.0;
    for (final pair in _pairs) {
      if (pair.depth >= 0.0) continue;
      final a = pair.a;
      final b = pair.b;
      final invA = a.isAsleep ? 0.0 : a.inverseMass;
      final invB = b == null || b.isAsleep ? 0.0 : b.inverseMass;
      final inverseSum = invA + invB;
      if (inverseSum <= 0.0) continue;
      var gap = -pair.depth;
      if (!a.isAsleep && a.isMovable) {
        gap += _moved[a]?.dot(pair.normal) ?? 0.0;
      }
      if (b != null && !b.isAsleep && b.isMovable) {
        gap -= _moved[b]?.dot(pair.normal) ?? 0.0;
      }
      if (gap <= 0.0) continue;
      var vn = a.velocity.dot(pair.normal);
      if (b != null) vn -= b.velocity.dot(pair.normal);
      final target = -gap / h;
      if (vn >= target) continue;
      final lambda = (target - vn) / inverseSum;
      pair.normalImpulse += lambda;
      _scratch
        ..setFrom(pair.normal)
        ..scale(lambda);
      a.velocity.addScaled(_scratch, invA);
      b?.velocity.addScaled(_scratch, -invB);
    }
  }

  /// The bodies a contact pushed on this step.
  final Set<RigidBody> _pushed = <RigidBody>{};

  /// How much less of a step's gravity, times the step squared, a body
  /// falls in the core's four substeps than added whole: (n − 1) / 2n.
  static const double _fallShortfall = 3.0 / 8.0;

  /// How much less of a step's gravity, times the step squared, a body
  /// nothing pushes on falls than its velocity at the end of the step
  /// carries it: [_fallShortfall] for the core's substeps, a half for the
  /// parabola the accurate profile flies.
  double get _shortfall => _exact ? 0.5 : _fallShortfall;

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

  void _solveVelocities(double dt, Vector3 gravity) {
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
        // Unpushed, a pair closes by less than its speed times the step —
        // the fall the core's substeps take ([_shortfall]) — and the
        // speed allowed is the one that closes the gap by that reckoning.
        final separation = -pair.depth;
        var falls = _fell.contains(a) ? gravity.dot(pair.normal) : 0.0;
        if (b != null && _fell.contains(b)) falls -= gravity.dot(pair.normal);
        final target = separation > 0.0
            ? -separation / dt + _shortfall * dt * falls
            : pair.bounce;
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

    // Restitution for a pair caught a gap short: the solver stopped it
    // where the two touch, and a pair that was closing fast enough to bounce
    // and was pushed on gets its bounce now, as the native core gives it —
    // or a ball caught a step early would land dead.
    for (final pair in _pairs) {
      if (pair.depth >= 0.0 || pair.bounce <= 0.0) continue;
      if (pair.normalImpulse <= 0.0) continue;
      final a = pair.a;
      final b = pair.b;
      final invA = a.isAsleep ? 0.0 : a.inverseMass;
      final invB = b == null || b.isAsleep ? 0.0 : b.inverseMass;
      final inverseSum = invA + invB;
      if (inverseSum <= 0.0) continue;
      var vn = a.velocity.dot(pair.normal);
      if (b != null) vn -= b.velocity.dot(pair.normal);
      final before = pair.normalImpulse;
      pair.normalImpulse = math.max(
        0.0,
        before + (pair.bounce - vn) / inverseSum,
      );
      _scratch
        ..setFrom(pair.normal)
        ..scale(pair.normalImpulse - before);
      a.velocity.addScaled(_scratch, invA);
      b?.velocity.addScaled(_scratch, -invB);
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
