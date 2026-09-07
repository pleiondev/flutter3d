/// A thing on the map that takes orders, and the order it is taking.
///
/// **A record of numbers rather than a body.** The other three genres give
/// their movers a `CharacterController`, which sweeps against the collision
/// world and is the right shape for one protagonist among a few dozen
/// mechanisms. A crowd is not that: ten thousand of them were measured
/// stepping in under a millisecond by descending a shared field and shoving
/// each other apart, and a sweep apiece would have been a different order of
/// cost for an answer nobody looks at. A unit knows where it is, how wide it
/// is, and where it was told to go.
library;

import 'package:vector_math/vector_math.dart';

/// What a unit has been told to do.
///
/// One class rather than a hierarchy, because the only thing a step does with
/// an order today is ask where it points; attacking and holding are decisions
/// about *what* to aim at, and they arrive as fields on this when the game has
/// them rather than as a shape the step has to switch on.
final class UnitOrder {
  /// An order to stand where it is.
  const UnitOrder.hold() : goal = null, slot = null;

  /// An order to walk to [goal], standing at [slot] beside it on arrival.
  const UnitOrder.moveTo(Vector3 this.goal, {this.slot});

  /// Where the order points, or null for one that points nowhere.
  final Vector3? goal;

  /// Where in the arrangement this unit stands, as an offset from [goal].
  ///
  /// Null for an order given to one unit rather than to a squad, which then
  /// walks to the goal itself. See `Formation` for why the slot is an offset
  /// taken on arrival rather than a goal of its own.
  final Vector3? slot;
}

/// One unit on the map.
final class Unit {
  /// Builds a unit standing at [position].
  Unit({
    required this.position,
    this.radius = 0.4,
    this.speed = 3.0,
    UnitOrder? order,
  }) : order = order ?? const UnitOrder.hold();

  /// Where it is, in world space. Mutated in place by the step: a crowd that
  /// allocated a vector per unit per frame would spend its budget on the
  /// collector.
  final Vector3 position;

  /// How much room it needs, in metres. Two units closer than the sum of their
  /// radii are shoved apart.
  final double radius;

  /// How fast it walks, in metres a second.
  final double speed;

  /// What it is doing. Assigning a new one is how a game gives an order.
  UnitOrder order;
}
