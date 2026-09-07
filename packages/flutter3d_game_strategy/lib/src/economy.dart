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
}
