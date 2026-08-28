import 'dart:math' as math;

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';

/// Which clip the runner should be playing.
///
/// A pure function from what the simulation says to a name in the model, which
/// is what makes it testable without a renderer — and the reason it is here
/// rather than inside the frame loop. `AnimationPlayer` does the crossfade;
/// this only decides what to fade *to*.
///
/// The names carry the exporter's armature prefix because that is what is in
/// the file: `crossFadeToNamed` matches exactly, and inventing tidier names
/// here would mean a table mapping tidy names to real ones, which is this
/// function with an extra step.
abstract final class RunnerClips {
  static const String idle = 'CharacterArmature|Idle';
  static const String walk = 'CharacterArmature|Walk';
  static const String run = 'CharacterArmature|Run';
  static const String jump = 'CharacterArmature|Jump';
  static const String falling = 'CharacterArmature|Jump_Idle';
  static const String landing = 'CharacterArmature|Jump_Land';
  static const String duck = 'CharacterArmature|Duck';
  static const String death = 'CharacterArmature|Death';

  /// Every clip this game asks for, so a test can check the model has them.
  static const List<String> all = <String>[
    idle,
    walk,
    run,
    jump,
    falling,
    landing,
    duck,
    death,
  ];

  /// What to play, given what the runner is doing.
  ///
  /// Ordered by what overrides what, and the order is the whole content: dead
  /// beats everything, being in the air beats being crouched, and speed only
  /// decides between the two grounded clips. A state machine written as a
  /// switch over an enum would need the enum to exist first, and the
  /// simulation deliberately has no such thing — it reports facts, and which
  /// fact wins is a decision about looks.
  static String forRunner(Runner runner) {
    if (!runner.health.isAlive) return death;
    if (runner.climbing != null) return walk;
    if (!runner.isGrounded) {
      return runner.body.velocity.y > 0.5 ? jump : falling;
    }
    if (runner.isCrouching) return duck;
    final speed = math.sqrt(
      runner.body.velocity.x * runner.body.velocity.x +
          runner.body.velocity.z * runner.body.velocity.z,
    );
    if (speed > 4.0) return run;
    if (speed > 0.4) return walk;
    return idle;
  }

  /// How fast to play [clip] at [speed] metres a second.
  ///
  /// A run clip played at a fixed rate while the body moves at a variable one
  /// is the sliding-feet problem, and it is the single most noticeable thing
  /// about a character that is otherwise animated well.
  static double rateFor(String clip, double speed) {
    if (clip == run) return (speed / 6.0).clamp(0.6, 1.8);
    if (clip == walk) return (speed / 2.4).clamp(0.5, 1.6);
    return 1.0;
  }
}
