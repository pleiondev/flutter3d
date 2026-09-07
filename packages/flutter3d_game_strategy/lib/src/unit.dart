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

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'economy.dart';

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

  /// The two points, written down, and nothing else — there is nothing else.
  ///
  /// Both keys are left out for an order that points nowhere, so that a hold
  /// reads back as a hold rather than as a walk to the origin. That difference
  /// is not cosmetic: the origin is a corner of the map, and a crowd restored
  /// with orders to walk there is a crowd that empties its own camp.
  Map<String, Object?> save() => <String, Object?>{
    if (goal case final Vector3 at) 'goal': vectorOf(at),
    if (slot case final Vector3 at) 'slot': vectorOf(at),
  };

  /// An order read back from [save].
  factory UnitOrder.fromSnapshot(Map<String, Object?> from) {
    final Vector3 goal = Vector3.zero();
    if (!from.vectorInto('goal', goal)) return const UnitOrder.hold();
    final Vector3 slot = Vector3.zero();
    return UnitOrder.moveTo(
      goal,
      slot: from.vectorInto('slot', slot) ? slot : null,
    );
  }
}

/// One unit on the map.
final class Unit {
  /// Builds a unit standing at [position].
  Unit({
    required this.position,
    this.radius = 0.4,
    this.speed = 3.0,
    this.sight = 18.0,
    this.side = 0,
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

  /// How far it uncovers the map around itself, in metres.
  ///
  /// Wider than a unit could plausibly *see* on foot, and deliberately: sight
  /// is what makes a crowd's own ground legible, and a radius near the walking
  /// distance of one step leaves a side stumbling through a map it has already
  /// walked over. See `FogOfWar` for what the radius does and does not model.
  final double sight;

  /// Whose it is. Sides are small integers because that is all a simulation
  /// needs them to be; what a side is called belongs to the game.
  final int side;

  /// What it is doing. Assigning a new one is how a game gives an order.
  UnitOrder order;

  /// The loop it runs when nobody is pointing, or null for a unit that only
  /// does as it is told. See `HarvestJob`.
  HarvestJob? job;

  /// Which entity carries it, once a simulation has taken it in.
  ///
  /// [Entity.none] until then, which is what a unit built by a caller and not
  /// yet handed to `StrategySimulation.add` is. The handle exists so that a
  /// crowd can be written down and read back by an `EcsWorld` rather than by a
  /// list index: production makes units while the match runs, so a save taken
  /// at minute three has more of them than the map it is restored into, and an
  /// index into a list of a different length names the wrong unit or none.
  Entity entity = Entity.none;

  /// Everything about it that is not a place in somebody else's list.
  ///
  /// **The job is not here**, and the omission is the interesting part: a job
  /// points straight at a deposit and at a building, JSON has no references,
  /// and what identifies those two is where they sit in the simulation's own
  /// lists — which a unit cannot see. `StrategySimulation` writes that half
  /// beside this one, because it is the thing holding the lists.
  ///
  /// Its width, speed and sight are saved even though they never change,
  /// because a restore has to *build* this unit rather than fill one in: the
  /// map it lands in never made it.
  Map<String, Object?> save() => <String, Object?>{
    'at': vectorOf(position),
    'radius': radius,
    'speed': speed,
    'sight': sight,
    'side': side,
    ...order.save(),
  };

  /// A unit read back from [save], standing where it stood.
  ///
  /// A factory rather than a `restore` on an existing unit, for the reason the
  /// note on [entity] gives: the crowd a snapshot describes is not the crowd
  /// the fresh map was staged with.
  factory Unit.fromSnapshot(Map<String, Object?> from) {
    final Vector3 at = Vector3.zero();
    from.vectorInto('at', at);
    return Unit(
      position: at,
      radius: from.number('radius', 0.4),
      speed: from.number('speed', 3.0),
      sight: from.number('sight', 18.0),
      side: from.integer('side'),
      order: UnitOrder.fromSnapshot(from),
    );
  }
}
