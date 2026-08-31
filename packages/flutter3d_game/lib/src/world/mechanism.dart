import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'activation.dart';
import 'activation_outcome.dart';
import 'key_ring.dart';

export 'activation.dart';
export 'activation_outcome.dart';
export 'signal.dart';

/// Something in the level that can be switched on and that has a life of its
/// own between switchings.
///
/// The two halves are deliberate. [activate] is the edge — a hand on a button,
/// a foot in a trigger — and [step] is everything that happens afterwards
/// without anyone asking: a door finishing its swing, waiting, and closing
/// again. Splitting them is what lets one door reopen because a monster stood
/// in it while no one was looking.
abstract base class Mechanism {
  Mechanism({this.name});

  /// What other entities call this one, when anything does.
  final String? name;

  MechanismWorld? _world;

  /// The world this belongs to, once it has been added to one.
  MechanismWorld get world {
    final world = _world;
    if (world == null) {
      throw StateError('$runtimeType has not been added to a MechanismWorld');
    }
    return world;
  }

  ActivationOutcome activate(Activation by);

  /// Advances by [dt]. Called every simulation step, for every mechanism.
  void step(double dt) {}

  /// Where this is, for anything that wants to make a noise there.
  ///
  /// Null for a mechanism with no place — a relay wired between two others is
  /// somewhere in the level file and nowhere in the world.
  Vector3? get origin => null;

  /// Reports what happened to this mechanism since the last collection.
  ///
  /// Nothing by default, which is right for the ones that do their work by
  /// switching something else on. See [MechanismWorld.publish] for why each
  /// mechanism answers for itself rather than being interrogated.
  void collect(MechanismEvents into) {}

  /// What this mechanism holds that a save has to carry.
  ///
  /// **Abstract, and that is the whole point of it being here.** Each game used
  /// to keep a hand-written `switch` over mechanism types in its own `save`,
  /// listing the five or six it knew about — so a new mechanism was silently
  /// unsaved, and the shooter's notes had already recorded that as debt before
  /// the platformer inherited it. A door that was open closed itself on load, a
  /// once-only trigger fired again, and nothing anywhere said so.
  ///
  /// A mechanism with nothing to remember answers `const <String, Object?>{}`
  /// and says why in a line. That is not ceremony: the empty map is a decision
  /// somebody made, and the compiler now insists that somebody make it.
  ///
  /// **Identity is [name].** A save is a map from name to row, so a mechanism
  /// with no name cannot be saved and is skipped — the genre packages' own
  /// simulations say so where they write the map.
  Map<String, Object?> save();

  /// Puts back what [save] took. Given the same map it produced.
  ///
  /// Restoring is not the reverse of a step: it must leave the mechanism in a
  /// state it could have reached by playing, including any collider it owns.
  void restore(Map<String, Object?> from);
}

/// What the level's machinery did during one step.
final class MechanismEvents {
  /// Movers that began travelling.
  final List<Mechanism> started = <Mechanism>[];

  /// Movers that arrived.
  final List<Mechanism> stopped = <Mechanism>[];

  /// Pickups collected.
  final List<Mechanism> taken = <Mechanism>[];

  /// Exits reached. Usually empty, and never more than once per level.
  final List<Mechanism> reached = <Mechanism>[];

  /// Anything the level said to the player.
  ///
  /// A trigger fires from inside the collision dispatch, where there is nobody
  /// to return an outcome to, so it parks one and this collects it.
  final List<String> messages = <String>[];

  void _clear() {
    started.clear();
    stopped.clear();
    taken.clear();
    reached.clear();
    messages.clear();
  }
}

/// Every mechanism in the level, and the wiring between them.
///
/// Holds the [CollisionWorld] because almost everything here needs it: a mover
/// asks whether it is about to close on somebody, and the use key asks what the
/// player is looking at. Passing it separately to each of them would mean every
/// call site could pass a different one.
final class MechanismWorld {
  MechanismWorld(this.collisions);

  /// The physics this level runs on.
  ///
  /// Named for what it holds rather than called `world`, because a mechanism
  /// already has a `world` — this one — and two different things under one name
  /// is how `world.world.overlap` gets written.
  final CollisionWorld collisions;

  final List<Mechanism> _all = <Mechanism>[];
  final Map<String, Mechanism> _byName = <String, Mechanism>{};

  /// Everything in the level, in the order it was added.
  List<Mechanism> get all => List<Mechanism>.unmodifiable(_all);

  T add<T extends Mechanism>(T mechanism) {
    mechanism._world = this;
    _all.add(mechanism);
    final name = mechanism.name;
    // Last one wins, which the validator has already reported as a duplicate.
    if (name != null) _byName[name] = mechanism;
    return mechanism;
  }

  Mechanism? operator [](String name) => _byName[name];

  /// Switches on whatever answers to [name].
  ///
  /// An unknown name is [NothingToDo] rather than a throw: the validator
  /// reports a dangling target as an error before the level ever loads, and a
  /// level being repaired in an editor must still be playable.
  ActivationOutcome activate(String name, Activation by) =>
      _byName[name]?.activate(by) ?? const NothingToDo();

  /// Builds an activation for whatever [body] happens to be.
  ///
  /// Here rather than at each call site because a trigger firing from inside
  /// the physics step and a hand on a button have to produce the same thing —
  /// otherwise a door is locked to one of them and not the other.
  Activation activationBy(Collider? body) {
    final data = body?.userData;
    return Activation(
      by: body,
      keys: data is KeyHolder ? data.keys : const <String>{},
    );
  }

  /// What happened to the level's machinery this step.
  ///
  /// Filled by [publish]. Empty lists rather than nulls, and cleared rather
  /// than replaced, so a caller that drains them every step allocates nothing.
  final MechanismEvents events = MechanismEvents();

  void step(double dt) {
    for (var i = 0; i < _all.length; i++) {
      _all[i].step(dt);
    }
  }

  /// Asks every mechanism what it did, for a caller that wants to make a noise
  /// about it.
  ///
  /// **Called at the end of the simulation step, not from [step].** A button
  /// pressed with the use key is activated *after* mechanisms have stepped, so
  /// a door it starts is not yet moving when `step` returns — publishing there
  /// would report it a step late, every time. It looks like a wart and it is
  /// the honest shape: the end of the step is when the step's facts are in.
  ///
  /// **Each mechanism reports itself.** The application used to walk every
  /// mechanism in the level, type-testing as it went, and hand-diff
  /// `Mover.isMoving` against a map of sounds. Doing that here instead would
  /// only move the switch: this world would have to know what a door and a
  /// pickup are, and a game's own mechanism would have nowhere to report from.
  void publish() {
    events._clear();
    for (var i = 0; i < _all.length; i++) {
      _all[i].collect(events);
    }
  }

  /// The mechanism the player is looking at, within arm's reach.
  ///
  /// A ray rather than a proximity test, because two buttons a metre apart on
  /// the same wall have to be separately pressable — and because "what am I
  /// pointing at" is the question the player thinks they are asking.
  Mechanism? underCrosshair(
    Vector3 eye,
    Vector3 forward, {
    double reach = 2.5,
    Collider? ignore,
  }) {
    collisions.raycast(
      eye,
      forward,
      reach,
      _reach,
      ignore: ignore,
      includeTriggers: true,
    );
    final collider = _reach.collider;
    if (collider == null) return null;
    final data = collider.userData;
    return data is Mechanism ? data : null;
  }

  final RayHit _reach = RayHit();
}
