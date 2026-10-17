/// The strategy map's world on a bare field: a fire arrow lights a hall
/// where it strikes its timber, by the core's contact, and stones and arrows
/// are thrown by the core's own flight of them.
///
///     flutter test test/strategy/map_world_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_demo_content/map_world.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show GameRandom, Heightfield;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A level field a hundred and twenty metres across, a hall of the far
/// side in its middle, and the world over it with a trickle of a stream in
/// a corner.
({StrategySimulation simulation, MapWorld world}) _field() {
  const samples = 61;
  final simulation =
      StrategySimulation(
        ground: Heightfield(
          columns: samples,
          rows: samples,
          cellSize: 2.0,
          heights: Float32List(samples * samples),
        ),
        random: GameRandom(1),
      )..build(
        Building(
          center: Vector3(60.0, 0.0, 60.0),
          width: 6.0,
          depth: 5.0,
          side: 1,
        ),
      );
  final world = MapWorld(
    simulation,
    water: MapWater(
      x0: 0.0,
      z0: 0.0,
      cell: 0.5,
      nx: 24,
      nz: 24,
      course: <Vector2>[
        Vector2(2.0, 2.0),
        Vector2(6.0, 6.0),
        Vector2(9.0, 9.0),
      ],
      flow: 0.01,
      drainX: 10.0,
      drainZ: 10.0,
      sill: 1.0,
      pondLevel: -1.0,
    ),
    trees: const <MapTree>[],
  );
  return (simulation: simulation, world: world);
}

void main() {
  test('a fire arrow lights the timber it strikes, where it strikes it', () {
    // The hall used to be lit by a flame held to the timber nearest any
    // shooter standing within its range and three metres more. Now the
    // arrow is loosed, flies, and what it strikes is the core's contact.
    // Mutation: hold no flame where the arrow strikes — the arrow is spent
    // and the roof never catches.
    final (:simulation, :world) = _field();
    addTearDown(world.dispose);
    final timbers = world.halls.single.timbers;
    world.shootAtHall(0, Vector3(50.0, 0.0, 60.0));
    var lit = false;
    for (var i = 0; i < 60 * 40 && !lit; i++) {
      simulation.step(_dt);
      lit = timbers.any(world.world.isBurning);
    }
    expect(lit, isTrue);
  });

  test('an arrow loosed at a timber already alight is not loosed', () {
    // One arrow at a time at a hall: the core's flight of each is aimed,
    // and a hall alight wants no more.
    final (:simulation, :world) = _field();
    addTearDown(world.dispose);
    final before = world.world.bodyCount;
    // Loosed twice, one call after the other.
    for (var i = 0; i < 2; i++) {
      world.shootAtHall(0, Vector3(50.0, 0.0, 60.0));
    }
    // Mutation: drop the arrow-in-flight check — two bodies are added.
    expect(world.world.bodyCount, before + 1);
    simulation.step(_dt);
  });

  group('the river carved into the ground', () {
    // A valley of hills falling to the east, a hall at each end of it, and
    // a river down its middle: its water's cells half a metre square and
    // their middles on the carved ground's points, so the two can be
    // compared point for point.
    Heightfield valley() {
      const samples = 61;
      final heights = Float32List(samples * samples);
      for (var r = 0; r < samples; r++) {
        for (var c = 0; c < samples; c++) {
          heights[r * samples + c] =
              3.0 * math.sin(c / 9.0) + 2.0 * math.cos(r / 7.0) - c * 0.08;
        }
      }
      return Heightfield(
        columns: samples,
        rows: samples,
        cellSize: 2.0,
        heights: heights,
      );
    }

    StrategySimulation match(Heightfield ground) =>
        StrategySimulation(ground: ground, random: GameRandom(1))
          ..build(
            Building(center: Vector3(30.0, 0.0, 20.0), width: 6.0, depth: 5.0),
          )
          ..build(
            Building(
              center: Vector3(30.0, 0.0, 100.0),
              width: 6.0,
              depth: 5.0,
              side: 1,
            ),
          );

    final water = MapWater(
      x0: 3.75,
      z0: 39.75,
      cell: 0.5,
      nx: 200,
      nz: 60,
      course: <Vector2>[
        Vector2(8.0, 60.0),
        Vector2(30.0, 58.0),
        Vector2(60.0, 62.0),
        Vector2(90.0, 60.0),
      ],
      flow: 0.5,
      drainX: 100.0,
      drainZ: 60.0,
      sill: 4.0,
      pondLevel: -6.0,
    );

    test('is the bed the water stands in, and the ground elsewhere', () {
      // Strategy's river ran in a bed of its own under the grass, which no
      // drawn ground had. Mutation: carve with the ground as it is — the
      // carved ground is the hillside as it was and the water's bed is not in
      // it.
      final ground = valley();
      final open = match(ground);
      final world = MapWorld(open, water: water, trees: const <MapTree>[]);
      addTearDown(world.dispose);
      final carved = water.carve(
        ground,
        halls: open.buildings,
        seams: open.resources,
      );
      expect(carved.cellSize, water.cell);
      var shaped = 0;
      for (var j = 0; j < water.nz; j++) {
        for (var i = 0; i < water.nx; i++) {
          final bed = world.bed[i + j * water.nx];
          // To the single precision a heightfield keeps.
          expect(carved.sample(i + 8, j + 80), closeTo(bed, 1e-5));
          final x = water.x0 + (i + 0.5) * water.cell;
          final z = water.z0 + (j + 0.5) * water.cell;
          if ((bed - ground.heightAt(x, z)).abs() > 0.1) shaped++;
        }
      }
      expect(shaped, greaterThan(500), reason: 'banks raised, a bed laid');
      // Far from the river, the hillside.
      expect(
        carved.heightAt(10.0, 10.0),
        closeTo(ground.heightAt(10, 10), 1e-5),
      );
    });

    test('and a world over a match on it lays the same bed, not one carved '
        'into the carving', () {
      // Mutation: lay the river over the match's own ground — the bed is
      // graded again over the one carved, and stands higher at its falls.
      final ground = valley();
      final open = match(ground);
      final world = MapWorld(open, water: water, trees: const <MapTree>[]);
      addTearDown(world.dispose);
      final carved = water.carve(
        ground,
        halls: open.buildings,
        seams: open.resources,
      );
      final onCarved = MapWorld(
        match(carved),
        water: water,
        trees: const <MapTree>[],
        uncarved: ground,
      );
      addTearDown(onCarved.dispose);
      expect(onCarved.bed, world.bed);
      // What the mutation gives.
      final twice = MapWorld(
        match(carved),
        water: water,
        trees: const <MapTree>[],
      );
      addTearDown(twice.dispose);
      expect(twice.bed, isNot(world.bed));
    });
  });
}
