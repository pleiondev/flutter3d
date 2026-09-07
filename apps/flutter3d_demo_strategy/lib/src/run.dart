/// The match as a run: opened, watched, written down, and put back.
///
/// **What was missing here was not a feature but a shape.** The other three
/// demos read a document, watch how it is going, save it and resume it through
/// one class — `RunSession`, in `flutter3d_session` — and this one did none of
/// those things: the map was read in the widget's `initState`, the match was
/// stepped straight off a `Ticker` at a constant sixtieth, and nothing was ever
/// written anywhere. A match that cannot be written down is also a match that
/// cannot be rewound or recorded, so this file is what a tape in the live game
/// has to stand on rather than a convenience on top of one.
///
/// **The genre package does not know this file exists, and that is the
/// boundary.** No genre package in this repository depends on
/// `flutter3d_session`; a session is what an *application* has, because only an
/// application knows where a save lives and which side the person at the mouse
/// is playing. What the package owes one is two methods — `Match.save` and
/// `Match.restore` — and both were written before there was a session to call
/// them.
///
/// **Restoring happens after the level is whole**, which is `RunSession`'s own
/// contract and not a habit: [open] returns a fully staged match, and only then
/// does the session hand it a snapshot. It matters here for a reason the other
/// genres do not have. A restored match carries the crowd a side had grown by
/// the moment it was saved, which is larger than the crowd the document stages,
/// and the batch that draws it is sized once in [stage] — see the capacity
/// there. Restoring during the assembly would size the batch against the
/// document instead of against the save.
library;

import 'package:flutter3d/flutter3d.dart' show GraphicsDevice;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_session/flutter3d_session.dart';

import 'level_document.dart';
import 'staging.dart';

/// How much simulated time one step of this game covers.
///
/// **Named once and read in two places on purpose**: the demo's clock and the
/// playthrough that plays the same map without a screen. A test that stepped at
/// its own rate would be measuring a game nobody ships — a crowd walks a fixed
/// distance per step, so the size of the step is the speed of the match.
const double strategyStep = 1.0 / 60.0;

/// The clock a frame is spent through.
///
/// A builder rather than one shared instance, because a [FixedStep] carries an
/// accumulator: two loops handed the same one would spend each other's time.
/// The ceiling on steps per frame is the class's own, and it earns its keep
/// here more than anywhere else in this repository — a step over a crowd of
/// hundreds is the most expensive step any of these games runs, so a frame that
/// fell behind and then tried to catch up is exactly the spiral that class was
/// written to refuse.
FixedStep strategyClock() => FixedStep(stepSeconds: strategyStep);

/// How a match reads to the side watching it, in the words every genre shares.
///
/// **Three answers folded onto two, and the draw is where the folding shows.**
/// A match can quite properly finish level — `Match` treats that as a real
/// answer rather than a missing one, because two sides running one policy from
/// mirrored starts *should* come out equal. [RunOutcome] has no word for it, so
/// a draw is read here as a loss, and what makes that the right reading is what
/// the caller does next: `RunSession.advance` clears the save when a run is won
/// and hands a loss to `onLost`, and a match that ended without this side
/// crossing the line is a match there is nothing to carry out of either way.
///
/// The screen is not told this. `standingText` in `hud_readout.dart` reads the
/// [Standing] itself and says "drawn", which is the honest word for a player;
/// a session's two-way answer and a scoreboard's three-way one are different
/// sentences and neither should be derived from the other.
///
/// A free function rather than a method, so the reading can be asserted without
/// staging a match — which is to say without a [GraphicsDevice].
RunOutcome outcomeFor(Standing standing, {required int side}) {
  if (!standing.isOver) return RunOutcome.playing;
  return standing.winner == side ? RunOutcome.won : RunOutcome.lost;
}

/// This game's answers to the five questions a run asks.
///
/// Two of the five are one line each, which is the point of having the base
/// class: a match already knows how to write itself down and read itself back,
/// so a session over it is mostly a statement of who is watching.
final class StrategyRun extends RunSession<Staged> {
  /// Plays [firstLevel] on behalf of [side], keeping the run in [saves].
  StrategyRun({
    required super.firstLevel,
    required super.saves,
    required this.openDevice,
    required this.onLevelBuilt,
    this.side = viewerSide,
  });

  /// The device the picture is uploaded through, waited for rather than
  /// assumed: the first map is asked for while the renderer is still opening.
  final Future<GraphicsDevice> Function() openDevice;

  /// Everything the widget has to do with a match once it exists — put the
  /// visuals in its scene, open a command post over the crowd. Handed in
  /// because it touches the widget's own fields, which a run has no business
  /// holding.
  final void Function(Staged staged) onLevelBuilt;

  /// Whose run this is. A number rather than a nought written out, for the
  /// reason the rest of this genre gives: how many sides a match has is read
  /// out of the document.
  final int side;

  /// Reads a map and stages a match on it.
  ///
  /// **The document is read before the device is asked for**, which is the
  /// order `main.dart` used to keep by hand and the reason is unchanged: a map
  /// that will not parse should not have cost a device first. The throw goes to
  /// `RunSession`, which puts the filename on the screen instead of leaving a
  /// black one.
  @override
  Future<Staged> open(String asset) async {
    final StrategyMap map = await StrategyMap.load(asset: asset);
    final Staged staged = stage(device: await openDevice(), map: map);
    onLevelBuilt(staged);
    return staged;
  }

  @override
  RunOutcome outcomeOf(Staged level) =>
      outcomeFor(level.match.standing, side: side);

  /// Nowhere. **A map is not a level in a chain here**, and saying so is a
  /// decision rather than a gap: the other genres end a level at an exit that
  /// names the next document, and a match ends when somebody wins it. A
  /// campaign would be a document listing maps, which is a thing this game does
  /// not have and would not get by guessing a filename.
  @override
  String? nextOf(Staged level) => null;

  @override
  Snapshot snapshotOf(Staged level) => level.match.save();

  @override
  void restoreInto(Staged level, Snapshot snapshot) =>
      level.match.restore(snapshot);
}
