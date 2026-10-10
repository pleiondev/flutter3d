import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The moments inside a shooter's step that a game hangs its own rules off,
/// through `GameSimulation.addSystem`.
///
/// **Named here rather than in the engine, and that is the point of a phase
/// being a name.** "After the weapons fired" is a sentence about this genre;
/// a racer has no weapons and a platformer has no line of sight. They are
/// phases of the loop's kind (`LoopPhase.step`), named for the genre, so a
/// system written for a loop phase is written the same way for one of these:
/// it is handed a `LoopContext` either way.
///
/// The order is fixed and is the order `GameSimulation.step` announces them
/// in:
///
/// 1. [begin] — last step's news is cleared, nothing has been read;
/// 2. [afterPlayer] — the player has looked, moved and been pushed out of
///    whatever they were inside; doors and lifts have moved;
/// 3. [afterWorld] — triggers have fired and the use key has been answered, so
///    what the level did this step can be read;
/// 4. [afterWeapons] — a shot this step exists and has been heard;
/// 5. [afterActors] — the monsters have thought and moved, and the dead are
///    counted;
/// 6. [end] — projectiles have flown and detonated and the game state is
///    resolved.
///
/// **A system runs inside the step, so the rules of a step apply to it**: no
/// clock, no loose dice (ARCHITECTURE.md §9.3). One that wants randomness takes
/// `GameSimulation.random`, which is the generator a snapshot records — a
/// system rolling its own is a replay that diverges and a save that comes back
/// wrong.
abstract final class ShooterPhases {
  /// The top of the step: last step's news is cleared, nothing has been
  /// read.
  static const LoopPhase begin = LoopPhase.step('shooter.begin');

  /// The player has moved and the level's machinery has moved with them.
  ///
  /// Where a rule about *where the player is* belongs: a floor that burns, a
  /// zone that drains air. Reading their position earlier reads last step's.
  static const LoopPhase afterPlayer = LoopPhase.step('shooter.afterPlayer');

  /// Triggers have dispatched and been published.
  ///
  /// Where a rule that reacts to what the level did belongs. Earlier than this
  /// the events are still the empty lists they were built with — the whole
  /// reason `publish` exists.
  static const LoopPhase afterWorld = LoopPhase.step('shooter.afterWorld');

  /// A shot fired this step has been reported as `ShotFired` and has been
  /// heard.
  ///
  /// Before the actors think, so a rule that reacts to a shot is acting on the
  /// same step the monsters are.
  static const LoopPhase afterWeapons = LoopPhase.step('shooter.afterWeapons');

  /// The monsters have thought, moved, hurt what they could reach, and the
  /// dead of this step are in `ActorSystem.died`.
  static const LoopPhase afterActors = LoopPhase.step('shooter.afterActors');

  /// The bottom: projectiles have flown and detonated and the game state is
  /// resolved.
  static const LoopPhase end = LoopPhase.step('shooter.end');

  /// Every phase, in the order the step reaches them.
  static const List<LoopPhase> all = <LoopPhase>[
    begin,
    afterPlayer,
    afterWorld,
    afterWeapons,
    afterActors,
    end,
  ];
}
