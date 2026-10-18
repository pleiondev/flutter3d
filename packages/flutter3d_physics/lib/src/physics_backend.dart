import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Registration;
import 'package:vector_math/vector_math.dart';

import 'cloth/cloth_mesh.dart';
import 'cloth/cloth_simulation.dart';
import 'collision_world.dart';
import 'dynamics.dart';
import 'fluid/fluid_solver.dart';
import 'rigid_body.dart';
import 'rigid_dynamics.dart';

/// What simulates a world's physics: the bodies, the characters' moves and
/// the rays and sweeps every query asks — one answer for the whole world.
///
/// **Chosen per world, never globally.** A world whose characters walk on
/// one engine and whose crates fall on another is two simulations that
/// disagree about where the floor is, and a tape recorded on it replays on
/// neither. So a world is made with its backend
/// (`CollisionWorld(backend: …)`), and everything that stages the world asks
/// [CollisionWorld.backend]. There is no process-wide answer: two engines in
/// one isolate — an editor and the game it plays — may run two backends.
/// `flutter3d_physics_native`'s `usePhysics` says which backend the platform
/// can give; it does not make the choice for anybody.
///
/// The two built-in backends are not promised to agree with each other, only
/// each with itself: a run recorded on one replays bit for bit on the same
/// one, and a recording says which it was (`Demo.physics`).
///
/// **Extended outside this package: an `abstract base class` with defaults**
/// (decision 5 of `tasks/1.0-api-review.md`). Every member but [name] has a
/// body — the Dart reference — so a backend overrides what it does on its
/// own and inherits the rest, and a member added in a minor breaks nobody.
/// What only some backends can do arrives beside it as a capability a
/// backend mixes in: [JointPhysics], [ConstraintPhysics], [ShapePhysics].
abstract base class PhysicsBackend {
  /// A backend; a subclass gives its [name] and overrides what it does on
  /// its own.
  const PhysicsBackend();

  /// What a recording calls it: `'native'` or `'dart'`.
  String get name;

  /// The request's world's rigid bodies, on this backend — and its
  /// characters and rays too, where the backend has its own of those. The
  /// reference [Dynamics] by default.
  ///
  /// They fall by the world's gravity (`CollisionWorld.properties`);
  /// [DynamicsRequest.gravity], when given, becomes the world's, as
  /// [Dynamics] says.
  RigidDynamics dynamics(DynamicsRequest request) =>
      Dynamics(world: request.world, gravity: request.gravity);

  /// Gives [world] this backend's character moves and rays without any
  /// rigid bodies of its own — for a world nothing loose falls in. The
  /// answer is kept alive by the world; [release] lets it go. Nothing by
  /// default: a world's own sweeps and walk are the reference.
  void attach(CollisionWorld world) {}

  /// Lets go of what [attach] or [dynamics] gave [world]; it goes back to
  /// its own sweeps and walk. Nothing by default.
  void release(CollisionWorld world) {}

  /// A simulation of [mesh] on this backend. The reference [DartCloth] by
  /// default.
  ClothSimulation cloth(ClothMesh mesh) => DartCloth(mesh);

  /// This backend's fluid solver. The reference [DartFluid] by default.
  FluidSolver get fluid => const DartFluid();

  @override
  String toString() => 'PhysicsBackend($name)';
}

/// What [PhysicsBackend.dynamics] is handed.
///
/// **One object, so a minor can hand a backend more** — a solver's
/// iterations, a sleeping threshold — without breaking a backend written
/// against 1.0.
final class DynamicsRequest {
  /// A request for [world]'s dynamics, replacing its gravity with [gravity]
  /// when given.
  const DynamicsRequest(this.world, {this.gravity});

  /// The world whose rigid bodies the dynamics simulate.
  final CollisionWorld world;

  /// The world's gravity from now on, when given.
  final Vector3? gravity;
}

/// The reference: everything in Dart, on every platform, from the first
/// line. What a world is made with unless it is given another.
final class DartPhysics extends PhysicsBackend {
  /// The reference backend; it holds nothing, so one is as good as another.
  const DartPhysics();

  @override
  String get name => 'dart';
}

/// A kind of joint between two bodies: open, so a backend names its own.
///
/// **A class with constants, not an enum** (§A.2): the four below are what
/// every backend that has joints is expected to solve, and a backend with a
/// rope or a gear names one of its own with [JointType.named]. A backend
/// says which it solves in [JointPhysics.jointTypes] and refuses the rest.
final class JointType {
  /// A joint kind of a backend's own, by its [name].
  const JointType.named(this.name);

  /// Holds B where it was against A, place and turn.
  static const JointType fixed = JointType.named('fixed');

  /// Holds a point of each together; they turn freely about it.
  static const JointType ball = JointType.named('ball');

  /// A hinge about an axis.
  static const JointType hinge = JointType.named('hinge');

  /// A slider along an axis.
  static const JointType slider = JointType.named('slider');

  /// The four every jointed backend is expected to solve.
  static const List<JointType> standard = <JointType>[
    fixed,
    ball,
    hinge,
    slider,
  ];

  /// Its word in a file and a message.
  final String name;

  @override
  bool operator ==(Object other) => other is JointType && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'JointType.$name';
}

/// A joint a [JointPhysics] backend made, as the caller holds it.
final class JointHandle {
  /// The handle of the backend's joint [id], of [type].
  const JointHandle(this.type, this.id);

  /// The kind of joint it is.
  final JointType type;

  /// The backend's number for it.
  final int id;

  @override
  bool operator ==(Object other) =>
      other is JointHandle && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

/// A backend that joins bodies: hinges, sliders, balls, welds, and whatever
/// [JointType] of its own it adds.
///
/// **A capability a backend mixes in**: `extends PhysicsBackend with
/// JointPhysics`. A caller asks `backend is JointPhysics` before reaching for
/// it, and a backend without joints is not made to say so.
abstract base mixin class JointPhysics {
  /// The joint kinds this backend solves.
  Set<JointType> get jointTypes;

  /// The joint the request asks for. Throws an [ArgumentError] for a type
  /// not in [jointTypes].
  JointHandle join(JointRequest request);

  /// Takes the request's joint apart.
  void unjoin(JointRelease request);
}

/// What [JointPhysics.join] is handed: a joint of [type] between [a] and [b]
/// of [dynamics], at [anchor] and along [axis] for a hinge or a slider.
///
/// **One object, so a minor can hand a backend more** — a joint's limits, a
/// motor — without breaking a backend written against 1.0.
///
/// **[anchor] is origin-local**: a position in the world's float32 frame,
/// relative to its floating origin (`CollisionWorld.origin`), as every
/// body's position is — not a `WorldPosition`. A caller holding a
/// `WorldPosition` narrows it with `toVector3Relative(world.origin)`.
final class JointRequest {
  /// A request for a [type] joint holding [b] against [a] at [anchor],
  /// along [axis] for a hinge or a slider (null for the others).
  const JointRequest(
    this.type,
    this.a,
    this.b, {
    required this.dynamics,
    required this.anchor,
    this.axis,
  });

  /// The kind of joint.
  final JointType type;

  /// The first body, which the joint holds [b] against.
  final RigidBody a;

  /// The second body.
  final RigidBody b;

  /// The dynamics both bodies were added to.
  final RigidDynamics dynamics;

  /// Where the joint is, origin-local.
  final Vector3 anchor;

  /// The axis of a hinge or a slider.
  final Vector3? axis;
}

/// What [JointPhysics.unjoin] is handed, for the reason [JointRequest]
/// gives.
final class JointRelease {
  /// A request to take [joint] apart, made by [dynamics].
  const JointRelease(this.joint, {required this.dynamics});

  /// The joint to take apart.
  final JointHandle joint;

  /// The dynamics that made it.
  final RigidDynamics dynamics;
}

/// A constraint a [ConstraintPhysics] backend solves inside its step: a law
/// on one body or between two, computed in Dart before the step from where
/// the bodies are.
abstract base class PhysicsConstraint {
  /// A constraint; a subclass gives its [name] and its [forceOn].
  const PhysicsConstraint();

  /// A stable name for a report and a snapshot.
  String get name;

  /// The force, in newtons, this constraint puts on the context's body this
  /// step, written into its [ConstraintForce.out].
  void forceOn(ConstraintForce context);
}

/// What [PhysicsConstraint.forceOn] is handed: the body, the step, and the
/// force to write.
///
/// **One object, so a minor can hand a constraint more** — the other bodies
/// it binds, the world's gravity — without breaking one written against
/// 1.0. **Reused**: the backend owns one per constraint and sets it before
/// every body of every step, so a step allocates nothing for it; a
/// constraint reads it during the call and does not keep it.
final class ConstraintForce {
  /// A context for [body], if given, over a step of [dt] seconds, writing
  /// into [out] (a new zero vector by default). [body] must be set before
  /// it is read.
  ConstraintForce({RigidBody? body, this.dt = 0.0, Vector3? out})
    : out = out ?? Vector3.zero() {
    if (body != null) this.body = body;
  }

  /// The body the force is on; set before every call.
  late RigidBody body;

  /// The step, in seconds.
  double dt;

  /// The force, in newtons, that the constraint writes; zero before the
  /// call.
  final Vector3 out;
}

/// A backend that solves a caller's own constraints — a spring, a magnet, a
/// rope's pull — in its step.
abstract base mixin class ConstraintPhysics {
  /// Solves the request's constraint on its bodies every step until the
  /// returned registration is cancelled — the engine's one shape for "until
  /// taken back", as a loop system's or a subscriber's is.
  Registration constrain(ConstraintRequest request);
}

/// What [ConstraintPhysics.constrain] is handed: [constraint] on [bodies] of
/// [dynamics].
///
/// One object, for the reason [JointRequest] gives.
final class ConstraintRequest {
  /// A request to solve [constraint] on [bodies] of [dynamics].
  const ConstraintRequest(
    this.constraint, {
    required this.dynamics,
    required this.bodies,
  });

  /// The law to solve.
  final PhysicsConstraint constraint;

  /// The dynamics the bodies were added to.
  final RigidDynamics dynamics;

  /// The bodies it acts on.
  final List<RigidBody> bodies;
}

/// A backend that collides a caller's own convex shape — a subclass of
/// `CollisionShape`, often a `CustomShape` — described by its support
/// function and turned into whatever the backend's core holds (a hull of
/// support points, usually). The extension point for shapes on the backend's
/// side: `CollisionShape` is open to extension, and this says which backends
/// can run what extends it.
///
/// **A capability with no operation of its own, on purpose: a marker.** A
/// custom shape is handed to the world like any other — a `Collider` with
/// that shape — so there is nothing to call. What the marker says is that
/// the backend's own core collides it, as a hull sampled in
/// [customShapeSamples] directions; a backend without it leaves the shape to
/// the world's own queries (the Dart reference's GJK walk over its support).
/// A caller asks `backend is ShapePhysics` before relying on the core's
/// contacts for one, and reads [customShapeSamples] before trusting a hull
/// with fine detail.
abstract base mixin class ShapePhysics {
  /// How many directions a custom shape is sampled in for the backend's
  /// hull; more is rounder and slower. What a tool reports, and a game reads
  /// before it trusts a hull with fine detail.
  int get customShapeSamples => 42;
}
