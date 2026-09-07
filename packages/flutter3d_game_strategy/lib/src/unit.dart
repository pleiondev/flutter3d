/// A thing on the map that takes orders, the kind of thing it is, and the order
/// it is taking.
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

/// What kind of thing a unit is: everything about it that never changes.
///
/// **The difference between a worker, a soldier and a tank is numbers, not
/// code.** Written the other way — a subclass apiece, or a switch on a kind —
/// every pass of the step would have to learn the roster, and adding a fourth
/// kind would mean touching the walk, the fight and the production. Written as
/// a value, a kind is a row of measurements that the same passes read: the walk
/// asks how fast, the fight asks how hard and how far, and production asks for
/// one of these rather than for a name it has to interpret.
///
/// **It travels in documents as its own numbers rather than as a name.** A
/// registry of kinds would mean a tape recorded against one balance replaying
/// against another and coming out somewhere else, silently; the same argument
/// `MoveOrder` already makes about carrying its formation. So a save writes the
/// row out, a train order carries it, and a build that has never heard of a
/// kind still replays it correctly.
final class UnitType {
  /// A kind measured out by hand. The defaults are the worker.
  const UnitType({
    this.name = 'worker',
    this.radius = 0.4,
    this.speed = 3.0,
    this.sight = 18.0,
    this.health = 40.0,
    this.damage = 0.0,
    this.range = 0.0,
    this.reload = 1.0,
  }) : assert(health > 0.0, 'a kind that is dead the moment it is made'),
       assert(radius > 0.0, 'a kind that needs no room');

  /// The kind that digs. Unarmed, and that is the interesting part: [damage]
  /// of nought is what makes the fight skip it entirely rather than what makes
  /// it lose one.
  static const UnitType worker = UnitType();

  /// The kind that shoots from a few metres off.
  static const UnitType soldier = UnitType(
    name: 'soldier',
    speed: 3.4,
    sight: 20.0,
    health: 70.0,
    damage: 9.0,
    range: 6.0,
    reload: 0.9,
  );

  /// The kind that walks slowly, takes a great deal and gives it back.
  static const UnitType tank = UnitType(
    name: 'tank',
    radius: 0.9,
    speed: 2.2,
    sight: 22.0,
    health: 260.0,
    damage: 26.0,
    range: 5.0,
    reload: 1.6,
  );

  /// What it is called, for a game that shows the word and for a reader of a
  /// save who wants to know what a row of numbers was meant to be.
  final String name;

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

  /// How much punishment one of these starts with.
  final double health;

  /// How much it takes off whatever it hits, per shot.
  final double damage;

  /// How far it can reach, in metres, measured centre to centre.
  ///
  /// Shorter than [sight] for every armed kind here, and that ordering is the
  /// whole of what makes an approach interesting: a side sees trouble coming
  /// before it can answer it.
  final double range;

  /// How many seconds pass between one shot and the next.
  final double reload;

  /// Whether it can hurt anything at all.
  ///
  /// Both halves, because either one alone is a kind that cannot fight: damage
  /// with no reach never finds anybody, and reach with no damage finds
  /// everybody and does nothing. The fight asks this once per unit per step and
  /// leaves the unarmed alone, which is why an economy with no soldiers in it
  /// pays a comparison a unit rather than a search.
  bool get isArmed => damage > 0.0 && range > 0.0;

  /// The same kind with a few numbers moved, for a game or a test that wants a
  /// worker with a shorter sight rather than a whole new roster.
  UnitType copyWith({
    String? name,
    double? radius,
    double? speed,
    double? sight,
    double? health,
    double? damage,
    double? range,
    double? reload,
  }) => UnitType(
    name: name ?? this.name,
    radius: radius ?? this.radius,
    speed: speed ?? this.speed,
    sight: sight ?? this.sight,
    health: health ?? this.health,
    damage: damage ?? this.damage,
    range: range ?? this.range,
    reload: reload ?? this.reload,
  );

  /// The row, written down.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'radius': radius,
    'speed': speed,
    'sight': sight,
    'health': health,
    'damage': damage,
    'range': range,
    'reload': reload,
  };

  /// A kind read back from [toJson], filling in the worker for anything the
  /// document left out.
  factory UnitType.fromJson(Map<String, Object?> from) => UnitType(
    name: from.text('name') ?? worker.name,
    radius: from.number('radius', worker.radius),
    speed: from.number('speed', worker.speed),
    sight: from.number('sight', worker.sight),
    health: from.number('health', worker.health),
    damage: from.number('damage', worker.damage),
    range: from.number('range', worker.range),
    reload: from.number('reload', worker.reload),
  );

  /// Two kinds are the same kind when their numbers are.
  ///
  /// A value rather than an identity, because a kind that has been through a
  /// document is not the constant it was written from: a restored soldier has
  /// to answer yes to "is this a soldier", or every test of a save would be
  /// asking whether two objects happen to be one object.
  @override
  bool operator ==(Object other) =>
      other is UnitType &&
      other.name == name &&
      other.radius == radius &&
      other.speed == speed &&
      other.sight == sight &&
      other.health == health &&
      other.damage == damage &&
      other.range == range &&
      other.reload == reload;

  @override
  int get hashCode =>
      Object.hash(name, radius, speed, sight, health, damage, range, reload);

  @override
  String toString() => 'UnitType($name)';
}

/// What a unit has been told to do.
///
/// One class rather than a hierarchy, because the only thing a step does with
/// an order is ask where it points; attacking and holding are decisions about
/// *what* to aim at, and they are fields on this rather than a shape the step
/// has to switch on.
///
/// **An attack is a target, and its goal is that target's own position.** Not a
/// second way of moving: the vector an attack order points at *is* the vector
/// the quarry walks around with, so the walk that already descends a field
/// towards a goal follows a retreating enemy for free and nothing in it had to
/// learn what a target is.
final class UnitOrder {
  /// An order to stand where it is.
  const UnitOrder.hold() : goal = null, slot = null, target = null;

  /// An order to walk to [goal], standing at [slot] beside it on arrival.
  const UnitOrder.moveTo(Vector3 this.goal, {this.slot}) : target = null;

  /// An order to go for [target] and keep shooting it.
  UnitOrder.attack(Unit this.target) : goal = target.position, slot = null;

  /// Where the order points, or null for one that points nowhere.
  final Vector3? goal;

  /// Where in the arrangement this unit stands, as an offset from [goal].
  ///
  /// Null for an order given to one unit rather than to a squad, which then
  /// walks to the goal itself. See `Formation` for why the slot is an offset
  /// taken on arrival rather than a goal of its own.
  final Vector3? slot;

  /// Whom it is for, or null for an order about a place rather than a body.
  ///
  /// The unit itself and not its entity index, because the fight asks this
  /// every step and a lookup per shot would be a map read in the hottest loop
  /// this genre has. The index is what [save] writes; the object is what the
  /// step holds.
  final Unit? target;

  /// The points, written down, and nothing else — there is nothing else.
  ///
  /// **An attack writes only whom, and works the goal out again on the far
  /// side.** Writing the point as well would restore an attack as a walk to
  /// wherever the quarry happened to be standing when the save was taken: the
  /// unit would trudge to an empty patch of hillside and hold there while the
  /// thing it was told to kill walked away.
  ///
  /// For everything else both keys are left out when the order points nowhere,
  /// so that a hold reads back as a hold rather than as a walk to the origin.
  /// That difference is not cosmetic: the origin is a corner of the map, and a
  /// crowd restored with orders to walk there is a crowd that empties its own
  /// camp.
  Map<String, Object?> save() => switch (target) {
    final Unit mark => <String, Object?>{'target': mark.entity.index},
    null => <String, Object?>{
      if (goal case final Vector3 at) 'goal': vectorOf(at),
      if (slot case final Vector3 at) 'slot': vectorOf(at),
    },
  };

  /// An order read back from [save], minus the target.
  ///
  /// **A unit cannot resolve an entity index and this does not pretend to.**
  /// The crowd a save describes is being built while this runs, so the quarry
  /// may not exist yet — `StrategySimulation` puts the target back once every
  /// unit is standing up, which is the same second pass a harvest job needs and
  /// for the same reason.
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
  /// Builds a unit of [type] standing at [position], at full health unless
  /// [health] says otherwise.
  Unit({
    required this.position,
    this.type = UnitType.worker,
    this.side = 0,
    UnitOrder? order,
    double? health,
  }) : order = order ?? const UnitOrder.hold(),
       health = health ?? type.health;

  /// Where it is, in world space. Mutated in place by the step: a crowd that
  /// allocated a vector per unit per frame would spend its budget on the
  /// collector.
  final Vector3 position;

  /// What kind of thing it is. Never changes: a worker does not become a tank,
  /// and the numbers behind it are shared by every unit of the kind rather than
  /// copied onto each.
  final UnitType type;

  /// Whose it is. Sides are small integers because that is all a simulation
  /// needs them to be; what a side is called belongs to the game.
  final int side;

  /// How much punishment it has left.
  ///
  /// **The one number a fight changes, and aliveness is derived from it rather
  /// than kept beside it.** A flag and a number are two things that can
  /// disagree, and the disagreement is silent: a unit on nought health with the
  /// flag still set goes on shooting, and one above nought with the flag
  /// cleared is swept up mid-stride. One number cannot contradict itself.
  double health;

  /// How many seconds until it can shoot again.
  ///
  /// **A phase, and therefore in the save**, for the reason `FogOfWar`'s beat
  /// and a bot's thinking count are: a unit restored ready to fire when it was
  /// half a second from it wins an exchange it should have lost, and two runs
  /// of one recording then disagree about who is left standing.
  double cooldown = 0.0;

  /// Whether it is still on the map. See [health].
  bool get isAlive => health > 0.0;

  /// How much room it needs, in metres. Its kind's.
  double get radius => type.radius;

  /// How fast it walks, in metres a second. Its kind's.
  double get speed => type.speed;

  /// How far it uncovers the map around itself. Its kind's.
  double get sight => type.sight;

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

  /// Takes [amount] off, never past nought.
  ///
  /// Clamped so that a save carries how dead a thing is rather than how hard it
  /// was hit last: a tank finished off by a shot that would have taken it to
  /// minus two hundred reads back as nought either way, and only one of those
  /// two numbers means anything.
  void hurt(double amount) {
    health -= amount;
    if (health < 0.0) health = 0.0;
  }

  /// Everything about it that is not a place in somebody else's list.
  ///
  /// **The job is not here**, and the omission is the interesting part: a job
  /// points straight at a deposit and at a building, JSON has no references,
  /// and what identifies those two is where they sit in the simulation's own
  /// lists — which a unit cannot see. `StrategySimulation` writes that half
  /// beside this one, because it is the thing holding the lists.
  ///
  /// Its kind is saved even though it never changes, because a restore has to
  /// *build* this unit rather than fill one in: the map it lands in never made
  /// it, and a crowd restored as workers would be an army of diggers holding an
  /// army's orders.
  Map<String, Object?> save() => <String, Object?>{
    'at': vectorOf(position),
    'type': type.toJson(),
    'side': side,
    'health': health,
    'cooldown': cooldown,
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
    final UnitType type = switch (from.object('type')) {
      final Map<String, Object?> row => UnitType.fromJson(row),
      null => UnitType.worker,
    };
    return Unit(
      position: at,
      type: type,
      side: from.integer('side'),
      order: UnitOrder.fromSnapshot(from),
      health: from.number('health', type.health),
    )..cooldown = from.number('cooldown');
  }
}
