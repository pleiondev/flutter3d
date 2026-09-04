/// The readouts this genre has, as widgets a game lays out itself.
///
/// **Not a HUD.** The demo's display is a speedometer with a needle, a mirror,
/// a minimap of the circuit and a steering band — all of that is a game's
/// drawing. What belongs to the genre is the pair below, which every racing
/// game has and every one of them gets subtly wrong the first time: the lap
/// counter and the position.
///
/// The genre ships the readouts and the game ships the layout, which is the
/// split the other two genres' `hud.dart` files make.
library;

import 'package:flutter/widgets.dart';

import 'race_state.dart';

/// How a game wants its readouts drawn.
final class ReadoutStyle {
  const ReadoutStyle({
    this.text = const TextStyle(color: Color(0xFFFFFFFF), fontSize: 18.0),
    this.dim = const Color(0x66FFFFFF),
  });

  final TextStyle text;

  /// The `/ 3` half of "1 / 3", and anything the driver is not being asked to
  /// look at at two hundred kilometres an hour.
  final Color dim;
}

/// Which lap this is, out of how many.
///
/// **Counts from one and stops at the last.** [RacerProgress.lap] is how many
/// laps are *complete*, so the first lap of a race reads nought — and the last
/// one, once crossed, reads one more than the race has. Both were drawn
/// straight to the screen by every game that reached for the field, which is
/// the reason this widget exists rather than a getter.
///
/// **Draws nothing in a mode that counts no laps.** `RaceMode.freeRoam` has no
/// lap to be on, and a counter reading "1 / 0" is worse than no counter.
final class LapReadout extends StatelessWidget {
  const LapReadout({
    super.key,
    required this.racer,
    required this.race,
    this.style = const ReadoutStyle(),
  });

  final RacerProgress racer;
  final RaceState race;
  final ReadoutStyle style;

  @override
  Widget build(BuildContext context) {
    if (!race.mode.countsProgress) return const SizedBox.shrink();
    final showing = (racer.lap + 1).clamp(1, race.laps);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('$showing', style: style.text),
        Text(' / ${race.laps}', style: style.text.copyWith(color: style.dim)),
      ],
    );
  }
}

/// Where this car is in the field.
///
/// Takes the [RaceState] rather than a number, because working out a position
/// is [RaceState.positionOf]'s job and a game that computed its own got a
/// different answer on the step somebody crossed the line.
///
/// **Draws nothing when there is nobody to be ahead of.** One car in a time
/// trial is always first, and a readout saying so is a readout that means
/// nothing.
final class PositionReadout extends StatelessWidget {
  const PositionReadout({
    super.key,
    required this.racer,
    required this.race,
    this.style = const ReadoutStyle(),
    this.ordinals = const <String>['st', 'nd', 'rd'],
    this.otherwise = 'th',
  });

  final RacerProgress racer;
  final RaceState race;
  final ReadoutStyle style;

  /// The suffixes for first, second and third. English by default and
  /// replaceable, because a genre package has no business deciding what
  /// language a game is in.
  final List<String> ordinals;

  /// What every other place gets.
  final String otherwise;

  @override
  Widget build(BuildContext context) {
    if (race.progress.length < 2 || race.phase == RacePhase.countdown) {
      return const SizedBox.shrink();
    }
    final place = race.positionOf(racer.index);
    final suffix = place >= 1 && place <= ordinals.length
        ? ordinals[place - 1]
        : otherwise;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('$place', style: style.text),
        Text(suffix, style: style.text.copyWith(color: style.dim)),
        Text(
          ' / ${race.progress.length}',
          style: style.text.copyWith(color: style.dim),
        ),
      ],
    );
  }
}
