/// A one-car race on a flat ring, driven by a tape, as the racing genre
/// stages it: what the default simulation is held to.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

const GameAction _throttle = GameAction('throttle');
const GameAction _steer = GameAction('steer');

/// A flat ring 70 m across with four checkpoints, as the racing package's
/// own tests draw it.
TrackSpline ringTrack() {
  const points = 20;
  const radius = 70.0;
  final center = CatmullRom(<Vector3>[
    for (var i = 0; i < points; i++)
      Vector3(
        radius * math.cos(2 * math.pi * i / points),
        0.0,
        radius * math.sin(2 * math.pi * i / points),
      ),
  ]);
  return TrackSpline(
    center: center,
    widths: List<double>.filled(points, 18.0),
    banks: List<double>.filled(points, 0.0),
    surfaces: <SurfaceBand>[
      SurfaceBand(
        fromS: 0.0,
        toS: center.length,
        center: 'asphalt',
        shoulder: 'grass',
      ),
    ],
    checkpoints: <double>[for (var i = 1; i < 4; i++) center.length * i / 4],
    grid: const StartGrid(s: -10.0, columns: 2),
  );
}

/// The tape: full throttle through the lights, then a steady left-hand
/// line with the steering swept, step by step.
InputTape racingTape({int steps = 600}) => InputTape(
  seed: 0,
  frames: <InputFrame>[
    for (var step = 0; step < steps; step++)
      InputFrame(
        values: <String, double>{
          _throttle.name: 1.0,
          _steer.name: ((step % 120) - 60) / 120.0,
        },
      ),
  ],
);

/// The racing loop: the genre's plugin, its race on the ring with one car,
/// the [tape] driving it, and [plugins] beside the genre. [also] is handed
/// the loop before the first step.
EngineLoop racingLoop({
  List<Flutter3dPlugin> plugins = const <Flutter3dPlugin>[],
  void Function(EngineLoop loop)? also,
  int steps = 600,
}) {
  final racing = RacingPlugin();
  final loop = EngineLoop(
    input: InputState(),
    simulationBase: racingSimulationVersion,
    plugins: <Flutter3dPlugin>[racing, ...plugins],
  );
  final world = CollisionWorld();
  raceIn(world);
  loop.stageWorld(world);
  final track = ringTrack();
  final field = TrackField(track: track, world: world);
  final position = Vector3.zero();
  final forward = Vector3.zero();
  track.startSlot(0, position, forward);
  final car = SphereVehicle(
    world: world,
    ground: field,
    position: position.clone()..y += 0.6,
    headingYaw: Portable.atan2(forward.x, forward.z),
  );
  car.placeAt(
    VehiclePlacement(
      position: car.position,
      headingYaw: car.headingYaw,
      trackDistance: track.center.wrap(track.grid.s),
    ),
  );
  final sim = RacingSimulation(
    collision: world,
    vehicles: <VehicleController>[car],
    race: RaceState(mode: RaceMode.race, track: track, racers: 1),
  );
  racing.simulation = sim;
  loop.addSystem('tape.driver', LoopPhase.input, (LoopContext context) {
    sim.inputs[0]
      ..throttle = loop.input.value(_throttle)
      ..steer = loop.input.value(_steer);
  });
  loop.playback = InputTapePlayback(racingTape(steps: steps));
  also?.call(loop);
  return loop;
}

/// The loop's digest every [every] steps of [steps], in hex.
List<String> digestsOf(EngineLoop loop, {int steps = 600, int every = 60}) =>
    <String>[
      for (var at = every; at <= steps; at += every)
        (loop..runSteps(every)).digest().toUnsigned(32).toRadixString(16),
    ];
