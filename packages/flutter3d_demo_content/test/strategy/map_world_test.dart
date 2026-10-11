/// The strategy map's world on a bare field: a fire arrow lights a hall
/// where it strikes its timber, by the core's contact, and stones and arrows
/// are thrown by the core's own flight of them.
///
///     flutter test test/strategy/map_world_test.dart
library;

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
    world
      ..shootAtHall(0, Vector3(50.0, 0.0, 60.0))
      ..shootAtHall(0, Vector3(50.0, 0.0, 60.0));
    // Mutation: drop the arrow-in-flight check — two bodies are added.
    expect(world.world.bodyCount, before + 1);
    simulation.step(_dt);
  });
}
