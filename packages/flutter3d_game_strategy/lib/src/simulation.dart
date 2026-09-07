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
    double cellSize = 2.0,
    double maxSlope = 0.698,
  }) : // ignore_for_file: prefer_initializing_formals
       _cellSize = cellSize,
       _maxSlope = maxSlope {
    _bake();
  }

  final double _cellSize;
  final double _maxSlope;

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

  /// Puts a building on the map and takes its ground out of the grid.
  Building build(Building building) {
    building.centre.y = ground.heightAt(building.centre.x, building.centre.z);
    buildings.add(building);
    _bake();
    return building;
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
  Unit add(Unit unit) {
    unit.position.y = ground.heightAt(unit.position.x, unit.position.z);
    units.add(unit);
    return unit;
  }

  /// What each side has taken and not yet spent, by side.
  final List<Stockpile> stock = <Stockpile>[Stockpile(), Stockpile()];

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

  /// Which bucket a position falls in. Two metres, so that a pair close enough
  /// to touch is a pair in one bucket for any radius a unit has.
  int _bucketOf(Vector3 at) {
    const double cell = 2.0;
    final int x = (at.x / cell).floor();
    final int z = (at.z / cell).floor();
    return x * 73856093 ^ z * 19349663;
  }
}
