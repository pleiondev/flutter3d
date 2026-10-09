import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'ai/ai_driver.dart';
import 'race_state.dart';
import 'racing_world.dart';
import 'simulation.dart';
import 'simulation_version.dart';
import 'track.dart';
import 'track_field.dart';
import 'vehicle/sphere_vehicle.dart';

/// A racing circuit as a tool that plays it blind needs one: the player's
/// car driven from the stick, rivals driven by the genre's AI.
///
/// **Given the circuit, not read from the level.** A `HeadlessGame` is handed
/// a [Level], and a circuit is more than one: its measured centre line, its
/// width and camber, its grid, which a `TrackDocument` carries beside its
/// level. So the host reads the document and hands this its [track]; the
/// level [start] is given is the document's own, already in the world.
///
/// The stick drives: forward is the throttle, back the brake, left and
/// right the steering, each by how far it is held. [buttons] adds the
/// handbrake.
///
/// **The backend is the host's.** The cars sweep through the world they
/// are handed, on whatever physics it was made with; the application picks
/// the core for its own, and a host that wants the same answers does too.
final class RacingHeadlessGame extends HeadlessGame {
  const RacingHeadlessGame({
    required this.track,
    this.rivals = 0,
    this.laps = 3,
    this.mode = RaceMode.race,
  });

  /// The circuit the cars race round.
  final TrackSpline track;

  /// How many AI cars start behind the player.
  final int rivals;
  final int laps;
  final RaceMode mode;

  /// The one button a driver has beside the stick.
  static const GameAction handbrake = GameAction('handbrake');

  @override
  SimulationVersion get simulation => racingSimulationVersion;

  @override
  String get name => 'racing';

  @override
  Map<String, GameAction> get buttons => const <String, GameAction>{
    'handbrake': handbrake,
  };

  /// None of its own: a circuit's level is built from the engine's kinds.
  @override
  EntityRegistry registry() => EntityRegistry(const <EntityKind>[]);

  @override
  HeadlessRun start(Level level, CollisionWorld world, InputState input) {
    // The race's world, with the level's laid over it, as the application's.
    raceIn(world, level: level);
    final cars = 1 + rivals;
    final field = TrackField(track: track, world: world);
    final race = RaceState(mode: mode, track: track, racers: cars, laps: laps);
    final position = Vector3.zero();
    final forward = Vector3.zero();
    final vehicles = <SphereVehicle>[
      for (var slot = 0; slot < cars; slot++)
        _onGrid(slot, world, field, position, forward),
    ];
    return _RacingRun(
      sim: RacingSimulation(collision: world, vehicles: vehicles, race: race),
      ai: AiDriver(track: track),
      input: input,
    );
  }

  // As the application lines a grid up: slot by slot, the body's middle
  // over the road, told where on the lap it stands. The heading through
  // `Portable`, which a run's step reads by; the application's own grid
  // still takes the platform's, so a heading may differ in its last bit.
  SphereVehicle _onGrid(
    int slot,
    CollisionWorld world,
    TrackField field,
    Vector3 position,
    Vector3 forward,
  ) {
    track.startSlot(slot, position, forward);
    final car = SphereVehicle(
      world: world,
      ground: field,
      position: position.clone()..y += 0.6,
      headingYaw: Portable.atan2(forward.x, forward.z),
    );
    car.placeAt(
      car.position,
      car.headingYaw,
      trackDistance: track.center.wrap(track.grid.s),
    );
    return car;
  }
}

final class _RacingRun extends RestorableRun {
  _RacingRun({required this.sim, required this.ai, required this.input});

  final RacingSimulation sim;
  final AiDriver ai;
  final InputState input;

  @override
  void step(double dt) {
    // The stick, or the four keys that stand for it: forward is the
    // throttle, back the brake, across the steering.
    final move = input.moveAxis;
    sim.inputs[0]
      ..throttle = move.y > 0.0 ? move.y : 0.0
      ..brake = move.y < 0.0 ? -move.y : 0.0
      ..handbrake = input.held(RacingHeadlessGame.handbrake)
      ..steer = move.x;
    final length = sim.race.track.length;
    final player = sim.race.progress[0];
    for (var i = 1; i < sim.vehicles.length; i++) {
      // The rubber band reads the gap to the player, wrapped: as the
      // application drives its rivals.
      var gap =
          player.progressAlong(length) -
          sim.race.progress[i].progressAlong(length);
      if (gap.abs() > length / 2) gap -= gap.sign * length;
      ai.drive(
        sim.vehicles[i],
        sim.inputs[i],
        others: sim.vehicles,
        playerGap: gap,
      );
    }
    sim.step(dt);
  }

  @override
  Snapshot save() => sim.save();

  @override
  void restore(Snapshot snapshot) => sim.restore(snapshot);

  /// Won when the player crosses the line first, lost when somebody else
  /// did; playing until the player finishes.
  @override
  RunOutcome get outcome {
    final race = sim.race;
    if (!race.progress[0].isFinished && race.phase != RacePhase.finished) {
      return RunOutcome.playing;
    }
    return race.positionOf(0) == 1 ? RunOutcome.won : RunOutcome.lost;
  }

  @override
  WorldPosition get position => sim.vehicles[0].position.toWorldPosition();

  /// A driver's eye: a metre over the car's middle.
  @override
  WorldPosition get eye =>
      sim.vehicles[0].position.toWorldPosition().translated(0.0, 1.0, 0.0);

  /// Where the car is pointing, level.
  @override
  void aim(Vector3 out) {
    final yaw = sim.vehicles[0].headingYaw;
    out.setValues(Portable.sin(yaw), 0.0, Portable.cos(yaw));
  }

  @override
  String get summary {
    final race = sim.race;
    final me = race.progress[0];
    final at = position;
    return 'car at (${at.x.toStringAsFixed(1)}, ${at.y.toStringAsFixed(1)}, '
        '${at.z.toStringAsFixed(1)}), lap ${me.lap + 1} of ${race.laps}, '
        'position ${race.positionOf(0)} of ${race.progress.length}, '
        '${sim.vehicles[0].speed.toStringAsFixed(1)} m/s.';
  }

  @override
  Map<String, Object?> get reading {
    final race = sim.race;
    return <String, Object?>{
      'phase': race.phase.name,
      'elapsed': race.elapsed,
      'cars': <Map<String, Object?>>[
        for (var i = 0; i < sim.vehicles.length; i++)
          <String, Object?>{
            'index': i,
            'position': <double>[
              sim.vehicles[i].position.x,
              sim.vehicles[i].position.y,
              sim.vehicles[i].position.z,
            ],
            'speed': sim.vehicles[i].speed,
            'lap': race.progress[i].lap,
            'along': race.progress[i].s,
            'place': race.positionOf(i),
            'finished': race.progress[i].isFinished,
          },
      ],
    };
  }
}
