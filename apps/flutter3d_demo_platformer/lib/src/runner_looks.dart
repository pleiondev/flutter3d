import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:vector_math/vector_math.dart';

// `RunnerClips` used to live here too. Split out to `runner_clips.dart`
// because it answers a different question — which clip, not how squashed —
// and re-exported so nothing that imports this file for the pose has to
// learn a second one for the clip.
export 'runner_clips.dart';

/// How the runner is drawn, worked out from what it is doing.
///
/// **Procedural, and not because clips would be better.** The model this game
/// ships has no animation in it at all — `animations: 0` — so the choice was
/// between a statue and arithmetic. But squash and stretch is also what a
/// platformer wants most: the reason a jump reads as a jump is anticipation and
/// follow-through, and those are functions of the same numbers the simulation
/// already has. When a rigged model arrives, this stays: a clip says *what* the
/// body is doing and this says *how hard*.
///
/// Nothing here draws. It takes a [Runner] and a delta, and gives back a scale,
/// a lean and a spin — which is what makes it testable without a renderer, and
/// is the same split `PlatformerLooks` uses for the coin.
final class RunnerLooks {
  RunnerLooks({this.tuning = const PoseTuning()});

  final PoseTuning tuning;

  /// Positive squashes, negative stretches. Decays to nothing.
  double _squash = 0.0;

  /// Radians of lean, positive forward.
  double _lean = 0.0;

  /// Radians of roll, positive towards the runner's right.
  double _roll = 0.0;

  /// How much of a mid-air flip is left, in turns.
  double _flip = 0.0;

  /// How much of the body's height the crouch has taken, as a fraction.
  ///
  /// Held apart from [_squash] because it is not an impulse: a squash is
  /// something that happened and decays, and a crouch is a state that is either
  /// true or over. Adding them into one number made standing up a decay, and a
  /// runner who stood up rose over a quarter of a second while the collider had
  /// already changed.
  double _crouch = 0.0;

  /// The pose, as a scale about the feet.
  ///
  /// Volume is kept: a body that squashes to four fifths of its height widens
  /// by the square root of five quarters, which is what makes it read as a
  /// squash rather than as a shrink.
  Vector3 get scale {
    // The crouch is not decayed and not scaled by `depth`: it is the body's own
    // height, so it applies whole and it lasts exactly as long as the crouch.
    final vertical = (1.0 - _squash * tuning.depth) * (1.0 - _crouch);
    final horizontal = 1.0 / math.sqrt(vertical.abs().clamp(0.05, 4.0));
    return Vector3(horizontal, vertical, horizontal);
  }

  /// Lean, in radians: forward when running, back when stopping hard.
  double get lean => _lean;

  /// Roll, in radians: into a turn, and towards a wall while sliding down one.
  double get roll => _roll;

  /// Extra yaw, in radians. A whole turn for a double jump, unwinding.
  double get spin => _flip * 2.0 * math.pi;

  /// Advances the pose by [dt] from what the runner did this step.
  void advance(Runner runner, double dt, List<GameEvent> events) {
    // Events first, because they set the pose; the decay below is what takes it
    // away again.
    if (events.has<Jumped>()) {
      _squash = -tuning.jumpStretch;
      if (!runner.isGrounded && runner.airJumpsLeft < 1) _flip = 1.0;
    }
    if (events.has<Landed>()) {
      // Proportional to how hard, and clamped: a fall from the top of the level
      // should read as heavier than a hop, and neither should turn the runner
      // inside out.
      final hardness = (runner.landingSpeed / tuning.hardLanding).clamp(
        0.0,
        1.0,
      );
      _squash = tuning.landSquash * hardness;
    }
    // The pounded landing is the same event, asked a different way: a landing
    // that ended a pound squashes harder than one that did not.
    if (events.whereType<Landed>().any((Landed e) => e.pounded)) {
      _squash = tuning.poundSquash;
    }
    if (events.has<Slid>()) _squash = tuning.slideSquash;

    // Everything decays back to standing. Exponential rather than linear, and
    // frame-rate independent for the reason the camera's lag is: a pose that
    // recovers in a fixed number of steps recovers at a different speed on a
    // different monitor.
    final recover = 1.0 - math.exp(-tuning.recovery * dt);
    _squash += (0.0 - _squash) * recover;
    _flip = math.max(0.0, _flip - dt / tuning.flipTime);

    // Lean follows speed, and rolls into the wall it is sliding down.
    final speed = math.sqrt(
      runner.body.velocity.x * runner.body.velocity.x +
          runner.body.velocity.z * runner.body.velocity.z,
    );
    final wantedLean = runner.isGrounded
        ? (speed / tuning.leanAtSpeed).clamp(0.0, 1.0) * tuning.leanAngle
        : 0.0;
    final wantedRoll = runner.isOnWall ? tuning.wallRoll : 0.0;
    final follow = 1.0 - math.exp(-tuning.leanFollow * dt);
    _lean += (wantedLean - _lean) * follow;
    _roll += (wantedRoll - _roll) * follow;

    // A crouched body is drawn short, which is the one place the pose has to
    // agree with the physics rather than decorate it — so it is *measured*
    // rather than tuned. The collider halves in height when it crouches, and a
    // model drawn at the eyeballed 0.685 a tuned `crouchSquash` gave was a
    // body visibly taller than the gap it had just fitted through.
    _crouch = runner.isCrouching
        ? 1.0 - runner.body.halfExtents.y / runner.standingHalfHeight
        : 0.0;
  }

  /// Forgets everything. For a death, a respawn, a level change.
  void reset() {
    _squash = 0.0;
    _lean = 0.0;
    _roll = 0.0;
    _flip = 0.0;
    _crouch = 0.0;
  }

  /// Where to put the model's origin so its feet are on the body's feet.
  ///
  /// **The arithmetic a crouch breaks if nobody does it.** The node is placed
  /// from the body's *centre*, and a crouching body's centre drops by half of
  /// what it lost — so a model placed at a fixed offset below that centre sinks
  /// into the floor by exactly that much, at exactly the moment the player is
  /// looking at it. [modelFloor] is the model's own lowest point in its local
  /// space, which the vertical scale moves along with everything else.
  double drawnHeight({
    required double bodyY,
    required double halfHeight,
    required double modelFloor,
  }) => bodyY - halfHeight - modelFloor * scale.y;
}

/// The numbers behind the pose, in one place for the same reason
/// `MovementTuning` is.
final class PoseTuning {
  const PoseTuning({
    this.depth = 0.35,
    this.jumpStretch = 0.5,
    this.landSquash = 0.9,
    this.poundSquash = 1.2,
    this.slideSquash = 0.8,
    this.hardLanding = 18.0,
    this.recovery = 9.0,
    this.flipTime = 0.42,
    this.leanAngle = 0.22,
    this.leanAtSpeed = 8.0,
    this.leanFollow = 8.0,
    this.wallRoll = 0.35,
  });

  /// How much a squash of one changes the height, as a fraction.
  final double depth;

  /// The stretch a jump leaves. Negative squash: taller and narrower.
  final double jumpStretch;

  /// The squash a landing at [hardLanding] leaves.
  final double landSquash;

  /// The squash a ground pound leaves, which is the heaviest thing there is.
  final double poundSquash;

  final double slideSquash;

  /// The falling speed that counts as a hard landing, in m/s.
  final double hardLanding;

  /// How fast the pose returns to standing, per second.
  final double recovery;

  /// How long a mid-air flip takes.
  final double flipTime;

  /// How far to lean at [leanAtSpeed], in radians.
  final double leanAngle;
  final double leanAtSpeed;
  final double leanFollow;

  /// How far to roll into a wall while sliding down it.
  final double wallRoll;
}
