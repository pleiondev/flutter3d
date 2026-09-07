/// What a side asks for, standing in a queue between the hand that asks and
/// the step that carries it out.
///
/// **Until this file, this genre's input was an assignment.** A bot wrote
/// `unit.job = HarvestJob(...)` and the application wrote `Squad(mine).moveTo`,
/// both reaching straight into the crowd from outside the step. That works and
/// it cannot be written down: there is no moment at which the intent exists as
/// a value, so the only way to get a second run out of a first one was to run
/// the same policy again — which measures that the policy is deterministic and
/// measures nothing at all about a recording. An order that stands in a queue
/// is an order somebody can write down, and that is the whole of why the
/// indirection is here.
///
/// **Why this genre carries its own orders rather than the engine's input.**
/// `InputFrame` in `flutter3d_sim` holds what was pressed and released, two
/// stick axes, a look delta, a bag of analogue readings and a numbered slot.
/// A strategy's order is a point on the map and a set of units, and neither is
/// expressible in any of those fields: a mouse click on a hillside is not a
/// press, and "these eleven units" is not a slot. Widening `InputFrame` to
/// carry them would reach into the three genres that use it as it stands and
/// into every test that reads one, to add a shape none of them can use. So the
/// tape here is the same *shape* as an input tape — a seed, and one entry per
/// step, indexed by step number — and none of the other three change. See
/// `order_tape.dart`.
///
/// **Units are named by the numbers the save already uses.** An order that held
/// `Unit` objects could not survive a document, and one that held a place in
/// `StrategySimulation.units` would name the wrong unit on the far side of a
/// save: production makes units while a match runs, so that list is a different
/// length by minute three. The entity index is what the snapshot writes down
/// for exactly that reason, and it is what an order writes down too — one
/// scheme, so an order and a save cannot disagree about which worker is which.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'building.dart';
import 'economy.dart';
import 'formation.dart';
import 'order_tape.dart';
import 'simulation.dart';
import 'unit.dart';

/// One thing a side asked for, on one step.
///
/// Sealed, so that reading a tape and writing one are two lists of the same
/// length: a kind added here has to be given a line in [orderFromJson] before
/// this file compiles, and a kind that could be written and not read is exactly
/// how a replay diverges without saying so.
sealed class StrategyOrder {
  const StrategyOrder();

  /// The order as a document writes it down. `kind` is what reads it back.
  Map<String, Object?> toJson();

  /// Carries the order out on [simulation], with [crowd] naming the units that
  /// are actually on the map by their entity index.
  ///
  /// **Anything it cannot find, it drops.** An order given to a unit that has
  /// since gone, or pointing at a seam this map does not have, is an order
  /// about a world that has moved on — and a step that threw there would turn a
  /// stale click into a crash. The one place that must not be lenient is
  /// [orderFromJson], and it is not.
  void obey(StrategySimulation simulation, Map<int, Unit> crowd);
}

/// Send these units there, and stand in an arrangement when they arrive.
final class MoveOrder extends StrategyOrder {
  /// Sends the units at [units] — entity indices — to [goal].
  MoveOrder({
    required this.units,
    required Vector3 goal,
    this.formation = const Formation.block(),
  }) : goal = goal.clone();

  /// Whom it was given to, by entity index, in the order the slots are handed
  /// out. Order is visible in the picture — the first unit takes the first
  /// place in the block — so it is a list and it is written down as one.
  final List<int> units;

  /// Where they are going.
  final Vector3 goal;

  /// How they stand once they get there.
  final Formation formation;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'move',
    'units': units,
    'goal': vectorOf(goal),
    // The arrangement travels with the order rather than being a fact about
    // the game: two runs of one tape have to arrange the same crowd the same
    // way, and a squad sent in a line of ten by an application that later
    // changed its default block would come back in fives.
    'spacing': formation.spacing,
    'width': formation.width,
  };

  /// An order read back from [toJson].
  factory MoveOrder.fromJson(Map<String, Object?> from) {
    final Vector3 goal = Vector3.zero();
    from.vectorInto('goal', goal);
    final Object? units = from['units'];
    return MoveOrder(
      units: <int>[
        if (units is List)
          for (final Object? index in units)
            if (index is num) index.toInt(),
      ],
      goal: goal,
      formation: Formation.block(
        spacing: from.number('spacing', 1.4),
        width: from.integer('width', 5),
      ),
    );
  }

  @override
  void obey(StrategySimulation simulation, Map<int, Unit> crowd) {
    final List<Unit> found = <Unit>[
      for (final int index in units)
        if (crowd[index] case final Unit unit) unit,
    ];
    if (found.isEmpty) return;
    // Through [Squad], which is where the arrangement lives and where the note
    // about an order ending a job is written. One place knows what a slot is.
    Squad(found, formation: formation).moveTo(goal);
  }
}

/// Put this unit to work at that seam, carrying to that hall.
///
/// **A job is an order even though it is not a point.** The other half of what
/// a side does is hand somebody a loop to run — dig here, carry there — and a
/// tape that recorded only the pointing would replay a match in which nobody
/// ever went to work. It is one entry every thirty steps or so, which is what a
/// policy's cadence costs.
final class AssignOrder extends StrategyOrder {
  /// Sets [unit] — an entity index — digging [node] and carrying to [dropOff],
  /// both of them places in the simulation's own lists.
  const AssignOrder({
    required this.unit,
    required this.node,
    required this.dropOff,
    this.capacity = 10.0,
    this.rate = 8.0,
  });

  /// Who is being put to work, by entity index.
  final int unit;

  /// Where it digs, as a place in `StrategySimulation.resources`.
  final int node;

  /// Where it carries to, as a place in `StrategySimulation.buildings`.
  ///
  /// The same two numbers `HarvestJob.save` writes, and deliberately the same:
  /// a job restored from a snapshot and a job handed out by a tape have to name
  /// the same seam, and two identity schemes for one pair of lists is two
  /// things to keep right.
  final int dropOff;

  /// How much the worker can carry at once.
  final double capacity;

  /// How fast it fills, per second, standing at the seam.
  final double rate;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'assign',
    'unit': unit,
    'node': node,
    'dropOff': dropOff,
    'capacity': capacity,
    'rate': rate,
  };

  /// An order read back from [toJson].
  factory AssignOrder.fromJson(Map<String, Object?> from) => AssignOrder(
    unit: from.integer('unit', -1),
    node: from.integer('node', -1),
    dropOff: from.integer('dropOff', -1),
    capacity: from.number('capacity', 10.0),
    rate: from.number('rate', 8.0),
  );

  @override
  void obey(StrategySimulation simulation, Map<int, Unit> crowd) {
    final Unit? worker = crowd[unit];
    if (worker == null) return;
    if (node < 0 || node >= simulation.resources.length) return;
    if (dropOff < 0 || dropOff >= simulation.buildings.length) return;
    worker.job = HarvestJob(
      node: simulation.resources[node],
      dropOff: simulation.buildings[dropOff],
      capacity: capacity,
      rate: rate,
    );
  }
}

// MARK: - Where the fight goes
//
// **An attack is the third kind, and it is deliberately not here.** The shape
// it will take is already decided by the two above: a `kind` of `attack`, a
// list of entity indices for whoever is swinging, and an entity index for
// whatever they are swinging at — the same addressing, the same one entry in
// the frame the order was given on, the same sealed switch in `orderFromJson`.
//
// What is missing is not the order, it is the thing it would point at: a unit
// has no target, no reach and no health, so an `AttackOrder` written today
// would be a document with nowhere to be carried out. Writing it now would fix
// the shape of a mechanism that has not been measured, which is the mistake
// this package has avoided twice already — the crowd and the fog were both
// built after the probe rather than before it. When there is a fight, this is
// where its order goes, and the tape's format does not move to let it in.

/// An order read back from whatever wrote it down.
///
/// **Throws on a kind it does not know rather than skipping it**, which is the
/// opposite of what every other reader in this package does with a field it
/// does not recognise, and the reason is what the document is for. A snapshot
/// that skips an unknown field loads a world with one thing missing and carries
/// on; a tape that skips an unknown order replays a *different match* and says
/// nothing — the crowd simply ends up somewhere else, and the person holding
/// the file is told that the simulation is not deterministic.
StrategyOrder orderFromJson(Map<String, Object?> from) =>
    switch (from.text('kind')) {
      'move' => MoveOrder.fromJson(from),
      'assign' => AssignOrder.fromJson(from),
      final String? kind => throw DemoFormatException(
        'the tape holds an order of kind "$kind", which this build cannot '
        'carry out',
      ),
    };

/// Everything a side has asked for and the step has not yet done.
///
/// **Emptied at the top of every step, which is what makes a tape's index mean
/// something.** An order given between two steps is carried out by the step
/// that follows it — always, whether it came from a policy thinking, from a
/// mouse, or from a tape being played back — so the moment an order lands is a
/// step number and nothing finer. Two runs then agree about *when* as well as
/// about *what*, which a queue drained lazily or in the middle of a step would
/// not give.
///
/// The queue is the simulation's; a caller reaches it through
/// `StrategySimulation.orders` rather than making one.
final class OrderQueue {
  /// Holds orders for [_simulation] until its next step.
  OrderQueue(this._simulation);

  final StrategySimulation _simulation;

  final List<StrategyOrder> _waiting = <StrategyOrder>[];

  /// Where each step's orders are written down, or null when nobody is
  /// recording.
  ///
  /// Hung on the queue rather than passed to every call, because the two things
  /// that give orders — a policy and a pointer — must not have to know whether
  /// anybody is watching. A recorder attached here sees every order both of
  /// them give and nothing either of them has to say about it.
  OrderTapeRecorder? recorder;

  /// What is waiting, in the order it was given.
  List<StrategyOrder> get waiting => List<StrategyOrder>.unmodifiable(_waiting);

  /// Puts a ready-made order in. How a tape gets back in, and how a caller with
  /// an order it built itself does.
  void add(StrategyOrder order) => _waiting.add(order);

  /// Puts a step's worth in at once.
  void addAll(Iterable<StrategyOrder> orders) => _waiting.addAll(orders);

  /// Sends [units] to [goal] together, standing in [formation] on arrival.
  void moveTo(
    Iterable<Unit> units,
    Vector3 goal, {
    Formation formation = const Formation.block(),
  }) => add(
    MoveOrder(
      units: <int>[for (final Unit unit in units) unit.entity.index],
      goal: goal,
      formation: formation,
    ),
  );

  /// Sets [unit] digging [node] and carrying home to [dropOff].
  ///
  /// The two handles are turned into places in the simulation's lists here,
  /// while the caller still has them; an order that carried the objects would
  /// be an order that could not be written down.
  void assign(
    Unit unit, {
    required ResourceNode node,
    required Building dropOff,
    double capacity = 10.0,
    double rate = 8.0,
  }) => add(
    AssignOrder(
      unit: unit.entity.index,
      node: _simulation.resources.indexOf(node),
      dropOff: _simulation.buildings.indexOf(dropOff),
      capacity: capacity,
      rate: rate,
    ),
  );

  /// Carries out everything waiting, and writes the step down if anybody is
  /// recording. Called by the step; nothing else should.
  ///
  /// **The recording happens whether or not anything was asked for**, because
  /// an empty step is what makes the entry after it land on the right step
  /// number. A tape that wrote only the steps somebody did something on would
  /// replay a match at a gallop.
  void obey() {
    recorder?.record(_waiting);
    if (_waiting.isEmpty) return;

    // The crowd by entity index, built once for the whole batch rather than
    // searched per order: a click on a hundred units would otherwise walk the
    // whole crowd a hundred times.
    final Map<int, Unit> crowd = <int, Unit>{
      for (final Unit unit in _simulation.units) unit.entity.index: unit,
    };
    for (final StrategyOrder order in _waiting) {
      order.obey(_simulation, crowd);
    }
    _waiting.clear();
  }

  /// What has been asked for and not yet done.
  ///
  /// **In the save because the step reads it.** The window is real: an
  /// application takes a click in a pointer callback and the step that obeys it
  /// runs a frame later, so a save taken in between describes a world in which
  /// somebody has already given an order. Dropped, the crowd carries on with
  /// what it was doing and the player's click is lost across a reload — which
  /// reads as an order the game ignored.
  List<Object?> save() => <Object?>[
    for (final StrategyOrder order in _waiting) order.toJson(),
  ];

  /// Puts back what [saved] was holding, in place of whatever is waiting now.
  ///
  /// **Lenient where [orderFromJson] is strict, and the difference is the
  /// document.** A tape that cannot read one of its orders would replay a
  /// different match and say nothing, so it throws. A save is the one document
  /// that must not refuse to load — see [Snapshot] — and an order it cannot
  /// carry out is one click, in a world it is otherwise describing perfectly.
  /// So a save from a build that knows an order this one does not comes back
  /// with that click missing rather than not at all.
  void restore(List<Map<String, Object?>> saved) {
    _waiting.clear();
    for (final Map<String, Object?> order in saved) {
      try {
        add(orderFromJson(order));
      } on DemoFormatException {
        continue;
      }
    }
  }
}
