/// Two sides, a finishing line, and the loop that runs between them.
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
library;

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

  /// The world both sides play in.
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
    final double ours = simulation.delivered[0];
    final double theirs = simulation.delivered[1];
    if (ours >= goal.delivered || theirs >= goal.delivered) {
      return _between(ours, theirs);
    }
    // Nothing left in the ground and nothing left in anybody's hands: the
    // totals cannot move again, so the match is decided even though neither
    // side reached the line.
    if (_anythingLeft()) return const Standing.running();
    return _between(ours, theirs);
  }

  static Standing _between(double ours, double theirs) {
    if (ours > theirs) return const Standing.wonBy(0);
    if (theirs > ours) return const Standing.wonBy(1);
    return const Standing.drawn();
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
