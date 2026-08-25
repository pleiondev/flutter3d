import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

/// A circuit with a field of cars on the grid, ready to be stepped.
final class Staged {
  const Staged({
    required this.track,
    required this.field,
    required this.race,
    required this.cars,
    required this.sim,
    required this.chase,
    required this.ai,
  });

  final TrackSpline track;

  /// What the cars stand on: the road, sampled from the spline.
  final TrackField field;

  final RaceState race;

  /// The field, the player first.
  final List<SphereVehicle> cars;

  final RacingSimulation sim;
  final ChaseCamera chase;
  final AiDriver ai;
}

/// How many cars line up, the player included.
const int kFieldSize = 4;
const int kLapsInARace = 3;

/// Turns a circuit document into a race, given a world its level is already in.
///
/// **There were three copies of this**: the application in `_loadCircuit`, the
/// frame test and the playthrough test, each lining a grid up in its own words.
/// The platformer and the crypt each went through the same thing, and in the
/// platformer's case the drift had already cost something — a harness that left
/// the surfaces out, so a level's ice walked exactly like its moss.
///
/// This is the shipped assembly, and now it is the only one. What is *not* here
/// is everything needing a graphics device — the road mesh, the car boxes, the
/// scene — because a test has no device, which is the whole reason the copies
/// existed.
///
/// [world] must already hold the level's brushes: the application gets them
/// from `LevelLoader`, which builds collision and scene together, and a test
/// calls `document.level!.addTo(world)`. That seam is one line on each side
/// rather than forty.
Staged stage(
  TrackDocument document,
  CollisionWorld world, {
  int cars = kFieldSize,
  RaceMode mode = RaceMode.race,
  int laps = kLapsInARace,
}) {
  final track = document.track;
  final field = TrackField(track: track, world: world);
  final race = RaceState(mode: mode, track: track, racers: cars, laps: laps);

  final vehicles = <SphereVehicle>[];
  final position = Vector3.zero();
  final forward = Vector3.zero();
  for (var i = 0; i < cars; i++) {
    track.startSlot(i, position, forward);
    final car = SphereVehicle(
      world: world,
      ground: field,
      // The body is a sphere whose centre floats above the road.
      position: position.clone()..y += 0.6,
      headingYaw: math.atan2(forward.x, forward.z),
    );
    // Told where it is on the lap, or its first step is a car that has never
    // been on the circuit and counts the grid as somewhere off it.
    car.placeAt(
      car.position,
      car.headingYaw,
      trackDistance: track.centre.wrap(track.grid.s),
    );
    vehicles.add(car);
  }

  return Staged(
    track: track,
    field: field,
    race: race,
    cars: vehicles,
    sim: RacingSimulation(collision: world, vehicles: vehicles, race: race),
    chase: ChaseCamera(world: world, track: track),
    ai: AiDriver(track: track),
  );
}

/// How far above its own origin a car is drawn, in metres.
///
/// A car is simulated as a sphere whose centre floats `rideHeight` above the
/// road, and a box model is a metre tall about its middle — so drawn at the
/// sphere's centre it sits half a metre into the tarmac.
double liftFor(SphereVehicle car) => 0.5 - car.tuning.rideHeight;
