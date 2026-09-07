/// Where each member of a squad stands once it arrives.
///
/// **A formation is an arrangement at the destination, not a destination each.**
/// The obvious way to send twenty units somewhere in a line is to give each of
/// them its own point and let the crowd sort itself out; it is also the way that
/// throws away the thing that makes an order cheap. Fields are shared by the
/// grid cell a goal falls in — a hundred units sent into one two-metre cell walk
/// one field — and twenty separate points are twenty cells, so twenty fields,
/// so twenty times half a millisecond for a difference nobody can see from a
/// camera above the map.
///
/// So the squad walks to one place together and takes its slots when it gets
/// there. The step does the second part: within [Formation.arriveWithin] of the
/// goal a unit steers at `goal + slot` directly instead of descending the
/// field, which is also the only part of the walk where a formation is visible.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'unit.dart';

/// How a squad arranges itself around the place it was sent.
final class Formation {
  /// A block [spacing] metres apart, at most [width] units across.
  const Formation.block({this.spacing = 1.4, this.width = 5})
    : assert(width > 0, 'a block no units wide holds nobody');

  /// Metres between neighbours.
  final double spacing;

  /// How many stand shoulder to shoulder before a second rank starts.
  final int width;

  /// How near the goal a unit has to be before it takes its slot.
  ///
  /// Far enough out that the crowd spreads while it is still walking rather
  /// than piling up and then untangling, and near enough that the walk itself
  /// is still one shared field.
  static const double arriveWithin = 6.0;

  /// Where the unit at [index] of [count] stands, relative to the goal.
  ///
  /// **Ranks along X and files along Z, centred on the goal**, so that a squad
  /// sent to a point stands *around* it rather than starting there and growing
  /// in one direction — an order given at the edge of a cliff should not push
  /// half the squad off it.
  ///
  /// No facing. A block that turned to face its travel would be a nicer picture
  /// and a worse simulation: the direction of travel changes every step near
  /// the goal, so the slots would rotate under the units standing in them and
  /// the squad would never settle.
  void slotFor(int index, int count, Vector3 out) {
    final int columns = math.min(width, count);
    final int rows = (count / columns).ceil();
    final int column = index % columns;
    final int row = index ~/ columns;

    out.setValues(
      (column - (columns - 1) / 2.0) * spacing,
      0.0,
      (row - (rows - 1) / 2.0) * spacing,
    );
  }
}

/// A group of units that takes one order together.
///
/// **Reached through the queue rather than built by a caller**, now that an
/// order is a thing that can be written down: a `MoveOrder` names its units by
/// entity index and gathers them into one of these to hand out the slots, so
/// this is where the arrangement is applied and `orders.dart` is where the
/// asking happens. A caller with the handles in front of it can still make one
/// — a test does — but a squad built outside the queue gives an order no tape
/// will ever see.
final class Squad {
  /// Gathers [units] under [formation].
  Squad(this.units, {this.formation = const Formation.block()});

  /// The members, in the order orders are handed out in — which is the order
  /// the simulation steps them in, so that two runs of one tape agree.
  final List<Unit> units;

  /// How they stand when they get there.
  final Formation formation;

  /// Sends everybody to [goal], each with its own place in the arrangement.
  ///
  /// **An order from outside ends whatever loop the unit was running.** A job
  /// writes an order of its own every step, so a squad order given to a worker
  /// without cancelling the job is overwritten before anybody moves — and a
  /// player who clicks a busy harvester sees it carry on digging. That reads as
  /// disobedience and is a job nobody cancelled. Telling a unit where to go is
  /// telling it to stop what it was doing; a side that wants it back at work
  /// says so again, which is exactly what a bot's policy does on its next
  /// thought.
  void moveTo(Vector3 goal) {
    final slot = Vector3.zero();
    for (var i = 0; i < units.length; i++) {
      formation.slotFor(i, units.length, slot);
      units[i]
        ..job = null
        ..order = UnitOrder.moveTo(goal, slot: slot.clone());
    }
  }

  /// Tells everybody to stand still, and to stop working while they are at it.
  void hold() {
    for (final Unit unit in units) {
      unit
        ..job = null
        ..order = const UnitOrder.hold();
    }
  }
}
