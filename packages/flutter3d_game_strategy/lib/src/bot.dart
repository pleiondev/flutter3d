/// A side played by nobody, using the same handles a player has.
///
/// **The mirror is the point.** This is not an opponent written to be beaten;
/// it is the player's own vocabulary — orders, jobs, a stockpile — driven by a
/// policy instead of a mouse. Two of them on one map is the cheapest hard test
/// this genre can have: it is a long simulation, it is a load, and because both
/// sides run the same code, anything that makes a run differ from itself shows
/// up as the wrong side winning rather than as a number a hair out.
///
/// **It decides on a cadence, not every step.** Not for speed — the policy is a
/// few comparisons — but because deciding sixty times a second is how a bot
/// ends up re-ordering a unit that has not had time to take a step, which reads
/// as a crowd shivering in place. Every [Bot.thinkEvery] steps is a decision
/// often enough for a game measured in minutes.
///
/// Nothing here reads a clock or rolls a die. A bot that did could not be part
/// of a run anybody replays, and the whole reason two of them are put on a map
/// is to watch a replay come out the same.
///
/// **It has one lever, and that is honest rather than lazy.** It sends idle
/// workers to a seam; it does not choose *whether* to make units, and it does
/// not place buildings. Both were considered and both wait for the same missing
/// thing: production spends a stockpile the moment it can, so there is nothing
/// yet for a bot to save *for*, and a policy that chose between two things when
/// only one of them exists would be a shape pretending to be a decision. The
/// day there is a second use for a pile — a hall nearer the seam, an army worth
/// keeping — this is where that choice goes.
library;

import 'building.dart';
import 'economy.dart';
import 'simulation.dart';
import 'unit.dart';

/// A side, played.
final class Bot {
  /// Plays [side], carrying what it digs to [base].
  Bot({required this.side, required this.base, this.thinkEvery = 30});

  /// Which side this plays.
  final int side;

  /// Where its workers take what they dig.
  final Building base;

  /// How many steps pass between decisions.
  final int thinkEvery;

  int _sinceThought = 0;

  /// Gives the orders this side would give, if it is time to give them.
  void step(StrategySimulation simulation) {
    if (_sinceThought++ < thinkEvery) return;
    _sinceThought = 0;

    for (final Unit unit in simulation.units) {
      if (unit.side != side) continue;
      final HarvestJob? job = unit.job;
      // Idle, or standing at a seam that has run out: both mean "needs
      // somewhere to dig". A worker already carrying a load is left alone —
      // taking its job away would strand what it is holding.
      if (job != null && !job.node.isEmpty) continue;
      if (job != null && job.carried > 0.0) continue;

      final ResourceNode? seam = _nearestSeam(simulation);
      if (seam == null) return;
      unit.job = HarvestJob(node: seam, dropOff: base);
    }
  }

  /// The nearest deposit with anything left in it.
  ///
  /// Nearest to the base rather than to the worker, so that every worker of a
  /// side agrees about which seam is the seam — a fleet that each chose its own
  /// nearest would spread across the map and halve the delivery rate for a
  /// picture nobody asked for. Ties break on the order deposits were added,
  /// because the list is walked in order and a tie broken by anything else
  /// would be a tie broken differently on a different run.
  ResourceNode? _nearestSeam(StrategySimulation simulation) {
    ResourceNode? best;
    var bestAt = double.infinity;
    for (final ResourceNode node in simulation.resources) {
      if (node.isEmpty) continue;
      final double dx = node.at.x - base.centre.x;
      final double dz = node.at.z - base.centre.z;
      final double at = dx * dx + dz * dz;
      if (at >= bestAt) continue;
      best = node;
      bestAt = at;
    }
    return best;
  }
}
