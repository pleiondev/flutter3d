/// Everything the HUD needs, gathered once a frame.
///
/// Split out of `hud.dart`: this is the data the widgets there read, and
/// keeping it separate from them is what keeps a widget from reaching into a
/// car and being the reason a lap counter changed.
library;

import 'package:flutter3d_app/flutter3d_app.dart'; // clockText, from flutter3d_ui
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
