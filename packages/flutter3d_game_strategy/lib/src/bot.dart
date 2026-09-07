/// A side played by nobody, using the same handles a player has.
///
/// **The mirror is the point.** This is not an opponent written to be beaten;
/// it is the player's own vocabulary — orders, jobs, a stockpile — driven by a
/// policy instead of a mouse. Two of them on one map is the cheapest hard test
/// this genre can have: it is a long simulation, it is a load, and because both
/// sides run the same code, anything that makes a run differ from itself shows
/// up as the wrong side winning rather than as a number a hair out.
///
/// **It gives its orders through the queue, and that is the same door the
/// mouse uses.** Nothing here writes `Unit.order` or `Unit.job`: a policy asks
/// `StrategySimulation.orders` for a move or a job the way a click does, and
/// the step carries both out at the same moment. That is what makes a match
/// recordable at all — see `order_tape.dart` — and it is also the honest test
/// of the claim this file opens with, since a bot with a private door would be
/// a mirror of nothing.
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

import 'package:flutter3d_game/flutter3d_game.dart';

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
      if (seam == null) {
        _scout(simulation, unit);
        continue;
      }
      simulation.orders.assign(unit, node: seam, dropOff: base);
    }
  }

  /// Where in its thinking cycle it is.
  ///
  /// **A phase rather than a number, and the only thing here worth saving.**
  /// Which side this plays and where its base is were given to it by whoever
  /// staged the match, and come back from there. The count of steps since its
  /// last thought is the one thing it has invented for itself, and a bot
  /// restored at nought thinks on a different beat than the one that was saved
  /// — which is a run that agrees for a second and then hands a worker its next
  /// job at a different moment, near a different seam.
  Map<String, Object?> save() => <String, Object?>{
    'sinceThought': _sinceThought,
  };

  void restore(Map<String, Object?> from) =>
      _sinceThought = from.integer('sinceThought', _sinceThought);

  /// Sends a unit with nothing to dig towards the nearest ground nobody of this
  /// side has seen.
  ///
  /// **This is what makes the fog a rule rather than a filter on the picture.**
  /// The policy above can only send workers to seams it knows about, so a side
  /// that opens with everything beyond its hall in the dark has exactly one
  /// sensible move, and it is this one. Take the scouting away and the fog
  /// becomes a way of losing: the crowd stands at home beside a map full of ore
  /// it is not allowed to have heard of.
  ///
  /// No job, so the worker is idle again the moment it arrives and gets asked
  /// the same question with more of the map uncovered. That is the whole loop:
  /// walk, look, be asked again — and the "no job" is now the order's doing
  /// rather than this method's, because a move cancels whatever loop the unit
  /// was running. What that changed is worth naming: a scout used to keep the
  /// exhausted job it was sent out with, and the job's own loop rewrote its
  /// order every step to walk it home again. It went scouting in name only.
  ///
  /// A squad of one, which takes a slot of nothing: a formation centres its
  /// block on the goal, and a block one unit wide is centred on it exactly.
  void _scout(StrategySimulation simulation, Unit unit) {
    final int cell = simulation.fog.nearestUnexplored(
      side,
      unit.position.x,
      unit.position.z,
      reachable: (double x, double z) {
        final int at = simulation.grid.cellAtPoint(x, z);
        return at >= 0 && simulation.grid.isWalkable(at);
      },
    );
    if (cell < 0) return;
    simulation.orders.moveTo(<Unit>[unit], simulation.fog.centreOf(cell));
  }

  /// The nearest deposit this side has found that still has something in it.
  ///
  /// Nearest to the base rather than to the worker, so that every worker of a
  /// side agrees about which seam is the seam — a fleet that each chose its own
  /// nearest would spread across the map and halve the delivery rate for a
  /// picture nobody asked for. Ties break on the order deposits were added,
  /// because the list is walked in order and a tie broken by anything else
  /// would be a tie broken differently on a different run.
  ///
  /// **Found, not merely present.** A seam in unexplored ground is not a seam
  /// as far as this side is concerned — that is what the fog is for. What is
  /// *not* asked is whether the seam is visible now: a side remembers where the
  /// ore was, and finding out that somebody else has emptied it is what walking
  /// there is for.
  ResourceNode? _nearestSeam(StrategySimulation simulation) {
    ResourceNode? best;
    var bestAt = double.infinity;
    for (final ResourceNode node in simulation.resources) {
      if (node.isEmpty) continue;
      if (!simulation.fog.knows(side, node.at.x, node.at.z)) continue;
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
