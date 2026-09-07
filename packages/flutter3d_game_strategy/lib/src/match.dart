/// The sides, a finishing line, and the loop that runs between them.
///
/// **There are two ways to win and they do not replace each other.** The
/// economic one came first, when nothing on this map could fight: what a side
/// does is dig, carry and grow, so how much of the map it turned into its own
/// is a real answer and inventing a battle to decide it would have meant
/// writing a combat system to serve a scoreboard. The military one arrived when
/// there was a fight to arrive with, and it is deliberately narrow — a side is
/// beaten when it has no unit left and nothing left that could make one. Not
/// when its halls fall: buildings have no health here, and a victory that
/// depended on knocking them down would be a victory this game cannot reach.
///
/// **Every match ends.** Three ways now, and the last is still the one that
/// matters: somebody reaches the target, somebody is the only side left able to
/// act, or the map runs out and the bigger pile wins. Without the last, a
/// target set higher than the ground can pay for would leave the loop running
/// for ever with nothing left to change — which in a test is not a failure but
/// a hang, the worst kind of red.
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
  }) : _contenders = _whoIsPlaying(simulation);

  /// Which sides turned up, taken once from the map as it was staged.
  ///
  /// **A side that never had anything is not a side that lost anything.** The
  /// military ending is about being *reduced* to nothing, and a simulation
  /// carries as many sides as somebody asked it for whether or not each was
  /// given a camp — a test map with one camp on it, a three-cornered world with
  /// the third seat empty. Counted without this, every such match would be won
  /// on its first step by whoever happened to have a worker, which is a
  /// finishing line crossed by standing still.
  ///
  /// Not saved, for the reason [standing] is not: it is a fact about the map,
  /// and a restore stages the map before it reads the document.
  final Set<int> _contenders;

  static Set<int> _whoIsPlaying(StrategySimulation simulation) => <int>{
    for (var side = 0; side < simulation.sides; side++)
      if (_canAct(simulation, side)) side,
  };

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

  /// Which of the three endings this is, asked in the order they beat each
  /// other.
  ///
  /// **A crossed line is asked first, and that ordering is a decision.** A side
  /// that has already brought home what the match was set at has won it, and
  /// finding afterwards that its last worker fell in the same step should not
  /// take the win away. So the economy is settled, then the field, then the
  /// slow ending where the ground simply runs out.
  Standing _judge() {
    final bool crossed = simulation.delivered.any(
      (double total) => total >= goal.delivered,
    );
    if (crossed) return _leader();

    if (_fought() case final Standing over) return over;

    // Nothing left in the ground and nothing left in anybody's hands: the
    // totals cannot move again, so the match is decided even though nobody
    // reached the line — unless somebody is still holding a weapon, in which
    // case the *other* finishing line can still be crossed.
    if (_anythingLeft() || _stillContested()) return const Standing.running();
    return _leader();
  }

  /// Whether the fighting could still change the answer.
  ///
  /// **A worked-out map is not a finished match while two armies are standing
  /// on it.** The exhaustion ending was written when the totals were the only
  /// thing a step could move, and it says exactly that: nothing can change, so
  /// judge now. With a fight on the map that is no longer true — the last ore
  /// often runs out well before the last soldier does, and a match called drawn
  /// in the step before it was won is a match that hid its own ending.
  ///
  /// **And it asks the narrow question rather than "is anybody armed".** Halls
  /// cannot be knocked down here, so a side that has one is a side that can
  /// never be shot off the map however badly it is losing — and a match kept
  /// running because two such sides are glaring at each other over an empty map
  /// would run for ever, which is the exact failure the exhaustion ending was
  /// written to prevent. So: is there a side that could still be finished off,
  /// and somebody else able to do it.
  bool _stillContested() {
    final List<int> standing = <int>[
      for (final int side in _contenders)
        if (_canAct(simulation, side)) side,
    ];
    if (standing.length < 2) return false;

    for (final int mortal in standing) {
      if (_makesUnits(simulation, mortal)) continue;
      for (final Unit unit in simulation.units) {
        if (unit.side != mortal && unit.type.isArmed) return true;
      }
    }
    return false;
  }

  /// The ending the fighting decided, or null while more than one side can
  /// still act.
  ///
  /// **A side is out when it has neither a unit nor anything that could make
  /// one.** Buildings have no health here, so a hall is not a thing that can be
  /// knocked down — but a side reduced to buildings that make nothing has no
  /// move left of any kind, and a match that went on waiting for one would be
  /// waiting for the map to run out on a player who cannot dig. That is what
  /// makes this a finishing line rather than a scoreboard entry.
  ///
  /// **Nobody left standing is judged by what was earned**, and not called a
  /// draw outright: two armies that wipe each other out in the same step have
  /// still dug different amounts, the totals can never move again, and the side
  /// that dug more has as good a claim here as it does when the ground runs
  /// out. A level pair comes back drawn from the same pass, which is where the
  /// answer for a match nobody ever played comes from.
  Standing? _fought() {
    // Nobody to fight. A one-camp map is a map somebody is digging on, and it
    // should end when the ground does. See [_contenders].
    if (_contenders.length < 2) return null;

    var last = -1;
    var standing = 0;
    for (final int side in _contenders) {
      if (!_canAct(simulation, side)) continue;
      last = side;
      standing++;
    }
    return switch (standing) {
      1 => Standing.wonBy(last),
      0 => _leader(),
      _ => null,
    };
  }

  /// Whether [side] has anything left to act with in [simulation].
  static bool _canAct(StrategySimulation simulation, int side) {
    for (final Unit unit in simulation.units) {
      if (unit.side == side) return true;
    }
    return _makesUnits(simulation, side);
  }

  /// Whether [side] still holds something that turns a pile into units.
  static bool _makesUnits(StrategySimulation simulation, int side) {
    for (final Producer maker in simulation.producers) {
      if (maker.building.side == side) return true;
    }
    return false;
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
