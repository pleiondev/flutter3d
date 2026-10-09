/// A cutscene in a level: a mechanism a trigger starts, which plays a
/// [Sequence] in the step and directs the actors while it does.
library;

import '../actors/actor_system.dart';
import '../cinema/sequence.dart';
import '../cinema/sequence_player.dart';
import 'mechanism.dart';

/// A cutscene waiting in a level to be played.
///
/// **A mechanism, because that is what a level already has for "this
/// happens when the player gets here".** A trigger names it as its target, a
/// button can, a relay can chain it after a door; and a mechanism is stepped
/// with the world and saved by name, which is what a cutscene needs to be
/// rewound and replayed.
///
/// While it plays it is the actor system's director — see
/// `ActorSystem.director` — and lets go when it ends, or when a restore puts
/// the run back before it began.
final class Cutscene extends Mechanism {
  Cutscene({
    super.name,
    required Sequence sequence,
    required this.actors,
    this.once = true,
  }) : player = SequencePlayer(sequence);

  /// Where it plays: its step, its picture, its signals. The signals are
  /// published onto `player.events` as they fire, which the simulation that
  /// steps the level sets to its bus.
  final SequencePlayer player;

  /// The actors it directs.
  final ActorSystem actors;

  /// Whether it plays only the first time it is started.
  final bool once;

  bool _playing = false;
  bool _played = false;

  /// Whether it is playing now.
  bool get isPlaying => _playing;

  /// Whether it has been played, to the end or not — for a game whose own
  /// trigger should run a cutscene only once.
  bool get wasPlayed => _played;

  @override
  ActivationOutcome activate(Activation by) {
    if (_playing || (once && _played)) return const NothingToDo();
    player.restore(const <String, Object?>{'step': 0});
    _playing = true;
    _played = true;
    actors.director = player;
    return const Activated();
  }

  @override
  void step(double dt) {
    if (!_playing) return;
    player.advance();
    if (player.isFinished) _stop();
  }

  void _stop() {
    _playing = false;
    if (identical(actors.director, player)) actors.director = null;
  }

  @override
  Map<String, Object?> save() => <String, Object?>{
    'playing': _playing,
    'played': _played,
    'player': player.save(),
  };

  @override
  void restore(Map<String, Object?> from) {
    _played = from['played'] == true;
    final playing = from['playing'] == true;
    final row = from['player'];
    player.restore(
      row is Map ? row.cast<String, Object?>() : const <String, Object?>{},
    );
    if (playing) {
      _playing = true;
      actors.director = player;
    } else if (_playing) {
      _stop();
    }
  }
}
