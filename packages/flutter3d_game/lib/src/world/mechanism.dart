import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'key_ring.dart';

/// Who is switching something on, and what they are carrying.
///
/// Passed by value down the whole chain — a trigger volume hands it to the lift
/// it calls, which hands it to whatever that lift relays to — so a locked door
/// three relays away still knows whose keys to check.
final class Activation {
  const Activation({
    this.by,
    this.keys = const <String>{},
  });

  /// The body that did it, when there was one. Null for a mechanism switched
  /// on by another mechanism rather than by somebody walking into it.
  final Collider? by;

  /// What that body is carrying. A door reads it; nothing else does yet.
  final Set<String> keys;
}

/// What came of asking a mechanism to do something.
///
/// A sealed hierarchy rather than a bool because the interesting case is the
/// middle one: a locked door has to tell the player *why* nothing happened, and
/// a caller that only knows "it did not work" cannot.
sealed class ActivationOutcome {
  const ActivationOutcome();

  /// Something worth showing the player, or null when there is nothing to say.
  String? get message => null;
}

/// It did what it was asked.
final class Activated extends ActivationOutcome {
  const Activated();
}

/// It would not, and here is what to tell the player.
final class Refused extends ActivationOutcome {
  const Refused(this.message);

  @override
  final String message;
}

/// There was nothing to do — already open, still moving, or no such name.
///
/// Distinct from [Refused] because pressing a button twice is not a failure and
/// should not print anything.
final class NothingToDo extends ActivationOutcome {
  const NothingToDo();
}

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
}

/// A mechanism that does nothing itself and switches something else on.
///
/// Buttons and trigger volumes are the same thing wearing different clothes:
/// both watch for a condition and relay. Everything except the condition lives
/// here — the target, the once-only latch, the relay itself — so adding a third
/// kind of switch is a class with one method.
abstract base class Signal extends Mechanism {
  Signal({
    super.name,
    required this.target,
    this.once = false,
  });

  /// The [Mechanism.name] this switches on.
  final String target;

  /// Whether it works only the first time. A trap door should not rearm; a
  /// lift call button should.
  final bool once;

  bool _spent = false;

  /// Whether this has already fired and will not fire again.
  bool get isSpent => _spent;

  /// Passes the activation on to [target].
  ///
  /// The latch closes only on a genuine [Activated]: a player who walked into a
  /// locked door's trigger without the key has not used up their one chance.
  ActivationOutcome fire(Activation by) {
    if (_spent) return const NothingToDo();
    final outcome = world.activate(target, by);
    if (once && outcome is Activated) _spent = true;
    return outcome;
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

  void step(double dt) {
    for (var i = 0; i < _all.length; i++) {
      _all[i].step(dt);
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
