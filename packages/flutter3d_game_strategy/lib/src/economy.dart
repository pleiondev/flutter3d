/// What is taken from the map, and what is made from it.
///
/// **Sides exist from the first line of this file.** An economy written for one
/// player is an economy rewritten the day there are two, and the phase after
/// this one is a bot playing itself — so a unit belongs to a side, a building
/// belongs to a side, and a stockpile is a side's rather than the map's. It
/// costs an integer now.
///
/// **A job is not an order.** An order is where a player pointed; a job is what
/// a unit does when nobody is pointing. They live apart because they change on
/// different clocks: an order arrives from outside and replaces whatever was
/// there, while a job is a loop the unit runs — walk, take, walk back, drop —
/// and the loop issues orders of its own. Folding them together would make
/// every player click cancel a career.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'building.dart';

/// Something on the map worth carrying home.
final class ResourceNode {
  /// A deposit at [at] holding [amount].
  ResourceNode({required Vector3 at, required this.amount})
    : at = at.clone(),
      assert(amount >= 0.0, 'a deposit of less than nothing');

  /// Where it is.
  final Vector3 at;

  /// What is left in it. Falls to nought and stays there.
  double amount;

  /// Whether there is anything left to take.
  bool get isEmpty => amount <= 0.0;

  /// Takes up to [wanted] and answers what was actually there.
  double take(double wanted) {
    final double got = wanted < amount ? wanted : amount;
    amount -= got;
    return got;
  }

  /// What is left in it, which is the whole of what a match can change.
  ///
  /// Where the seam is belongs to the level: the map put it there, and a save
  /// restored into the map it was taken in finds it there again.
  Map<String, Object?> save() => <String, Object?>{'amount': amount};

  void restore(Map<String, Object?> from) =>
      amount = from.number('amount', amount);
}

/// What a unit is doing when nobody is giving it orders.
final class HarvestJob {
  /// Sends a unit back and forth between [node] and [dropOff].
  HarvestJob({
    required this.node,
    required this.dropOff,
    this.capacity = 10.0,
    this.rate = 8.0,
  });

  /// Where it digs.
  final ResourceNode node;

  /// Where it takes what it dug.
  final Building dropOff;

  /// How much it can carry at once.
  final double capacity;

  /// How fast it fills, per second, while it is standing at the deposit.
  final double rate;

  /// What it is carrying now.
  double carried = 0.0;

  /// Whether it is on its way home rather than out.
  bool get isFull => carried >= capacity;

  /// What it is carrying, how it carries, and where the two things it points at
  /// sit in the lists the simulation keeps.
  ///
  /// **The two indices come from outside**, because a job cannot see them. It
  /// holds a deposit and a building directly, and a document has no references;
  /// what identifies both is their place in `StrategySimulation.resources` and
  /// `StrategySimulation.buildings`, which are lists in the order they were
  /// staged and therefore the same lists on the far side of a save.
  Map<String, Object?> save({required int node, required int dropOff}) =>
      <String, Object?>{
        'node': node,
        'dropOff': dropOff,
        'carried': carried,
        'capacity': capacity,
        'rate': rate,
      };

  /// A job read back from [save], or null when either end of it is missing.
  ///
  /// Null rather than a throw, for the reason [Snapshot] gives: a save is the
  /// one document that must not refuse to load. A worker whose seam is not in
  /// this map comes back idle, and the policy that gave it the job gives it
  /// another one on its next thought.
  static HarvestJob? fromSnapshot(
    Map<String, Object?> from, {
    required List<ResourceNode> nodes,
    required List<Building> buildings,
  }) {
    final int node = from.integer('node', -1);
    final int dropOff = from.integer('dropOff', -1);
    if (node < 0 || node >= nodes.length) return null;
    if (dropOff < 0 || dropOff >= buildings.length) return null;
    return HarvestJob(
      node: nodes[node],
      dropOff: buildings[dropOff],
      capacity: from.number('capacity', 10.0),
      rate: from.number('rate', 8.0),
    )..carried = from.number('carried');
  }
}

/// What a side has taken and not yet spent.
final class Stockpile {
  /// Starts a side with [amount].
  Stockpile([this.amount = 0.0]);

  /// What is in it.
  double amount;

  /// Whether [cost] can be paid, and pays it if so.
  ///
  /// One call rather than a test and a subtraction, because those two drift
  /// apart: the version with two steps spent a stockpile twice in one step the
  /// first time two buildings finished together.
  bool spend(double cost) {
    if (amount < cost) return false;
    amount -= cost;
    return true;
  }

  Map<String, Object?> save() => <String, Object?>{'amount': amount};

  void restore(Map<String, Object?> from) =>
      amount = from.number('amount', amount);
}

/// A building that turns a stockpile into units.
final class Producer {
  /// Makes a unit every [seconds], for [cost] each, at [building].
  Producer({required this.building, this.cost = 25.0, this.seconds = 4.0});

  /// Where the units come out.
  final Building building;

  /// What each one costs its side.
  final double cost;

  /// How long each one takes.
  final double seconds;

  /// How far through the current one it is, in seconds. Nought when nothing is
  /// being made — a producer that cannot afford to start has not started.
  double progress = 0.0;

  /// Whether it has begun one it has not finished.
  bool get isBusy => progress > 0.0;

  /// How far through the current one it is, and only that.
  ///
  /// **Which is the field that pays for the whole pair.** A producer restored
  /// at nought has not merely lost a few seconds: it has forgotten that it
  /// already paid, so the stockpile is charged a second time for a unit that
  /// was three-quarters built — and the side that saved while building comes
  /// back poorer than the side that did not.
  ///
  /// What it costs and how long it takes are what the game set it to, and come
  /// back from the game.
  Map<String, Object?> save() => <String, Object?>{'progress': progress};

  void restore(Map<String, Object?> from) =>
      progress = from.number('progress', progress);
}
