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
///
/// [gridOrder], when given, says which physical slot each car starts in:
/// `gridOrder[slot]` is the index — into the returned [Staged.cars] and into
/// every other list this game addresses a car by — of the car standing in
/// that slot. Left null, car `i` starts in slot `i`, which is every existing
/// caller and every circuit's first running of it. See [gridOrderFrom] for
/// where a caller gets one.
Staged stage(
  TrackDocument document,
  CollisionWorld world, {
  int cars = kFieldSize,
  RaceMode mode = RaceMode.race,
  int laps = kLapsInARace,
  List<int>? gridOrder,
}) {
  final track = document.track;
  final field = TrackField(track: track, world: world);
  final race = RaceState(mode: mode, track: track, racers: cars, laps: laps);

  // Indexed by car rather than built up in slot order: a car's index is its
  // identity everywhere else this game reads one — the player is always
  // nought — and only where it starts on the grid is meant to move.
  final vehicles = List<SphereVehicle?>.filled(cars, null);
  final position = Vector3.zero();
  final forward = Vector3.zero();
  for (var slot = 0; slot < cars; slot++) {
    final carIndex = gridOrder != null ? gridOrder[slot] : slot;
    track.startSlot(slot, position, forward);
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
    vehicles[carIndex] = car;
  }
  final placed = vehicles.cast<SphereVehicle>();

  return Staged(
    track: track,
    field: field,
    race: race,
    cars: placed,
    sim: RacingSimulation(collision: world, vehicles: placed, race: race),
    chase: ChaseCamera(world: world, track: track),
    ai: AiDriver(track: track),
  );
}

/// The grid a fresh circuit should start on, given how [previous] ended.
///
/// **The convention chosen is pole-to-the-winner, not a reverse grid.** Both
/// are real racing formats; this one was picked because it is the one that
/// needs no new idea to justify — a season is not a spectacle format
/// decision, and "the front stays the front until somebody takes it" is the
/// reading that needs no further argument, where a reverse grid would be a
/// second feature (a comeback mechanic) wearing this one's name.
///
/// [previous] must be a race whose standing has settled — normally one whose
/// leader has already crossed the line, since [RaceState.positionOf] reads
/// laps and distance for anybody still running and would rank a race still
/// in progress by where it happens to be paused.
List<int> gridOrderFrom(RaceState previous) => List<int>.generate(
  previous.progress.length,
  (int i) => i,
)..sort(
  (int a, int b) => previous.positionOf(a).compareTo(previous.positionOf(b)),
);

/// How far above its own origin a car is drawn, in metres.
///
/// A car is simulated as a sphere whose centre floats `rideHeight` above the
/// road, and a box model is a metre tall about its middle — so drawn at the
/// sphere's centre it sits half a metre into the tarmac.
double liftFor(SphereVehicle car) => 0.5 - car.tuning.rideHeight;
