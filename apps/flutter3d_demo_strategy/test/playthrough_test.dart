/// The map this demo ships with, played to somebody winning it.
///
///     flutter test test/playthrough_test.dart
///
/// **The other three demos have had one of these for as long as they have had
/// levels, and this one had nothing.** Every test in `flutter3d_game_strategy`
/// plays a mirror staged in code — two camps, one flat field, numbers chosen by
/// the test — which is the right shape for measuring a policy and says nothing
/// about `map_a.json`. A map is a balance: a seam a little too far from a hall,
/// a finishing line a little above what the ground can pay for, and the game
/// that ships is one nobody can finish. Nothing else in this repository would
/// notice.
///
/// **Nothing here draws, and that is a requirement rather than a saving.**
/// `frame_test.dart` next door costs about forty seconds for a hundred frames,
/// because a software rasteriser fills two batches of fog tiles over the whole
/// hillside; a match played to its end is thousands of steps, and drawing them
/// would be an hour of frames nobody looks at. What makes this file possible is
/// the split `level_document.dart` and `staging.dart` were separated along:
/// `openMatch` builds the sides, the ground and the crowd out of the document
/// with no `GraphicsDevice` in existence, and `stage` is the half that puts a
/// picture over it.
///
/// **The assertion is on the ending, not on how long it took.** "Side nought
/// wins in 2140 ticks" is a sentence about a balance sheet nobody has agreed
/// to: move a seam ten metres in the document and it is red, with nothing wrong
/// anywhere. What the map has to answer for is that it *ends*, and that the side
/// somebody plays can win it.
library;

import 'dart:io';

import 'package:flutter3d_demo_strategy/src/command.dart';
import 'package:flutter3d_demo_strategy/src/level_document.dart';
import 'package:flutter3d_demo_strategy/src/run.dart';
import 'package:flutter3d_demo_strategy/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

/// The document, read off the disk rather than out of the bundle, so that this
/// is about the file that is committed — and so that no binding is needed,
/// which is what keeps the whole file free of Flutter's machinery.
StrategyMap _map() =>
    StrategyMap.parse(File('assets/levels/map_a.json').readAsStringSync());

/// The longest match this will sit through.
///
/// **A cap rather than a `while`, because the failure being guarded against is
/// a hang and not a wrong answer.** A finishing line the ground cannot pay for
/// leaves both sides digging an empty map for ever; `Match` has an ending for
/// exactly that and this is the backstop for the day it stops working, since a
/// suite that never returns tells nobody which test was to blame. Ten thousand
/// steps is nearly three minutes of match against a map that is settled in
/// well under one.
const int _cap = 10000;

/// Plays [match] the way the screen plays it, and says how many steps it took.
///
/// The near side is given its orders through [CommandPost] — the same object
/// `main.dart` builds and the same door a click uses — so what is being played
/// here is the game rather than a likeness of it. The far camp answers to the
/// policy the document staged for it.
///
/// **`restock` is the whole of what the near side does, and it is not a
/// shortcut.** A hall makes nothing until somebody asks it to, so the side
/// nobody is playing would open with the crowd the document gave it and never
/// gain another; the screen asks on the player's behalf every step, and so does
/// this. Anything more — sending squads about, picking a fight — would be this
/// file inventing a player's taste, and the map has to be finishable by the
/// plainest one there is.
int _play(Match match, CommandPost command) {
  for (var step = 0; step < _cap; step++) {
    if (match.standing.isOver) return step;
    command.restock();
    match.step(strategyStep);
  }
  return _cap;
}

void main() {
  test('the map the demo ships with can be played to a finish, and won', () {
    final StrategyMap map = _map();
    final StrategyStart start = openMatch(map);
    final command = CommandPost(simulation: start.simulation, side: viewerSide);

    final int steps = _play(start.match, command);

    expect(
      steps,
      lessThan(_cap),
      reason:
          'the match never ended: after ${(_cap * strategyStep).round()} '
          'seconds the sides had delivered ${start.simulation.delivered}, '
          'against a line at ${map.goal.delivered}',
    );
    expect(start.match.standing.isOver, isTrue);

    // **Won by the side somebody is holding the mouse for**, which is a claim
    // about the map and about the one lever the screen pulls. The far camp's
    // policy wants a dozen diggers and the document stages sixty a side, so its
    // hall is asked for nothing all match; the near camp's is asked every step
    // by `restock`, and out-digging is the whole of the near side's advantage.
    // A map edited until that stops being true is a map the player cannot win
    // without being told how, and this is where that shows up.
    expect(
      start.match.standing.winner,
      viewerSide,
      reason: 'the side the screen plays did not win its own map',
    );

    // And the same ending as the session reads it. The two are asserted
    // together because they are the pair a player actually meets: the HUD says
    // "you win" from the standing, and `RunSession` clears the save from this.
    expect(outcomeFor(start.match.standing, side: viewerSide), RunOutcome.won);
    expect(
      start.simulation.delivered[viewerSide],
      greaterThanOrEqualTo(map.goal.delivered),
      reason: 'the line was never crossed, so this was won some other way',
    );

    // **The far camp was in the match**, which is what keeps the assertion
    // above from being satisfied by a walkover. A map whose second side digs
    // nothing is a map that proves the near side can count rather than that it
    // can win.
    expect(
      start.simulation.delivered[1],
      greaterThan(0.0),
      reason: 'the far camp never brought anything home',
    );

    // **And the orders given above actually reached the match.** The far
    // camp's policy wants a dozen diggers and the document stages sixty a
    // side, so its halls are asked for nothing all match: every unit on this
    // map beyond the hundred and twenty the document staged was built because
    // `restock` put a `TrainOrder` in the queue. Break that door — the ask, the
    // queue, or the producer behind it — and the crowd stays exactly the size
    // it opened at, while everything else here still passes.
    final int mine = start.simulation.units
        .where((Unit it) => it.side == viewerSide)
        .length;
    expect(
      mine,
      greaterThan(start.mine.length),
      reason:
          'the near side finished with the crowd it opened with, so '
          'nothing it was told to build was ever built',
    );
  });

  group('a session reading a match', () {
    test('calls a match still running neither won nor lost', () {
      expect(outcomeFor(const Standing.running(), side: 0), RunOutcome.playing);
    });

    test('gives the win to the side it is watching, and to no other', () {
      expect(outcomeFor(const Standing.wonBy(0), side: 0), RunOutcome.won);
      expect(outcomeFor(const Standing.wonBy(1), side: 0), RunOutcome.lost);
      // A three-cornered map is read from whichever seat the screen is in.
      expect(outcomeFor(const Standing.wonBy(2), side: 2), RunOutcome.won);
    });

    test('reads a draw as a run with nothing to carry out of it', () {
      // Not a word `RunOutcome` has, and the fold is deliberate — see
      // `outcomeFor`. What matters is that a drawn match is over: read as
      // `playing`, the session would go on autosaving a match that can never
      // change again, and the next launch would resume it.
      expect(outcomeFor(const Standing.drawn(), side: 0), RunOutcome.lost);
      expect(outcomeFor(const Standing.drawn(), side: 0).isOver, isTrue);
    });
  });
}
