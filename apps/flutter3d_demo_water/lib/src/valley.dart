/// The valley the water runs through: a plateau with a spring, a stream
/// bed winding down it to a cliff, a pond at the cliff's foot and a channel
/// out of the pond to the edge of the map.
///
/// The ground is a function of where you stand, so the physics core's
/// water, the collision mesh the stones land on and the mesh that is drawn
/// are all read off one shape and cannot disagree.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

/// How many cells the valley has a side, and how wide each is, m.
const int valleyCells = 128;
const double valleyCell = 0.25;

/// The valley's side, m.
const double valleySize = valleyCells * valleyCell;

/// Where the cliff's top edge runs across the valley, and where its foot
/// is, along z: sheer, its whole height within half a cell, so the stream
/// goes over one lip as one sheet. Spread over a metre, four cells, each
/// cell of the face was a lip of its own, and the falls came down a stair
/// of short sheets each landing on the step below.
const double cliffTop = 13.0;
const double cliffFoot = cliffTop + 0.5 * valleyCell;

/// The pond's middle, and its radius.
const double pondX = 16.0, pondZ = 21.0, pondRadius = 7.0;

/// The stream bed's line down the plateau: x at a given z.
double streamX(double z) => 16.0 + 3.0 * Portable.sin(0.4 * z);

/// Where the spring wells up.
double get springX => streamX(springZ);
const double springZ = 2.0;

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

double _bump(double distance, double width) {
  final t = distance / width;
  return t >= 1.0 ? 0.0 : 1.0 - t * t;
}

/// The ground's height at (x, z), m.
double groundAt(double x, double z) {
  // The valley's walls rise either side of its middle.
  final walls = 3.0 * _smoothstep(9.0, 15.5, (x - 16.0).abs());
  double floor;
  if (z < cliffTop) {
    // The plateau, falling gently towards the cliff, its stream bed cut in.
    // Its banks rise away from the bed on both sides, so the stream keeps
    // to it instead of spreading over the flat.
    final off = (x - streamX(z)).abs();
    final bed = 0.5 * _bump(off, 1.4);
    floor = 5.0 + (cliffTop - z) * 0.2 - bed + 0.08 * off;
  } else if (z < cliffFoot) {
    // The cliff, four and a half metres sheer.
    final off = (x - streamX(cliffTop)).abs();
    final plateau = 5.0 - 0.5 * _bump(off, 1.4) + 0.08 * off;
    floor = plateau + (0.5 - plateau) * _smoothstep(cliffTop, cliffFoot, z);
  } else {
    // Below: the pond's bowl, and the channel that drains it to the edge.
    final bowl =
        1.6 *
        _bump(
          math.sqrt((x - pondX) * (x - pondX) + (z - pondZ) * (z - pondZ)),
          pondRadius,
        );
    final out = z > 25.0
        ? 0.45 * _bump((x - 16.0).abs(), 1.2) + (z - 25.0) * 0.08
        : 0.0;
    floor = 0.5 - bowl - out;
  }
  return floor + walls;
}

/// The ground at every cell's centre, x fastest: what the water and the
/// meshes are made from.
List<double> valleyGround() => <double>[
  for (var j = 0; j < valleyCells; j++)
    for (var i = 0; i < valleyCells; i++)
      groundAt((i + 0.5) * valleyCell, (j + 0.5) * valleyCell),
];
