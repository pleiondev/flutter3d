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
/// **It has two levers now, and the second one arrived with something to
/// choose between.** It sends idle workers to a seam, and it says what its
/// halls are to make. The second was refused for a long time on the grounds
/// that production spent a stockpile the moment it could, so there was nothing
/// to save *for* and a policy choosing between one thing would have been a
/// shape pretending to be a decision. Now a producer makes only what it was
/// asked for, and the choice is real in three directions: another digger,
/// another soldier, or nothing at all and a growing pile. It still does not
/// place buildings, and that is still waiting on the same kind of missing
/// thing.
///
/// **It only ever attacks what its own fog says it can see.** Not politeness —
/// the fog is a rule of this simulation, and a policy that read the crowd
/// directly would be a side that fights an enemy it has never met, in a game
/// where going and looking is half of what a side does. The cheat is invisible
/// in the picture, which is exactly why it is asserted rather than intended.
library;

import 'package:flutter3d_game/flutter3d_game.dart';

import 'building.dart';
import 'economy.dart';
import 'simulation.dart';
import 'unit.dart';

/// What a side is trying to have on the map.
///
/// **A plan rather than a rule**, because how many diggers are enough and
/// whether to raise an army at all are decisions about the game somebody is
/// making, not facts about a policy. The default is the economy this package
/// had before there was a fight: workers up to a comfortable number and no
/// soldiers, so a match staged the way the old ones were is played the way they
/// were played. A game that wants a war asks for one here.
final class ArmyPlan {
  /// Wants [workers] diggers and [fighters] of [fighter], and no more.
  const ArmyPlan({
    this.workers = 12,
    this.fighters = 0,
    this.worker = UnitType.worker,
    this.fighter = UnitType.soldier,
  });

  /// How many unarmed units this side wants working.
  final int workers;

  /// How many armed ones it wants standing. Nought is a side that never
  /// fights, which is a plan and not an omission.
  final int fighters;

  /// What it makes when it wants another digger.
  final UnitType worker;

  /// What it makes when it wants another soldier.
  final UnitType fighter;
}

/// A side, played.
final class Bot {
  /// Plays [side], carrying what it digs to [base] and building to [plan].
  Bot({
    required this.side,
    required this.base,
    this.thinkEvery = 30,
    this.plan = const ArmyPlan(),
  });

  /// Which side this plays.
  final int side;

  /// Where its workers take what they dig.
  final Building base;

  /// How many steps pass between decisions.
  final int thinkEvery;

  /// What it is trying to end up with.
  final ArmyPlan plan;

  int _sinceThought = 0;

  /// Gives the orders this side would give, if it is time to give them.
  ///
  /// Digging, then building, then fighting — in that order because the first
  /// two count the crowd this side already has and the third would otherwise be
  /// counting one that a moment ago it decided to change.
  void step(StrategySimulation simulation) {
    if (_sinceThought++ < thinkEvery) return;
    _sinceThought = 0;

    _dig(simulation);
    _make(simulation);
    _hunt(simulation);
  }

  /// Puts every idle digger back on a seam, or sends it to find one.
  void _dig(StrategySimulation simulation) {
    for (final Unit unit in simulation.units) {
      if (unit.side != side || unit.type.isArmed) continue;
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

  /// Decides what this side's halls are making: a digger, a soldier, or
  /// nothing.
  ///
  /// **The third answer is the one that makes this a decision.** A side that
  /// has the crowd it planned asks for nothing and lets the pile grow, which is
  /// a position rather than an idleness — the pile is what pays for the army it
  /// will want the moment its plan changes or somebody knocks a soldier over.
  ///
  /// One at a time per hall, and the check is on the book rather than on a
  /// count of its own: a producer already asked for something is left to finish
  /// it, so a cadence faster than a build time cannot stack up an army nobody
  /// meant to order.
  void _make(StrategySimulation simulation) {
    var workers = 0;
    var fighters = 0;
    for (final Unit unit in simulation.units) {
      if (unit.side != side) continue;
      if (unit.type.isArmed) {
        fighters++;
      } else {
        workers++;
      }
    }

    // The saving branch, and it is the early return rather than a third case:
    // a side with the crowd it planned asks nobody for anything.
    if (workers >= plan.workers && fighters >= plan.fighters) return;
    final UnitType wanted = workers < plan.workers ? plan.worker : plan.fighter;

    for (final Producer maker in simulation.producers) {
      if (maker.building.side != side) continue;
      if (maker.isWanted) continue;
      simulation.orders.train(maker, wanted);
    }
  }

  /// Points every idle soldier at something.
  ///
  /// A soldier already after a living quarry is left alone: re-ordering it
  /// every cadence would replace one attack order with an identical one, and
  /// the day the two are not identical it would be a squad that changes its
  /// mind about which enemy to chase twice a second.
  void _hunt(StrategySimulation simulation) {
    for (final Unit unit in simulation.units) {
      if (unit.side != side || !unit.type.isArmed) continue;
      if (unit.order.target != null) continue;

      if (_nearestFoe(simulation, unit) case final Unit quarry) {
        simulation.orders.attackWith(<Unit>[unit], quarry);
        continue;
      }
      // Nothing in sight. March on whatever enemy ground this side has found —
      // a hall does not move, so what it has *ever* seen is the right question
      // for one, the same question it asks about a seam. Failing that, go and
      // look: an army standing at home on a map it has not explored is an army
      // that never meets anybody.
      //
      // **Asked again every cadence rather than only when the unit is idle**,
      // which is the same loop `_dig` runs and for the same reason. The version
      // that skipped a soldier already holding a goal froze its whole army at
      // the first frontier it walked to: nothing clears a move order on
      // arrival, so "it still has somewhere to go" stayed true for the rest of
      // the match and the map beyond that point was never looked at.
      if (_nearestFoundHall(simulation) case final Building hall) {
        simulation.orders.moveTo(<Unit>[unit], hall.centre);
        continue;
      }
      _scout(simulation, unit);
    }
  }

  /// The nearest enemy unit this side can see **at this moment**, or null.
  ///
  /// **Visible, not remembered, and not merely present.** A seam stays where it
  /// was put, so a side is right to remember one; a unit walks away, so
  /// remembering where one stood is remembering nothing. And reading the crowd
  /// without asking at all is the oldest cheat in the genre and the one that
  /// leaves no mark in the picture — the soldiers simply always turn the right
  /// way. See `fog_test` and `combat_test`, which exist to make that cheat
  /// fail rather than to hope it is absent.
  Unit? _nearestFoe(StrategySimulation simulation, Unit from) {
    Unit? best;
    var bestAt = double.infinity;
    for (final Unit other in simulation.units) {
      if (other.side == side) continue;
      if (!simulation.fog.sees(side, other.position.x, other.position.z)) {
        continue;
      }
      final double dx = other.position.x - from.position.x;
      final double dz = other.position.z - from.position.z;
      final double at = dx * dx + dz * dz;
      if (at >= bestAt) continue;
      best = other;
      bestAt = at;
    }
    return best;
  }

  /// The nearest building of somebody else's that this side has found.
  ///
  /// Measured from this side's own base, for the reason [_nearestSeam] gives:
  /// an army whose members each chose their own nearest target is an army that
  /// arrives in pieces.
  Building? _nearestFoundHall(StrategySimulation simulation) {
    Building? best;
    var bestAt = double.infinity;
    for (final Building hall in simulation.buildings) {
      if (hall.side == side) continue;
      if (!simulation.fog.knows(side, hall.centre.x, hall.centre.z)) continue;
      final double dx = hall.centre.x - base.centre.x;
      final double dz = hall.centre.z - base.centre.z;
      final double at = dx * dx + dz * dz;
      if (at >= bestAt) continue;
      best = hall;
      bestAt = at;
    }
    return best;
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
