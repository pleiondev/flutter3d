/// Everything the HUD needs, gathered once a frame.
///
/// Split out of `hud.dart`: this is the data the widgets there read, and
/// keeping it separate from them is what keeps a widget from reaching into a
/// car and being the reason a lap counter changed.
library;

import 'package:flutter3d_app/flutter3d_app.dart'; // clockText, from flutter3d_screens
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

/// Everything the display needs, gathered once a frame.
///
/// A record of values rather than the simulation itself, so that the widgets
/// cannot reach into a car and cannot be the reason a lap counter changed.
class RaceReadout {
  const RaceReadout({
    required this.speed,
    required this.lap,
    required this.laps,
    required this.position,
    required this.racers,
    required this.lapTime,
    required this.bestLap,
    required this.record,
    required this.tyres,
    required this.damage,
    this.recordJustSet = false,
    this.tyresRefused = false,
    required this.wrongWay,
    required this.countdown,
    required this.mode,
    required this.outline,
    required this.carsOnMap,
    this.behind = false,
    this.paused = false,
    this.notice,
  });

  /// Metres per second. Turned into something a driver reads at the last
  /// moment, because the simulation has no opinion about miles.
  final double speed;

  final int lap;
  final int laps;
  final int position;
  final int racers;
  final double lapTime;
  final double? bestLap;

  /// The quickest lap ever driven here, across every launch, or null before
  /// there is one. **Not [bestLap]**, which starts again with every race: a
  /// number that resets when the window closes is a readout, and what a driver
  /// is actually chasing is the one that does not.
  final double? record;

  /// Whether that record was set a moment ago, so the line can say so.
  final bool recordJustSet;

  /// What the car is standing on the road with.
  final String tyres;

  /// How broken the car is, from nought to one. Shown only once there is
  /// something to show: a line reading NONE every lap of every clean race is a
  /// line a driver stops seeing, and this one has to be noticed the once.
  final double damage;

  /// Whether a change was asked for and refused, which happens at any speed
  /// above a walk. Said rather than ignored: a key that does nothing and says
  /// nothing is a key a player decides is broken.
  final bool tyresRefused;
  final bool wrongWay;

  /// Seconds left on the lights, or null once they have gone out.
  final double? countdown;

  final RaceMode mode;

  /// The circuit as a flat outline, in world XZ.
  final List<Vector2> outline;

  /// Where each car is, in the same space. The first is the player.
  final List<Vector2> carsOnMap;

  /// Whether the machine is not keeping up.
  ///
  /// A count of dropped steps means nothing to a player; what it means is that
  /// the race is running in slow motion and saying nothing about it. This game
  /// could not tell at all until the loop arrived.
  final bool behind;

  /// Whether the player has stopped the race.
  final bool paused;

  /// What is said across the screen between circuits, and when the season ends.
  ///
  /// A race that is won and says nothing is a race that looks broken, which is
  /// what this game did: the finish line was crossed, the simulation marked it,
  /// and the car kept driving round an empty circuit forever.
  final String? notice;
}

/// A lap, to the thousandth, and `--:--.---` when nobody has driven one.
String formatLapTime(double seconds) => clockText(seconds, thousandths: true);

/// What is written across the middle of the screen this frame, or nothing.
///
/// **Two things want that one line, and the precedence has to be written
/// down somewhere a test can read it.** [betweenCircuits] is the end of a
/// race — the next circuit's name, or that the season is over — and it wins,
/// because a car put back on the road half a second before the flag is not
/// what the driver is waiting to be told.
///
/// [justRespawned] is the second, and it is here because it was nowhere:
/// `RacerProgress.respawnedThisStep` says in its own doc that it exists "for a
/// sound or a caption", the simulation has been setting it since it was
/// written, and the only readers were tests. Picking a car up, turning it round
/// and setting it down elsewhere is the most violent thing this simulation does
/// to a driver, and in silence it reads as the game losing its place rather
/// than as a rule being applied.
String? raceNotice({
  required String? betweenCircuits,
  bool justRespawned = false,
}) => betweenCircuits ?? (justRespawned ? 'Back on the track' : null);

/// The end of the season, and what to press to race it again.
///
/// **This was two words and no way to act on them.** The last race keeps
/// running under the caption for ever — nothing here calls `moveOn` after the
/// final circuit — and the key handler had no restart in it at all, so a
/// driver who had won five circuits was finished with the game whether they
/// wanted to be or not. Both ends of the sentence are here rather than in the
/// widget so the wording and the control cannot drift apart, and so a test can
/// read it without a window.
///
/// [touch] because a handset has no R and no way to say so: the tap layer the
/// screen mounts on exactly the same condition is what this names.
String seasonCompleteNotice({required bool touch}) => touch
    ? 'Season complete — tap to race it again'
    : 'Season complete — press R to race it again';
