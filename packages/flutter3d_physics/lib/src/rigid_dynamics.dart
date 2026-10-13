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

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_world.dart';
import 'contact.dart';
import 'dynamics.dart';
import 'rigid_body.dart';

/// **Extended outside this package: an `abstract base class`** (decision 5
/// of `tasks/1.0-api-review.md`), so a member added in a minor arrives with a
/// default body and every implementation keeps compiling.
abstract base class RigidDynamics {
  const RigidDynamics();

  /// The world the bodies' colliders are in.
  CollisionWorld get world;

  /// Metres per second squared: the world's (`world.properties.gravity`),
  /// which every backend reads rather than keeping one of its own. A fresh
  /// vector; a world's gravity is changed through `world.properties`.
  Vector3 get gravity;

  /// Every body added, in the order it was.
  List<RigidBody> get bodies;

  /// Starts stepping [body], whose collider is already in [world].
  RigidBody add(RigidBody body);

  /// Stops stepping [body] and takes its collider out of [world].
  void remove(RigidBody body);

  /// The body a collider belongs to, or null for level geometry.
  RigidBody? bodyOf(Collider collider);

  /// The body whose collider [world] calls [id] (`CollisionWorld.idOf`):
  /// what a contact event names, read back. Null for level geometry, for a
  /// body taken out, and for an id the world never handed out. The same on
  /// every backend, since every backend's bodies are in the one [world].
  RigidBody? bodyOfId(int id) => switch (world.colliderOf(id)) {
    final collider? => bodyOf(collider),
    null => null,
  };

  /// One fixed step of [dt] seconds.
  void step(double dt);

  /// What the steps promise about their numbers: the deterministic profile
  /// by default, the only one a backend that says nothing keeps. [Dynamics]
  /// steps under the one it was made with.
  SimulationProfile get profile => SimulationProfile.deterministic;

  /// What the last [step] found in contact, and what stopped being: one
  /// [StepContact] a pair of colliders (and a face, for two that meet on
  /// two), at least one of them a body, in their order
  /// (`StepContact.compareTo`) — by the world's ids, so the same on every
  /// backend and in every run, which is what lets a tape replay the
  /// contact events a game makes of them.
  ///
  /// Empty by default: a backend that reports none has none to report. Read
  /// between steps; the next step replaces it.
  List<StepContact> get contacts => const <StepContact>[];

  /// Shoves whatever the push's [CharacterPush.by] is walking into,
  /// horizontally, at most at the speed it is walking into it: how a
  /// kinematic character pushes a crate. Nothing by default: a backend
  /// without loose bodies pushes nothing.
  void push(CharacterPush push) {}

  /// What a save must carry beyond the bodies' own `save()` for a run
  /// restored from it to step on to the same bits: null when there is
  /// nothing, as for [Dynamics], whose state is its bodies'. A value JSON
  /// can hold, so a simulation puts it in its snapshot as it is. Null by
  /// default.
  Object? saveState() => null;

  /// Back to what [saveState] gave, after the bodies' own `restore`; null
  /// changes nothing. Nothing by default.
  void restoreState(Object? saved) {}
}

/// What [RigidDynamics.push] is handed: who is walking, how fast, and how
/// hard.
///
/// **One object, so a minor can hand a backend more** — a push's height, a
/// mass to push with — without breaking one written against 1.0.
/// **Reusable**: a game that pushes every step keeps one and sets it before
/// the call; a backend reads it during [RigidDynamics.push] and does not
/// keep it.
final class CharacterPush {
  CharacterPush({
    required this.by,
    required this.velocity,
    this.strength = 1.0,
  });

  /// The character's collider.
  Collider by;

  /// Its velocity this step, metres per second.
  Vector3 velocity;

  /// How much of the walking speed a pushed body takes up, one for all of
  /// it.
  double strength;
}
