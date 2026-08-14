import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'mechanism.dart';
import '../physics/layers.dart';

/// Where a mover is in its trip.
///
/// Derived from the numbers rather than stored beside them, so there is no way
/// for the state and the position to disagree.
enum MoverState {
  /// Sitting where it was authored.
  closed,

  /// On its way to the far end.
  opening,

  /// Sitting at the far end.
  open,

  /// On its way back.
  closing,
}

/// A block of level geometry that travels between two places.
///
/// Doors, lifts and platforms are one machine with three schedules. The machine
/// — a kinematic collider sliding along an offset at a fixed speed, refusing to
/// squash anybody, and recording its motion so the character controller can
/// carry a passenger — is all here. What differs is only who decides where it
/// should be going, which is the one method a subclass writes.
///
/// Travel is expressed as an offset from where the brush was authored, not as a
/// second position, because that is what an editor can show as a drag handle
/// and what survives moving the whole thing three metres left.
abstract base class Mover extends Mechanism {
  Mover({
    super.name,
    required this.collider,
    required Vector3 travel,
    this.speed = 2.0,
    this.wait = 3.0,
  })  : rest = collider.position.clone(),
        travel = travel.clone(),
        _span = travel.length {
    collider.kind = ColliderKind.kinematic;
    collider.userData = this;
  }

  /// The body that actually moves, already in the collision world.
  final Collider collider;

  /// Where it sits when closed.
  final Vector3 rest;

  /// How far, and in which direction, it goes when open.
  final Vector3 travel;

  /// Metres per second. Constant: easing a door looks better and makes the
  /// moment it becomes passable impossible to predict.
  final double speed;

  /// Seconds to hold at the far end before starting back. Zero or less means
  /// it stays there.
  final double wait;

  final double _span;

  /// 0 at [rest], 1 at `rest + travel`.
  double _progress = 0.0;
  double get progress => _progress;

  /// Where the subclass wants it: 0 or 1.
  double goal = 0.0;

  /// How long it has been sitting still at whichever end it is at.
  double _held = 0.0;
  double get heldFor => _held;

  MoverState get state {
    if (_progress <= 0.0) return MoverState.closed;
    if (_progress >= 1.0) return MoverState.open;
    return goal > _progress ? MoverState.opening : MoverState.closing;
  }

  bool get isMoving => _progress != goal;

  /// Whether backing off when it meets a body is the right answer.
  ///
  /// True for a door, because a door that closes on the player is a door that
  /// kills them through no mistake of theirs. False for a platform, which
  /// should simply stall — a platform that reverses whenever a monster wanders
  /// under it never completes a circuit, and the level stops working.
  bool get reverseWhenBlocked => true;

  /// Decides where this mover wants to be. The one thing a subclass owes.
  void schedule(double dt);

  @override
  void step(double dt) {
    schedule(dt);

    if (_progress == goal) {
      _held += dt;
      return;
    }
    _held = 0.0;

    // A zero-length trip would divide by zero and is meaningless anyway; the
    // validator warns about it, and here it simply arrives.
    final rate = _span < 1e-6 ? double.infinity : speed / _span;
    final next = _towards(_progress, goal, rate * dt);

    _at(next, _candidate);
    if (_isBlocked(_candidate)) {
      if (reverseWhenBlocked) {
        goal = goal > _progress ? 0.0 : 1.0;
      }
      return;
    }

    _progress = next;
    collider.moveTo(_candidate);
  }

  /// Puts the mover back where it started, motionless.
  ///
  /// For a level restart, which must not leave a door standing open because the
  /// player opened it before dying.
  void reset() {
    _progress = 0.0;
    goal = 0.0;
    _held = 0.0;
    collider.moveTo(rest);
    collider.clearDelta();
  }

  void _at(double progress, Vector3 out) {
    out
      ..setFrom(travel)
      ..scale(progress)
      ..add(rest);
  }

  /// Whether a solid body is standing where this is about to be.
  ///
  /// Only bodies, never level geometry: a door closing into its own frame
  /// overlaps the wall by design, and testing against the world would jam every
  /// door in the level shut.
  bool _isBlocked(Vector3 candidate) {
    world.collisions.overlap(
      collider.shape,
      candidate,
      _touching,
      mask: CollisionLayers.player | CollisionLayers.monster,
      ignore: collider,
      includeTriggers: false,
    );
    return _touching.isNotEmpty;
  }

  static double _towards(double from, double to, double by) {
    if (by.isInfinite) return to;
    final delta = to - from;
    if (delta.abs() <= by) return to;
    return from + by * (delta < 0.0 ? -1.0 : 1.0);
  }

  final Vector3 _candidate = Vector3.zero();
  final List<Collider> _touching = <Collider>[];
}

/// Opens when somebody asks, waits, and closes itself.
///
/// The lock lives on the door rather than on the button that opens it, because
/// a door with two buttons and a trigger should be locked from all three, and
/// the alternative is remembering to write the key on each of them.
final class Door extends Mover {
  Door({
    super.name,
    required super.collider,
    required super.travel,
    super.speed = defaultSpeed,
    super.wait = defaultWait,
    this.key,
  });

  /// Read by the level reader when a document does not say, so the default
  /// lives in one place rather than in the class and the reader both.
  static const double defaultSpeed = 2.5;
  static const double defaultWait = 3.0;

  /// The key colour this door demands, or null when it opens for anyone.
  final String? key;

  bool get isLocked => key != null;

  @override
  ActivationOutcome activate(Activation by) {
    final needed = key;
    if (needed != null && !by.keys.contains(needed)) {
      return Refused('You need the $needed key.');
    }
    if (goal == 1.0 && _progress >= 1.0) {
      // Already open: hold it open a little longer rather than doing nothing,
      // so leaning on the use key keeps a door open behind you.
      _held = 0.0;
      return const NothingToDo();
    }
    goal = 1.0;
    return const Activated();
  }

  @override
  void schedule(double dt) {
    if (wait <= 0.0) return;
    if (goal == 1.0 && _progress >= 1.0 && _held >= wait) goal = 0.0;
  }
}

/// Travels to the far end when called, and comes back.
///
/// The difference from a [Door] is what a second activation means: pressing a
/// door again holds it open, calling a lift again while it is up sends it back
/// down. A lift is a toggle; a door is a request.
final class Lift extends Mover {
  Lift({
    super.name,
    required super.collider,
    required super.travel,
    super.speed = defaultSpeed,
    super.wait = defaultWait,
  });

  static const double defaultSpeed = 1.6;
  static const double defaultWait = 4.0;

  @override
  ActivationOutcome activate(Activation by) {
    // Mid-travel calls are ignored rather than queued. A lift that changes its
    // mind halfway is a lift that drops its passenger.
    if (isMoving) return const NothingToDo();
    goal = _progress >= 1.0 ? 0.0 : 1.0;
    _held = 0.0;
    return const Activated();
  }

  @override
  void schedule(double dt) {
    if (wait <= 0.0) return;
    if (_progress >= 1.0 && goal == 1.0 && _held >= wait) goal = 0.0;
  }
}

/// Goes back and forth for ever, whether or not anyone is watching.
///
/// Nobody activates it, which is why [activate] says so instead of pretending.
/// Timing is the level designer's problem and the reason [Mover.wait] exists:
/// a platform that pauses at each end is one a player can step onto.
final class Platform extends Mover {
  Platform({
    super.name,
    required super.collider,
    required super.travel,
    super.speed = defaultSpeed,
    super.wait = defaultWait,
  }) {
    goal = 1.0;
  }

  static const double defaultSpeed = 1.5;
  static const double defaultWait = 1.5;

  /// A platform stalls rather than reversing — see [Mover.reverseWhenBlocked].
  @override
  bool get reverseWhenBlocked => false;

  @override
  ActivationOutcome activate(Activation by) => const NothingToDo();

  @override
  void schedule(double dt) {
    if (isMoving) return;
    if (_held < wait) return;
    goal = _progress >= 1.0 ? 0.0 : 1.0;
  }

  /// Offsets the cycle, so a row of platforms does not move as one slab.
  ///
  /// Called once at spawn with the level's `phase`, in seconds.
  void offsetBy(double seconds) {
    if (seconds <= 0.0) return;
    var remaining = seconds;
    // Stepped rather than solved, because the answer has to respect the same
    // waits and reversals the running platform will, and a closed form would
    // be a second implementation of the schedule that could disagree with it.
    const tick = 1.0 / 60.0;
    while (remaining > 0.0) {
      step(math.min(tick, remaining));
      remaining -= tick;
    }
    collider.clearDelta();
  }
}
