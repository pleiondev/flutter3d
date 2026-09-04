/// A flat ring with four checkpoints, wide enough to drive round without
/// trying very hard.
///
/// Shared between the race tests and the readout tests: two copies of a
/// fixture is two fixtures that drift, and a readout compared against a track
/// slightly unlike the one the race uses is a readout checked against nothing.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:vector_math/vector_math.dart';

TrackSpline ringTrack({double radius = 70.0, int points = 20}) {
  final positions = <Vector3>[
    for (var i = 0; i < points; i++)
      Vector3(
        radius * math.cos(2 * math.pi * i / points),
        0.0,
        radius * math.sin(2 * math.pi * i / points),
      ),
  ];
  final centre = CatmullRom(positions);
  return TrackSpline(
    centre: centre,
    widths: List<double>.filled(points, 18.0),
    banks: List<double>.filled(points, 0.0),
    surfaces: <SurfaceBand>[
      SurfaceBand(
        fromS: 0.0,
        toS: centre.length,
        centre: 'asphalt',
        shoulder: 'grass',
      ),
    ],
    checkpoints: <double>[for (var i = 1; i < 4; i++) centre.length * i / 4],
    grid: const StartGrid(s: -10.0, columns: 2),
  );
}
