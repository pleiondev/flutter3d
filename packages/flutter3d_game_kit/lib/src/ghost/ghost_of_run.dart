import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// The track of one body through a shared run, or the reason there is none.
///
/// **Not sent; played again.** A run is a tape and a starting state, and the
/// simulation it was played in is deterministic, so what a viewer needs to
/// draw a ghost is already in the bundle: [replay] plays the tape through the
/// game's own staging, headless, and writes the body down as it goes. Only
/// the game knows how to stage its level, so that half is the caller's.
///
/// **When the tape cannot be played, the poses can.** A run recorded on other
/// physics, on another version of the game's simulation, or with its level
/// edited as it went would come out somewhere else if replayed — so its tape
/// is not, and the ghost is read off the pose record written beside it, the
/// track of [body], at that record's own rate. A run with no pose record is
/// refused with the reason. A run in another version of [level] is refused
/// either way: its ghost would go through walls.
///
/// [note] says what the ghost is — how long, and why it came from the pose
/// record when it did — as a [GhostNote] a screen words in the player's
/// language with [GhostNote.say].
({Tape? ghost, GhostNote note}) ghostOfRun(
  Level level,
  Demo demo, {
  required String body,
  required SimulationVersion simulation,
  required Tape Function() replay,
  PhysicsBackend physics = const DartPhysics(),
}) {
  if (demo.levelHash != level.digestHex) {
    return (ghost: null, note: const GhostNote._(GhostNote.otherLevel));
  }
  final GhostNote? notReplayed = demo.levelSwaps.isNotEmpty
      ? const GhostNote._(GhostNote.levelEdited)
      : switch (demo.physics) {
          final String recorded when recorded != physics.name => GhostNote._(
            GhostNote.otherPhysics,
            physics: recorded,
            here: physics.name,
          ),
          _ => switch (demo.refusalOn(simulation)) {
            final String reason => GhostNote._(
              GhostNote.otherSimulation,
              reason: reason,
            ),
            null => null,
          },
        };
  if (notReplayed != null) {
    final track = demo.poses?.track(body);
    if (track == null || track.isEmpty) return (ghost: null, note: notReplayed);
    return (
      ghost: track,
      note: GhostNote._(
        GhostNote.fromPoseRecord,
        seconds: track.seconds,
        because: notReplayed,
      ),
    );
  }
  final track = replay();
  return (
    ghost: track,
    note: GhostNote._(GhostNote.replayed, seconds: track.seconds),
  );
}

/// What [ghostOfRun] has to say about a ghost: an [id] and what it carries,
/// worded by [say] in the player's language.
///
/// **An id, not a sentence.** It answered an English sentence, which a game
/// in another language could only show in English or parse. The ids are an
/// open set — compare [id] with the constants, and expect a later release to
/// add one — and [say] words every id it knows in English and Russian.
final class GhostNote {
  const GhostNote._(
    this.id, {
    this.seconds,
    this.physics,
    this.here,
    this.reason,
    this.because,
  });

  /// The run was made in another version of this level, so there is no
  /// ghost: it would go through walls.
  static const String otherLevel = 'otherLevel';

  /// The run had its level edited as it went, so its tape is not replayed.
  static const String levelEdited = 'levelEdited';

  /// The run was played on [physics], and this game is on [here].
  static const String otherPhysics = 'otherPhysics';

  /// The run was recorded on other rules — [reason] says which, in the
  /// simulation's own words.
  static const String otherSimulation = 'otherSimulation';

  /// A ghost of [seconds] read off the pose record, [because] the tape could
  /// not be replayed.
  static const String fromPoseRecord = 'fromPoseRecord';

  /// A ghost of [seconds], replayed from the tape.
  static const String replayed = 'replayed';

  /// Which of the above this is.
  final String id;

  /// How long the ghost is, in seconds, for [fromPoseRecord] and [replayed].
  final double? seconds;

  /// The physics the run was played on, and this game's, for
  /// [otherPhysics].
  final String? physics;
  final String? here;

  /// The simulation's refusal, for [otherSimulation].
  final String? reason;

  /// Why the tape was not replayed, for [fromPoseRecord].
  final GhostNote? because;

  /// The note as a sentence in the language [languageCode] names — `ru`, or
  /// English for anything else.
  String say([String languageCode = 'en']) {
    final ru = languageCode == 'ru';
    final length = seconds?.toStringAsFixed(1) ?? '?';
    return switch (id) {
      otherLevel =>
        ru
            ? 'забег сделан в другой версии этого уровня'
            : 'the run was made in another version of this level',
      levelEdited =>
        ru
            ? 'уровень этого забега правили по ходу игры'
            : 'the run had its level edited as it went',
      otherPhysics =>
        ru
            ? 'забег сыгран на физике $physics, а эта игра — на $here'
            : 'the run was played on the $physics physics, and this game is '
                  'on $here',
      otherSimulation => reason ?? id,
      fromPoseRecord =>
        ru
            ? 'призрак на $length с из записи поз — ${because?.say(languageCode)}'
            : 'a ghost of $length s from its pose record — '
                  '${because?.say(languageCode)}',
      replayed => ru ? 'призрак на $length с' : 'a ghost of $length s',
      _ => id,
    };
  }

  @override
  String toString() => say();
}
