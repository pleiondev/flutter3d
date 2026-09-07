/// The one place a run is assembled.
///
/// **One place, and the structure rule `each assembly has one home per
/// application` is what keeps it one.** A test that built its own hillside and
/// its own crowd would agree with every bug this file has; calling [stage] is
/// how a test gets the game rather than a likeness of it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/bridge.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:vector_math/vector_math.dart';

/// Everything a frame needs.
final class Staged {
  /// Holds the halves together.
  const Staged({
    required this.simulation,
    required this.visuals,
    required this.camera,
  });

  /// The crowd and the ground it walks on.
  final StrategySimulation simulation;

  /// What draws them.
  final StrategyVisuals visuals;

  /// The view over the map.
  final MapCamera camera;
}

/// Ground with two ridges and a valley between them.
///
/// Built from a formula rather than loaded, because what this demo is showing
/// is a crowd crossing terrain and a formula is a hillside anybody can read.
/// Deterministic, so two runs of the app are the same map.
Heightfield hills({int samples = 81, double cellSize = 2.0}) {
  final heights = Float32List(samples * samples);
  for (var row = 0; row < samples; row++) {
    for (var column = 0; column < samples; column++) {
      final double x = column / (samples - 1);
      final double z = row / (samples - 1);
      // Amplitude chosen by looking at it: ten metres over a hundred and sixty
      // reads as one tilted plane under a camera fifty degrees off the
      // horizon, because nothing in the picture is nearer than anything else
      // by enough to see. These ridges are steep enough to hide a crowd behind
      // and still gentle enough to walk over — the bake refuses forty degrees,
      // and the steepest here is about twenty-five.
      heights[row * samples + column] =
          math.sin(x * math.pi * 2.0) * 9.0 +
          math.sin(z * math.pi * 3.0 + 1.0) * 6.0 +
          math.sin((x + z) * math.pi * 5.0) * 1.5 +
          14.0;
    }
  }
  return Heightfield(
    columns: samples,
    rows: samples,
    cellSize: cellSize,
    heights: heights,
  );
}

/// Builds a run: the ground, the crowd standing on it, and the view over it.
Staged stage({required GraphicsDevice device, int units = 600}) {
  final ground = hills();
  final simulation = StrategySimulation(ground: ground);

  // A block in the near corner, spaced so nobody starts inside anybody.
  const int across = 25;
  for (var i = 0; i < units; i++) {
    simulation.add(
      Unit(
        position: Vector3(
          12.0 + (i % across) * 1.1,
          0.0,
          12.0 + (i ~/ across) * 1.1,
        ),
      ),
    );
  }

  simulation.build(
    Building(
      centre: Vector3(80.0, 0.0, 80.0),
      width: 14.0,
      depth: 10.0,
      name: 'hall',
    ),
  );

  final visuals = StrategyVisuals(
    simulation: simulation,
    device: device,
    capacity: units + 64,
  );

  // Pointed at the crowd rather than at the middle of the map. The default is
  // the centre of the ground, and the block above stands in a corner sixty
  // metres away — which drew a picture of empty hillside with the game just
  // out of frame.
  final camera = MapCamera(ground: ground)
    ..pan(
      12.0 + across * 1.1 / 2.0 - ground.width / 2.0,
      12.0 + (units / across) * 1.1 / 2.0 - ground.depth / 2.0,
    );

  return Staged(simulation: simulation, visuals: visuals, camera: camera);
}
