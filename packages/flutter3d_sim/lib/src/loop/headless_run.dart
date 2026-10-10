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
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationVersion, WorldPosition;
import 'package:vector_math/vector_math.dart';

import '../input/game_action.dart';
import '../input/input_state.dart';
import '../level/entity_registry.dart';
import '../level/level.dart';
import '../save/snapshot.dart';
import 'run_outcome.dart';

/// A [HeadlessRun] that can be put back to a state it saved — what
/// `bisectTapes` needs of each side, to step on from a state it kept rather
/// than from the start every time it asks.
///
/// **Beside [HeadlessRun], not part of it**, so a game whose run cannot be
/// put back still plays, and a tool that needs this says so of it.
///
/// **Extended outside this package: an `abstract base class` with defaults**
/// (decision 5 of `tasks/1.0-api-review.md`), so a member added in a minor
/// arrives with a default body and every game keeps compiling.
abstract base class RestorableRun extends HeadlessRun {
  const RestorableRun();

  /// Puts the run back to [snapshot], one this run's [save] wrote.
  void restore(Snapshot snapshot);
}

/// One run of a level, started by a [HeadlessGame].
///
/// **Extended outside this package: an `abstract base class` with defaults**
/// (decision 5 of `tasks/1.0-api-review.md`), so a member added in a minor
/// arrives with a default body and every game keeps compiling.
abstract base class HeadlessRun {
  const HeadlessRun();

  /// Advances the run one fixed step of [dt] seconds, reading the
  /// `InputState` the run was started with.
  void step(double dt);

  /// The whole state, as a save or a replay checkpoint holds it.
  Snapshot save();

  /// Whether the run is still going, and how it ended if not.
  RunOutcome get outcome;

  /// Where the one the input moves is standing, in the world, in double
  /// precision (`docs/CONTRACTS.md`).
  WorldPosition get position;

  /// Where that one looks from, in the world. [position] by default.
  WorldPosition get eye => position;

  /// Writes the direction that one looks in into [out].
  void aim(Vector3 out);

  /// One sentence about how things stand, for an answer read as prose.
  String get summary;

  /// How things stand as data — positions, health, whatever the game counts —
  /// for an answer read by a program. Nothing by default.
  Map<String, Object?> get reading => const <String, Object?>{};
}

/// A game, as a tool that plays it blind needs one.
///
/// **Extended outside this package: an `abstract base class` with defaults**
/// (decision 5 of `tasks/1.0-api-review.md`), so a member added in a minor
/// arrives with a default body and every game keeps compiling.
abstract base class HeadlessGame {
  const HeadlessGame();

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

  /// Which simulation this game runs, so a tool refuses a tape recorded on
  /// another before playing it; null for a game that names none, whose tapes
  /// are played and let the checkpoints speak. Null by default.
  ///
  /// It was the opt-in interface `VersionedSimulation` before 1.0; on a base
  /// class it is a member with a default.
  SimulationVersion? get simulation => null;
}

/// One verb an [OrderedGame] takes: what it does, and the numbers it reads.
final class GameOrder {
  const GameOrder({
    required this.description,
    this.arguments = const <String, String>{},
  });

  /// What the order does, in a sentence a tool shows a caller.
  final String description;

  /// The order's arguments, every one a number, by name, each with a
  /// sentence saying what it means and what it is when left out.
  final Map<String, String> arguments;
}

/// A [HeadlessGame] played by orders as well as by the stick — a strategy,
/// where a selection is sent somewhere rather than one body walked there.
///
/// **A subclass a game opts into**: a game without orders is untouched, and a
/// tool offers its order verb only to a game that is one of these.
///
/// **An order travels through the input**, as [OrderTunes] writes it: a
/// tunable for the one step that takes it. So it is written on the run's
/// input tape with that step and given again at the same step when the tape
/// replays, and a run played by orders verifies and bisects as a run played
/// by the stick does. The run reads them with [OrderTunes.read].
///
/// **Extended outside this package**, on the terms [HeadlessGame] gives.
abstract base class OrderedGame extends HeadlessGame {
  const OrderedGame();

  /// The orders this game takes, by verb: `move`, `attack`.
  Map<String, GameOrder> get orders;
}

/// One order as a step reads it: the verb and its numbers.
final class GivenOrder {
  const GivenOrder(this.verb, this.arguments);

  final String verb;

  /// The arguments given; one left out is not here.
  final Map<String, double> arguments;

  /// The argument [name], or [fallback] when it was not given.
  double number(String name, [double fallback = 0.0]) =>
      arguments[name] ?? fallback;

  @override
  String toString() => 'GivenOrder($verb, $arguments)';
}

/// How an [OrderedGame]'s order is written into an [InputState]: the
/// tunable `order.<verb>`, and `order.<verb>.<argument>` for each argument.
///
/// **Tunables because they are what the input already records per step** —
/// one-shot, named, numeric, written on the tape and muted during a replay
/// with the devices. Nothing new crosses the tape's format.
abstract final class OrderTunes {
  /// What every order's tunables start with.
  static const String prefix = 'order.';

  /// The tunables [verb] with [arguments] is written as.
  static Map<String, double> encode(
    String verb,
    Map<String, double> arguments,
  ) => <String, double>{
    '$prefix$verb': 1.0,
    for (final MapEntry(:key, :value) in arguments.entries)
      '$prefix$verb.$key': value,
  };

  /// Gives [input] the order [verb] with [arguments], for the next step.
  static void give(
    InputState input,
    String verb, [
    Map<String, double> arguments = const <String, double>{},
  ]) {
    for (final MapEntry(:key, :value) in encode(verb, arguments).entries) {
      input.tune(key, value);
    }
  }

  /// The orders [input] holds this step, by verb in alphabetical order, so
  /// two given in one step are carried out in the same order on every
  /// replay whatever order the tape lists them in.
  static List<GivenOrder> read(InputState input) {
    final tunes = input.tunesThisStep;
    final verbs = <String>[
      for (final name in tunes.keys)
        if (name.startsWith(prefix) &&
            !name.substring(prefix.length).contains('.'))
          name.substring(prefix.length),
    ]..sort();
    return <GivenOrder>[
      for (final verb in verbs)
        GivenOrder(verb, <String, double>{
          for (final MapEntry(:key, :value) in tunes.entries)
            if (key.startsWith('$prefix$verb.'))
              key.substring(prefix.length + verb.length + 1): value,
        }),
    ];
  }
}
