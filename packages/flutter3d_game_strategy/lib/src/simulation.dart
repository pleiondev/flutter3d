/// The step a crowd takes, and the three things in it.
///
/// Descend a shared field, shove neighbours apart, sit on the ground. All three
/// were measured before any of this was written, on a flat map with ten
/// thousand agents: 256 microseconds to descend, 717 to shove everybody against
/// everybody, 19 to write the transforms — under a millisecond together, six
/// per cent of a frame at sixty. **The measurement is why the shape is this
/// shape**, and two decisions came straight out of it.
///
/// **Everyone is shoved, not just the visible.** Limiting separation to what is
/// on screen was the obvious saving and it costs 717 microseconds not to make;
/// worse, it would have made the simulation depend on where the camera points,
/// which is the end of a run that replays the same way twice.
///
/// **The grid is coarse, and that is what makes an order cheap.** A field
/// rebuilt on a half-metre lattice costs 8.4 milliseconds — half a frame, for
/// one order. The same field on two-metre cells costs 0.52, while descending it
/// gets barely cheaper (375 microseconds against 307 for ten thousand agents).
/// So a strategy bakes its own coarse grid instead of the one a shooter bakes
/// for its corridors, and an order can then be answered in the step that
/// received it — no cache keyed by goal, no isolate, no field built across
/// several frames.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'building.dart';
import 'economy.dart';
import 'fog.dart';
import 'formation.dart';
import 'unit.dart';

/// A crowd on a piece of ground.
final class StrategySimulation {
  /// Builds a simulation over [ground], with a navigation grid baked at
  /// [cellSize] metres.
  ///
  /// [cellSize] defaults to two metres because that is where the measurement
  /// put the knee: fields cost a sixteenth of what they cost at half a metre,
  /// and the units walking them cannot tell.
  StrategySimulation({
    required this.ground,
    required this.random,
    double cellSize = 2.0,
    double maxSlope = 0.698,
    double fogCellSize = 4.0,
    this.fogEvery = 6,
    this.sides = 2,
  }) : assert(sides > 0, 'a match nobody plays'),
       // ignore_for_file: prefer_initializing_formals
       _cellSize = cellSize,
       _maxSlope = maxSlope,
       fog = FogOfWar(ground: ground, cellSize: fogCellSize, sides: sides),
       stock = List<Stockpile>.generate(sides, (_) => Stockpile()),
       delivered = List<double>.filled(sides, 0.0) {
    entities.register<Unit>('unit', encode: _writeUnit, decode: _readUnit);
    _bake();
  }

  final double _cellSize;
  final double _maxSlope;

  /// The generator every roll in this simulation comes out of.
  ///
  /// **Nothing here rolls it yet, and it is required anyway.** The three other
  /// genres each shipped a game that took a default generator, saved dice
  /// nobody was rolling, and diverged from the run it had saved at the first
  /// roll somebody later added. The cheap moment to close that is before the
  /// first die exists: a fight, a scatter of spawn points, a policy that picks
  /// between two seams that are the same distance away — each of those wants
  /// randomness, and every one of them would otherwise arrive alongside a save
  /// format that had to be bumped to carry it.
  ///
  /// So this is bookkeeping paid in advance, and the assertion it makes is that
  /// there is no way to leave it out.
  final GameRandom random;

  /// Where the crowd lives, entity by entity.
  ///
  /// **The reason is the save, and it is worth stating because a crowd this
  /// simple does not otherwise need an ECS.** [_produce] makes units while the
  /// match runs, so a snapshot taken at minute three describes more of them
  /// than the freshly staged map it is restored into — and a snapshot restores
  /// objects that already exist. Saving unit *n* as the *n*th entry of a list
  /// would therefore restore three units into a map that has four, or four into
  /// a map that has three, and either way the wrong worker is holding the load.
  ///
  /// An entity is a handle rather than a position, and [EcsWorld.restore]
  /// raises the ones a save describes without the map having staged them. That
  /// is the whole of what is bought here; [units] below is still the order the
  /// step walks, and that order is still what makes a run repeat.
  final EcsWorld entities = EcsWorld();

  /// How many sides are playing.
  ///
  /// **Two is a default, not a law.** Everything a side owns here is a slot in
  /// a list — a purse, a running total, a layer of fog — and the count is the
  /// length of those lists rather than a pair of names written into the code.
  /// A three-cornered match therefore costs a constructor argument instead of a
  /// pass over every place that used to say "ours" and "theirs".
  final int sides;

  /// What each side knows of the map. See [FogOfWar]: visibility is a rule of
  /// the simulation here rather than a coat of paint on the picture, which is
  /// why a policy reads it and why it is part of what a replay compares.
  final FogOfWar fog;

  /// How many steps pass between recomputing what everybody can see.
  ///
  /// Counted in steps rather than seconds, because a fog that refreshed on a
  /// clock would make two runs of one tape disagree the moment one of them ran
  /// on a slower machine. Six is a tenth of a second at sixty: far below what
  /// anybody notices a crowd moving, and a sixth of the work.
  final int fogEvery;

  int _sinceFog = 0;

  /// The ground everything stands on.
  final Heightfield ground;

  /// Where a unit may walk, baked from [ground] and whatever stands on it.
  ///
  /// Re-baked when a building is placed rather than kept current by hand: the
  /// bake costs about a millisecond at this cell size, and a placement is a
  /// thing a player does now and then.
  late NavGrid grid;

  /// What has been built, in the order it was built.
  final List<Building> buildings = <Building>[];

  /// Puts a building on the map, takes its ground out of the grid, and moves
  /// anybody who was standing where it now stands.
  ///
  /// **The eviction is not tidiness.** A flow field refuses to give a direction
  /// out of a cell it could not reach, and taking a cell out of the grid is
  /// exactly what makes it unreachable — so a unit left under a new building
  /// stops walking for the rest of the match, silently, with its orders
  /// intact. Placing a hall on top of one's own crowd is a thing a player does
  /// on the first day, so it is answered here rather than in a note.
  Building build(Building building) {
    building.centre.y = ground.heightAt(building.centre.x, building.centre.z);
    buildings.add(building);
    fog.reveal(
      building.side,
      building.centre.x,
      building.centre.z,
      building.sight,
    );
    _bake();
    _evict(building);
    return building;
  }

  /// Moves whoever is under [building] to the nearest ground they can stand on.
  void _evict(Building building) {
    for (final Unit unit in units) {
      if (!building.covers(unit.position.x, unit.position.z)) continue;
      final int to = _standableNear(
        grid.cellAtPoint(unit.position.x, unit.position.z),
      );
      if (to < 0) continue;
      final Vector3 centre = grid.centreOfCell(to);
      unit.position
        ..x = centre.x
        ..z = centre.z
        ..y = ground.heightAt(centre.x, centre.z);
    }
  }

  void _bake() {
    grid = NavGrid.bakeHeightfield(
      ground,
      cellSize: _cellSize,
      maxSlope: _maxSlope,
      blocked: buildings.isEmpty
          ? null
          : (double x, double z) {
              for (final Building building in buildings) {
                if (building.covers(x, z)) return true;
              }
              return false;
            },
    );
  }

  /// The crowd, in the order it was added.
  ///
  /// **A list, and the step walks it in order.** A set or a map keyed by
  /// identity would step the same crowd in a different order on a different
  /// run, and two runs of one tape would stop agreeing — which is the whole of
  /// what a strategy's replay is worth.
  final List<Unit> units = <Unit>[];

  /// The fields built this step, one per distinct goal.
  final Map<int, FlowField> _fields = <int, FlowField>{};

  /// Scratch, so that a step of ten thousand allocates nothing.
  final Vector3 _step = Vector3.zero();
  final Map<int, List<int>> _buckets = <int, List<int>>{};

  /// Adds a unit and returns it, so a caller can keep the handle.
  ///
  /// It sees where it stands the moment it exists, rather than at the next fog
  /// refresh. Without that, everything staged before the first step is blind
  /// for a tenth of a second — long enough for a policy asked for its opening
  /// orders to find a map it has never seen and send its whole crowd out to
  /// explore the ground it is standing on.
  Unit add(Unit unit) {
    unit.position.y = ground.heightAt(unit.position.x, unit.position.z);
    unit.entity = entities.spawn();
    entities.set<Unit>(unit.entity, unit);
    units.add(unit);
    fog.reveal(unit.side, unit.position.x, unit.position.z, unit.sight);
    return unit;
  }

  /// What each side has taken and not yet spent, by side. One entry per side.
  final List<Stockpile> stock;

  /// What each side has ever brought home, by side, spent or not.
  ///
  /// Held apart from [stock] because they answer different questions and only
  /// one of them can settle a match: a stockpile is what a side has *left*, and
  /// a side that turns everything it digs into units would show nought in it
  /// while out-earning an opponent sitting on a pile. What a side achieved is
  /// the running total, and it only ever goes up — which is also what makes it
  /// a usable finishing line.
  final List<double> delivered;

  /// What is left on the map to take.
  final List<ResourceNode> resources = <ResourceNode>[];

  /// The buildings that make units.
  final List<Producer> producers = <Producer>[];

  /// Adds a deposit and returns it.
  ResourceNode addResource(ResourceNode node) {
    node.at.y = ground.heightAt(node.at.x, node.at.z);
    resources.add(node);
    return node;
  }

  /// Adds a producer and returns it.
  Producer addProducer(Producer producer) {
    producers.add(producer);
    return producer;
  }

  /// Moves the crowd on by [dt] seconds.
  ///
  /// **Jobs first, then the walk.** A harvester decides where it is going this
  /// step before anything moves it, so an order issued by a job takes effect in
  /// the same step it was issued rather than the next one — which is the
  /// difference between a stream of workers and a stutter of them.
  void step(double dt) {
    _work(dt);
    _walk(dt);
    _separate();
    _sit();
    _produce(dt);
    _look();
  }

  /// Recomputes what every side can see, now and then.
  ///
  /// **Last in the step, so that what a side knows agrees with where its crowd
  /// is.** A policy runs between steps and reads this; refreshed first, it
  /// would be answering about the step before, and a scout would be told to go
  /// and look at the cell it is standing in.
  void _look() {
    if (_sinceFog++ < fogEvery) return;
    _sinceFog = 0;

    fog.forgetVisible();
    for (final Building building in buildings) {
      fog.reveal(
        building.side,
        building.centre.x,
        building.centre.z,
        building.sight,
      );
    }
    for (final Unit unit in units) {
      fog.reveal(unit.side, unit.position.x, unit.position.z, unit.sight);
    }
  }

  /// Runs each unit's job: out to the deposit, back to the drop-off.
  void _work(double dt) {
    for (final Unit unit in units) {
      final HarvestJob? job = unit.job;
      if (job == null) continue;

      if (job.isFull || job.node.isEmpty) {
        final Vector3 home = job.dropOff.centre;
        if (job.dropOff.distanceTo(unit.position.x, unit.position.z) <=
            _reach) {
          stock[unit.side].amount += job.carried;
          delivered[unit.side] += job.carried;
          job.carried = 0.0;
          // A worker whose seam ran dry while it was walking home delivers what
          // it has and then stands: finding it another seam is a decision about
          // the game rather than about carrying, and it belongs to whoever gave
          // the job.
          unit.order = job.node.isEmpty
              ? const UnitOrder.hold()
              : UnitOrder.moveTo(job.node.at);
        } else {
          unit.order = UnitOrder.moveTo(home);
        }
        continue;
      }

      if (_within(unit.position, job.node.at, _reach)) {
        job.carried += job.node.take(
          _least(job.rate * dt, job.capacity - job.carried),
        );
        unit.order = const UnitOrder.hold();
      } else {
        unit.order = UnitOrder.moveTo(job.node.at);
      }
    }
  }

  /// Turns stockpiles into units.
  void _produce(double dt) {
    for (final Producer producer in producers) {
      final Stockpile purse = stock[producer.building.side];
      if (!producer.isBusy && !purse.spend(producer.cost)) continue;

      producer.progress += dt;
      if (producer.progress < producer.seconds) continue;
      producer.progress = 0.0;

      // Out of the near face rather than the middle, so a unit is not born
      // inside the building that made it and shoved out by the separation pass
      // in whichever direction it happened to be leaning.
      final Building at = producer.building;
      add(
        Unit(
          position: Vector3(
            at.centre.x,
            0.0,
            at.centre.z + at.depth / 2.0 + 1.0,
          ),
          side: at.side,
        ),
      );
    }
  }

  /// The nearest cell that can actually be stood in, starting from [cell].
  ///
  /// **A goal is not always somewhere to stand, and the commonest case is the
  /// one a player makes on purpose: clicking a building.** Its cells are out of
  /// the grid — that is what placing it did — so a field built for its centre
  /// reaches nothing and the crowd stands still, which reads as an order that
  /// was ignored rather than as one that was impossible. A worker taking a load
  /// home hit this first: the drop-off it was walking to was the very thing
  /// that had removed the ground under itself.
  ///
  /// Rings outward, so the answer is the nearest edge of whatever was clicked.
  /// Bounded, because a click in the middle of a lake should give up rather
  /// than search the map.
  int _standableNear(int cell) {
    if (cell < 0 || grid.isWalkable(cell)) return cell;

    final int cx = grid.cellX(cell);
    final int cz = grid.cellZ(cell);
    for (var ring = 1; ring <= 8; ring++) {
      for (var dz = -ring; dz <= ring; dz++) {
        for (var dx = -ring; dx <= ring; dx++) {
          // Only the ring itself: the inside was searched by the ring before.
          if (dx.abs() != ring && dz.abs() != ring) continue;
          final int x = cx + dx;
          final int z = cz + dz;
          if (x < 0 || z < 0 || x >= grid.columns || z >= grid.rows) continue;
          final int at = grid.cellIndex(x, z);
          if (grid.isWalkable(at)) return at;
        }
      }
    }
    return -1;
  }

  /// How near a thing a unit has to be to work at it, in metres.
  ///
  /// Measured from the edge of a building and from the middle of a deposit,
  /// because a deposit has no footprint to be outside of. Wide enough to cover
  /// the ring of cells a building takes out of the grid, which is most of a
  /// cell on every side.
  static const double _reach = 3.5;

  static bool _within(Vector3 a, Vector3 b, double reach) {
    final double dx = a.x - b.x;
    final double dz = a.z - b.z;
    return dx * dx + dz * dz <= reach * reach;
  }

  static double _least(double a, double b) => a < b ? a : b;

  /// Every unit under a move order descends the field for its goal.
  void _walk(double dt) {
    _fields.clear();
    for (final Unit unit in units) {
      final Vector3? goal = unit.order.goal;
      if (goal == null) continue;

      // Goals are shared by the cell they fall in rather than by their
      // coordinates: a hundred units told to go to a hundred points inside one
      // two-metre cell walk the same field, and telling them apart would cost a
      // field each for a difference nothing can see.
      final int cell = _standableNear(grid.cellAt(goal));
      if (cell < 0) continue;
      final FlowField field = _fields.putIfAbsent(cell, () {
        final made = FlowField(grid)..rebuild(grid.centreOfCell(cell));
        return made;
      });

      // Near the goal a unit steers at its own place in the arrangement; far
      // from it everybody shares one field. See `Formation`: slots are an
      // arrangement at the destination rather than a destination each, which
      // is what keeps an order costing one field instead of one per unit.
      final Vector3? slot = unit.order.slot;
      if (slot != null) {
        final double dx = goal.x + slot.x - unit.position.x;
        final double dz = goal.z + slot.z - unit.position.z;
        final double toGoal =
            (goal.x - unit.position.x) * (goal.x - unit.position.x) +
            (goal.z - unit.position.z) * (goal.z - unit.position.z);
        if (toGoal < Formation.arriveWithin * Formation.arriveWithin) {
          final double distance = math.sqrt(dx * dx + dz * dz);
          if (distance < 1e-4) continue;
          final double travel = math.min(unit.speed * dt, distance);
          final double toX = unit.position.x + dx / distance * travel;
          final double toZ = unit.position.z + dz / distance * travel;

          // **Steering still asks the grid.** The first version of this branch
          // moved the unit outright, on the grounds that a slot is a few metres
          // from a goal the field had already found. It is not: a squad sent to
          // the far side of a ridge walked *up the ridge*, because nothing in
          // the direct step consulted walkability and `_sit` obligingly put
          // each unit on top of the wall it was crossing. Cheap to ask, and the
          // answer is the difference between a formation and a climb.
          final int to = grid.cellAtPoint(toX, toZ);
          if (to < 0 || !grid.isWalkable(to)) continue;
          unit.position.x = toX;
          unit.position.z = toZ;
          continue;
        }
      }

      if (!field.descend(unit.position, _step)) continue;
      unit.position.x += _step.x * unit.speed * dt;
      unit.position.z += _step.z * unit.speed * dt;
    }
  }

  /// Shoves overlapping neighbours apart.
  ///
  /// A hash of the cell a unit is in, rebuilt every step. Rebuilding it is
  /// cheaper than keeping it current: units move every step, so a kept index
  /// would be rewritten every step anyway, and a fresh one cannot go stale.
  void _separate() {
    _buckets.clear();
    for (var i = 0; i < units.length; i++) {
      _buckets.putIfAbsent(_bucketOf(units[i].position), () => <int>[]).add(i);
    }

    for (final List<int> bucket in _buckets.values) {
      for (var a = 0; a < bucket.length; a++) {
        for (var b = a + 1; b < bucket.length; b++) {
          final Unit one = units[bucket[a]];
          final Unit other = units[bucket[b]];
          final double dx = other.position.x - one.position.x;
          final double dz = other.position.z - one.position.z;
          final double gap = one.radius + other.radius;
          final double squared = dx * dx + dz * dz;
          if (squared >= gap * gap || squared < 1e-9) continue;

          final double distance = math.sqrt(squared);
          final double push = (gap - distance) * 0.5;
          final double nx = dx / distance * push;
          final double nz = dz / distance * push;
          one.position.x -= nx;
          one.position.z -= nz;
          other.position.x += nx;
          other.position.z += nz;
        }
      }
    }
  }

  /// Puts everybody back on the ground they are standing over.
  void _sit() {
    for (final Unit unit in units) {
      unit.position.y = ground.heightAt(unit.position.x, unit.position.z);
    }
  }

  /// A unit and the job it is running, as one row of the entity world.
  ///
  /// The job's half is written here rather than in [Unit.save] because it is
  /// two places in the lists this object holds — see [HarvestJob.save].
  Object? _writeUnit(Unit unit) {
    final HarvestJob? job = unit.job;
    return <String, Object?>{
      ...unit.save(),
      if (job != null)
        'job': job.save(
          node: resources.indexOf(job.node),
          dropOff: buildings.indexOf(job.dropOff),
        ),
    };
  }

  /// The other direction, and the reason [entities] is here at all: this builds
  /// a unit the map it is restoring into never staged.
  Unit? _readUnit(Object? data) {
    if (data is! Map) return null;
    final Map<String, Object?> from = data.cast<String, Object?>();
    final Map<String, Object?>? job = from.object('job');
    return Unit.fromSnapshot(from)
      ..job = job == null
          ? null
          : HarvestJob.fromSnapshot(
              job,
              nodes: resources,
              buildings: buildings,
            );
  }

  /// Everything needed to carry on digging, and nothing needed only to draw.
  ///
  /// **What is deliberately absent, and why each one is safe to leave out:**
  ///
  /// * [ground] and the buildings standing on it are the level. A save restores
  ///   into the map it was taken in — see [Snapshot] — so the hillside, and
  ///   where each hall sits on it, come back from whatever staged them. That is
  ///   what lets a map be re-generated under a save rather than frozen by one.
  /// * [grid] is derived. It is baked from the ground and the footprints, both
  ///   of which the level brings back, so carrying it would be carrying a
  ///   lattice to say what the level already says. [restore] re-bakes instead.
  /// * The scratch of one step — the flow fields, the separation buckets, the
  ///   step vector — describes a step that has already happened and is cleared
  ///   at the top of the next one.
  ///
  /// **[_sinceFog] is here and is not a number, it is a phase.** Fog refreshes
  /// every [fogEvery] steps and is left alone in between; restore that counter
  /// at nought and a run agrees with the one it was saved from for as many
  /// steps as were left in the cycle and then refreshes on a beat of its own,
  /// for ever. Two runs of one tape then disagree about what each side can see
  /// on most steps, which is the whole of what a replay compares — and the day
  /// something decides on what a side can see *now* rather than on what it has
  /// ever seen, it becomes a disagreement about orders too.
  Snapshot save() => Snapshot(<String, Object?>{
    'random': random.state,
    'entities': entities.save(),
    // The order the step walks the crowd in, which is the whole of this
    // simulation's determinism. An entity world is a map keyed by index and a
    // map has no order, so the order is written down rather than inferred from
    // one.
    'order': <int>[for (final Unit unit in units) unit.entity.index],
    'stock': <Object?>[for (final Stockpile purse in stock) purse.save()],
    'delivered': List<double>.of(delivered),
    'resources': <Object?>[
      for (final ResourceNode node in resources) node.save(),
    ],
    'producers': <Object?>[
      for (final Producer maker in producers) maker.save(),
    ],
    'fog': fog.save(),
    'sinceFog': _sinceFog,
  });

  /// Puts [snapshot] back into this map.
  ///
  /// **Every unit handle taken before this call is stale afterwards.** The
  /// crowd a save describes is not the crowd that was staged, so the units are
  /// built rather than filled in, and the objects that were here are gone —
  /// [units] is where the new ones are, in the order the step will walk them.
  /// Buildings, deposits and producers are the other way round and for the
  /// opposite reason: the map staged those, so they keep their identity and
  /// take their numbers back.
  void restore(Snapshot snapshot) {
    final Map<String, Object?> from = snapshot.data;
    random.state = from.integer('random', random.state);

    final Map<String, Object?>? saved = from.object('entities');
    if (saved != null) entities.restore(saved);
    _restoreCrowd(from['order']);

    final List<Map<String, Object?>> purses = from.rows('stock');
    for (var side = 0; side < stock.length && side < purses.length; side++) {
      stock[side].restore(purses[side]);
    }
    final Object? totals = from['delivered'];
    if (totals is List) {
      for (
        var side = 0;
        side < delivered.length && side < totals.length;
        side++
      ) {
        final Object? total = totals[side];
        if (total is num) delivered[side] = total.toDouble();
      }
    }
    final List<Map<String, Object?>> seams = from.rows('resources');
    for (var i = 0; i < resources.length && i < seams.length; i++) {
      resources[i].restore(seams[i]);
    }
    final List<Map<String, Object?>> makers = from.rows('producers');
    for (var i = 0; i < producers.length && i < makers.length; i++) {
      producers[i].restore(makers[i]);
    }
    final Map<String, Object?>? known = from.object('fog');
    if (known != null) fog.restore(known);
    _sinceFog = from.integer('sinceFog', _sinceFog);

    _settle();
  }

  /// Puts the map and the crowd back into agreement, after something has moved
  /// the crowd without asking the map.
  ///
  /// **The counterpart of the racer's `afterRestore`, and it exists for the
  /// reason [_evict] already gives.** A restore is the second door a unit's
  /// position can be set through; the first is [build], which has always
  /// evicted whoever it buried, because a unit standing on ground that is out
  /// of the grid gets no direction out of a flow field and stops walking for
  /// the rest of the match, silently, holding its orders. A save is a document
  /// and a document can say anything — a hand edit, a crowd written down before
  /// a hall was raised over it — so the same guarantee is made at both doors
  /// rather than at one.
  ///
  /// The re-bake ahead of it costs about a millisecond, which is what buys the
  /// eviction an up-to-date grid to look for open ground in without this having
  /// to know what the caller staged, or in what order.
  void _settle() {
    _bake();
    for (final Building building in buildings) {
      _evict(building);
    }
  }

  /// Rebuilds [units] in the order the save wrote down.
  ///
  /// Two things happen here that nothing else can do: each restored unit is
  /// told which entity it came back on, and the crowd is put back in the order
  /// the step walks it. Anything the save named that this world does not have
  /// is skipped rather than filled with a hole.
  void _restoreCrowd(Object? order) {
    final Map<int, Unit> found = <int, Unit>{};
    for (final Entity entity in entities.query<Unit>()) {
      final Unit? unit = entities.get<Unit>(entity);
      if (unit == null) continue;
      unit.entity = entity;
      found[entity.index] = unit;
    }
    units
      ..clear()
      ..addAll(<Unit>[
        if (order is List)
          for (final Object? index in order)
            if (index is num)
              if (found[index.toInt()] case final Unit unit) unit,
      ]);
  }

  /// Which bucket a position falls in. Two metres, so that a pair close enough
  /// to touch is a pair in one bucket for any radius a unit has.
  int _bucketOf(Vector3 at) {
    const double cell = 2.0;
    final int x = (at.x / cell).floor();
    final int z = (at.z / cell).floor();
    return x * 73856093 ^ z * 19349663;
  }
}
