/// A level played with nobody at a window — what a tool that drives a game
/// blind needs from one, whatever the game is.
///
/// **Here, beside [RunOutcome], for the reason that file gives.** The tools
/// live above the genres — an MCP server an agent plays through, a farm of
/// playtests — the answers have to come from a genre package, and a genre
/// package depends on neither the tool nor anything that draws. So the
/// vocabulary both sides share sits down here with them. Before it, the tool
/// imported one genre and called that genre's types directly, and a second
/// genre would have been a second tool.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart' show CollisionWorld;
import 'package:vector_math/vector_math.dart';

import '../input/game_action.dart';
import '../input/input_state.dart';
import '../level/entity_registry.dart';
import '../level/level.dart';
import '../save/snapshot.dart';
import 'run_outcome.dart';

/// One run of a level, started by a [HeadlessGame].
abstract interface class HeadlessRun {
  /// Advances the run one fixed step of [dt] seconds, reading the
  /// `InputState` the run was started with.
  void step(double dt);

  /// The whole state, as a save or a replay checkpoint holds it.
  Snapshot save();

  /// Whether the run is still going, and how it ended if not.
  RunOutcome get outcome;

  /// Where the one the input moves is standing.
  Vector3 get position;

  /// Writes where that one looks from into [out].
  void eye(Vector3 out);

  /// Writes the direction that one looks in into [out].
  void aim(Vector3 out);

  /// One sentence about how things stand, for an answer read as prose.
  String get summary;

  /// How things stand as data — positions, health, whatever the game counts —
  /// for an answer read by a program.
  Map<String, Object?> get reading;
}

/// A game, as a tool that plays it blind needs one.
abstract interface class HeadlessGame {
  /// What the tool calls it in a sentence: `shooter`, `platformer`.
  String get name;

  /// The buttons a caller may hold down, by the name it asks for them by —
  /// a shooter's `fire`. Movement and looking are not here: every game reads
  /// them from the same stick and look axes.
  Map<String, GameAction> get buttons;

  /// The entities a level of this game may spawn.
  EntityRegistry registry();

  /// [level], already added to [world], spawned and ready to step, reading
  /// [input].
  HeadlessRun start(Level level, CollisionWorld world, InputState input);
}
