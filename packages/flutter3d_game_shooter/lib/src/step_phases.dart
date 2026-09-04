import 'package:flutter3d_game/flutter3d_game.dart';

/// The moments inside a shooter's step that a game can hang its own rules off.
///
/// **Named here rather than in `flutter3d_game`, and that is the point of
/// [StepPhase] being a string.** "After the weapons fired" is a sentence about
/// this genre; a racer has no weapons and a platformer has no line of sight.
/// The engine declares the two every genre has — [StepPhase.begin] and
/// [StepPhase.end] — and each genre declares the rest.
///
/// The order is fixed and is the order `Simulation.step` announces them in:
///
/// 1. [StepPhase.begin] — last step's news is cleared, nothing has been read;
/// 2. [afterPlayer] — the player has looked, moved and been pushed out of
///    whatever they were inside; doors and lifts have moved;
/// 3. [afterWorld] — triggers have fired and the use key has been answered, so
///    what the level did this step can be read;
/// 4. [afterWeapons] — a shot this step exists and has been heard;
/// 5. [afterActors] — the monsters have thought and moved, and the dead are
///    counted;
/// 6. [StepPhase.end] — projectiles have flown and detonated and the game state
///    is resolved.
///
/// **A system runs inside the step, so the rules of a step apply to it**: no
/// clock, no loose dice (ARCHITECTURE.md §9.3). One that wants randomness takes
/// `Simulation.random`, which is the generator a snapshot records — a system
/// rolling its own is a replay that diverges and a save that comes back wrong.
abstract final class ShooterPhases {
  /// The player has moved and the level's machinery has moved with them.
  ///
  /// Where a rule about *where the player is* belongs: a floor that burns, a
  /// zone that drains air. Reading their position earlier reads last step's.
  static const StepPhase afterPlayer = StepPhase('afterPlayer');

  /// Triggers have dispatched and been published.
  ///
  /// Where a rule that reacts to what the level did belongs. Earlier than this
  /// the events are still the empty lists they were built with — the whole
  /// reason `publish` exists.
  static const StepPhase afterWorld = StepPhase('afterWorld');

  /// A shot fired this step has been reported as `ShotFired` and has been heard.
  ///
  /// Before the actors think, so a rule that reacts to a shot is acting on the
  /// same step the monsters are.
  static const StepPhase afterWeapons = StepPhase('afterWeapons');

  /// The monsters have thought, moved, hurt what they could reach, and the
  /// dead of this step are in `ActorSystem.died`.
  static const StepPhase afterActors = StepPhase('afterActors');
}
