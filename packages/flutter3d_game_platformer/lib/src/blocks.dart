import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// A platform that gives way under whoever stands on it.
///
/// The oldest trick in the genre and one of the cheapest: a timer, and a
/// collider that leaves the world and comes back. What makes it a *mechanism*
/// rather than a script is that it has to be honest about the moment it goes —
/// a player who was walking across it and a player who has already jumped off
/// deserve the same platform, and that is what [sinceTouched] counting only
/// while somebody is on it buys.
///
/// Removal is deferred (`removeLater`), because the touch that starts the
/// countdown is dispatched from inside the collision step and taking a collider
/// out of the world there is how a broadphase gets corrupted.
final class Crumbling extends Mechanism with CollisionListener {
  Crumbling({
    super.name,
    required this.collider,
    this.delay = 0.5,
    this.gone = 2.5,
  }) {
    collider
      ..kind = ColliderKind.static
      ..userData = this;
    _restingAt.setFrom(collider.position);
  }

  final Collider collider;

  /// How long it holds after somebody steps on it.
  final double delay;

  /// How long it stays away before coming back.
  ///
  /// Zero or less means it never returns, which is a one-shot bridge — a fine
  /// thing to author and a terrible default.
  final double gone;

  final Vector3 _restingAt = Vector3.zero();

  /// Seconds of weight it has taken. Infinite until somebody stands on it.
  double sinceTouched = double.infinity;

  /// Whether it is currently out of the world.
  bool get hasFallen => _fallen;
  bool _fallen = false;
  double _away = 0.0;

  /// True on the step it gave way, for a crack and a puff of dust.
  bool crumbledThisStep = false;

  @override
  Vector3 get origin => _restingAt;

  @override
  void step(double dt) {
    crumbledThisStep = false;

    if (_fallen) {
      if (gone <= 0.0) return;
      _away += dt;
      if (_away < gone) return;
      _fallen = false;
      _away = 0.0;
      sinceTouched = double.infinity;
      world.collisions.add(collider);
      return;
    }

    if (sinceTouched.isInfinite) return;
    sinceTouched += dt;
    if (sinceTouched < delay) return;

    _fallen = true;
    crumbledThisStep = true;
    world.collisions.removeLater(collider);
  }

  /// Nothing activates it: weight does, through [takeWeight].
  @override
  ActivationOutcome activate(Activation by) => const NothingToDo();

  /// Standing on it is what starts the clock, and only standing on it.
  ///
  /// Read from the ground rather than from an overlap: a runner brushing the
  /// side of a crumbling platform on the way past has not stepped on it, and a
  /// trigger volume cannot tell the difference.
  void takeWeight() {
    if (_fallen) return;
    if (sinceTouched.isInfinite) sinceTouched = 0.0;
  }

  @override
  Map<String, Object?> save() => <String, Object?>{
        'since': sinceTouched.isFinite ? sinceTouched : null,
        'fallen': _fallen,
        'away': _away,
      };

  /// **Restoring is a move in both directions, and it used only to go one.**
  ///
  /// The collider is not in the saved state — [_fallen] is, and the world's
  /// copy of it is a consequence the block keeps in step. So a restore that
  /// only ever removed was right exactly as long as every restore was into a
  /// freshly loaded level, where nothing had fallen yet. Load a checkpoint
  /// taken *before* a platform crumbled, into a session where it since had,
  /// and the block came back solid-looking, walk-through, and unrecoverable:
  /// `_fallen` is false, so [step] returns at the first line and never adds it
  /// back. A floor the player can see and fall through.
  ///
  /// Compared against the previous value rather than asked of the world,
  /// because [_fallen] is what the block has always used to mean "the collider
  /// is out" — asking twice would be a second answer to the same question.
  @override
  void restore(Map<String, Object?> from) {
    final wasFallen = _fallen;
    final since = from['since'];
    sinceTouched = since is num ? since.toDouble() : double.infinity;
    _fallen = from['fallen'] == true;
    final away = from['away'];
    _away = away is num ? away.toDouble() : 0.0;
    if (_fallen == wasFallen) return;
    if (_fallen) {
      world.collisions.removeLater(collider);
    } else {
      world.collisions.add(collider);
    }
  }
}

/// A block that a ground pound breaks and nothing else does.
///
/// The pair to the verb: an attack with nothing to use it on is a key with no
/// door. Deliberately not damageable by anything else — a block that also
/// breaks when a crate falls on it is a block a level cannot rely on.
final class Breakable extends Mechanism {
  Breakable({super.name, required this.collider}) {
    collider
      ..kind = ColliderKind.static
      ..userData = this;
    _at.setFrom(collider.position);
  }

  final Collider collider;
  final Vector3 _at = Vector3.zero();

  bool get isBroken => _broken;
  bool _broken = false;

  /// True on the step it broke.
  bool brokeThisStep = false;

  @override
  Vector3 get origin => _at;

  /// Nothing activates a block. A pound breaks it, and a pound is a body
  /// arriving rather than a hand reaching out.
  @override
  ActivationOutcome activate(Activation by) => const NothingToDo();

  @override
  void step(double dt) => brokeThisStep = false;

  /// Breaks it, if it is not already broken. Returns whether it broke now.
  bool shatter() {
    if (_broken) return false;
    _broken = true;
    brokeThisStep = true;
    world.collisions.removeLater(collider);
    return true;
  }

  @override
  Map<String, Object?> save() => <String, Object?>{'broken': _broken};

  /// Both directions, for the reason written out at [Crumbling.restore].
  ///
  /// Worse here than there, because nothing ever un-breaks a broken block: a
  /// restore that could only remove had no second chance to put it right.
  @override
  void restore(Map<String, Object?> from) {
    final wasBroken = _broken;
    _broken = from['broken'] == true;
    brokeThisStep = false;
    if (_broken == wasBroken) return;
    if (_broken) {
      world.collisions.removeLater(collider);
    } else {
      world.collisions.add(collider);
    }
  }
}

/// A ladder, or a rope — the same thing at two speeds of swinging.
///
/// A volume you can be *in* rather than *on*: while a body is inside one,
/// gravity is somebody else's problem and up and down are the only directions
/// that matter. A rope is a ladder whose volume swings, and because a climber's
/// position is written from the volume's, the swing carries them — which is the
/// whole of rope physics a platformer needs and none of the pendulum it does
/// not.
final class Climbable extends Mechanism {
  Climbable({
    super.name,
    required this.collider,
    this.climbSpeed = 4.0,
    this.swing = 0.0,
    this.period = 2.4,
    double phase = 0.0,
  })  : _time = phase {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this;
    _restingAt.setFrom(collider.position);
  }

  final Collider collider;

  /// How fast a body climbs it.
  final double climbSpeed;

  /// How far it swings from rest, in metres. Zero for a ladder.
  final double swing;

  /// Seconds for a full swing there and back.
  final double period;

  final Vector3 _restingAt = Vector3.zero();
  final Vector3 _at = Vector3.zero();
  double _time = 0.0;

  /// Where it is now, which is where a climber is.
  @override
  Vector3 get origin => collider.position;

  /// How fast the volume itself is moving sideways, so a climber who lets go
  /// leaves with it.
  double get swingVelocity => _swingVelocity;
  double _swingVelocity = 0.0;

  /// Where the swing has got to.
  ///
  /// A rope's offset is a function of its own clock, so this is the clock. Not
  /// saving it is visible rather than subtle: the rope is somewhere when you
  /// save and somewhere else the instant you load, and a climber standing on it
  /// is left in the air beside it.
  @override
  Map<String, Object?> save() => <String, Object?>{'time': _time};

  @override
  void restore(Map<String, Object?> from) {
    final at = from['time'];
    if (at is num) _time = at.toDouble();
  }

  /// The top of the volume: where a climb ends and a step-off begins.
  double get top => _restingAt.y + collider.shape.boundsHalfExtents.y;

  /// Grabbing a rope is walking into it, not pressing a key at it.
  @override
  ActivationOutcome activate(Activation by) => const NothingToDo();

  @override
  void step(double dt) {
    if (swing <= 0.0 || period <= 0.0) return;
    _time += dt;
    final rate = 2.0 * math.pi / period;
    _at
      ..setFrom(_restingAt)
      ..x += swing * math.sin(rate * _time);
    // The derivative, so a climber who jumps off leaves with the rope's own
    // speed — which is what makes timing a jump off a swing worth anything.
    _swingVelocity = swing * rate * math.cos(rate * _time);
    collider.moveTo(_at);
  }
}
