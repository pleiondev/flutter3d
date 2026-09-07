/// The sides, a finishing line, and the loop that runs between them.
///
/// **The victory is economic because the game is.** Nothing on this map fights;
/// what a side does is dig, carry and grow, so what settles a match is how much
/// of the map a side turned into its own — and inventing a battle to decide it
/// would mean writing a combat system to serve a scoreboard rather than a game.
/// When there is a fight, it gets its own condition and this one keeps working
/// beside it.
///
/// **Every match ends.** Two ways, and the second is the one that matters:
/// somebody reaches the target, or the map runs out and the bigger pile wins.
/// Without the second, a target set higher than the ground can pay for would
/// leave the loop running for ever with nothing left to change — which in a
/// test is not a failure but a hang, the worst kind of red.
///
/// **A draw is a real answer, not a missing one.** Two sides running the same
/// policy from mirrored starts *should* finish level, and a match that
/// invented a winner there would be hiding exactly the bias the mirror was
/// built to expose.
///
/// **How many sides there are is the simulation's business, not this file's.**
/// Judging asks for the largest total among however many were staged, so a
/// three-cornered match is scored by the same pass as a duel and a tie for the
/// lead is a draw wherever in the list it happens to fall.
library;

import 'package:flutter3d_game/flutter3d_game.dart';

import 'bot.dart';
import 'economy.dart';
import 'simulation.dart';
import 'unit.dart';

/// Where the finishing line is.
final class MatchGoal {
  /// A match won by the first side to bring home [delivered].
  const MatchGoal({this.delivered = 400.0});

  /// How much a side must have brought home, in total, to win outright.
  final double delivered;
}

/// How a match stands.
final class Standing {
  /// Nobody has won yet.
  const Standing.running() : winner = null, isOver = false;

  /// [winner] has won.
  const Standing.wonBy(int this.winner) : isOver = true;

  /// It is over and level.
  const Standing.drawn() : winner = null, isOver = true;

  /// Which side won, or null while it runs and null when it is drawn — which
  /// is why [isOver] is asked first.
  final int? winner;

  /// Whether anything further can change the answer.
  final bool isOver;
}

/// A match between sides that play themselves.
///
/// The step order is the point: **policies first, then the world**. A bot that
/// decided after the step would be answering the previous frame's map, and two
/// bots doing that would take turns being a step stale — which is a difference
/// between sides that nobody put there.
final class Match {
  /// Runs [bots] against each other on [simulation].
  Match({
    required this.simulation,
    required this.bots,
    this.goal = const MatchGoal(),
  });

  /// The world every side plays in, and the one that says how many there are.
  final StrategySimulation simulation;

  /// The policies, in the order they are asked. Order is visible — the first
  /// bot's orders reach the step first — so it is a list rather than a set, and
  /// a caller that wants a fair match gives its sides mirrored starts rather
  /// than hoping the order does not matter.
  final List<Bot> bots;

  /// The finishing line.
  final MatchGoal goal;

  /// How it stands now.
  Standing get standing => _standing;
  Standing _standing = const Standing.running();

  /// Moves the match on by [dt] seconds, and does nothing once it is over.
  void step(double dt) {
    if (_standing.isOver) return;
    for (final Bot bot in bots) {
      bot.step(simulation);
    }
    simulation.step(dt);
    _standing = _judge();
  }

  Standing _judge() {
    final bool crossed = simulation.delivered.any(
      (double total) => total >= goal.delivered,
    );
    // Nothing left in the ground and nothing left in anybody's hands: the
    // totals cannot move again, so the match is decided even though nobody
    // reached the line.
    if (!crossed && _anythingLeft()) return const Standing.running();
    return _leader();
  }

  /// Who is ahead, or a draw when nobody is on their own.
  ///
  /// One pass, keeping the best total seen and whether anything has since drawn
  /// level with it. A later side that beats the lead clears the tie — it is
  /// alone in front again — which is why the flag is written rather than only
  /// set, and why `[3, 5, 5]` is a draw while `[5, 5, 7]` is won by the last.
  Standing _leader() {
    final List<double> delivered = simulation.delivered;
    var best = delivered[0];
    var leader = 0;
    var level = false;
    for (var side = 1; side < delivered.length; side++) {
      final double total = delivered[side];
      if (total > best) {
        best = total;
        leader = side;
        level = false;
      } else if (total == best) {
        level = true;
      }
    }
    return level ? const Standing.drawn() : Standing.wonBy(leader);
  }

  /// The world, the policies playing it, and nothing that can be worked out
  /// from either.
  ///
  /// **A match is what a caller saves, not a simulation.** Everything the step
  /// touches is either in the world below or in a bot's own head, and saving
  /// only the first is what makes a restored match give its next order at a
  /// different moment than the one that was saved — see [Bot.save].
  ///
  /// [standing] is not written down. It is a function of what the simulation
  /// holds — who has delivered what, and whether anything is left to deliver —
  /// so [restore] asks the judgement rather than reading an answer that a
  /// hand-edited or half-written document could put at odds with the totals it
  /// claims to describe. A finishing line moved between the save and the load
  /// is then honoured, which is the same boundary [MatchGoal] already sits on:
  /// the goal belongs to whoever staged the match.
  Snapshot save() => Snapshot(<String, Object?>{
    'simulation': simulation.save().data,
    'bots': <Object?>[for (final Bot bot in bots) bot.save()],
  });

  void restore(Snapshot snapshot) {
    final Map<String, Object?> from = snapshot.data;
    final Map<String, Object?>? world = from.object('simulation');
    if (world != null) simulation.restore(Snapshot(world));
    final List<Map<String, Object?>> saved = from.rows('bots');
    for (var i = 0; i < bots.length && i < saved.length; i++) {
      bots[i].restore(saved[i]);
    }
    _standing = _judge();
  }

  bool _anythingLeft() {
    for (final ResourceNode node in simulation.resources) {
      if (!node.isEmpty) return true;
    }
    for (final Unit unit in simulation.units) {
      if ((unit.job?.carried ?? 0.0) > 0.0) return true;
    }
    return false;
  }
}
